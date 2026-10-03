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

    // لا نرسل أي إجابة للمستخدم مباشرة. كل نتيجة محلية يجب أن يراجعها Gemini
    // مقابل السؤال، وإذا رفضها نعيد البحث قبل الإرسال.
    if (AppConfig.geminiApiKey.trim().isEmpty) {
      throw const LegalAiException('لا يمكن إرسال الإجابة قبل مراجعتها بواسطة Gemini. مفتاح Gemini غير مُعد.');
    }

    var searchQuestion = q;
    final rejectedIds = <int>{};

    for (var attempt = 0; attempt < 3; attempt++) {
      final local = await _searchLocalFirst(searchQuestion, excludeIds: rejectedIds);
      if (local.isNotEmpty) {
        final answer = _buildLocalAnswer(local);
        final review = await _reviewWithGemini(q, answer, local, history);
        if (review.isMatch) {
          await _saveHistory(q, answer, 'local_db_gemini_verified');
          return LegalAiResult(answer: answer, sources: local.map(LegalAiSource.fromMadda).toList(), conversationId: conversationId, responseSource: 'local_db_gemini_verified');
        }
        rejectedIds.addAll(local.map((m) => m.id));
        if (review.searchQuery.trim().isNotEmpty) {
          searchQuestion = review.searchQuery.trim();
        } else {
          searchQuestion = '$q ${review.reason}'.trim();
        }
        continue;
      }
      break;
    }

    // إذا لم نجد نصاً محلياً مطابقاً بعد إعادة البحث، يجيب Gemini كمسار احتياطي.
    // ثم تتم مراجعة إجابته أيضاً قبل إرسالها للمستخدم.
    final generated = await _askGeminiFallback(q, history);
    final generatedReview = await _reviewGeneratedAnswerWithGemini(q, generated, history);
    if (!generatedReview.isMatch) {
      // لا نرسل إجابة رفضها المراجع. نعطي رسالة واضحة بدلاً من إجابة غير موثوقة.
      const answer = 'لم أجد في قاعدة القوانين المحلية نصاً مرتبطاً بما يكفي بسؤالك، ولم تعتمد المراجعة الذكية إجابة بديلة لإرسالها.';
      await _saveHistory(q, answer, 'gemini_review_rejected');
      return LegalAiResult(answer: answer, sources: const [], conversationId: conversationId, responseSource: 'gemini_review_rejected');
    }

    await _saveHistory(q, generated, 'gemini_ai_reviewed');
    return LegalAiResult(answer: generated, sources: const [], conversationId: conversationId, responseSource: 'gemini_ai_reviewed');
  }

  Future<List<Madda>> _searchLocalFirst(String q, {Set<int> excludeIds = const {}}) async {
    final laws = await _lawsRepository.getAllLaws();
    final scope = _detectLegalScope(laws, q);
    final terms = _terms(q, scope);
    if (terms.isEmpty) return [];

    final found = <Madda>[];
    final seen = <int>{};

    Future<void> addTerm(String term, {int? lawId}) async {
      if (term.length < 2) return;
      try {
        final rows = await _lawsRepository.search(term, lawId: lawId, limit: 40);
        for (final m in rows) {
          if (excludeIds.contains(m.id)) continue;
          if (seen.add(m.id)) found.add(m);
        }
      } catch (_) {}
    }

    if (scope != null) {
      for (final term in terms) {
        await addTerm(term, lawId: scope.lawId);
        if (found.length >= 100) break;
      }
    } else {
      try {
        final direct = await _lawsRepository.search(q, limit: 30);
        for (final m in direct) {
          if (!excludeIds.contains(m.id) && seen.add(m.id)) found.add(m);
        }
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

  Future<_GeminiReview> _reviewWithGemini(String question, String candidate, List<Madda> sources, List<Map<String,String>> history) async {
    final sourceText = sources.take(8).map((m) => 'القانون: ${m.lawName ?? 'القوانين اليمنية'}\nالمادة: ${m.number}\nالنص: ${m.body}').join('\n\n');
    final prompt = '''راجع الإجابة القانونية التالية مقابل سؤال المستخدم مراجعة صارمة.
السؤال الأصلي: $question

الإجابة المرشحة:
$candidate

المصادر المحلية:
$sourceText

أعد JSON فقط بهذا الشكل:
{"match":true,"reason":"...","search_query":"..."}

match=true فقط إذا كانت الإجابة تجيب السؤال نفسه والمصادر مرتبطة بموضوعه مباشرة.
إذا كانت غير مرتبطة أو عامة أو من قانون خاطئ، اجعل match=false واقترح search_query عربيًا أدق لإعادة البحث.
لا تعتمد على مجرد تشابه كلمة واحدة مثل شروط أو حالات.
''';
    final text = await _callGemini(prompt, history: history, system: 'أنت مراجع قانوني صارم. مهمتك التحقق من تطابق السؤال مع الإجابة والمصادر. لا تخمن. أخرج JSON فقط.');
    return _parseReview(text);
  }

  Future<_GeminiReview> _reviewGeneratedAnswerWithGemini(String question, String answer, List<Map<String,String>> history) async {
    final prompt = '''راجع إجابة Gemini التالية مقابل السؤال.
السؤال: $question
الإجابة: $answer

أعد JSON فقط:
{"match":true,"reason":"...","search_query":"..."}

match=true فقط إذا كانت الإجابة تجيب السؤال مباشرة وبوضوح ولا تدعي نصاً قانونياً يمنياً غير متاح لها.''';
    final text = await _callGemini(prompt, history: history, system: 'أنت مراجع مستقل لإجابات المساعد القانوني. لا تسمح بإرسال إجابة لا تطابق السؤال. أخرج JSON فقط.');
    return _parseReview(text);
  }

  _GeminiReview _parseReview(String text) {
    var cleaned = text.trim();
    cleaned = cleaned.replaceAll(RegExp(r'^```(?:json)?\s*'), '').replaceAll(RegExp(r'\s*```$'), '').trim();
    try {
      final decoded = jsonDecode(cleaned);
      if (decoded is Map) {
        final match = decoded['match'] == true;
        return _GeminiReview(match, decoded['reason']?.toString() ?? '', decoded['search_query']?.toString() ?? '');
      }
    } catch (_) {}
    return const _GeminiReview(false, 'تعذر التحقق من الإجابة بصيغة موثوقة.', '');
  }

  Future<String> _callGemini(String prompt, {List<Map<String,String>> history = const [], required String system}) async {
    final model = AppConfig.geminiModel.trim().isEmpty ? 'gemini-3.5-flash-lite' : AppConfig.geminiModel.trim();
    final uri = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent');
    final contents = <Map<String,dynamic>>[];
    for (final item in history.take(6)) {
      final text = item['content']?.trim() ?? '';
      if (text.isEmpty) continue;
      contents.add({'role': item['role'] == 'assistant' ? 'model' : 'user', 'parts': [{'text': _stripMarkdown(text)}]});
    }
    contents.add({'role': 'user', 'parts': [{'text': prompt}]});
    http.Response response;
    try {
      response = await http.post(uri, headers: {'Content-Type': 'application/json', 'Accept': 'application/json', 'x-goog-api-key': AppConfig.geminiApiKey.trim()}, body: jsonEncode({'systemInstruction': {'parts': [{'text': system}]}, 'contents': contents, 'generationConfig': {'temperature': 0.0}}));
    } catch (_) {
      throw const LegalAiException('تعذر الاتصال بـ Gemini لمراجعة الإجابة. لم يتم إرسال أي إجابة للمستخدم.');
    }
    Map<String,dynamic> body = {};
    try { final d = jsonDecode(response.body); if (d is Map<String,dynamic>) body = d; } catch (_) {}
    if (response.statusCode != 200) throw LegalAiException(_apiError(body) ?? 'تعذر استخدام Gemini لمراجعة الإجابة. لم يتم إرسالها.');
    final answer = _generatedText(body);
    if (answer.isEmpty) throw const LegalAiException('لم تصل مراجعة صالحة من Gemini، لذلك لم يتم إرسال الإجابة.');
    return answer.trim();
  }

  Future<String> _askGeminiFallback(String q, List<Map<String,String>> history) async {
    return _callGemini('''أنت مساعد قانوني داخل موسوعة القانون اليمني. لم نجد مادة محلية مباشرة بعد البحث وإعادة البحث. أجب عن السؤال بالعربية بوضوح.
السؤال: $q
لا تنسب نصاً إلى قانون يمني محدد ما لم يكن النص متاحاً لك. إذا لم تستطع الإجابة بثقة، صرّح بذلك. لا تستخدم Markdown.''', history: history, system: 'أنت مساعد قانوني عربي. كن دقيقاً ولا تختلق نصوصاً قانونية ولا تستخدم Markdown.');
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

class _GeminiReview {
  final bool isMatch;
  final String reason;
  final String searchQuery;
  const _GeminiReview(this.isMatch, this.reason, this.searchQuery);
}

const Set<String> _stopWords = {'ما','ماذا','هل','هو','هي','هذا','هذه','ذلك','تلك','من','في','فيه','عن','على','الى','إلى','مع','لي','لدي','اريد','أريد','يمكن','كيف','متى','أين','اين','ماهي','وما'};
const Set<String> _genericTerms = {'شروط','شرط','حالات','حاله','حالة','جميع','ماهي','ماهى','هي','هو','ما','هل','كيف','متى','من','في','عن','على','الى','إلى','وما'};
