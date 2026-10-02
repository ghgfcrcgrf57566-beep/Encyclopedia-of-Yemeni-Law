import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// يتحكم هذا الصف في نسخ قاعدة البيانات الجاهزة (المرفقة كأصل asset) إلى
/// المجلد القابل للكتابة الخاص بالتطبيق ثم فتحها. هذا يسمح للتطبيق بالعمل
/// بالكامل دون اتصال بالإنترنت لأن كل بيانات القوانين مضمّنة مسبقًا.
///
/// ارفع رقم [dbAssetVersion] كلما استبدلت ملف assets/db/app_database.db
/// بنسخة محدّثة من القوانين، ليقوم التطبيق تلقائيًا باستبدال النسخة القديمة
/// المخزنة على جهاز المستخدم (ملاحظة: هذا يعيد أيضًا تصفير المفضلة الحالية
/// لأنها مخزنة في نفس الملف - إن أردت الحفاظ عليها يمكن نقلها إلى قاعدة
/// بيانات منفصلة صغيرة).
const int dbAssetVersion = 3;

class DBHelper {
  DBHelper._internal();
  static final DBHelper instance = DBHelper._internal();

  static const _dbName = 'app_database.db';
  static const _assetPath = 'assets/db/app_database.db';

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    final documentsDir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(documentsDir.path, _dbName);
    final versionMarker = File(p.join(documentsDir.path, '$_dbName.version'));

    final dbFile = File(dbPath);
    final needsCopy = !(await dbFile.exists()) || !(await _isUpToDate(versionMarker));

    if (needsCopy) {
      final data = await rootBundle.load(_assetPath);
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      await dbFile.writeAsBytes(bytes, flush: true);
      await versionMarker.writeAsString(dbAssetVersion.toString());
    }

    return openDatabase(dbPath, readOnly: false);
  }

  Future<bool> _isUpToDate(File versionMarker) async {
    if (!(await versionMarker.exists())) return false;
    final content = await versionMarker.readAsString();
    final storedVersion = int.tryParse(content.trim()) ?? -1;
    return storedVersion == dbAssetVersion;
  }

  Future<void> close() async {
    final db = _db;
    if (db != null) {
      await db.close();
      _db = null;
    }
  }
}
