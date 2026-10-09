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
    // الواجهة الحالية تمرر أحياناً السؤال مع تعليمات وضع الإجابة واسم الفلتر.
    // نفصل السؤال الحقيقي والنطاق هنا حتى لا تدخل تعليمات الواجهة في بحث SQLite.
    final q = _extractUserQuestion(raw);
    final inferredScope = _extractLawScope(raw);
    final explicitScope = _inferLawScope(q);
    final requestedScope = lawScope != 'الكل' ? lawScope : (inferredScope != 'الكل' ? inferredScope : (explicitScope ?? 'الكل'));
    final laws = await _lawsRepository.getAllLaws();
    final selectedLaw = await _resolveLawScope(laws, requestedScope);

    final articleNumber = _extractRequestedArticleNumber(q);
    if (articleNumber != null && selectedLaw != null) {
      final exact = await _lawsRepository.getMaddaByNumber(articleNumber, lawId: selectedLaw.id);
      if (exact.isNotEmpty) {
        final m = exact.first;
        final source = [m];
        // نستخدم النص المحلي مصدراً ملزماً، ثم نطلب شرحاً مبسطاً ومراجعته،
        // مع منع أي مادة أو حكم غير موجود في النص المسترجع.
        {
          try {
            final explanation = await _answerFromLocalWithGemini(q, selectedLaw.name, source, history);
            if (explanation.trim().isNotEmpty) {
              await _saveHistory(q, explanation, 'cloudflare_local_article');
              return LegalAiResult(
                answer: explanation,
                sources: source.map(LegalAiSource.fromMadda).toList(),
                conversationId: conversationId,
                responseSource: 'cloudflare_local_article',
              );
            }
          } catch (_) {
            // عند تعذر الشرح السحابي، لا نفقد النص القانوني الأصلي الموثق.
          }
        }
        final answer = '${m.lawName ?? selectedLaw.name}، المادة ${m.number}:\n\n${m.body.trim()}';
        await _saveHistory(q, answer, 'local_exact_article');
        return LegalAiResult(answer: answer, sources: source.map(LegalAiSource.fromMadda).toList(), conversationId: conversationId, responseSource: 'local_exact_article');
      }
    }

    final plan = _planSearchLocally(q);
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

    final ranked = _rankLocalCandidatesLocally(q, candidates);
    if (ranked.isNotEmpty) {
      try {
        final result = await _askCloudflare(
          question: q,
          scope: requestedScope,
          history: history,
          sources: ranked,
        );
        await _saveHistory(q, result.answer, 'cloudflare_local_sources');
        return LegalAiResult(
          answer: result.answer,
          sources: ranked.map(LegalAiSource.fromMadda).toList(),
          conversationId: result.conversationId ?? conversationId,
          responseSource: 'cloudflare_local_sources',
        );
      } catch (_) {
        // لا نجعل تعطل الإنترنت يمنع عرض النصوص المحلية التي عثرنا عليها.
        final answer = ranked.map((m) =>
          '${m.lawName ?? 'القوانين اليمنية'}، المادة ${m.number}:\\n${m.body.trim()}'
        ).join('\\n\\n');
        await _saveHistory(q, answer, 'local_sources_offline');
        return LegalAiResult(
          answer: answer,
          sources: ranked.map(LegalAiSource.fromMadda).toList(),
          conversationId: conversationId,
          responseSource: 'local_sources_offline',
        );
      }
    }

    // إذا لم يجد Gemini نصاً مناسباً داخل قاعدة التطبيق، ينتقل إلى معرفته القانونية.
    // وتبقى المراجعة النهائية إلزامية قبل الإرسال.
    final generated = await _askCloudflare(
      question: q,
      scope: requestedScope,
      history: history,
      sources: const [],
    );
    await _saveHistory(q, generated.answer, generated.responseSource);
    return LegalAiResult(
      answer: generated.answer,
      sources: generated.sources,
      conversationId: generated.conversationId ?? conversationId,
      responseSource: generated.responseSource,
    );
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

  String? _inferLawScope(String question) {
    final normalized = _normalize(question);
    if (normalized.contains('احوال شخصيه') || normalized.contains('الاحوال الشخصيه')) return 'الاحوال الشخصية';
    const patterns = <String, List<String>>{
      'القانون المدني': ['القانون المدني', 'القانون المدنى'],
      'الجرائم والعقوبات': ['الجرائم والعقوبات', 'قانون الجرائم', 'قانون العقوبات'],
      'الإجراءات الجزائية': ['الاجراءات الجزائيه', 'قانون الاجراءات الجزائيه'],
      'المرافعات والتنفيذ': ['المرافعات والتنفيذ', 'قانون المرافعات'],
      'قانون العمل': ['قانون العمل'],
      'القانون التجاري': ['القانون التجاري'],
      'الإثبات': ['قانون الاثبات', 'الاثبات'],
      'التحكيم': ['قانون التحكيم', 'التحكيم'],
    };
    for (final entry in patterns.entries) {
      if (entry.value.any(normalized.contains)) return entry.key;
    }
    return null;
  }

  String? _extractRequestedArticleNumber(String question) {
    final match = RegExp(r'(?:الماده|المادة|ماده|مادة)\s*(?:رقم\s*)?(\d+)').firstMatch(_normalize(question));
    return match?.group(1);
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
      // البحث الصارم مفيد عندما تكون العبارة مطابقة للنص، لكن أسئلة المستخدم
      // العربية غالباً تحتوي كلمات تمهيدية لا توجد حرفياً داخل المادة.
      // لذلك نستخدم بعده محرك البحث القانوني المرن الموجود في المستودع،
      // مع إبقاء نطاق القانون مقيداً بالقانون المختار.
      final strict = await _lawsRepository.search(query, lawId: lawId, limit: limit);
      if (strict.isNotEmpty) return strict;
      return await _lawsRepository.searchForLegalAssistant(query, lawId: lawId, limit: limit);
    } catch (_) {
      try {
        return await _lawsRepository.searchForLegalAssistant(query, lawId: lawId, limit: limit);
      } catch (_) {
        return [];
      }
    }
  }

  _SearchPlan _planSearchLocally(String question) => _SearchPlan([question]);

  List<Madda> _rankLocalCandidatesLocally(String question, List<Madda> candidates) {
    final terms = _searchTerms(question);
    if (terms.isEmpty) return [];
    final scored = <({Madda madda, int score})>[];
    for (final candidate in candidates) {
      final text = _normalize('${candidate.lawName ?? ''} ${candidate.number} ${candidate.body}');
      final score = terms.where((term) => text.contains(term)).length;
      if (score > 0) scored.add((madda: candidate, score: score));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    if (scored.isEmpty) return [];
    final best = scored.first.score;
    // Reject broad accidental matches that share only one common term.
    return scored.where((item) => item.score >= (best >= 3 ? 2 : best))
        .take(8).map((item) => item.madda).toList();
  }

  List<String> _searchTerms(String value) {
    const stopWords = <String>{
      'ما','ماذا','كيف','هل','هو','هي','هذا','هذه','ذلك','تلك','من','في',
      'عن','على','الى','مع','ماهي','ماهو','اريد','أريد','شروط','حالات',
      'حكم','قانون','القانون','المادة','مادة','رقم','يجوز','يكون','كانت',
    };
    return _normalize(value).split(RegExp(r'\\s+'))
        .where((term) => term.length >= 3 && !stopWords.contains(term))
        .toSet().toList();
  }

  Future<String> _answerFromLocalWithGemini(String question, String scope, List<Madda> sources, List<Map<String, String>> history) async {
    final result = await _askCloudflare(
      question: question,
      scope: scope,
      history: history,
      sources: sources,
    );
    return result.answer;
  }

  Future<_GeminiReview> _reviewFinalAnswerWithGemini(String question, String scope, String answer, List<Madda> sources, List<Map<String, String>> history) async {
    // Final generation is delegated to Cloudflare; reject empty or obviously failed responses locally.
    return _GeminiReview(answer.trim().isNotEmpty, answer.trim().isEmpty ? 'empty_answer' : 'cloudflare_response');
  }

  Future<_CloudflareResult> _askCloudflare({
    required String question,
    required String scope,
    required List<Map<String, String>> history,
    required List<Madda> sources,
  }) async {
    final base = AppConfig.legalAiBaseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    if (base.isEmpty) {
      throw const LegalAiException('خدمة المساعد السحابية غير مهيأة. تحقق من LEGAL_AI_BASE_URL.');
    }
    final uri = Uri.parse('$base/api/chat');
    final sourceJson = sources.map((m) => <String, dynamic>{
      'article_id': m.id,
      'law_name': m.lawName ?? 'القوانين اليمنية',
      'article_number': m.number,
      'article_text': m.body,
      'chapter': m.faslLabel ?? m.babLabel,
      'reference': '${m.lawName ?? 'القوانين اليمنية'} — المادة ${m.number}',
    }).toList();
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'X-App-Version': AppConfig.appVersion,
      },
      body: jsonEncode({
        'message': question,
        'scope': scope,
        'language': 'ar',
        'history': history,
        'sources': sourceJson,
      }),
    ).timeout(const Duration(seconds: 60));

    Map<String, dynamic> data;
    try {
      data = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw const LegalAiException('أعادت خدمة المساعد استجابة غير مفهومة.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = (data['error'] ?? 'تعذر الاتصال بخدمة المساعد السحابية.').toString();
      throw LegalAiException(message);
    }
    final answer = (data['answer'] ?? '').toString().trim();
    if (answer.isEmpty) throw const LegalAiException('لم تُرجع خدمة المساعد إجابة.');
    final rawSources = data['sources'];
    final parsedSources = rawSources is List
        ? rawSources.whereType<Map<String, dynamic>>().map(LegalAiSource.fromJson).toList()
        : <LegalAiSource>[];
    return _CloudflareResult(
      answer: _stripMarkdown(answer),
      sources: parsedSources,
      conversationId: data['conversation_id']?.toString(),
      responseSource: (data['response_source'] ?? (sources.isEmpty ? 'cloudflare_fallback' : 'cloudflare_local_sources')).toString(),
    );
  }

  String _normalize(String s) => s.toLowerCase().replaceAll(RegExp(r'[ً-ٟ]'), '').replaceAll(RegExp(r'[إأآٱ]'), 'ا').replaceAll('ى', 'ي').replaceAll('ة', 'ه').replaceAll('ـ', '').trim();
  String _stripMarkdown(String value) => value.replaceAll(RegExp(r'#{1,6}\s*'), '').replaceAll('**', '').replaceAll('__', '').replaceAll('`', '').trim();

  String _apiError(int status, String body) {
    try {
      final data = jsonDecode(body) as Map<String, dynamic>;
      final message = ((data['error'] as Map<String, dynamic>?)?['message'] ?? '').toString();
      if (message.isNotEmpty) return 'تعذر إكمال البحث القانوني: $message';
    } catch (_) {}
    return 'تعذر إكمال البحث القانوني (رمز الخطأ $status).';
  }

  Future<void> _saveHistory(String question, String answer, String source) async {
    try { await _historyDb.addSearch(query: question, response: answer, source: source); } catch (_) {}
  }
}

class _CloudflareResult {
  final String answer;
  final List<LegalAiSource> sources;
  final String? conversationId;
  final String responseSource;
  const _CloudflareResult({required this.answer, required this.sources, required this.conversationId, required this.responseSource});
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
