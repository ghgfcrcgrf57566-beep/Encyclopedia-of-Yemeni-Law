import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/app_config.dart';
import '../data/models/law.dart';
import '../data/models/madda.dart';
import '../data/repositories/laws_repository.dart';
import 'chat_history_db.dart';

class LegalAiSource {
  final int articleId;
  final String lawName;
  final String articleNumber;
  final String articleText;
  final String? chapter;
  final double? score;
  final String? reference;

  const LegalAiSource({
    required this.articleId,
    required this.lawName,
    required this.articleNumber,
    required this.articleText,
    this.chapter,
    this.score,
    this.reference,
  });

  factory LegalAiSource.fromJson(Map<String, dynamic> json) {
    return LegalAiSource(
      articleId: (json['article_id'] as num?)?.toInt() ??
          (json['id'] as num?)?.toInt() ?? 0,
      lawName: (json['law_name'] ?? json['law_title'] ?? '').toString(),
      articleNumber: (json['article_number'] ?? '').toString(),
      articleText: (json['article_text'] ?? '').toString(),
      chapter: json['chapter']?.toString(),
      score: (json['score'] as num?)?.toDouble(),
      reference: json['reference']?.toString(),
    );
  }

  factory LegalAiSource.fromMadda(Madda madda) {
    final context = [
      if (madda.babLabel != null && madda.babLabel!.trim().isNotEmpty)
        madda.babLabel!.trim(),
      if (madda.faslLabel != null && madda.faslLabel!.trim().isNotEmpty)
        madda.faslLabel!.trim(),
    ].join(' - ');

    return LegalAiSource(
      articleId: madda.id,
      lawName: madda.lawName ?? 'القوانين اليمنية',
      articleNumber: madda.number,
      articleText: madda.body,
      reference: context.isEmpty ? null : context,
    );
  }
}

class LegalAiResult {
  final String answer;
  final List<LegalAiSource> sources;
  final String? conversationId;
  final String responseSource;

  const LegalAiResult({
    required this.answer,
    required this.sources,
    this.conversationId,
    required this.responseSource,
  });
}

class _LegalQueryPlan {
  final String topic;
  final String lawHint;
  final List<String> searchTerms;

  const _LegalQueryPlan({
    required this.topic,
    required this.lawHint,
    required this.searchTerms,
  });
}

class LegalAiService {
  LegalAiService._();

  static final instance = LegalAiService._();

  final ChatHistoryDb _historyDb = ChatHistoryDb.instance;
  final LawsRepository _lawsRepository = LawsRepository.instance;

  Future<LegalAiResult> ask({
    required String question,
    String? conversationId,
    List<Map<String, String>> history = const [],
  }) async {
    final q = question.trim();

    if (q.isEmpty) {
      throw const LegalAiException('يرجى كتابة السؤال أولاً.');
    }

    if (q.length > 1200) {
      throw const LegalAiException(
        'السؤال طويل جداً. اختصره إلى 1200 حرف كحد أقصى.',
      );
    }

    if (AppConfig.geminiApiKey.trim().isEmpty) {
      final localMatches = await _lawsRepository.searchForLegalAssistant(
        q,
        limit: 8,
      );
      if (localMatches.isNotEmpty) {
        final result = LegalAiResult(
          answer: _buildLocalAnswer(localMatches),
          sources: localMatches.map(LegalAiSource.fromMadda).toList(),
          conversationId: conversationId,
          responseSource: 'local_db',
        );
        await _saveHistorySafely(
          query: q,
          response: result.answer,
          source: result.responseSource,
        );
        return result;
      }

      throw const LegalAiException(
        'لم يتم إعداد مفتاح المساعد الذكي. ابنِ التطبيق باستخدام GEMINI_API_KEY.',
      );
    }

    try {
      final plan = await _planLegalQuery(q);
      final localMatches = await _refinedLocalSearch(q, plan);

      final result = await _askGemini(
        question: q,
        conversationId: conversationId,
        history: history,
        localMatches: localMatches,
        queryPlan: plan,
      );

      await _saveHistorySafely(
        query: q,
        response: result.answer,
        source: result.responseSource,
      );

      return result;
    } on LegalAiException {
      rethrow;
    } catch (_) {
      throw const LegalAiException(
        'تعذر الاتصال بالمساعد الذكي. تحقق من اتصال الإنترنت وحاول مرة أخرى.',
      );
    }
  }

  Future<_LegalQueryPlan> _planLegalQuery(String question) async {
    final text = await _callGeminiText(
      systemInstruction: '''
أنت محلل استعلامات قانونية لموسوعة القوانين اليمنية.
لا تجب عن سؤال المستخدم.
مهمتك تحويل السؤال إلى خطة بحث داخل قاعدة القوانين اليمنية المحلية.

حدد:
1. الموضوع القانوني الرئيسي.
2. القانون اليمني المحتمل أن يحكم الموضوع.
3. مصطلحات البحث القانونية المرتبطة بالموضوع.

قواعد مهمة:
- لا تخترع رقم مادة أو نصاً قانونياً.
- لا تعتمد على مواد خارجية.
- افهم المعنى القانوني للسؤال ولا تعتمد على التطابق الحرفي فقط.
- إذا كان السؤال عن الزواج أو الطلاق أو الخلع أو النفقة أو الحضانة أو النشوز أو المهر أو العدة أو النسب أو ال�[...] 
- لا تضع كلمات السؤال العامة مثل: ما، هي، جميع، حالات، ما هي ضمن مصطلحات البحث.
- استخدم مرادفات قانونية مفيدة للبحث.

أعد JSON صالحاً فقط بهذا الشكل:
{"topic":"...","law":"...","search_terms":["...","..."]}
''',
      userText: question,
    );

    final json = _extractJsonObject(text);
    if (json == null) {
      return _LegalQueryPlan(
        topic: question,
        lawHint: '',
        searchTerms: _fallbackSearchTerms(question),
      );
    }

    final topic = (json['topic'] ?? '').toString().trim();
    final law = (json['law'] ?? '').toString().trim();
    final rawTerms = json['search_terms'];
    final terms = <String>[];
    if (rawTerms is List) {
      for (final item in rawTerms) {
        final value = item.toString().trim();
        if (value.isNotEmpty) terms.add(value);
      }
    }

    if (terms.isEmpty) terms.addAll(_fallbackSearchTerms(topic.isEmpty ? question : topic));

    return _LegalQueryPlan(
      topic: topic.isEmpty ? question : topic,
      lawHint: law,
      searchTerms: terms.take(10).toList(),
    );
  }

  Future<List<Madda>> _refinedLocalSearch(
    String question,
    _LegalQueryPlan plan,
  ) async {
    final laws = await _lawsRepository.getAllLaws();
    final law = _findLaw(laws, plan.lawHint);
    final lawId = law?.id;

    final candidates = <Madda>[];
    final seen = <int>{};

    Future<void> addResults(String term) async {
      if (term.trim().isEmpty) return;
      try {
        final rows = await _lawsRepository.search(
          term,
          lawId: lawId,
          limit: 12,
        );
        for (final row in rows) {
          if (seen.add(row.id)) candidates.add(row);
        }
      } catch (_) {}
    }

    for (final term in plan.searchTerms) {
      await addResults(term);
      if (candidates.length >= 24) break;
    }

    if (candidates.isEmpty && lawId != null) {
      await addResults(plan.topic);
    }

    if (candidates.isEmpty && lawId == null) {
      for (final term in plan.searchTerms.take(5)) {
        try {
          final rows = await _lawsRepository.search(term, limit: 12);
          for (final row in rows) {
            if (seen.add(row.id)) candidates.add(row);
          }
        } catch (_) {}
        if (candidates.length >= 24) break;
      }
    }

    if (candidates.isEmpty) return [];

    return _filterAndRankWithGemini(question, plan, candidates);
  }

  Future<List<Madda>> _filterAndRankWithGemini(
    String question,
    _LegalQueryPlan plan,
    List<Madda> candidates,
  ) async {
    final context = _buildLocalContext(candidates.take(24).toList());
    final text = await _callGeminiText(
      systemInstruction: '''
أنت مراجع نتائج البحث القانوني في موسوعة القوانين اليمنية.
لا تجب عن سؤال المستخدم.
راجع المواد المحلية المرشحة وحدد المواد التي ترتبط مباشرة بموضوع السؤال.

القواعد:
- استبعد أي مادة غير مرتبطة بالموضوع القانوني.
- لا تعتبر تشابه كلمة واحدة دليلاً على الصلة.
- إذا كان السؤال من الأحوال الشخصية، فلا تقبل مواد الدستور أو القوانين الأخرى لمجرد وجود كلمات عامة مشتركة.
- لا تخترع مادة أو تعدل نص مادة.
- إذا كانت النتائج غير كافية، لا تحاول تعويض النقص بمعلومات من خارج المواد.

أعد JSON صالحاً فقط:
{"relevant_article_numbers":["1","2"],"sufficient":true}
''',
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
      for (final term in terms) {
        if (haystack.contains(term)) score += term.length >= 4 ? 2 : 1;
      }
      scored.add(MapEntry(m, score));
    }

    scored.sort((a, b) => b.value.compareTo(a.value));
    return scored.where((e) => e.value > 0).map((e) => e.key).take(8).toList();
  }

  Law? _findLaw(List<Law> laws, String hint) {
    final normalizedHint = _normalize(hint);
    if (normalizedHint.isEmpty) return null;

    for (final law in laws) {
      final name = _normalize(law.name);
      if (name == normalizedHint || name.contains(normalizedHint) || normalizedHint.contains(name)) {
        return law;
      }
    }
    return null;
  }

  List<String> _fallbackSearchTerms(String input) {
    final terms = input
        .split(RegExp(r'\s+'))
        .map(_normalize)
        .where((term) => term.length >= 3 && !_assistantStopWords.contains(term))
        .toList();
    return terms.take(8).toList();
  }

  String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[ً-ٟ]'), '')
        .replaceAll(RegExp(r'[إأآٱ]'), 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ة', 'ه')
        .replaceAll('ـ', '')
        .trim();
  }

  Map<String, dynamic>? _extractJsonObject(String text) {
    var value = text.trim();
    if (value.startsWith('```')) {
      value = value.replaceFirst(RegExp(r'^```(?:json)?\s*'), '');
      value = value.replaceFirst(RegExp(r'\s*```$'), '');
    }

    try {
      final decoded = jsonDecode(value);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {}

    final start = value.indexOf('{');
    final end = value.lastIndexOf('}');
    if (start >= 0 && end > start) {
      try {
        final decoded = jsonDecode(value.substring(start, end + 1));
        return decoded is Map<String, dynamic> ? decoded : null;
      } catch (_) {}
    }
    return null;
  }

  Future<String> _callGeminiText({
    required String systemInstruction,
    required String userText,
  }) async {
    final model = AppConfig.geminiModel.trim().isEmpty
        ? 'gemini-3.5-flash-lite'
        : AppConfig.geminiModel.trim();
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent',
    );

    http.Response? response;
    Map<String, dynamic> body = {};
    const retryDelays = <int>[2, 4, 6];

    for (var attempt = 0; attempt <= retryDelays.length; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(Duration(seconds: retryDelays[attempt - 1]));
      }

      try {
        response = await http
            .post(
              uri,
              headers: {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
                'x-goog-api-key': AppConfig.geminiApiKey.trim(),
              },
              body: jsonEncode({
                'systemInstruction': {
                  'parts': [
                    {'text': systemInstruction},
                  ],
                },
                'contents': [
                  {
                    'role': 'user',
                    'parts': [
                      {'text': userText},
                    ],
                  },
                ],
                'generationConfig': {'temperature': 0.1},
              }),
            )
            .timeout(const Duration(seconds: 45));

        body = {};
        try {
          body = jsonDecode(response.body) as Map<String, dynamic>;
        } catch (_) {}

        if (response.statusCode == 200) break;

        if (!_isTemporaryGeminiFailure(response.statusCode, body) || attempt == retryDelays.length) {
          final apiMessage = _extractApiError(body);
          final isQuotaExceeded = _isGeminiQuotaExceeded(response.statusCode, body);
          throw LegalAiException(
            isQuotaExceeded
                ? 'تم تجاوز الحد المتاح حالياً لخدمة المساعد. يرجى المحاولة لاحقاً.'
                : (apiMessage ?? _status(response.statusCode)),
          );
        }
      } catch (e) {
        if (e is LegalAiException) rethrow;
        if (attempt == retryDelays.length) {
          throw const LegalAiException(
            'تعذر الاتصال بالمساعد الذكي. تحقق من اتصال الإنترنت وحاول مرة أخرى.',
          );
        }
      }
    }

    if (response == null || response.statusCode != 200) {
      throw const LegalAiException(
        'الخدمة مشغولة حالياً. تمت إعادة المحاولة تلقائياً، ويرجى المحاولة بعد قليل إذا استمر الخطأ.',
      );
    }

    final answer = _extractGeneratedText(body);
    if (answer.isEmpty) {
      throw const LegalAiException('تعذر توليد إجابة من المساعد الذكي.');
    }
    return answer;
  }

  String _buildLocalAnswer(List<Madda> matches) {
    if (matches.length == 1) {
      final m = matches.first;
      final law = m.lawName?.trim();
      final lawText = law == null || law.isEmpty ? '' : ' — $law';
      return 'وجدت في قاعدة القوانين المحلية المادة (${m.number})$lawText:\n\n${m.body.trim()}';
    }

    final buffer = StringBuffer('وجدت ${matches.length} مواد مرتبطة بسؤالك في قاعدة القوانين المحلية:\n');
    for (var i = 0; i < matches.length; i++) {
      final m = matches[i];
      final law = m.lawName?.trim();
      buffer
        ..write('\n${i + 1}. المادة (${m.number})')
        ..write(law == null || law.isEmpty ? '' : ' — $law')
        ..write('\n${m.body.trim()}\n');
    }
    return buffer.toString().trim();
  }

  Future<LegalAiResult> _askGemini({
    required String question,
    String? conversationId,
    required List<Map<String, String>> history,
    required List<Madda> localMatches,
    required _LegalQueryPlan queryPlan,
  }) async {
    final model = AppConfig.geminiModel.trim().isEmpty
        ? 'gemini-3.5-flash-lite'
        : AppConfig.geminiModel.trim();

    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent',
    );

    final contents = <Map<String, dynamic>>[];
    for (final item in history) {
      final role = item['role'] == 'assistant' ? 'model' : 'user';
      final content = item['content']?.trim() ?? '';
      if (content.isEmpty) continue;
      contents.add({
        'role': role,
        'parts': [
          {'text': content},
        ],
      });
    }

    final localContext = _buildLocalContext(localMatches);
    contents.add({
      'role': 'user',
      'parts': [
        {
          'text': 'السؤال:\n$question\n\n'
              'خطة البحث القانونية:\nالموضوع: ${queryPlan.topic}\n'
              'القانون المرشح: ${queryPlan.lawHint}\n\n'
              'المواد القانونية المحلية التي تم تنقيحها والتحقق من صلتها:\n'
              '${localContext.isEmpty ? 'لا توجد مواد محلية مؤكدة الصلة.' : localContext}',
        },
      ],
    });

    const retryDelays = <int>[2, 4, 6];
    http.Response? response;
    Map<String, dynamic> body = {};

    for (var attempt = 0; attempt <= retryDelays.length; attempt++) {
      if (attempt > 0) await Future<void>.delayed(Duration(seconds: retryDelays[attempt - 1]));
      try {
        response = await http
            .post(
              uri,
              headers: {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
                'x-goog-api-key': AppConfig.geminiApiKey.trim(),
              },
              body: jsonEncode({
                'systemInstruction': {
                  'parts': [
                    {
                      'text': '''
أنت «المساعد القانوني الذكي» لموسوعة القوانين اليمنية.

دورك النهائي هو تحليل النصوص القانونية المحلية التي تم البحث عنها وتنقيحها، ثم صياغة إجابة دقيقة ومفهومة.

قواعد إلزامية:
- قاعدة القوانين اليمنية المحلية هي المصدر الأساسي للنص القانوني.
- لا تستشهد بأي مادة لمجرد وجودها في النتائج؛ استخدم فقط المواد التي تتعلق مباشرة بالسؤال.
- لا تخترع أي مادة أو رقم مادة أو نص قانوني.
- لا تغير نص المادة عند نقله.
- اذكر اسم القانون ورقم المادة عند الاستناد إليها.
- إذا كانت المواد المحلية غير كافية، قل ذلك بوضوح ولا تعوض النقص باختلاق نصوص.
- يمكنك شرح وتحليل النصوص، لكن يجب أن تميز بين النص القانوني وبين التحليل.
- لا تقدم الإجابة على أنها فتوى أو حكم قضائي ملزم.
- لا تذكر اسم مزود الذكاء الاصطناعي أو تفاصيل البنية التقنية.
- استخدم اسم «المساعد القانوني الذكي» فقط.

أسلوب الإجابة:
- ابدأ بتحية ودودة قصيرة.
- اشرح بلغة عربية واضحة ومفهومة.
- إذا كان السؤال يطلب «جميع» الحالات أو الشروط، فاستعرض جميع المواد المحلية ذات الصلة التي تم التحقق منها، �[...] 
- لا تستخدم Markdown.
- ممنوع استخدام # أو ## أو ### أو ** أو __ أو --- أو * أو - كتعداد زخرفي.
- استخدم عناوين نصية عادية مثل: النصوص القانونية:، التحليل:، النتيجة:، تنبيه:.
- يمكن استخدام ترقيم عربي بسيط عند الحاجة.
- اختم باقتراح أو سؤال قصير متعلق بالاستفسار.
''',
                    },
                  ],
                },
                'contents': contents,
                'generationConfig': {'temperature': 0.2},
              }),
            )
            .timeout(const Duration(seconds: 45));

        body = {};
        try {
          body = jsonDecode(response.body) as Map<String, dynamic>;
        } catch (_) {}

        if (response.statusCode == 200) break;

        if (!_isTemporaryGeminiFailure(response.statusCode, body) || attempt == retryDelays.length) {
          final apiMessage = _extractApiError(body);
          final isQuotaExceeded = _isGeminiQuotaExceeded(response.statusCode, body);
          throw LegalAiException(
            isQuotaExceeded
                ? 'تم تجاوز الحد المتاح حالياً لخدمة المساعد. يرجى المحاولة لاحقاً.'
                : _isTemporaryGeminiFailure(response.statusCode, body)
                    ? 'الخدمة مشغولة حالياً. تمت إعادة المحاولة تلقائياً، ويرجى المحاولة بعد قليل إذا استمر الخطأ.'
                    : (apiMessage ?? _status(response.statusCode)),
          );
        }
      } catch (e) {
        if (e is LegalAiException) rethrow;
        if (attempt == retryDelays.length) {
          throw const LegalAiException(
            'تعذر الاتصال بالمساعد الذكي. تحقق من اتصال الإنترنت وحاول مرة أخرى.',
          );
        }
      }
    }

    if (response == null || response.statusCode != 200) {
      throw const LegalAiException(
        'الخدمة مشغولة حالياً. تمت إعادة المحاولة تلقائياً، ويرجى المحاولة بعد قليل إذا استمر الخطأ.',
      );
    }

    final answer = _extractGeneratedText(body);
    if (answer.isEmpty) {
      throw const LegalAiException('تعذر توليد إجابة من المساعد الذكي.');
    }

    return LegalAiResult(
      answer: answer,
      sources: localMatches.map(LegalAiSource.fromMadda).toList(),
      conversationId: conversationId,
      responseSource: localMatches.isEmpty ? 'gemini_ai' : 'local_db_gemini',
    );
  }

  String _buildLocalContext(List<Madda> matches) {
    if (matches.isEmpty) return '';
    final buffer = StringBuffer();
    for (var i = 0; i < matches.length; i++) {
      final m = matches[i];
      buffer
        ..writeln('[المصدر ${i + 1}]')
        ..writeln('القانون: ${m.lawName?.trim().isNotEmpty == true ? m.lawName!.trim() : 'القوانين اليمنية'}')
        ..writeln('المادة: ${m.number}')
        ..writeln('النص:')
        ..writeln(m.body.trim());

      final context = [
        if (m.babLabel?.trim().isNotEmpty == true) m.babLabel!.trim(),
        if (m.faslLabel?.trim().isNotEmpty == true) m.faslLabel!.trim(),
      ].join(' - ');
      if (context.isNotEmpty) buffer.writeln('السياق: $context');
      buffer.writeln();
    }
    return buffer.toString().trim();
  }

  String _extractGeneratedText(Map<String, dynamic> body) {
    final candidates = body['candidates'];
    if (candidates is! List || candidates.isEmpty) return '';
    final content = candidates.first is Map ? (candidates.first as Map)['content'] : null;
    if (content is! Map) return '';
    final parts = content['parts'];
    if (parts is! List) return '';
    final buffer = StringBuffer();
    for (final part in parts) {
      if (part is Map && part['text'] != null) buffer.write(part['text'].toString());
    }
    return buffer.toString().trim();
  }

  bool _isTemporaryGeminiFailure(int statusCode, Map<String, dynamic> body) {
    final message = _extractApiError(body)?.toLowerCase() ?? '';
    if (statusCode == 429) {
      final quotaExceeded = message.contains('quota exceeded') ||
          message.contains('quota') ||
          message.contains('free_tier_requests') ||
          message.contains('rate limit');
      if (quotaExceeded) return false;
      return true;
    }
    if ({500, 502, 503, 504}.contains(statusCode)) return true;
    return message.contains('high demand') ||
        message.contains('overloaded') ||
        message.contains('temporarily unavailable') ||
        message.contains('temporarily busy');
  }

  bool _isGeminiQuotaExceeded(int statusCode, Map<String, dynamic> body) {
    if (statusCode == 429) {
      final message = _extractApiError(body)?.toLowerCase() ?? '';
      return message.contains('quota exceeded') ||
          message.contains('quota') ||
          message.contains('free_tier_requests') ||
          message.contains('rate limit');
    }
    return false;
  }

  String? _extractApiError(Map<String, dynamic> body) {
    final error = body['error'];
    if (error is Map && error['message'] != null) return error['message'].toString();
    return null;
  }

  Future<void> _saveHistorySafely({
    required String query,
    required String response,
    required String source,
  }) async {
    try {
      await _historyDb.addSearch(query: query, response: response, source: source);
    } catch (_) {}
  }

  String _status(int statusCode) {
    if (statusCode == 400) return 'تعذر فهم طلب المساعد. حاول صياغة السؤال بطريقة أخرى.';
    if (statusCode == 401 || statusCode == 403) return 'مفتاح المساعد الذكي غير صالح أو غير مصرح به.';
    if (statusCode == 429) return 'تم تجاوز حد استخدام المساعد مؤقتاً. حاول لاحقاً.';
    if (statusCode >= 500) return 'خدمة المساعد الذكي غير متاحة حالياً.';
    return 'حدث خطأ أثناء معالجة السؤال.';
  }

  static const Set<String> _assistantStopWords = {
    'ما', 'ماذا', 'هل', 'هو', 'هي', 'هذا', 'هذه', 'ذلك', 'تلك', 'من', 'في',
    'فيه', 'عن', 'على', 'الى', 'إلى', 'مع', 'لي', 'لدي', 'اريد', 'أريد',
    'يمكن', 'كيف', 'متى', 'أين', 'اين', 'جميع', 'ماهي',
  };
}

class LegalAiException implements Exception {
  final String message;

  const LegalAiException(this.message);

  @override
  String toString() => message;
}
