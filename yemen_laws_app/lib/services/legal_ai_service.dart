import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/app_config.dart';
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
          (json['id'] as num?)?.toInt() ??
          0,
      lawName: (json['law_name'] ?? json['law_title'] ?? '').toString(),
      articleNumber: (json['article_number'] ?? '').toString(),
      articleText: (json['article_text'] ?? '').toString(),
      chapter: json['chapter']?.toString(),
      score: (json['score'] as num?)?.toDouble(),
      reference: json['reference']?.toString(),
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

    // المساعد يبحث أولاً في قاعدة القوانين المركزية، ثم يستخدم الذكاء الاصطناعي لصياغة الإجابة. الويب احتياطي عند عدم العثور على نص محلي.
    final baseUrl = AppConfig.legalAiBaseUrl.trim().replaceFirst(
          RegExp(r'\/$'),
          '',
        );

    if (baseUrl.isEmpty) {
      throw const LegalAiException(
        'لم يتم إعداد عنوان خادم المساعد بعد. ابنِ التطبيق باستخدام LEGAL_AI_BASE_URL.',
      );
    }

    if (!baseUrl.startsWith('https://')) {
      throw const LegalAiException(
        'عنوان خادم المساعد يجب أن يستخدم HTTPS.',
      );
    }

    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/chat'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'X-App-Version': AppConfig.appVersion,
            },
            body: jsonEncode({
              'message': q,
              'language': 'ar',
              if (conversationId != null) 'conversation_id': conversationId,
              if (history.isNotEmpty) 'history': history,
            }),
          )
          .timeout(const Duration(seconds: 45));

      Map<String, dynamic> body = {};
      try {
        body = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {
        // The HTTP status below still gives the user a safe generic error.
      }

      if (response.statusCode != 200) {
        throw LegalAiException(
          (body['error'] ?? _status(response.statusCode)).toString(),
        );
      }

      final answer = (body['answer'] ?? '').toString().trim();
      final rawSources = body['sources'] as List? ?? const [];
      final responseSource =
          (body['response_source'] ?? 'gemini_ai').toString().trim();

      final result = LegalAiResult(
        answer: answer.isEmpty
            ? 'تعذر توليد إجابة من خدمة المساعد.'
            : answer,
        sources: rawSources
            .whereType<Map>()
            .map(
              (source) => LegalAiSource.fromJson(
                Map<String, dynamic>.from(source),
              ),
            )
            .toList(),
        conversationId: body['conversation_id']?.toString(),
        responseSource:
            responseSource.isEmpty ? 'web_search' : responseSource,
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
        'تعذر الاتصال بخدمة المساعد. تحقق من اتصال الإنترنت وحاول مرة أخرى.',
      );
    }
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
    } catch (_) {
      // فشل حفظ السجل لا يجب أن يمنع المستخدم من استلام الإجابة.
    }
  }

  String _status(int statusCode) {
    if (statusCode == 429) {
      return 'تم تجاوز حد الاستخدام مؤقتاً. حاول لاحقاً.';
    }
    if (statusCode >= 500) {
      return 'خادم المساعد غير متاح حالياً.';
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
