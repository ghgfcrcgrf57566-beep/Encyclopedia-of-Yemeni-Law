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

    final local = await _searchLocalFirst(q);
    if (local.isNotEmpty) {
      final answer = _buildLocalAnswer(local);
      await _saveHistory(q, answer, 'local_db');
      return LegalAiResult(answer: answer, sources: local.map(LegalAiSource.fromMadda).toList(), conversationId: conversationId, responseSource: 'local_db');
    }

    if (AppConfig.geminiApiKey.trim().isEmpty) {
      const answer = 'لم أجد مادة قانونية مرتبطة مباشرة بسؤالك في قاعدة القوانين المحلية، ولم يتم تشغيل Gemini لأن مفتاحه غير مُعد.';
      await _saveHistory(q, answer, 'local_db_empty');
      return LegalAiResult(answer: answer, sources: const [], conversationId: conversationId, responseSource: 'local_db_empty');
    }

    final answer = await _askGeminiFallback(q, history);
    await _saveHistory(q, answer, 'gemini_ai_fallback');
    return LegalAiResult(answer: answer, sources: const [], conversationId: conversationId, responseSource: 'gemini_ai_fallback');
  }

  Future<List<Madda>> _searchLocalFirst(String q) async {
    final laws = await _lawsRepository.getAllLaws();
    final scope = _detectLegalScope(laws, q);
    final terms = _terms(q, scope);
    if (terms.isEmpty) return [];

    final found = <Madda>[];
    final seen = <int>{};

    Future<void> addTerm(String term, {int? lawId}) async {
      if (term.length < 2) return;
      try {
        final rows = await _lawsRepository.search(term, lawId: lawId, limit: 30);
        for (final m in rows) {
          if (seen.add(m.id)) found.add(m);
        }
      } catch (_) {}
    }

    // إذا عُرف مجال السؤال، لا نبحث في جميع القوانين. هذا يمنع كلمات عامة مثل
    // "شروط" من سحب مواد من الدستور أو القانون التجاري لمجرد أنها تحتوي الكلمة.
    if (scope != null) {
      for (final term in terms) {
        await addTerm(term, lawId: scope.lawId);
        if (found.length >= 80) break;
      }
    } else {
      // الأسئلة التي لا يمكن تصنيفها لا تحصل على نتائج عشوائية من كلمة عامة.
      // نطلب تطابقاً مباشراً للسؤال أولاً فقط.
      try {
        final direct = await _lawsRepository.search(q, limit: 20);
        for (final m in direct) if (seen.add(m.id)) found.add(m);
      } catch (_) {}
    }

    if (found.isEmpty) return [];

    final scored = <_ScoredMadda>[];
    for (final m in found) {
      final text = _normalize('${m.lawName ?? ''} ${m.number} ${m.babLabel ?? ''} ${m.faslLabel ?? ''} ${m.body}');
      var score = 0;
      var matchedCore = false;
      for (final term in terms) {
        final t = _normalize(term);
        if (t.length < 2) continue;
        if (text.contains(t)) {
          score += t.length >= 4 ? 5 : 2;
          if (scope != null && scope.coreTerms.any((c) => _normalize(c) == t)) matchedCore = true;
        }
      }
      if (scope != null && m.lawId == scope.lawId) score += 20;
      if (scope != null && !matchedCore) continue;
      // لا نعرض نتيجة لمجرد تطابق كلمة عامة مثل "شروط" أو "ما".
      if (score < (scope != null ? 25 : 8)) continue;
      scored.add(_ScoredMadda(m, score));
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(8).map((e) => e.madda).toList();
  }

  _LegalScope? _detectLegalScope(List<Law> laws, String question) {
    final q = _normalize(question);
    final definitions = <_ScopeDefinition>[
      _ScopeDefinition(['طلاق','فسخ','خلع','زواج','نكاح','زوج','زوجة','مهر','عدة','نفقة','حضانة','نسب'], ['احوال شخصية','الأحوال الشخصية','شخصية']),
      _ScopeDefinition(['عمل','عامل','عمال','موظف','اجازه','اجازة','أجر','راتب','فصل تعسفي','صاحب العمل'], ['عمل','العمل']),
      _ScopeDefinition(['تجاري','تجارة','تاجر','شركة','شركات','افلاس','إفلاس','سجل تجاري'], ['تجاري','التجارة','الشركات']),
      _ScopeDefinition(['جريمة','عقوبة','قصاص','جناية','جنحة','قتل','سرقة'], ['جرائم','العقوبات','العقوبات']),
      _ScopeDefinition(['اجراءات جزائية','إجراءات جزائية','تحقيق','نيابة','محاكمة جزائية','ضبط'], ['إجراءات جزائية','الإجراءات الجزائية']),
      _ScopeDefinition(['مرافعات','اجراءات مدنية','إجراءات مدنية','دعوى','استئناف','تنفيذ مدني','حجز'], ['مرافعات','التنفيذ المدني']),
      _ScopeDefinition(['اثبات','إثبات','بينة','شهادة','يمين','إقرار','محرر'], ['إثبات']),
      _ScopeDefinition(['تحكيم','محكم','محكمين'], ['تحكيم']),
      _ScopeDefinition(['صحافة','مطبوعات','نشر','صحفي'], ['صحافة','المطبوعات']),
      _ScopeDefinition(['مرور','سيارة','مركبة','قيادة','رخصة'], ['مرور']),
      _ScopeDefinition(['صيدلة','صيدلي','دواء','صيدلية'], ['مزاولة المهن الطبية','المهن الطبية','صيدلة']),
      _ScopeDefinition(['محاماة','محامي','محام'], ['المحاماة','مهنة المحاماة']),
      _ScopeDefinition(['اوقاف','أوقاف','وقف'], ['وقف','الأوقاف']),
      _ScopeDefinition(['سجون','سجن','مسجون'], ['السجون']),
      _ScopeDefinition(['اراضي الدولة','أراضي الدولة','املاك الدولة','أملاك الدولة','عقارات الدولة'], ['أراضي وعقارات الدولة','أراضي الدولة','عقارات الدولة']),
    ];

    for (final d in definitions) {
      final matched = d.coreTerms.where((t) => q.contains(_normalize(t))).toList();
      if (matched.isEmpty) continue;
      Law? law;
      for (final candidate in laws) {
        final name = _normalize(candidate.name);
        if (d.lawHints.any((h) => name.contains(_normalize(h)))) { law = candidate; break; }
      }
      if (law != null) return _LegalScope(law.id, matched, d.coreTerms);
    }
    return null;
  }

  List<String> _terms(String q, _LegalScope? scope) {
    final words = _normalize(q).split(RegExp(r'\s+')).where((w) => w.length >= 2 && !_stopWords.contains(w)).toList();
    final result = <String>{};
    if (scope != null) result.addAll(scope.coreTerms.where((t) => q.contains(t)).map(_normalize));
    result.addAll(words.where((w) => !_genericTerms.contains(w)));
    return result.take(12).toList();
  }

  String _normalize(String s) => s.toLowerCase().replaceAll(RegExp(r'[ً-ٟ]'),'').replaceAll(RegExp(r'[إأآٱ]'),'ا').replaceAll('ى','ي').replaceAll('ة','ه').replaceAll('ـ','').trim();

  String _buildLocalAnswer(List<Madda> matches) {
    final b = StringBuffer('وجدت النصوص القانونية المرتبطة بسؤالك في قاعدة القوانين المحلية:\n\n');
    for (var i = 0; i < matches.length; i++) {
      final m = matches[i];
      final law = m.lawName?.trim();
      b.writeln('${i + 1}. ${law?.isNotEmpty == true ? law : 'القوانين اليمنية'}');
      b.writeln('المادة ${m.number}');
      if (m.babLabel?.trim().isNotEmpty == true) b.writeln('الباب: ${m.babLabel!.trim()}');
      if (m.faslLabel?.trim().isNotEmpty == true) b.writeln('الفصل: ${m.faslLabel!.trim()}');
      b.writeln(m.body.trim());
      if (i < matches.length - 1) b.writeln('\n---\n');
    }
    return b.toString().trim();
  }

  Future<String> _askGeminiFallback(String q, List<Map<String,String>> history) async {
    final model = AppConfig.geminiModel.trim().isEmpty ? 'gemini-3.5-flash-lite' : AppConfig.geminiModel.trim();
    final uri = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent');
    final contents = <Map<String,dynamic>>[];
    for (final item in history.take(8)) {
      final text = item['content']?.trim() ?? '';
      if (text.isEmpty) continue;
      contents.add({'role': item['role'] == 'assistant' ? 'model' : 'user', 'parts': [{'text': _stripMarkdown(text)}]});
    }
    contents.add({'role': 'user', 'parts': [{'text': 'أنت مساعد قانوني داخل موسوعة القانون اليمني. تم البحث أولاً في قاعدة القوانين المحلية ولم توجد مادة مباشرة، ولذلك أنت مسار احتياطي فقط. السؤال: $q\nأجب بالعربية بوضوح. لا تنسب نصاً إلى قانون يمني محدد ما لم يكن النص متاحاً لك. إذا كان السؤال يحتاج نصاً يمنياً محدداً فاذكر أن قاعدة التطبيق لم تجد مادة مباشرة. لا تستخدم Markdown مثل # أو ** أو `.'}]});
    http.Response response;
    try {
      response = await http.post(uri, headers: {'Content-Type': 'application/json', 'Accept': 'application/json', 'x-goog-api-key': AppConfig.geminiApiKey.trim()}, body: jsonEncode({'systemInstruction': {'parts': [{'text': 'أنت مساعد قانوني عربي. كن دقيقاً ولا تختلق نصوصاً قانونية ولا تستخدم Markdown.'}]}, 'contents': contents}));
    } catch (_) {
      throw const LegalAiException('تعذر الاتصال بالمساعد الذكي. تحقق من اتصال الإنترنت أو مفتاح Gemini.');
    }
    Map<String,dynamic> body = {};
    try { final d = jsonDecode(response.body); if (d is Map<String,dynamic>) body = d; } catch (_) {}
    if (response.statusCode != 200) throw LegalAiException(_apiError(body) ?? 'تعذر الحصول على إجابة من Gemini حالياً.');
    final answer = _generatedText(body);
    if (answer.isEmpty) throw const LegalAiException('تعذر توليد إجابة من المساعد الذكي.');
    return _stripMarkdown(answer);
  }

  String _generatedText(Map<String,dynamic> body) {
    final candidates = body['candidates'];
    if (candidates is! List || candidates.isEmpty) return '';
    final first = candidates.first;
    if (first is! Map) return '';
    final content = first['content'];
    if (content is! Map) return '';
    final parts = content['parts'];
    if (parts is! List) return '';
    return parts.whereType<Map>().map((p) => p['text']?.toString() ?? '').where((s) => s.trim().isNotEmpty).join('\n').trim();
  }

  String? _apiError(Map<String,dynamic> body) {
    final e = body['error'];
    if (e is Map) {
      final m = e['message']?.toString().trim();
      if (m?.isNotEmpty == true) return m;
    }
    return null;
  }

  String _stripMarkdown(String s) => s.replaceAll(RegExp(r'```[\s\S]*?```'), '').replaceAll(RegExp(r'(^|\n)\s*#{1,6}\s*'), r'$1').replaceAll('**', '').replaceAll('__', '').replaceAll('`', '').trim();
  Future<void> _saveHistory(String q, String answer, String source) async { try { await _historyDb.addSearch(query: q, response: answer, source: source); } catch (_) {} }
}

class _ScoredMadda {
  final Madda madda;
  final int score;
  const _ScoredMadda(this.madda, this.score);
}

class _ScopeDefinition {
  final List<String> coreTerms;
  final List<String> lawHints;
  const _ScopeDefinition(this.coreTerms, this.lawHints);
}

class _LegalScope {
  final int lawId;
  final List<String> matchedTerms;
  final List<String> coreTerms;
  const _LegalScope(this.lawId, this.matchedTerms, this.coreTerms);
}

const Set<String> _stopWords = {'ما','ماذا','هل','هو','هي','هذا','هذه','ذلك','تلك','من','في','فيه','عن','على','الى','إلى','مع','لي','لدي','اريد','أريد','يمكن','كيف','متى','أين','اين','ماهي','وما'};
const Set<String> _genericTerms = {'شروط','شرط','حالات','حاله','حالة','جميع','ماهي','ماهى','ماهي','هي','هو','ما','هل','كيف','متى','من','في','عن','على','الى','إلى','ما','وما'};
