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
  @override
  String toString() => message;
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
  factory LegalAiSource.fromJson(Map<String, dynamic> j) => LegalAiSource(id: (j['article_id'] as num?)?.toInt() ?? (j['id'] as num?)?.toInt() ?? 0, articleNumber: (j['article_number'] ?? j['number'] ?? '').toString(), lawName: (j['law_name'] ?? j['law'] ?? 'القوانين اليمنية').toString(), body: (j['article_text'] ?? j['body'] ?? '').toString(), babLabel: j['bab_label']?.toString(), faslLabel: j['fasl_label']?.toString());
  int get articleId => id;
  String get articleText => body;
  String get reference => '$lawName — المادة $articleNumber';
}

class LegalAiService {
  static final LegalAiService instance = LegalAiService();
  final LawsRepository _lawsRepository;
  final ChatHistoryDb _historyDb;
  LegalAiService({LawsRepository? lawsRepository, ChatHistoryDb? historyDb}) : _lawsRepository = lawsRepository ?? LawsRepository.instance, _historyDb = historyDb ?? ChatHistoryDb.instance;

  Future<LegalAiResult> ask({
    required String question,
    String? conversationId,
    List<Map<String, String>> history = const [],
    String lawScope = 'الكل',
  }) async {
    final raw = question.trim();
    if (raw.isEmpty) throw const LegalAiException('اكتب سؤالك القانوني أولاً.');
    if (AppConfig.geminiApiKey.trim().isEmpty) {
      throw const LegalAiException('لا يمكن إرسال الإجابة قبل أن يبحث فيها Gemini. مفتاح Gemini غير مُعد.');
    }

    // الواجهة الحالية تمرر أحياناً السؤال مع تعليمات وضع الإجابة واسم الفلتر.
    // نفصل السؤال الحقيقي والنطاق هنا حتى لا تدخل تعليمات الواجهة في بحث SQLite.
    final q = _extractUserQuestion(raw);
    final requestedScope = lawScope == 'الكل' ? _extractLawScope(raw) : lawScope;
    final laws = await _lawsRepository.getAllLaws();
    final selectedLaw = await _resolveLawScope(laws, requestedScope);

    // Gemini هو محرك البحث: يحدد عبارات البحث والقانون المقصود، ثم نستخدم قاعدة التطبيق كمصدر يمكنه البحث داخله.
    final plan = await _planSearchWithGemini(q, requestedScope, history);
    final queries = <String>{
      ...plan.queries.where((v) => v.trim().isNotEmpty),
      q,
    }.take(4).toList();

    final candidates = <Madda>[];
    final seen = <int>{};
    for (final query in queries) {
      final rows = await _searchLocal(query, lawId: selectedLaw?.id, limit: 40);
      for (final row in rows) {
        if (seen.add(row.id)) candidates.add(row);
      }
      if (candidates.length >= 40) break;
    }

    final ranked = await _rankLocalCandidatesWithGemini(q, requestedScope, candidates, history);
    if (ranked.isNotEmpty) {
      final answer = await _answerFromLocalWithGemini(q, requestedScope, ranked, history);
      final review = await _reviewFinalAnswerWithGemini(q, requestedScope, answer, ranked, history);
      if (review.isMatch) {
        await _saveHistory(q, answer, 'gemini_search_local_db');
        return LegalAiResult(answer: answer, sources: ranked.map(LegalAiSource.fromMadda).toList(), conversationId: conversationId, responseSource: 'gemini_search_local_db');
      }
    }

    // إذا لم يجد Gemini نصاً مناسباً داخل قاعدة التطبيق، ينتقل إلى معرفته القانونية.
    // وتبقى المراجعة النهائية إلزامية قبل الإرسال.
    final generated = await _answerFromGeminiKnowledge(q, requestedScope, history);
    final generatedReview = await _reviewFinalAnswerWithGemini(q, requestedScope, generated, const [], history);
    if (!generatedReview.isMatch) {
      const answer = 'لم يعتمد Gemini إجابة مرتبطة بما يكفي بسؤالك، لذلك لم يتم إرسال إجابة غير موثوقة.';
      await _saveHistory(q, answer, 'gemini_rejected');
      return LegalAiResult(answer: answer, sources: const [], conversationId: conversationId, responseSource: 'gemini_rejected');
    }

    await _saveHistory(q, generated, 'gemini_search_knowledge');
    return LegalAiResult(answer: generated, sources: const [], conversationId: conversationId, responseSource: 'gemini_search_knowledge');
  }

  String _extractUserQuestion(String raw) {
    final marker = 'السؤال القانوني:';
    final index = raw.lastIndexOf(marker);
    if (index >= 0) {
      final value = raw.substring(index + marker.length).trim();
      if (value.isNotEmpty) return value;
    }
    return raw;
  }

  String _extractLawScope(String raw) {
    final match = RegExp(r'نطاق البحث الإلزامي:\s*(.+?)\s*فقط').firstMatch(raw);
    if (match != null && match.group(1)?.trim().isNotEmpty == true) return match.group(1)!.trim();
    return 'الكل';
  }

  Future<Law?> _resolveLawScope(List<Law> laws, String scope) async {
    final requested = _normalize(scope);
    if (requested.isEmpty || requested == 'الكل' || requested == 'كل') return null;
    final aliases = <String, List<String>>{
      'الاحوال الشخصية': ['احوال شخصية', 'الأحوال الشخصية', 'شخصية'],
      'القانون المدني': ['القانون المدني', 'مدني'],
      'القانون التجاري': ['القانون التجاري', 'تجاري'],
      'الجرائم والعقوبات': ['الجرائم والعقوبات', 'جرائم', 'العقوبات'],
      'الإجراءات الجزائية': ['الإجراءات الجزائية', 'إجراءات جزائية'],
      'المرافعات والتنفيذ': ['المرافعات والتنفيذ', 'المرافعات', 'التنفيذ المدني'],
      'الإثبات': ['الإثبات'],
      'التحكيم': ['التحكيم'],
      'قانون العمل': ['قانون العمل', 'العمل'],
      'الصحافة والمطبوعات': ['الصحافة والمطبوعات', 'الصحافة', 'المطبوعات'],
      'المرور': ['المرور'],
      'المهن الطبية والصيدلة': ['مزاولة المهن الطبية', 'المهن الطبية', 'الصيدلة'],
      'المحاماة': ['المحاماة', 'مهنة المحاماة'],
      'الوقف': ['الوقف', 'الأوقاف'],
      'السجون': ['السجون'],
      'أراضي وعقارات الدولة': ['أراضي وعقارات الدولة', 'أراضي الدولة', 'عقارات الدولة'],
      'الشركات': ['الشركات'],
      'القضاء': ['القضاء'],
      'تنظيم العلاقة بين المؤجر والمستأجر': ['المؤجر والمستأجر', 'المستأجر'],
    };
    final wanted = aliases[requested] ?? [scope];
    for (final law in laws) {
      final name = _normalize(law.name);
      if (wanted.any((alias) => name.contains(_normalize(alias)))) return law;
    }
    return null;
  }

  Future<List<Madda>> _searchLocal(String query, {int? lawId, int limit = 40}) async {
    try {
      return await _lawsRepository.search(query, lawId: lawId, limit: limit);
    } catch (_) {
      return [];
    }
  }

  Future<_SearchPlan> _planSearchWithGemini(String question, String scope, List<Map<String, String>> history) async {
    final prompt = '''أنت محرك البحث القانوني لموسوعة القوانين اليمنية.
السؤال: $question
نطاق البحث المختار: $scope

مهمتك ليست إعطاء جواب نهائي الآن. حلل السؤال وحدد المصطلحات القانونية التي يجب استخدامها للبحث في قاعدة القوانين داخل التطبيق.
إذا كان النطاق قانوناً محدداً فلا تخرج عن ذلك القانون.
إذا كان النطاق هو الكل، حدد القانون أو القوانين اليمنية الأكثر صلة بالسؤال.

أعد JSON فقط:
{"queries":["عبارة بحث دقيقة 1","عبارة بحث دقيقة 2","عبارة بحث دقيقة 3"]}

اجعل العبارات قصيرة ومباشرة، واستخدم المصطلحات القانونية العربية لا الكلمات العامة.''';
    final raw = await _callGemini(prompt, history: history, temperature: 0.0);
    return _parseSearchPlan(raw);
  }

  Future<List<Madda>> _rankLocalCandidatesWithGemini(String question, String scope, List<Madda> candidates, List<Map<String, String>> history) async {
    if (candidates.isEmpty) return [];
    final limited = candidates.take(30).toList();
    final sourceText = limited.asMap().entries.map((e) => '[${e.key}] القانون: ${e.value.lawName ?? 'القوانين اليمنية'} | المادة: ${e.value.number}\n${e.value.body}').join('\n\n');
    final prompt = '''أنت الباحث القانوني في موسوعة القوانين اليمنية.
السؤال: $question
النطاق: $scope

هذه نتائج البحث من قاعدة التطبيق:
$sourceText

اختر فقط المواد التي تجيب عن السؤال مباشرة أو تشكل أساساً قانونياً مباشراً للإجابة. استبعد النتائج العامة أو غير المرتبطة.
أعد JSON فقط بالشكل:
{"ids":[0,2,5]}
ولا تختر مادة لمجرد وجود كلمة مشتركة.''';
    final raw = await _callGemini(prompt, history: history, temperature: 0.0);
    final ids = _parseIntList(raw, 'ids');
    return [for (final i in ids) if (i >= 0 && i < limited.length) limited[i]].take(8).toList();
  }

  Future<String> _answerFromLocalWithGemini(String question, String scope, List<Madda> sources, List<Map<String, String>> history) async {
    final sourceText = sources.map((m) => 'القانون: ${m.lawName ?? 'القوانين اليمنية'}\nالمادة: ${m.number}\nالنص: ${m.body}').join('\n\n');
    final prompt = '''أجب عن السؤال القانوني باستخدام المصادر التالية فقط إذا كانت ذات صلة.
السؤال: $question
نطاق البحث: $scope

المصادر:
$sourceText

اشرح بالعربية الواضحة. ميّز بين النص القانوني وأي شرح. لا تخترع مادة أو رقم مادة أو نصاً غير موجود في المصادر.
لا تستخدم Markdown مثل ### أو **. لا تذكر أنك نموذج ذكاء اصطناعي.''';
    return _stripMarkdown(await _callGemini(prompt, history: history, temperature: 0.0));
  }

  Future<String> _answerFromGeminiKnowledge(String question, String scope, List<Map<String, String>> history) async {
    final prompt = '''أجب عن السؤال القانوني التالي اعتماداً على معرفتك القانونية، مع مراعاة أن المطلوب هو القانون اليمني ما لم يحدد المستخدم غير ذلك.
السؤال: $question
نطاق البحث: $scope

إذا كان النطاق قانوناً محدداً، التزم به. إذا لم تكن متأكداً من نص أو رقم مادة فلا تخترعه، واذكر بوضوح أن المعلومة تحتاج إلى التحقق من النص الأصلي.
اكتب بالعربية الواضحة وبدون Markdown مثل ### أو **.''';
    return _stripMarkdown(await _callGemini(prompt, history: history, temperature: 0.0));
  }

  Future<_GeminiReview> _reviewFinalAnswerWithGemini(String question, String scope, String answer, List<Madda> sources, List<Map<String, String>> history) async {
    final sourceText = sources.isEmpty ? 'لا توجد مصادر محلية مرسلة.' : sources.map((m) => 'القانون: ${m.lawName ?? 'القوانين اليمنية'} | المادة: ${m.number}\n${m.body}').join('\n\n');
    final prompt = '''راجع الإجابة قبل إرسالها للمستخدم.
السؤال: $question
النطاق: $scope
الإجابة:
$answer

المصادر المحلية:
$sourceText

match=true فقط إذا كانت الإجابة مرتبطة مباشرة بالسؤال وتحترم النطاق. إذا كانت الإجابة تحتوي ادعاءً قانونياً غير مسند إلى المصادر المحلية، فلا ترفضها تلقائياً إذا كان المسار من معرفة Gemini، لكن ارفض الإجابة إذا كانت غير مرتبطة بالسؤال أو خرجت عن القانون المطلوب أو اخترعت نصاً محدداً بلا أساس.
أعد JSON فقط:
{"match":true,"reason":"..."}''';
    return _parseReview(await _callGemini(prompt, history: history, temperature: 0.0));
  }

  Future<String> _callGemini(String prompt, {List<Map<String, String>> history = const [], double temperature = 0.0}) async {
    final model = AppConfig.geminiModel.trim().isEmpty ? 'gemini-3.5-flash-lite' : AppConfig.geminiModel.trim();
    final uri = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=${Uri.encodeQueryComponent(AppConfig.geminiApiKey.trim())}');
    final contents = <Map<String, dynamic>>[];
    for (final item in history.take(8)) {
      final role = item['role'] == 'assistant' ? 'model' : 'user';
      final text = item['content']?.trim() ?? '';
      if (text.isNotEmpty) contents.add({'role': role, 'parts': [{'text': text}]});
    }
    contents.add({'role': 'user', 'parts': [{'text': prompt}]});

    final response = await http.post(uri, headers: {'Content-Type': 'application/json'}, body: jsonEncode({
      'contents': contents,
      'generationConfig': {'temperature': temperature, 'responseMimeType': 'text/plain'},
    })).timeout(const Duration(seconds: 45));

    if (response.statusCode < 200 || response.statusCode >= 300) throw LegalAiException(_apiError(response.statusCode, response.body));
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = data['candidates'] as List<dynamic>? ?? const [];
    if (candidates.isEmpty) throw const LegalAiException('لم يُرجع Gemini إجابة.');
    final content = candidates.first['content'] as Map<String, dynamic>?;
    final parts = content?['parts'] as List<dynamic>? ?? const [];
    final text = parts.map((p) => (p as Map<String, dynamic>)['text']?.toString() ?? '').join().trim();
    if (text.isEmpty) throw const LegalAiException('أعاد Gemini استجابة فارغة.');
    return text;
  }

  _SearchPlan _parseSearchPlan(String raw) {
    final json = _extractJson(raw);
    if (json is Map<String, dynamic>) {
      final values = (json['queries'] as List<dynamic>?)?.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList() ?? const <String>[];
      if (values.isNotEmpty) return _SearchPlan(values);
    }
    return _SearchPlan([raw.replaceAll(RegExp(r'[{}\[\]"]'), ' ').trim()]);
  }

  List<int> _parseIntList(String raw, String key) {
    final json = _extractJson(raw);
    if (json is Map<String, dynamic>) return (json[key] as List<dynamic>?)?.map((e) => int.tryParse(e.toString())).whereType<int>().toList() ?? const [];
    return const [];
  }

  _GeminiReview _parseReview(String raw) {
    final json = _extractJson(raw);
    if (json is Map<String, dynamic>) return _GeminiReview(json['match'] == true, (json['reason'] ?? '').toString());
    final normalized = raw.toLowerCase();
    return _GeminiReview(normalized.contains('"match":true') || normalized.contains('"match": true'), raw);
  }

  dynamic _extractJson(String raw) {
    var value = raw.trim();
    if (value.startsWith('```')) {
      value = value.replaceFirst(RegExp(r'^```(?:json)?\s*'), '').replaceFirst(RegExp(r'\s*```$'), '').trim();
    }
    try { return jsonDecode(value); } catch (_) {}
    final start = value.indexOf('{');
    final end = value.lastIndexOf('}');
    if (start >= 0 && end > start) {
      try { return jsonDecode(value.substring(start, end + 1)); } catch (_) {}
    }
    return null;
  }

  String _normalize(String s) => s.toLowerCase().replaceAll(RegExp(r'[ً-ٟ]'), '').replaceAll(RegExp(r'[إأآٱ]'), 'ا').replaceAll('ى', 'ي').replaceAll('ة', 'ه').replaceAll('ـ', '').trim();
  String _stripMarkdown(String value) => value.replaceAll(RegExp(r'#{1,6}\s*'), '').replaceAll('**', '').replaceAll('__', '').replaceAll('`', '').trim();

  String _apiError(int status, String body) {
    try {
      final data = jsonDecode(body) as Map<String, dynamic>;
      final message = ((data['error'] as Map<String, dynamic>?)?['message'] ?? '').toString();
      if (message.isNotEmpty) return 'تعذر الاتصال بـ Gemini: $message';
    } catch (_) {}
    return 'تعذر الاتصال بـ Gemini (HTTP $status).';
  }

  Future<void> _saveHistory(String question, String answer, String source) async {
    try { await _historyDb.addSearch(query: question, response: answer, source: source); } catch (_) {}
  }
}

class _SearchPlan {
  final List<String> queries;
  const _SearchPlan(this.queries);
}

class _GeminiReview {
  final bool isMatch;
  final String reason;
  const _GeminiReview(this.isMatch, this.reason);
}
