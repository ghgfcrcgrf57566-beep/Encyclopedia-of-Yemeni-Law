import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/app_config.dart';
import '../data/models/law.dart';
import '../data/models/madda.dart';
import '../data/repositories/laws_repository.dart';
import 'chat_history_db.dart';

class LegalAiException implements Exception {
  final String message;
  const LegalAiException(this.message);
  @override String toString() => message;
}

class LegalAiResult {
  final String answer;
  final List<LegalAiSource> sources;
  final String? conversationId;
  final String responseSource;
  const LegalAiResult({required this.answer, required this.sources, required this.conversationId, required this.responseSource});
}

class LegalAiSource {
  final int id;
  final String articleNumber;
  final String lawName;
  final String body;
  final String? babLabel;
  final String? faslLabel;
  const LegalAiSource({required this.id, required this.articleNumber, required this.lawName, required this.body, this.babLabel, this.faslLabel});
  factory LegalAiSource.fromMadda(Madda m) => LegalAiSource(id: m.id, articleNumber: m.number, lawName: m.lawName?.trim().isNotEmpty == true ? m.lawName!.trim() : 'القوانين اليمنية', body: m.body, babLabel: m.babLabel, faslLabel: m.faslLabel);
  factory LegalAiSource.fromJson(Map<String,dynamic> j) => LegalAiSource(id: (j['article_id'] as num?)?.toInt() ?? (j['id'] as num?)?.toInt() ?? 0, articleNumber: (j['article_number'] ?? j['number'] ?? '').toString(), lawName: (j['law_name'] ?? j['law'] ?? 'القوانين اليمنية').toString(), body: (j['article_text'] ?? j['body'] ?? '').toString(), babLabel: j['bab_label']?.toString(), faslLabel: j['fasl_label']?.toString());
  int get articleId => id;
  String get articleText => body;
  String get reference => '$lawName — المادة $articleNumber';
}

class LegalAiService {
  static final LegalAiService instance = LegalAiService();
  final LawsRepository _lawsRepository;
  final ChatHistoryDb _historyDb;
  LegalAiService({LawsRepository? lawsRepository, ChatHistoryDb? historyDb}) : _lawsRepository = lawsRepository ?? LawsRepository.instance, _historyDb = historyDb ?? ChatHistoryDb.instance;

  Future<LegalAiResult> ask({required String question, String? conversationId, List<Map<String,String>> history = const []}) async {
    final q = question.trim();
    if (q.isEmpty) throw const LegalAiException('اكتب سؤالك القانوني أولاً.');

    // قاعدة القوانين المحلية هي المصدر الأول والحصري عند وجود تطابق.
    final local = await _searchLocalFirst(q);
    if (local.isNotEmpty) {
      final answer = _buildLocalAnswer(local);
      await _saveHistory(q, answer, 'local_db');
      return LegalAiResult(answer: answer, sources: local.map(LegalAiSource.fromMadda).toList(), conversationId: conversationId, responseSource: 'local_db');
    }

    // Gemini لا يستعمل إلا كمسار احتياطي عند عدم العثور على مادة محلية.
    if (AppConfig.geminiApiKey.trim().isEmpty) {
      const answer = 'لم أجد مادة مرتبطة مباشرة بسؤالك في قاعدة القوانين المحلية.';
      await _saveHistory(q, answer, 'local_db_empty');
      return LegalAiResult(answer: answer, sources: const [], conversationId: conversationId, responseSource: 'local_db_empty');
    }
    final answer = await _askGeminiFallback(q, history);
    await _saveHistory(q, answer, 'gemini_ai_fallback');
    return LegalAiResult(answer: answer, sources: const [], conversationId: conversationId, responseSource: 'gemini_ai_fallback');
  }

  Future<List<Madda>> _searchLocalFirst(String q) async {
    final laws = await _lawsRepository.getAllLaws();
    final law = _findLaw(laws, q);
    final terms = _terms(q);
    final found = <Madda>[];
    final seen = <int>{};
    Future<void> add(String term, int? lawId) async {
      if (term.trim().length < 2) return;
      try {
        final rows = await _lawsRepository.search(term, lawId: lawId, limit: 20);
        for (final m in rows) { if (seen.add(m.id)) found.add(m); }
      } catch (_) {}
    }
    if (law != null) {
      for (final term in terms) { await add(term, law.id); if (found.length >= 40) break; }
    }
    if (found.isEmpty) {
      for (final term in terms) { await add(term, null); if (found.length >= 60) break; }
    }
    if (found.isEmpty) return [];
    final normalizedTerms = terms.map(_normalize).where((e) => e.length >= 2).toSet();
    final scored = <MapEntry<Madda,int>>[];
    for (final m in found) {
      final text = _normalize('${m.lawName ?? ''} ${m.number} ${m.babLabel ?? ''} ${m.faslLabel ?? ''} ${m.body}');
      var score = law != null && m.lawId == law.id ? 10 : 0;
      for (final term in normalizedTerms) { if (text.contains(term)) score += term.length >= 4 ? 3 : 1; }
      if (score >= (law == null ? 3 : 8)) scored.add(MapEntry(m, score));
    }
    scored.sort((a,b) => b.value.compareTo(a.value));
    return scored.take(8).map((e) => e.key).toList();
  }

  Law? _findLaw(List<Law> laws, String question) {
    final q = _normalize(question);
    final groups = <List<String>>[
      ['طلاق','فسخ','خلع','زواج','نكاح','زوج','زوجة','مهر','عدة','نفقة','حضانة','نسب'],
      ['عمل','عامل','موظف','اجازه','اجازة','أجر','راتب','فصل تعسفي'],
      ['تجاري','تجارة','تاجر','شركة','شركات','افلاس'],
      ['جريمة','عقوبة','قصاص','جناية','جنحة'],
      ['اجراءات جزائية','إجراءات جزائية','تحقيق','نيابة','محاكمة جزائية'],
      ['مرافعات','اجراءات مدنية','إجراءات مدنية','دعوى','استئناف','تنفيذ مدني'],
      ['اثبات','إثبات','بينة','شهادة','يمين'], ['تحكيم','محكم'], ['صحافة','مطبوعات','نشر'],
      ['مرور','سيارة','مركبة','قيادة'], ['صيدلة','صيدلي','دواء','صيدلية'], ['محاماة','محامي','محام'],
      ['اوقاف','أوقاف','وقف'], ['سجون','سجن','مسجون'], ['اراضي الدولة','أراضي الدولة','املاك الدولة','أملاك الدولة'],
    ];
    for (final group in groups) {
      if (!group.any((h) => q.contains(_normalize(h)))) continue;
      for (final law in laws) {
        final name = _normalize(law.name);
        if (group.any((h) => name.contains(_normalize(h)))) return law;
      }
    }
    for (final law in laws) { final name = _normalize(law.name); if (name.length >= 4 && q.contains(name)) return law; }
    return null;
  }

  List<String> _terms(String q) {
    final words = _normalize(q).split(RegExp(r'\s+')).where((w) => w.length >= 2 && !_stopWords.contains(w)).toList();
    final result = <String>{...words};
    final synonyms = <String,List<String>>{'طلاق':['طلاق','الطلاق'],'فسخ':['فسخ','فسخ الزواج','فسخ النكاح'],'خلع':['خلع','مخالعة'],'زواج':['زواج','نكاح','عقد الزواج'],'زوجة':['زوجة','الزوجة'],'زوج':['زوج','الزوج'],'عدة':['عدة','العدة'],'نفقة':['نفقة','النفقة'],'حضانة':['حضانة','الحضانة']};
    for (final w in words) { final s = synonyms[w]; if (s != null) result.addAll(s.map(_normalize)); }
    return result.take(12).toList();
  }

  String _normalize(String s) => s.toLowerCase().replaceAll(RegExp(r'[ً-ٟ]'),'').replaceAll(RegExp(r'[إأآٱ]'),'ا').replaceAll('ى','ي').replaceAll('ة','ه').replaceAll('ـ','').trim();

  String _buildLocalAnswer(List<Madda> matches) {
    final b = StringBuffer('وجدت النصوص القانونية المرتبطة بسؤالك في قاعدة القوانين المحلية:\n\n');
    for (var i=0;i<matches.length;i++) {
      final m=matches[i]; final law=m.lawName?.trim();
      b.writeln('${i+1}. ${law?.isNotEmpty == true ? law : 'القوانين اليمنية'}');
      b.writeln('المادة ${m.number}');
      if (m.babLabel?.trim().isNotEmpty == true) b.writeln('الباب: ${m.babLabel!.trim()}');
      if (m.faslLabel?.trim().isNotEmpty == true) b.writeln('الفصل: ${m.faslLabel!.trim()}');
      b.writeln(m.body.trim());
      if (i < matches.length-1) b.writeln('\n---\n');
    }
    return b.toString().trim();
  }

  Future<String> _askGeminiFallback(String q, List<Map<String,String>> history) async {
    final model = AppConfig.geminiModel.trim().isEmpty ? 'gemini-3.5-flash-lite' : AppConfig.geminiModel.trim();
    final uri = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent');
    final contents = <Map<String,dynamic>>[];
    for (final item in history.take(8)) {
      final text=item['content']?.trim() ?? ''; if (text.isEmpty) continue;
      contents.add({'role': item['role']=='assistant' ? 'model' : 'user','parts':[{'text':_stripMarkdown(text)}]});
    }
    contents.add({'role':'user','parts':[{'text':'أنت مساعد قانوني داخل موسوعة القانون اليمني. تم البحث أولاً في قاعدة القوانين المحلية ولم توجد مادة مباشرة، ولذلك أنت مسار احتياطي فقط. السؤال: $q\nأجب بالعربية بوضوح. لا تنسب نصاً إلى قانون يمني محدد ما لم يكن النص متاحاً لك. إذا كان السؤال يحتاج نصاً يمنياً محدداً فاذكر أن قاعدة التطبيق لم تجد مادة مباشرة. لا تستخدم Markdown مثل # أو ** أو `.'} ]});
    http.Response response;
    try {
      response=await http.post(uri,headers:{'Content-Type':'application/json','Accept':'application/json','x-goog-api-key':AppConfig.geminiApiKey.trim()},body:jsonEncode({'systemInstruction':{'parts':[{'text':'أنت مساعد قانوني عربي. كن دقيقاً ولا تختلق نصوصاً قانونية ولا تستخدم Markdown.'}]},'contents':contents}));
    } catch (_) { throw const LegalAiException('تعذر الاتصال بالمساعد الذكي. تحقق من اتصال الإنترنت أو مفتاح Gemini.'); }
    Map<String,dynamic> body={}; try { final d=jsonDecode(response.body); if(d is Map<String,dynamic>) body=d; } catch (_) {}
    if(response.statusCode!=200) throw LegalAiException(_apiError(body) ?? 'تعذر الحصول على إجابة من Gemini حالياً.');
    final answer=_generatedText(body); if(answer.isEmpty) throw const LegalAiException('تعذر توليد إجابة من المساعد الذكي.');
    return _stripMarkdown(answer);
  }

  String _generatedText(Map<String,dynamic> body) {
    final candidates=body['candidates']; if(candidates is! List || candidates.isEmpty) return '';
    final first=candidates.first; if(first is! Map) return ''; final content=first['content']; if(content is! Map) return '';
    final parts=content['parts']; if(parts is! List) return '';
    return parts.whereType<Map>().map((p)=>p['text']?.toString() ?? '').where((s)=>s.trim().isNotEmpty).join('\n').trim();
  }
  String? _apiError(Map<String,dynamic> body) { final e=body['error']; if(e is Map){ final m=e['message']?.toString().trim(); if(m?.isNotEmpty==true)return m; } return null; }
  String _stripMarkdown(String s) => s.replaceAll(RegExp(r'```[\s\S]*?```'),'').replaceAll(RegExp(r'(^|\n)\s*#{1,6}\s*'),r'$1').replaceAll('**','').replaceAll('__','').replaceAll('`','').trim();
  Future<void> _saveHistory(String q,String answer,String source) async { try { await _historyDb.addSearch(query:q,response:answer,source:source); } catch (_) {} }
}

const Set<String> _stopWords = {'ما','ماذا','هل','هو','هي','هذا','هذه','ذلك','تلك','من','في','فيه','عن','على','الى','إلى','مع','لي','لدي','اريد','أريد','يمكن','كيف','متى','أين','اين','ماهي','وما'};
