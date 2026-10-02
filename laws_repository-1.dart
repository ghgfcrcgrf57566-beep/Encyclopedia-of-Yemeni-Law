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

  // ---------------------------------------------------------------------
  // القوانين
  // ---------------------------------------------------------------------

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

  // ---------------------------------------------------------------------
  // الأبواب (يدعم التداخل: كتاب/قسم/باب عبر parent_bab_id)
  // ---------------------------------------------------------------------

  /// يعيد الأبواب المباشرة (top-level) لقانون معيّن، أو أبواب فرعية إن
  /// مُرِّر [parentBabId].
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
      'SELECT COUNT(*) FROM abwab WHERE parent_bab_id = ?',
      [babId],
    ));
    if ((childBabs ?? 0) > 0) return true;
    final fusul = Sqflite.firstIntValue(await db.rawQuery(
      'SELECT COUNT(*) FROM fusul WHERE bab_id = ?',
      [babId],
    ));
    return (fusul ?? 0) > 0;
  }

  // ---------------------------------------------------------------------
  // الفصول
  // ---------------------------------------------------------------------

  Future<List<Fasl>> getFusul(int babId) async {
    final db = await _db;
    final rows = await db.query(
      'fusul',
      where: 'bab_id = ?',
      whereArgs: [babId],
      orderBy: 'order_num ASC',
    );
    return rows.map(Fasl.fromMap).toList();
  }

  /// يعيد الفصول المرتبطة بالقانون مباشرة دون باب أب (حالة قوانين تبدأ
  /// هيكلتها بـ"فصل" مباشرة دون "باب" يسبقه، مثل قانون التحكيم وقانون
  /// المرافعات). بدون هذه الدالة تبقى هذه الفصول (وموادها) غير ظاهرة
  /// إطلاقًا في شاشة القانون الرئيسية رغم وجودها فعليًا في قاعدة البيانات.
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

  // ---------------------------------------------------------------------
  // المواد
  // ---------------------------------------------------------------------

  Future<List<Madda>> getMawadByFasl(int faslId) async {
    final db = await _db;
    final rows = await db.query(
      'mawad',
      where: 'fasl_id = ?',
      whereArgs: [faslId],
      orderBy: 'order_num ASC',
    );
    return rows.map(Madda.fromMap).toList();
  }

  Future<List<Madda>> getMawadByBab(int babId) async {
    final db = await _db;
    final rows = await db.query(
      'mawad',
      where: 'bab_id = ? AND fasl_id IS NULL',
      whereArgs: [babId],
      orderBy: 'order_num ASC',
    );
    return rows.map(Madda.fromMap).toList();
  }

  /// المواد التي تنتمي مباشرة إلى القانون دون أي باب (نادر: مقدمة قبل أول باب).
  Future<List<Madda>> getRootMawad(int lawId) async {
    final db = await _db;
    final rows = await db.query(
      'mawad',
      where: 'law_id = ? AND bab_id IS NULL AND fasl_id IS NULL',
      whereArgs: [lawId],
      orderBy: 'order_num ASC',
    );
    return rows.map(Madda.fromMap).toList();
  }

  Future<Madda?> getMaddaById(int id) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT m.*, l.name AS law_name, b.label AS bab_label, f.label AS fasl_label
      FROM mawad m
      JOIN laws l ON l.id = m.law_id
      LEFT JOIN abwab b ON b.id = m.bab_id
      LEFT JOIN fusul f ON f.id = m.fasl_id
      WHERE m.id = ?
    ''', [id]);
    if (rows.isEmpty) return null;
    return Madda.fromMap(rows.first);
  }

  /// يبحث برقم المادة داخل قانون معيّن (أو كل القوانين إن كان lawId فارغًا).
  Future<List<Madda>> getMaddaByNumber(String number, {int? lawId}) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT m.*, l.name AS law_name, b.label AS bab_label, f.label AS fasl_label
      FROM mawad m
      JOIN laws l ON l.id = m.law_id
      LEFT JOIN abwab b ON b.id = m.bab_id
      LEFT JOIN fusul f ON f.id = m.fasl_id
      WHERE m.number = ? ${lawId != null ? 'AND m.law_id = ?' : ''}
      ORDER BY l.order_num, m.order_num
    ''', lawId != null ? [number, lawId] : [number]);
    return rows.map(Madda.fromMap).toList();
  }

  // ---------------------------------------------------------------------
  // البحث الشامل (نص كامل عبر FTS5) داخل جميع القوانين أو قانون واحد
  // ---------------------------------------------------------------------

  Future<List<Madda>> search(String query, {int? lawId, int limit = 100}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    final db = await _db;

    // إن كان البحث رقمًا صرفًا، ابحث برقم المادة مباشرة أيضًا
    final isNumeric = RegExp(r'^\d+$').hasMatch(trimmed);
    if (isNumeric) {
      return getMaddaByNumber(trimmed, lawId: lawId);
    }

    final ftsQuery = _buildFtsQuery(trimmed);
    try {
      final rows = await db.rawQuery('''
        SELECT m.*, l.name AS law_name, b.label AS bab_label, f.label AS fasl_label
        FROM mawad_fts fts
        JOIN mawad m ON m.id = fts.rowid
        JOIN laws l ON l.id = m.law_id
        LEFT JOIN abwab b ON b.id = m.bab_id
        LEFT JOIN fusul f ON f.id = m.fasl_id
        WHERE mawad_fts MATCH ? ${lawId != null ? 'AND m.law_id = ?' : ''}
        ORDER BY rank
        LIMIT ?
      ''', lawId != null ? [ftsQuery, lawId, limit] : [ftsQuery, limit]);
      return rows.map(Madda.fromMap).toList();
    } catch (_) {
      // إن فشل استعلام FTS (مثلاً بسبب رموز خاصة) نرجع لبحث LIKE بسيط كخطة بديلة
      final rows = await db.rawQuery('''
        SELECT m.*, l.name AS law_name, b.label AS bab_label, f.label AS fasl_label
        FROM mawad m
        JOIN laws l ON l.id = m.law_id
        LEFT JOIN abwab b ON b.id = m.bab_id
        LEFT JOIN fusul f ON f.id = m.fasl_id
        WHERE m.body LIKE ? ${lawId != null ? 'AND m.law_id = ?' : ''}
        ORDER BY l.order_num, m.order_num
        LIMIT ?
      ''', lawId != null ? ['%$trimmed%', lawId, limit] : ['%$trimmed%', limit]);
      return rows.map(Madda.fromMap).toList();
    }
  }

  /// يحوّل نص المستخدم إلى استعلام FTS5 آمن (كل كلمة مع بادئة * للمطابقة الجزئية).
  String _buildFtsQuery(String input) {
    final words = input
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((w) => w.replaceAll('"', ''))
        .map((w) => '"$w"*')
        .toList();
    return words.join(' AND ');
  }

  // ---------------------------------------------------------------------
  // المفضلة
  // ---------------------------------------------------------------------

  Future<void> addFavorite(int maddaId) async {
    final db = await _db;
    await db.insert(
      'favorites',
      {'mada_id': maddaId},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> removeFavorite(int maddaId) async {
    final db = await _db;
    await db.delete('favorites', where: 'mada_id = ?', whereArgs: [maddaId]);
  }

  Future<bool> isFavorite(int maddaId) async {
    final db = await _db;
    final rows = await db.query('favorites', where: 'mada_id = ?', whereArgs: [maddaId]);
    return rows.isNotEmpty;
  }

  Future<List<Madda>> getFavorites() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT m.*, l.name AS law_name, b.label AS bab_label, f.label AS fasl_label
      FROM favorites fav
      JOIN mawad m ON m.id = fav.mada_id
      JOIN laws l ON l.id = m.law_id
      LEFT JOIN abwab b ON b.id = m.bab_id
      LEFT JOIN fusul f ON f.id = m.fasl_id
      ORDER BY fav.created_at DESC
    ''');
    return rows.map(Madda.fromMap).toList();
  }

  // ---------------------------------------------------------------------
  // نظام تصنيف القوانين (Filtering System)
  // ---------------------------------------------------------------------

  /// يعيد كل تصنيف مع عدد القوانين بداخله.
  Future<List<Map<String, dynamic>>> getCategories() async {
    final db = await _db;
    return db.rawQuery('''
      SELECT COALESCE(category, 'أخرى') AS category, COUNT(*) AS count
      FROM laws
      GROUP BY COALESCE(category, 'أخرى')
      ORDER BY MIN(order_num)
    ''');
  }

  Future<List<Law>> getLawsByCategory(String category) async {
    final db = await _db;
    final rows = await db.query(
      'laws',
      where: 'COALESCE(category, ?) = ?',
      whereArgs: ['أخرى', category],
      orderBy: 'order_num ASC',
    );
    return rows.map(Law.fromMap).toList();
  }

  // ---------------------------------------------------------------------
  // ملاحظة شخصية على مادة (منفصلة عن قسم "الملاحظات والاقتراحات" العام)
  // ---------------------------------------------------------------------

  Future<ArticleNote?> getArticleNote(int maddaId) async {
    final db = await _db;
    final rows = await db.query('article_notes', where: 'mada_id = ?', whereArgs: [maddaId]);
    if (rows.isEmpty) return null;
    return ArticleNote.fromMap(rows.first);
  }

  Future<void> saveArticleNote(int maddaId, String text) async {
    final db = await _db;
    if (text.trim().isEmpty) {
      await db.delete('article_notes', where: 'mada_id = ?', whereArgs: [maddaId]);
      return;
    }
    await db.insert(
      'article_notes',
      {
        'mada_id': maddaId,
        'note_text': text.trim(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ---------------------------------------------------------------------
  // قسم "الملاحظات والاقتراحات" العام (يُرسل إلى المطوّر)
  // ---------------------------------------------------------------------

  Future<int> addFeedbackNote(String body) async {
    final db = await _db;
    return db.insert('feedback_notes', {
      'body': body.trim(),
      'created_at': DateTime.now().toIso8601String(),
      'sent': 0,
    });
  }

  Future<void> markFeedbackSent(int id) async {
    final db = await _db;
    await db.update('feedback_notes', {'sent': 1}, where: 'id = ?', whereArgs: [id]);
  }

  Future<List<FeedbackNote>> getPendingFeedback() async {
    final db = await _db;
    final rows = await db.query('feedback_notes', where: 'sent = 0', orderBy: 'created_at DESC');
    return rows.map(FeedbackNote.fromMap).toList();
  }

  Future<List<FeedbackNote>> getAllFeedback() async {
    final db = await _db;
    final rows = await db.query('feedback_notes', orderBy: 'created_at DESC');
    return rows.map(FeedbackNote.fromMap).toList();
  }

  // ---------------------------------------------------------------------
  // سجل "آخر ما قرأت"
  // ---------------------------------------------------------------------

  Future<void> recordReading(int maddaId) async {
    final db = await _db;
    await db.insert('reading_history', {
      'mada_id': maddaId,
      'opened_at': DateTime.now().toIso8601String(),
    });
    // احتفظ بآخر 200 سجل فقط لتفادي تضخم القاعدة بلا داعٍ
    await db.rawDelete('''
      DELETE FROM reading_history WHERE id NOT IN (
        SELECT id FROM reading_history ORDER BY opened_at DESC LIMIT 200
      )
    ''');
  }

  /// يعيد آخر المواد المقروءة بدون تكرار (كل مادة تظهر مرة واحدة، بأحدث توقيت).
  Future<List<Madda>> getRecentlyRead({int limit = 20}) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT m.*, l.name AS law_name, b.label AS bab_label, f.label AS fasl_label,
             MAX(rh.opened_at) AS last_opened
      FROM reading_history rh
      JOIN mawad m ON m.id = rh.mada_id
      JOIN laws l ON l.id = m.law_id
      LEFT JOIN abwab b ON b.id = m.bab_id
      LEFT JOIN fusul f ON f.id = m.fasl_id
      GROUP BY m.id
      ORDER BY last_opened DESC
      LIMIT ?
    ''', [limit]);
    return rows.map(Madda.fromMap).toList();
  }

  // ---------------------------------------------------------------------
  // سجل البحث (للتوسع المستقبلي)
  // ---------------------------------------------------------------------

  Future<void> recordSearch(String query) async {
    if (query.trim().isEmpty) return;
    final db = await _db;
    await db.insert('search_history', {
      'query': query.trim(),
      'searched_at': DateTime.now().toIso8601String(),
    });
  }

  // ---------------------------------------------------------------------
  // القراءة التسلسلية الكاملة للقانون (كما في ملف Word الأصلي): تُرجع
  // تسلسلاً مسطّحًا من العناوين والمواد بترتيبها الطبيعي دفعة واحدة.
  // ---------------------------------------------------------------------

  Future<List<DocumentItem>> getFullLawDocument(int lawId) async {
    final db = await _db;
    final items = <DocumentItem>[];

    Future<void> walkBab(int? babId, int? parentBabId) async {
      // اجلب كل شيء بهذا المستوى مرتبًا بالتسلسل الطبيعي (order_num) عبر
      // دمج الأبواب الفرعية والفصول والمواد المباشرة في قائمة واحدة مرتبة.
      final subAbwab = await db.query(
        'abwab',
        where: parentBabId == null ? 'law_id = ? AND parent_bab_id IS NULL' : 'law_id = ? AND parent_bab_id = ?',
        whereArgs: parentBabId == null ? [lawId] : [lawId, parentBabId],
      );
      final fusul = babId == null
          ? await db.query('fusul', where: 'law_id = ? AND bab_id IS NULL', whereArgs: [lawId])
          : await db.query('fusul', where: 'bab_id = ?', whereArgs: [babId]);
      final directMawad = babId == null
          ? await db.query('mawad', where: 'law_id = ? AND bab_id IS NULL AND fasl_id IS NULL', whereArgs: [lawId])
          : await db.query('mawad', where: 'bab_id = ? AND fasl_id IS NULL', whereArgs: [babId]);

      // ادمج الكل واحفظ نوعه، ثم رتّب حسب order_num ليطابق تسلسل المستند الأصلي
      final merged = [
        ...subAbwab.map((e) => MapEntry('bab', e)),
        ...fusul.map((e) => MapEntry('fasl', e)),
        ...directMawad.map((e) => MapEntry('madda', e)),
      ]..sort((a, b) => ((a.value['order_num'] as int?) ?? 0).compareTo((b.value['order_num'] as int?) ?? 0));

      for (final entry in merged) {
        if (entry.key == 'bab') {
          final bab = Bab.fromMap(entry.value);
          items.add(DocumentItem.heading(bab.level, bab.displayName));
          await walkBab(bab.id, bab.id);
        } else if (entry.key == 'fasl') {
          final fasl = Fasl.fromMap(entry.value);
          items.add(DocumentItem.heading('فصل', fasl.displayName));
          final mawad = await db.query('mawad', where: 'fasl_id = ?', whereArgs: [fasl.id], orderBy: 'order_num ASC');
          for (final m in mawad) {
            items.add(DocumentItem.article(Madda.fromMap(m)));
          }
        } else {
          items.add(DocumentItem.article(Madda.fromMap(entry.value)));
        }
      }
    }

    await walkBab(null, null);
    return items;
  }
}

/// عنصر واحد في "العرض التسلسلي الكامل" للقانون: إما عنوان قسم (كتاب/قسم/
/// باب/فصل) أو مادة كاملة، بنفس تسلسلها الأصلي في ملف Word.
class DocumentItem {
  final bool isHeading;
  final String? headingLevel;
  final String? headingText;
  final Madda? madda;

  DocumentItem.heading(this.headingLevel, this.headingText)
      : isHeading = true,
        madda = null;

  DocumentItem.article(this.madda)
      : isHeading = false,
        headingLevel = null,
        headingText = null;
}
