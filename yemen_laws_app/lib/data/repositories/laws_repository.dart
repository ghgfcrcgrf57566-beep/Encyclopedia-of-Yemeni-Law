import 'package:sqflite/sqflite.dart';
import '../db_helper.dart';
import '../models/law.dart';
import '../models/bab.dart';
import '../models/fasl.dart';
import '../models/madda.dart';
import '../models/article_note.dart';
import '../models/feedback_note.dart';

class LawsRepository {
  LawsRepository._internal();
  static final LawsRepository instance = LawsRepository._internal();

  Future<Database> get _db async => DBHelper.instance.database;

  Future<List<Law>> getAllLaws() async {
    final db = await _db;
    final rows = await db.query('laws', orderBy: 'order_num ASC');
    return rows.map(Law.fromMap).toList();
  }

  Future<Law?> getLawById(int id) async {
    final db = await _db;
    final rows = await db.query('laws', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Law.fromMap(rows.first);
  }

  Future<List<Bab>> getAbwab(int lawId, {int? parentBabId}) async {
    final db = await _db;
    final rows = await db.query(
      'abwab',
      where: parentBabId == null
          ? 'law_id = ? AND parent_bab_id IS NULL'
          : 'law_id = ? AND parent_bab_id = ?',
      whereArgs: parentBabId == null ? [lawId] : [lawId, parentBabId],
      orderBy: 'order_num ASC',
    );
    return rows.map(Bab.fromMap).toList();
  }

  Future<bool> babHasChildren(int babId) async {
    final db = await _db;
    final childBabs = Sqflite.firstIntValue(await db.rawQuery(
      'SELECT COUNT(*) FROM abwab WHERE parent_bab_id = ?', [babId]));
    if ((childBabs ?? 0) > 0) return true;
    final fusul = Sqflite.firstIntValue(await db.rawQuery(
      'SELECT COUNT(*) FROM fusul WHERE bab_id = ?', [babId]));
    return (fusul ?? 0) > 0;
  }

  Future<List<Fasl>> getFusul(int babId) async {
    final db = await _db;
    final rows = await db.query('fusul', where: 'bab_id = ?', whereArgs: [babId], orderBy: 'order_num ASC');
    return rows.map(Fasl.fromMap).toList();
  }

  /// يعيد الفصول المرتبطة بالقانون مباشرة دون باب أب.
  Future<List<Fasl>> getRootFusul(int lawId) async {
    final db = await _db;
    final rows = await db.query(
      'fusul',
      where: 'law_id = ? AND bab_id IS NULL',
      whereArgs: [lawId],
      orderBy: 'order_num ASC',
    );
    return rows.map(Fasl.fromMap).toList();
  }

  Future<List<Madda>> getMawadByFasl(int faslId) async {
    final db = await _db;
    final rows = await db.query('mawad', where: 'fasl_id = ?', whereArgs: [faslId], orderBy: 'order_num ASC');
    return rows.map(Madda.fromMap).toList();
  }

  Future<List<Madda>> getMawadByBab(int babId) async {
    final db = await _db;
    final rows = await db.query('mawad', where: 'bab_id = ? AND fasl_id IS NULL', whereArgs: [babId], orderBy: 'order_num ASC');
    return rows.map(Madda.fromMap).toList();
  }

  Future<List<Madda>> getRootMawad(int lawId) async {
    final db = await _db;
    final rows = await db.query('mawad', where: 'law_id = ? AND bab_id IS NULL AND fasl_id IS NULL', whereArgs: [lawId], orderBy: 'order_num ASC');
    return rows.map(Madda.fromMap).toList();
  }

  Future<Madda?> getMaddaById(int id) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT m.*, l.name AS law_name, b.label AS bab_label, f.label AS fasl_label
      FROM mawad m JOIN laws l ON l.id = m.law_id
      LEFT JOIN abwab b ON b.id = m.bab_id LEFT JOIN fusul f ON f.id = m.fasl_id
      WHERE m.id = ?
    ''', [id]);
    if (rows.isEmpty) return null;
    return Madda.fromMap(rows.first);
  }

  Future<List<Madda>> getMaddaByNumber(String number, {int? lawId}) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT m.*, l.name AS law_name, b.label AS bab_label, f.label AS fasl_label
      FROM mawad m JOIN laws l ON l.id = m.law_id
      LEFT JOIN abwab b ON b.id = m.bab_id LEFT JOIN fusul f ON f.id = m.fasl_id
      WHERE m.number = ? ${lawId != null ? 'AND m.law_id = ?' : ''}
      ORDER BY l.order_num, m.order_num
    ''', lawId != null ? [number, lawId] : [number]);
    return rows.map(Madda.fromMap).toList();
  }

  Future<List<Madda>> search(String query, {int? lawId, int limit = 100}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];
    final db = await _db;
    final isNumeric = RegExp(r'^\d+$').hasMatch(trimmed);
    if (isNumeric) return getMaddaByNumber(trimmed, lawId: lawId);
    final words = trimmed.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).map((w) => w.replaceAll('"', '')).map((w) => '"$w"*').toList();
    final ftsQuery = words.join(' AND ');
    try {
      final rows = await db.rawQuery('''
        SELECT m.*, l.name AS law_name, b.label AS bab_label, f.label AS fasl_label
        FROM mawad_fts fts JOIN mawad m ON m.id = fts.rowid JOIN laws l ON l.id = m.law_id
        LEFT JOIN abwab b ON b.id = m.bab_id LEFT JOIN fusul f ON f.id = m.fasl_id
        WHERE mawad_fts MATCH ? ${lawId != null ? 'AND m.law_id = ?' : ''}
        ORDER BY rank LIMIT ?
      ''', lawId != null ? [ftsQuery, lawId, limit] : [ftsQuery, limit]);
      return rows.map(Madda.fromMap).toList();
    } catch (_) {
      final rows = await db.rawQuery('''
        SELECT m.*, l.name AS law_name, b.label AS bab_label, f.label AS fasl_label
        FROM mawad m JOIN laws l ON l.id = m.law_id
        LEFT JOIN abwab b ON b.id = m.bab_id LEFT JOIN fusul f ON f.id = m.fasl_id
        WHERE m.body LIKE ? ${lawId != null ? 'AND m.law_id = ?' : ''}
        ORDER BY l.order_num, m.order_num LIMIT ?
      ''', lawId != null ? ['%$trimmed%', lawId, limit] : ['%$trimmed%', limit]);
      return rows.map(Madda.fromMap).toList();
    }
  }

  Future<List<Madda>> searchForLegalAssistant(String query, {int limit = 8}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];
    final numeric = int.tryParse(trimmed);
    if (numeric != null) return getMaddaByNumber(trimmed);
    final direct = await search(trimmed, limit: limit);
    if (direct.isNotEmpty) return direct;
    final terms = trimmed.split(RegExp(r'\s+')).map(_normalizeAssistantTerm).where((term) => term.length >= 2 && !_assistantStopWords.contains(term)).take(8).toList();
    if (terms.isEmpty) return [];
    final db = await _db;
    final ftsQuery = terms.map((term) => '"' + term.replaceAll('"', '') + '"*').join(' OR ');
    try {
      final rows = await db.rawQuery('''
        SELECT m.*, l.name AS law_name, b.label AS bab_label, f.label AS fasl_label
        FROM mawad_fts fts JOIN mawad m ON m.id = fts.rowid JOIN laws l ON l.id = m.law_id
        LEFT JOIN abwab b ON b.id = m.bab_id LEFT JOIN fusul f ON f.id = m.fasl_id
        WHERE mawad_fts MATCH ? ORDER BY rank LIMIT ?
      ''', [ftsQuery, limit]);
      final result = rows.map(Madda.fromMap).toList();
      if (result.isNotEmpty) return result;
    } catch (_) {}
    final clauses = terms.map((_) => '(m.body LIKE ? OR m.number LIKE ? OR l.name LIKE ?)').join(' OR ');
    final args = <String>[];
    for (final term in terms) { args..add('%$term%')..add('%$term%')..add('%$term%'); }
    final rows = await db.rawQuery('SELECT m.*, l.name AS law_name, b.label AS bab_label, f.label AS fasl_label FROM mawad m JOIN laws l ON l.id = m.law_id LEFT JOIN abwab b ON b.id = m.bab_id LEFT JOIN fusul f ON f.id = m.fasl_id WHERE $clauses ORDER BY l.order_num, m.order_num LIMIT ?', [...args, limit]);
    return rows.map(Madda.fromMap).toList();
  }

  String _normalizeAssistantTerm(String value) => value.toLowerCase().replaceAll(RegExp(r'[ً-ٟ]'), '').replaceAll(RegExp(r'[إأآٱ]'), 'ا').replaceAll('ى', 'ي').replaceAll('ة', 'ه').replaceAll('ـ', '').trim();

  static const Set<String> _assistantStopWords = {'ما','ماذا','هل','هو','هي','هذا','هذه','ذلك','تلك','من','في','فيه','عن','على','الى','إلى','مع','لي','لدي','اريد','أريد','يمكن','كيف','متى','أين','اين'};

  Future<void> addFavorite(int maddaId) async { final db = await _db; await db.insert('favorites', {'mada_id': maddaId}, conflictAlgorithm: ConflictAlgorithm.ignore); }
  Future<void> removeFavorite(int maddaId) async { final db = await _db; await db.delete('favorites', where: 'mada_id = ?', whereArgs: [maddaId]); }
  Future<bool> isFavorite(int maddaId) async { final db = await _db; final rows = await db.query('favorites', where: 'mada_id = ?', whereArgs: [maddaId]); return rows.isNotEmpty; }
  Future<List<Madda>> getFavorites() async { final db = await _db; final rows = await db.rawQuery('''SELECT m.*, l.name AS law_name, b.label AS bab_label, f.label AS fasl_label FROM favorites fav JOIN mawad m ON m.id = fav.mada_id JOIN laws l ON l.id = m.law_id LEFT JOIN abwab b ON b.id = m.bab_id LEFT JOIN fusul f ON f.id = m.fasl_id ORDER BY fav.created_at DESC'''); return rows.map(Madda.fromMap).toList(); }

  Future<List<Map<String, dynamic>>> getCategories() async { final db = await _db; return db.rawQuery('''SELECT COALESCE(category, 'أخرى') AS category, COUNT(*) AS count FROM laws GROUP BY COALESCE(category, 'أخرى') ORDER BY MIN(order_num)'''); }
  Future<List<Law>> getLawsByCategory(String category) async { final db = await _db; final rows = await db.query('laws', where: 'COALESCE(category, ?) = ?', whereArgs: ['أخرى', category], orderBy: 'order_num ASC'); return rows.map(Law.fromMap).toList(); }

  Future<ArticleNote?> getArticleNote(int maddaId) async { final db = await _db; final rows = await db.query('article_notes', where: 'mada_id = ?', whereArgs: [maddaId]); if (rows.isEmpty) return null; return ArticleNote.fromMap(rows.first); }
  Future<void> saveArticleNote(int maddaId, String text) async { final db = await _db; if (text.trim().isEmpty) { await db.delete('article_notes', where: 'mada_id = ?', whereArgs: [maddaId]); return; } await db.insert('article_notes', {'mada_id': maddaId, 'note_text': text.trim(), 'updated_at': DateTime.now().toIso8601String()}, conflictAlgorithm: ConflictAlgorithm.replace); }

  Future<int> addFeedbackNote(String body) async { final db = await _db; return db.insert('feedback_notes', {'body': body.trim(), 'created_at': DateTime.now().toIso8601String(), 'sent': 0}); }
  Future<void> markFeedbackSent(int id) async { final db = await _db; await db.update('feedback_notes', {'sent': 1}, where: 'id = ?', whereArgs: [id]); }
  Future<List<FeedbackNote>> getPendingFeedback() async { final db = await _db; final rows = await db.query('feedback_notes', where: 'sent = 0', orderBy: 'created_at DESC'); return rows.map(FeedbackNote.fromMap).toList(); }
  Future<List<FeedbackNote>> getAllFeedback() async { final db = await _db; final rows = await db.query('feedback_notes', orderBy: 'created_at DESC'); return rows.map(FeedbackNote.fromMap).toList(); }

  Future<void> recordReading(int maddaId) async { final db = await _db; await db.insert('reading_history', {'mada_id': maddaId, 'opened_at': DateTime.now().toIso8601String()}); await db.rawDelete('''DELETE FROM reading_history WHERE id NOT IN (SELECT id FROM reading_history ORDER BY opened_at DESC LIMIT 200)'''); }
  Future<List<Madda>> getRecentlyRead({int limit = 20}) async { final db = await _db; final rows = await db.rawQuery('''SELECT m.*, l.name AS law_name, b.label AS bab_label, f.label AS fasl_label, MAX(rh.opened_at) AS last_opened FROM reading_history rh JOIN mawad m ON m.id = rh.mada_id JOIN laws l ON l.id = m.law_id LEFT JOIN abwab b ON b.id = m.bab_id LEFT JOIN fusul f ON f.id = m.fasl_id GROUP BY m.id ORDER BY last_opened DESC LIMIT ?''', [limit]); return rows.map(Madda.fromMap).toList(); }
  Future<void> recordSearch(String query) async { if (query.trim().isEmpty) return; final db = await _db; await db.insert('search_history', {'query': query.trim(), 'searched_at': DateTime.now().toIso8601String()}); }

  Future<List<DocumentItem>> getFullLawDocument(int lawId) async {
    final db = await _db;
    final items = <DocumentItem>[];
    Future<void> walkBab(int? babId, int? parentBabId) async {
      final subAbwab = await db.query('abwab', where: parentBabId == null ? 'law_id = ? AND parent_bab_id IS NULL' : 'law_id = ? AND parent_bab_id = ?', whereArgs: parentBabId == null ? [lawId] : [lawId, parentBabId]);
      final fusul = babId == null ? await db.query('fusul', where: 'law_id = ? AND bab_id IS NULL', whereArgs: [lawId]) : await db.query('fusul', where: 'bab_id = ?', whereArgs: [babId]);
      final directMawad = babId == null ? await db.query('mawad', where: 'law_id = ? AND bab_id IS NULL AND fasl_id IS NULL', whereArgs: [lawId]) : await db.query('mawad', where: 'bab_id = ? AND fasl_id IS NULL', whereArgs: [babId]);
      final merged = [...subAbwab.map((e) => MapEntry('bab', e)), ...fusul.map((e) => MapEntry('fasl', e)), ...directMawad.map((e) => MapEntry('madda', e))]..sort((a,b) => ((a.value['order_num'] as int?) ?? 0).compareTo((b.value['order_num'] as int?) ?? 0));
      for (final entry in merged) {
        if (entry.key == 'bab') { final bab = Bab.fromMap(entry.value); items.add(DocumentItem.heading(bab.level, bab.displayName)); await walkBab(bab.id, bab.id); }
        else if (entry.key == 'fasl') { final fasl = Fasl.fromMap(entry.value); items.add(DocumentItem.heading('فصل', fasl.displayName)); final mawad = await db.query('mawad', where: 'fasl_id = ?', whereArgs: [fasl.id], orderBy: 'order_num ASC'); for (final m in mawad) { items.add(DocumentItem.article(Madda.fromMap(m))); } }
        else { items.add(DocumentItem.article(Madda.fromMap(entry.value))); }
      }
    }
    await walkBab(null, null);
    return items;
  }
}

class DocumentItem {
  final bool isHeading;
  final String? headingLevel;
  final String? headingText;
  final Madda? madda;
  DocumentItem.heading(this.headingLevel, this.headingText) : isHeading = true, madda = null;
  DocumentItem.article(this.madda) : isHeading = false, headingLevel = null, headingText = null;
}
