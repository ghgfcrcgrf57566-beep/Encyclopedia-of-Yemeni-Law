import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/app_config.dart';
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

    final localMatches = await _lawsRepository.searchForLegalAssistant(
      q,
      limit: 8,
    );

    if (AppConfig.geminiApiKey.trim().isEmpty) {
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
      throw const LegalAiException(
        'لم يتم إعداد مفتاح المساعد الذكي. ابنِ التطبيق باستخدام GEMINI_API_KEY.',
      );
    }

    try {
      final result = await _askGemini(
        question: q,
        conversationId: conversationId,
        history: history,
        localMatches: localMatches,
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

  String _buildLocalAnswer(List<Madda> matches) {
    if (matches.length == 1) {
      final m = matches.first;
      final law = m.lawName?.trim();
      final lawText = law == null || law.isEmpty ? '' : ' — ' + law;
      return 'وجدت في قاعدة القوانين المحلية المادة (' +
          m.number +
          ')' +
          lawText +
          ':\n\n' +
          m.body.trim();
    }

    final buffer = StringBuffer(
      'وجدت ' +
          matches.length.toString() +
          ' مواد مرتبطة بسؤالك في قاعدة القوانين المحلية:\n',
    );

    for (var i = 0; i < matches.length; i++) {
      final m = matches[i];
      final law = m.lawName?.trim();

      buffer
        ..write('\n' + (i + 1).toString() + '. المادة (' + m.number + ')')
        ..write(law == null || law.isEmpty ? '' : ' — ' + law)
        ..write('\n' + m.body.trim() + '\n');
    }

    return buffer.toString().trim();
  }

  Future<LegalAiResult> _askGemini({
    required String question,
    String? conversationId,
    required List<Map<String, String>> history,
    List<Madda> localMatches = const [],
  }) async {
    final model = AppConfig.geminiModel.trim().isEmpty
        ? 'gemini-3.8-flash'
        : AppConfig.geminiModel.trim();

    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/'
      model + ':generateContent',
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
          'text': localContext.isEmpty
              ? question
              : 'السؤال:\n$question\n\n'
                  'المواد المستخرجة من قاعدة القوانين المحلية:\n'
                  '$localContext',
        },
      ],
    });

    final response = await http
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
أنت المساعد الذكي داخل تطبيق «موسوعة القوانين اليمنية».
أجب باللغة العربية وبأسلوب قانوني واضح ومتحفظ.

قواعد الإجابة:
- قاعدة البيانات القانونية المحلية هي المصدر القانوني الأساسي.
- إذا أُرفقت مواد مستخرجة من قاعدة القوانين المحلية، فاعتمد عليها كأساس للإجابة والتحليل.
- لا تغيّر نص المادة ولا تنسب إليها نصاً غير موجود.
- عند الاستشهاد، اذكر اسم القانون ورقم المادة.
- فرّق بوضوح بين «النص القانوني» و«التحليل والشرح».
- إذا كانت المواد المحلية لا تكفي للإجابة، اذكر حدودها ولا تخترع حكماً قانونياً.
- إذا لم تكن متأكداً من نص قانوني محدد، صرّح بذلك بوضوح.
- ميّز بين المعلومة العامة وبين النص القانوني الملزم.
- لا تدّعِ أن إجابتك فتوى أو حكم قضائي ملزم.
- لا تذكر اسم مزود الذكاء الاصطناعي أو تفاصيل البنية التقنية للمستخدم؛ قدم نفسك باسم «المساعد» فقط.
''',
                },
              ],
            },
            'contents': contents,
            'generationConfig': {
              'temperature': 0.2,
            },
          }),
        )
        .timeout(const Duration(seconds: 45));

    Map<String, dynamic> body = {};
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {}

    if (response.statusCode != 200) {
      final apiMessage = _extractApiError(body);
      throw LegalAiException(apiMessage ?? _status(response.statusCode));
    }

    final answer = _extractGeneratedText(body);

    if (answer.isEmpty) {
      throw const LegalAiException(
        'تعذر توليد إجابة من المساعد الذكي.',
      );
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

      if (context.isNotEmpty) {
        buffer.writeln('السياق: $context');
      }

      buffer.writeln();
    }

    return buffer.toString().trim();
  }

  String _extractGeneratedText(Map<String, dynamic> body) {
    final candidates = body['candidates'];
    if (candidates is! List || candidates.isEmpty) return '';

    final content =
        candidates.first is Map ? (candidates.first as Map)['content'] : null;
    if (content is! Map) return '';

    final parts = content['parts'];
    if (parts is! List) return '';

    final buffer = StringBuffer();

    for (final part in parts) {
      if (part is Map && part['text'] != null) {
        buffer.write(part['text'].toString());
      }
    }

    return buffer.toString().trim();
  }

  String? _extractApiError(Map<String, dynamic> body) {
    final error = body['error'];

    if (error is Map && error['message'] != null) {
      return error['message'].toString();
    }

    return null;
  }

  Future<void> _saveHistorySafely({
    required String query,
    required String response,
    required String source,
  }) async {
    try {
      await _historyDb.addSearch(
        query: query,
        response: response,
        source: source,
      );
    } catch (_) {}
  }

  String _status(int statusCode) {
    if (statusCode == 400) {
      return 'تعذر فهم طلب المساعد. حاول صياغة السؤال بطريقة أخرى.';
    }
    if (statusCode == 401 || statusCode == 403) {
      return 'مفتاح المساعد الذكي غير صالح أو غير مصرح به.';
    }
    if (statusCode == 429) {
      return 'تم تجاوز حد استخدام المساعد مؤقتاً. حاول لاحقاً.';
    }
    if (statusCode >= 500) {
      return 'خدمة المساعد الذكي غير متاحة حالياً.';
    }
    return 'حدث خطأ أثناء معالجة السؤال.';
  }
}

class LegalAiException implements Exception {
  final String message;

  const LegalAiException(this.message);

  @override
  String toString() => message;
}
