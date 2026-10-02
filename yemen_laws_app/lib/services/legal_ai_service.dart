import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/app_config.dart';
import '../data/models/law.dart';
import '../data/models/madda.dart';
import '../data/repositories/laws_repository.dart';
import 'chat_history_db.dart';

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

  factory LegalAiSource.fromMadda(Madda m) => LegalAiSource(
    id: m.id,
    articleNumber: m.number,
    lawName: m.lawName?.trim().isNotEmpty == true ? m.lawName!.trim() : 'القوانين اليمنية',
    body: m.body,
    babLabel: m.babLabel,
    faslLabel: m.faslLabel,
  );

  factory LegalAiSource.fromJson(Map<String, dynamic> json) {
    final id = (json['article_id'] as num?)?.toInt() ?? (json['id'] as num?)?.toInt() ?? 0;
    final lawName = (json['law_name'] ?? json['law'] ?? 'القوانين اليمنية').toString().trim();
    final articleNumber = (json['article_number'] ?? json['number'] ?? '').toString().trim();
    final body = (json['article_text'] ?? json['body'] ?? '').toString();
    return LegalAiSource(
      id: id,
      articleNumber: articleNumber,
      lawName: lawName.isEmpty ? 'القوانين اليمنية' : lawName,
      body: body,
      babLabel: json['bab_label']?.toString(),
      faslLabel: json['fasl_label']?.toString(),
    );
  }

  int get articleId => id;
  String get articleText => body;
  String get reference => '$lawName — المادة $articleNumber';
}

class LegalAiService {
  static final LegalAiService instance = LegalAiService();

  final LawsRepository _lawsRepository;
  final ChatHistoryDb _historyDb;

  LegalAiService({LawsRepository? lawsRepository, ChatHistoryDb? historyDb})
      : _lawsRepository = lawsRepository ?? LawsRepository.instance,
        _historyDb = historyDb ?? ChatHistoryDb.instance;

  Future<LegalAiResult> ask({required String question, String? conversationId, List<Map<String, String>> history = const []}) async {
    final trimmed = question.trim();
    if (trimmed.isEmpty) throw const LegalAiException('اكتب سؤالك القانوني أولاً.');

    if (AppConfig.geminiApiKey.trim().isEmpty) {
      final local = await _lawsRepository.searchForLegalAssistant(trimmed);
      final answer = local.isEmpty ? 'لم أجد مادة مرتبطة مباشرة بسؤالك في قاعدة القوانين المحلية.' : _buildLocalAnswer(local);
      await _saveHistorySafely(query: trimmed, response: answer, source: 'local_db');
      return LegalAiResult(answer: answer, sources: local.map(LegalAiSource.fromMadda).toList(), conversationId: conversationId, responseSource: 'local_db');
    }

    final plan = await _planLegalQuery(trimmed);
    final localMatches = await _refinedLocalSearch(trimmed, plan);
    final result = await _askGemini(question: trimmed, conversationId: conversationId, history: history, localMatches: localMatches, queryPlan: plan);
    await _saveHistorySafely(query: trimmed, response: result.answer, source: result.responseSource);
    return result;
  }

  Future<_LegalQueryPlan> _planLegalQuery(String question) async {
    final text = await _callGeminiText(
      systemInstruction: '''أنت محلل لاستفسارات قانونية يمنية. لا تجب عن السؤال. حدد الموضوع القانوني والقانون اليمني الأكثر صلة، ثم أعد JSON فقط في هذا الشكل: {"topic":"...","law":"...","search_terms":["..."]}.''',
      userText: question,
    );
    final json = _extractJsonObject(text);
    if (json == null) return _LegalQueryPlan(topic: question, lawHint: '', searchTerms: _fallbackSearchTerms(question));
    final topic = (json['topic'] ?? '').toString().trim();
    final law = (json['law'] ?? '').toString().trim();
    final rawTerms = json['search_terms'];
    final terms = <String>[];
    if (rawTerms is List) for (final item in rawTerms) { final value = item.toString().trim(); if (value.isNotEmpty) terms.add(value); }
    if (terms.isEmpty) terms.addAll(_fallbackSearchTerms(topic.isEmpty ? question : topic));
    return _LegalQueryPlan(topic: topic.isEmpty ? question : topic, lawHint: law, searchTerms: terms.take(10).toList());
  }

  Future<List<Madda>> _refinedLocalSearch(String question, _LegalQueryPlan plan) async {
    final laws = await _lawsRepository.getAllLaws();
    final law = _findLaw(laws, plan.lawHint);
    final lawId = law?.id;
    final candidates = <Madda>[];
    final seen = <int>{};
    Future<void> addResults(String term) async {
      if (term.trim().isEmpty) return;
      try { final rows = await _lawsRepository.search(term, lawId: lawId, limit: 12); for (final row in rows) { if (seen.add(row.id)) candidates.add(row); } } catch (_) {}
    }
    for (final term in plan.searchTerms) { await addResults(term); if (candidates.length >= 24) break; }
    if (candidates.isEmpty && lawId != null) await addResults(plan.topic);
    if (candidates.isEmpty && lawId == null) for (final term in plan.searchTerms.take(5)) { try { final rows = await _lawsRepository.search(term, limit: 12); for (final row in rows) { if (seen.add(row.id)) candidates.add(row); } } catch (_) {} }
    if (candidates.isEmpty) return [];
    return _filterAndRankWithGemini(question, plan, candidates);
  }

  Future<List<Madda>> _filterAndRankWithGemini(String question, _LegalQueryPlan plan, List<Madda> candidates) async {
    final context = _buildLocalContext(candidates.take(24).toList());
    final text = await _callGeminiText(
      systemInstruction: '''أنت مراجع نتائج البحث القانوني في موسوعة القوانين اليمنية. لا تجب عن سؤال المستخدم. راجع المواد المعطاة ثم أعد JSON فقط في الشكل {"relevant_article_numbers":["..."]}.''',
      userText: 'السؤال: $question\nالموضوع: ${plan.topic}\nالقانون المرشح: ${plan.lawHint}\n\nالمواد المرشحة:\n$context',
    );
    final json = _extractJsonObject(text);
    if (json == null) return _rankLocally(candidates, plan);
    final raw = json['relevant_article_numbers'];
    if (raw is! List) return _rankLocally(candidates, plan);
    final numbers = raw.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toSet();
    final filtered = candidates.where((m) => numbers.contains(m.number.trim())).toList();
    if (filtered.isEmpty) return [];
    return filtered.take(8).toList();
  }

  List<Madda> _rankLocally(List<Madda> candidates, _LegalQueryPlan plan) {
    final terms = plan.searchTerms.map(_normalize).where((e) => e.isNotEmpty).toList();
    final scored = <MapEntry<Madda, int>>[];
    for (final m in candidates) {
      final haystack = _normalize('${m.lawName ?? ''} ${m.number} ${m.babLabel ?? ''} ${m.faslLabel ?? ''} ${m.body}');
      var score = 0;
      for (final term in terms) { if (haystack.contains(term)) score += term.length >= 4 ? 2 : 1; }
      scored.add(MapEntry(m, score));
    }
    scored.sort((a, b) => b.value.compareTo(a.value));
    return scored.where((e) => e.value > 0).map((e) => e.key).take(8).toList();
  }

  Law? _findLaw(List<Law> laws, String hint) {
    final normalizedHint = _normalize(hint);
    if (normalizedHint.isEmpty) return null;
    for (final law in laws) { final name = _normalize(law.name); if (name == normalizedHint || name.contains(normalizedHint) || normalizedHint.contains(name)) return law; }
    return null;
  }

  List<String> _fallbackSearchTerms(String input) => input.split(RegExp(r'\s+')).map(_normalize).where((term) => term.length >= 3 && !_assistantStopWords.contains(term)).take(8).toList();

  String _normalize(String value) => value.toLowerCase().replaceAll(RegExp(r'[ً-ٟ]'), '').replaceAll(RegExp(r'[إأآٱ]'), 'ا').replaceAll('ى', 'ي').replaceAll('ة', 'ه').replaceAll('ـ', '').replaceAll(RegExp(r'[^\p{L}\p{N}\s]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

  Map<String, dynamic>? _extractJsonObject(String text) {
    var value = text.trim();
    if (value.startsWith('```')) { value = value.replaceFirst(RegExp(r'^```(?:json)?\s*'), ''); value = value.replaceFirst(RegExp(r'\s*```$'), ''); }
    try { final decoded = jsonDecode(value); return decoded is Map<String, dynamic> ? decoded : null; } catch (_) {}
    final start = value.indexOf('{'); final end = value.lastIndexOf('}');
    if (start >= 0 && end > start) { try { final decoded = jsonDecode(value.substring(start, end + 1)); return decoded is Map<String, dynamic> ? decoded : null; } catch (_) {} }
    return null;
  }

  Future<String> _callGeminiText({required String systemInstruction, required String userText}) async {
    final model = AppConfig.geminiModel.trim().isEmpty ? 'gemini-3.5-flash-lite' : AppConfig.geminiModel.trim();
    final uri = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent');
    http.Response? response; Map<String, dynamic> body = {};
    const retryDelays = <int>[2, 4, 6];
    for (var attempt = 0; attempt <= retryDelays.length; attempt++) {
      if (attempt > 0) await Future<void>.delayed(Duration(seconds: retryDelays[attempt - 1]));
      try {
        response = await http.post(
          uri,
          headers: {'Content-Type': 'application/json', 'Accept': 'application/json', 'x-goog-api-key': AppConfig.geminiApiKey.trim()},
          body: jsonEncode({'systemInstruction': systemInstruction, 'contents': [{'role': 'user', 'parts': [{'text': userText}]}]}),
        );
        body = {}; try { body = jsonDecode(response.body) as Map<String, dynamic>; } catch (_) {}
        if (response.statusCode == 200) break;
        if (!_isTemporaryGeminiFailure(response.statusCode, body) || attempt == retryDelays.length) { final apiMessage = _extractApiError(body); final isQuotaExceeded = _isGeminiQuotaExceeded(response.statusCode, body); if (apiMessage != null) { throw LegalAiException(isQuotaExceeded ? 'تجاوزت الحد المسموح من Gemini، حاول لاحقاً.' : apiMessage); } throw const LegalAiException('تعذر الاتصال بالمساعد الذكي.'); }
      } catch (e) {
        if (e is LegalAiException) rethrow;
        if (attempt == retryDelays.length) throw const LegalAiException('تعذر الاتصال بالمساعد الذكي. تحقق من اتصال الإنترنت أو مفتاح Gemini.');
      }
    }
    if (response == null || response.statusCode != 200) throw const LegalAiException('الخدمة مشغولة حالياً. حاول مرة أخرى لاحقاً.');
    final answer = _extractGeneratedText(body); if (answer.isEmpty) throw const LegalAiException('تعذر توليد إجابة من المساعد الذكي.'); return answer;
  }

  String _buildLocalAnswer(List<Madda> matches) {
    if (matches.length == 1) { final m = matches.first; final law = m.lawName?.trim(); final lawText = law == null || law.isEmpty ? '' : ' — $law'; return 'وجدت في قاعدة القوانين المحلية مادة مرتبطة بسؤالك${lawText}:\n\nالمادة ${m.number}\n${m.body}'; }
    final buffer = StringBuffer('وجدت ${matches.length} مواد مرتبطة بسؤالك في قاعدة القوانين المحلية:\n');
    for (var i = 0; i < matches.length; i++) { final m = matches[i]; final law = m.lawName?.trim(); buffer..write('\n${i + 1}. المادة (${m.number})')..write(law == null || law.isEmpty ? '' : ' — $law')..write('\n${m.body}'); }
    return buffer.toString().trim();
  }

  Future<LegalAiResult> _askGemini({required String question, String? conversationId, required List<Map<String, String>> history, required List<Madda> localMatches, required _LegalQueryPlan queryPlan}) async {
    final model = AppConfig.geminiModel.trim().isEmpty ? 'gemini-3.5-flash-lite' : AppConfig.geminiModel.trim();
    final uri = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent');
    final contents = <Map<String, dynamic>>[];
    for (final item in history) { final role = item['role'] == 'assistant' ? 'model' : 'user'; final content = item['content']?.trim() ?? ''; if (content.isEmpty) continue; contents.add({'role': role, 'parts': [{'text': content}]}); }
    final localContext = _buildLocalContext(localMatches);
    contents.add({'role': 'user', 'parts': [{'text': 'السؤال:\n$question\n\nخطة البحث القانونية:\nالموضوع: ${queryPlan.topic}\nالقانون المرشح: ${queryPlan.lawHint}\n\nالمواد المحلية:\n$localContext'}]});
    http.Response? response; Map<String, dynamic> body = {};
    const retryDelays = <int>[2, 4, 6];
    for (var attempt = 0; attempt <= retryDelays.length; attempt++) {
      if (attempt > 0) await Future<void>.delayed(Duration(seconds: retryDelays[attempt - 1]));
      try {
        response = await http.post(
          uri,
          headers: {'Content-Type': 'application/json', 'Accept': 'application/json', 'x-goog-api-key': AppConfig.geminiApiKey.trim()},
          body: jsonEncode({'contents': contents}),
        );
        body = {}; try { body = jsonDecode(response.body) as Map<String, dynamic>; } catch (_) {}
        if (response.statusCode == 200) break;
        if (!_isTemporaryGeminiFailure(response.statusCode, body) || attempt == retryDelays.length) { final apiMessage = _extractApiError(body); final isQuotaExceeded = _isGeminiQuotaExceeded(response.statusCode, body); if (apiMessage != null) { throw LegalAiException(isQuotaExceeded ? 'تجاوزت الحد المسموح من Gemini، حاول لاحقاً.' : apiMessage); } throw const LegalAiException('تعذر الاتصال بالمساعد الذكي.'); }
      } catch (e) { if (e is LegalAiException) rethrow; if (attempt == retryDelays.length) throw const LegalAiException('تعذر الاتصال بالمساعد الذكي. تحقق من اتصال الإنترنت أو مفتاح Gemini.'); }
    }
    if (response == null || response.statusCode != 200) throw const LegalAiException('الخدمة مشغولة حالياً. حاول مرة أخرى لاحقاً.');
    final answer = _extractGeneratedText(body); if (answer.isEmpty) throw const LegalAiException('تعذر توليد إجابة من المساعد الذكي.');
    return LegalAiResult(answer: answer, sources: localMatches.map(LegalAiSource.fromMadda).toList(), conversationId: conversationId, responseSource: localMatches.isEmpty ? 'gemini_ai' : 'local_db');
  }

  String _buildLocalContext(List<Madda> matches) {
    if (matches.isEmpty) return '';
    final buffer = StringBuffer();
    for (var i = 0; i < matches.length; i++) { final m = matches[i]; buffer..writeln('[المصدر ${i + 1}]')..writeln('القانون: ${m.lawName?.trim().isNotEmpty == true ? m.lawName!.trim() : 'القوانين اليمنية'}')..writeln('المادة: ${m.number}')..writeln(m.body)..writeln(); }
    return buffer.toString().trim();
  }

  String _extractGeneratedText(Map<String, dynamic> body) { final candidates = body['candidates']; if (candidates is! List || candidates.isEmpty) return ''; final content = candidates.first is Map ? (candidates.first as Map<String, dynamic>)['content'] : null; if (content is! Map) return ''; final parts = content['parts']; if (parts is! List || parts.isEmpty) return ''; final text = parts.first is Map ? (parts.first as Map<String, dynamic>)['text'] : null; return text?.toString() ?? ''; }
  bool _isTemporaryGeminiFailure(int statusCode, Map<String, dynamic> body) { final message = _extractApiError(body)?.toLowerCase() ?? ''; if (statusCode == 429) { final quotaExceeded = message.contains('quota') || message.contains('limit'); return quotaExceeded || message.contains('rate limit') || message.contains('too many requests'); } return statusCode == 500 || statusCode == 502 || statusCode == 503 || statusCode == 504 || message.contains('temporar') || message.contains('overloaded') || message.contains('unavailable'); }
  bool _isGeminiQuotaExceeded(int statusCode, Map<String, dynamic> body) { if (statusCode == 429) { final message = _extractApiError(body)?.toLowerCase() ?? ''; return message.contains('quota') || message.contains('limit'); } return false; }
  String? _extractApiError(Map<String, dynamic> body) { final error = body['error']; if (error is Map && error['message'] != null) return error['message'].toString(); return null; }
  Future<void> _saveHistorySafely({required String query, required String response, required String source}) async { try { await _historyDb.addSearch(query: query, response: response, source: source); } catch (_) {} }
  String _status(int statusCode) { if (statusCode == 400) return 'تعذر فهم طلب المساعد. حاول صياغة السؤال بطريقة أخرى.'; if (statusCode == 401 || statusCode == 403) return 'مفتاح Gemini غير صالح أو منتهي الصلاحية.'; if (statusCode == 429) return 'وصلت إلى الحد المسموح من طلبات Gemini.'; if (statusCode >= 500) return 'الخدمة غير متاحة حالياً.'; return 'تعذر الوصول إلى المساعد الذكي.'; }

  static const Set<String> _assistantStopWords = {
    'ما', 'ماذا', 'هل', 'هو', 'هي', 'هذا', 'هذه', 'ذلك', 'تلك', 'من', 'في',
    'فيه', 'عن', 'على', 'الى', 'إلى', 'مع', 'لي', 'لدي', 'اريد', 'أريد',
    'يمكن', 'كيف', 'متى', 'أين', 'اين', 'جميع', 'ماهي',
  };
}

class _LegalQueryPlan { final String topic; final String lawHint; final List<String> searchTerms; const _LegalQueryPlan({required this.topic, required this.lawHint, required this.searchTerms}); }
class LegalAiException implements Exception { final String message; const LegalAiException(this.message); @override String toString() => message; }
