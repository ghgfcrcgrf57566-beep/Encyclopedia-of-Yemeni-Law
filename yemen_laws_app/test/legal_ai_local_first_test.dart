import 'package:flutter_test/flutter_test.dart';
import 'package:yemen_law/services/chat_history_db.dart';
import 'package:yemen_law/services/legal_ai_service.dart';

void main() {
  test('parses legal assistant history entries', () {
    final entry = ChatHistoryEntry.fromMap({
      'id': 7,
      'query': 'ما شروط العقد؟',
      'response': 'المادة (10)...',
      'source': 'local_db',
      'created_at': '2026-09-26T20:00:00.000Z',
    });

    expect(entry.id, 7);
    expect(entry.query, 'ما شروط العقد؟');
    expect(entry.response, contains('المادة'));
    expect(entry.sourceLabel, 'قاعدة القوانين المحلية');
  });

  test('parses web-grounded legal source metadata', () {
    final source = LegalAiSource.fromJson({
      'article_id': 11,
      'law_name': 'القانون المدني',
      'article_number': '15',
      'article_text': 'نص المادة',
      'reference': 'القانون المدني — المادة 15',
    });

    expect(source.articleId, 11);
    expect(source.lawName, 'القانون المدني');
    expect(source.articleNumber, '15');
    expect(source.articleText, 'نص المادة');
    expect(source.reference, contains('القانون المدني'));
  });
}
