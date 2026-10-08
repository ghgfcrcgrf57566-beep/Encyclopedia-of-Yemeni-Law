import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

const kLegalReferencesMergedIndexUrl =
    'https://raw.githubusercontent.com/ghgfcrcgrf57566-beep/Encyclopedia-of-Yemeni-Law/main/legal_references/merged_books.json';

const _legalCategories = <_LibraryCategory>[
  _LibraryCategory('الشروح والموسوعات', Icons.menu_book_rounded),
  _LibraryCategory('القانون المدني', Icons.account_balance_wallet_rounded),
  _LibraryCategory('القانون الجنائي والإجراءات الجزائية', Icons.gavel_rounded),
  _LibraryCategory('القانون التجاري والشركات', Icons.business_rounded),
  _LibraryCategory('القانون الدستوري والإداري', Icons.account_balance_rounded),
  _LibraryCategory('القانون الدولي والمقارن', Icons.public_rounded),
  _LibraryCategory('الأحوال الشخصية', Icons.family_restroom_rounded),
  _LibraryCategory('قانون العمل', Icons.engineering_rounded),
  _LibraryCategory('العقارات والإيجارات', Icons.home_work_rounded),
  _LibraryCategory('الإجراءات والإثبات والتحكيم', Icons.fact_check_rounded),
  _LibraryCategory('القوانين المهنية والصحية', Icons.medical_services_rounded),
  _LibraryCategory('الدراسات والأبحاث', Icons.science_rounded),
  _LibraryCategory('المعاجم والمداخل القانونية', Icons.menu_book_rounded),
];

const _shariaCategories = <_LibraryCategory>[
  _LibraryCategory('الفقه الزيدي', Icons.menu_book_rounded),
  _LibraryCategory('الفقه الشافعي', Icons.menu_book_rounded),
  _LibraryCategory('الفقه الحنفي', Icons.menu_book_rounded),
  _LibraryCategory('الفقه المالكي', Icons.menu_book_rounded),
  _LibraryCategory('الفقه الحنبلي', Icons.menu_book_rounded),
  _LibraryCategory('الفقه الإمامي', Icons.menu_book_rounded),
  _LibraryCategory('الفقه المقارن', Icons.compare_arrows_rounded),
  _LibraryCategory('أصول الفقه', Icons.account_tree_rounded),
  _LibraryCategory('الفرائض والمواريث', Icons.calculate_rounded),
  _LibraryCategory('الحديث والفقه', Icons.auto_stories_rounded),
  _LibraryCategory('الشروح والحواشي', Icons.library_books_rounded),
  _LibraryCategory('الفتاوى', Icons.question_answer_rounded),
  _LibraryCategory('فقه المعاملات', Icons.handshake_rounded),
  _LibraryCategory('التراث الإسلامي', Icons.history_edu_rounded),
];

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  static const _cacheKey = 'cached_legal_references_json_v13';
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 90),
    responseType: ResponseType.plain,
  ));
  List<Map<String, dynamic>> _items = [];
  final Map<String, double> _progress = {};
  final Map<String, CancelToken> _tokens = {};
  final Set<String> _favorites = {};
  final Set<String> _reading = {};
  Set<String> _downloaded = {};
  bool _loading = true;

  @override
  void initState() { super.initState(); _loadIndex(); }

  @override
  void dispose() {
    for (final token in _tokens.values) token.cancel('library_disposed');
    _dio.close(force: true);
    super.dispose();
  }

  List<Map<String, dynamic>> _parse(String raw) {
    try {
      final value = jsonDecode(raw);
      if (value is! List) return [];
      return value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) { return []; }
  }

  bool _valid(Map<String, dynamic> item) {
    // احتفظ بكل عناصر الفهرس حتى إذا لم تتوفر نسخة PDF.
    return (item['id'] ?? item['title'] ?? '').toString().trim().isNotEmpty;
  }

  String _text(Map<String, dynamic> item) => [
    item['title'], item['author'], item['category'], item['description'], item['full_summary']
  ].join(' ').toLowerCase();

  bool _isSupremeCourt(Map<String, dynamic> item) {
    final id = (item['id'] ?? '').toString().toLowerCase();
    final category = (item['category'] ?? '').toString().toLowerCase();
    final section = (item['section'] ?? '').toString().toLowerCase();
    return id.startsWith('sc_') || category.contains('supreme_court') || section.contains('مراجع قضائية');
  }

  bool _isSharia(Map<String, dynamic> item) {
    final text = _text(item);
    const terms = [
      'فقه','شرعي','الشريعة','إسلام','الإسلام','المذاهب','مذهب','حديث','أصول الفقه',
      'قواعد فقهية','فتاوى','الفرائض','المواريث','الحلال والحرام','التشريع الإسلامي',
      'الشيعة','السنّة','السنة','جعفر الصادق','الفقه الإمامي','الإمامية','الزيدية',
      'الشافعي','الحنفي','المالكي','الحنبلي','التراث الإسلامي'
    ];
    return terms.any(text.contains);
  }

  bool _isSanhouri(Map<String, dynamic> item) {
    final text = _text(item);
    return text.contains('السنهوري') || text.contains('سنهوري');
  }

  String _legalCategory(Map<String, dynamic> item) {
    final text = _text(item);
    if (_isSanhouri(item) || text.contains('شرح') || text.contains('موسوعة') || text.contains('حاشية')) return 'الشروح والموسوعات';
    if (text.contains('قاموس') || text.contains('معجم') || text.contains('مصطلحات القانون')) return 'المعاجم والمداخل القانونية';
    if (text.contains('دراسة') || text.contains('بحث') || text.contains('أبحاث') || text.contains('دراسات')) return 'الدراسات والأبحاث';
    if (text.contains('دولي') || text.contains('مقارن') || text.contains('تنازع القوانين')) return 'القانون الدولي والمقارن';
    if (text.contains('أحوال شخصية') || text.contains('الزواج') || text.contains('الطلاق') || text.contains('الأسرة')) return 'الأحوال الشخصية';
    if (text.contains('عمل') || text.contains('عمال')) return 'قانون العمل';
    if (text.contains('إيجار') || text.contains('إيجارات') || text.contains('عقارات') || text.contains('ملكية') || text.contains('أراضي')) return 'العقارات والإيجارات';
    if (text.contains('تحكيم') || text.contains('إثبات') || text.contains('مرافعات') || text.contains('إجراءات مدنية') || text.contains('إجراءات جزائية')) return 'الإجراءات والإثبات والتحكيم';
    if (text.contains('تجاري') || text.contains('شركات') || text.contains('شركة') || text.contains('بحري')) return 'القانون التجاري والشركات';
    if (text.contains('جنائي') || text.contains('عقوبات') || text.contains('جريمة') || text.contains('جنائية')) return 'القانون الجنائي والإجراءات الجزائية';
    if (text.contains('دستوري') || text.contains('إداري') || text.contains('الإدارة')) return 'القانون الدستوري والإداري';
    if (text.contains('طبي') || text.contains('صيدل') || text.contains('مهني') || text.contains('طب')) return 'القوانين المهنية والصحية';
    return 'القانون المدني';
  }

  String _shariaCategory(Map<String, dynamic> item) {
    final text = _text(item);
    if (text.contains('زيد') || text.contains('الزيدية')) return 'الفقه الزيدي';
    if (text.contains('شافعي')) return 'الفقه الشافعي';
    if (text.contains('حنفي')) return 'الفقه الحنفي';
    if (text.contains('مالكي')) return 'الفقه المالكي';
    if (text.contains('حنبلي')) return 'الفقه الحنبلي';
    if (text.contains('إمامي') || text.contains('شيعي') || text.contains('الخميني') || text.contains('جعفري')) return 'الفقه الإمامي';
    if (text.contains('أصول الفقه')) return 'أصول الفقه';
    if (text.contains('فرائض') || text.contains('مواريث')) return 'الفرائض والمواريث';
    if (text.contains('حديث')) return 'الحديث والفقه';
    if (text.contains('فتوى') || text.contains('فتاوى')) return 'الفتاوى';
    if (text.contains('معاملات') || text.contains('بيع') || text.contains('عقود')) return 'فقه المعاملات';
    if (text.contains('شرح') || text.contains('حاشية')) return 'الشروح والحواشي';
    if (text.contains('مقارن') || text.contains('مقارنة')) return 'الفقه المقارن';
    if (text.contains('تراث') || text.contains('تاريخ') || text.contains('سيرة')) return 'التراث الإسلامي';
    return 'الفقه المقارن';
  }

  List<Map<String, dynamic>> get _libraryItems => _items.where((e) => !_isSupremeCourt(e)).toList();

  List<Map<String, dynamic>> _categoryItems(String category, bool sharia) => _libraryItems.where((item) {
    return (_isSharia(item) == sharia) &&
        (sharia ? _shariaCategory(item) : _legalCategory(item)) == category;
  }).toList();

  Future<void> _loadIndex() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_cacheKey);
    if (cached != null && mounted) setState(() => _items = _parse(cached).where(_valid).toList());
    _favorites.addAll(prefs.getStringList('library_favorites_v1') ?? []);
    _reading.addAll(prefs.getStringList('library_reading_v1') ?? []);
    try {
      final response = await _dio.get<String>(kLegalReferencesMergedIndexUrl);
      if (response.statusCode == 200 && response.data != null) {
        final items = _parse(response.data!).where(_valid).toList();
        if (items.isNotEmpty) {
          await prefs.setString(_cacheKey, jsonEncode(items));
          if (mounted) setState(() => _items = items);
        }
      }
    } catch (_) {}
    await _refreshDownloaded();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _saveFlags() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('library_favorites_v1', _favorites.toList());
    await prefs.setStringList('library_reading_v1', _reading.toList());
  }

  Future<void> _toggleFavorite(Map<String, dynamic> item) async {
    final id = (item['id'] ?? item['title'] ?? '').toString();
    setState(() {
      if (!_favorites.add(id)) _favorites.remove(id);
    });
    await _saveFlags();
  }

  Future<void> _deleteLocal(Map<String, dynamic> item) async {
    final file = await _file(item);
    final part = File(file.path + '.part');
    if (await file.exists()) await file.delete();
    if (await part.exists()) await part.delete();
    final id = (item['id'] ?? item['title'] ?? '').toString();
    _tokens[id]?.cancel('deleted');
    _tokens.remove(id);
    setState(() {
      _downloaded.remove(_fileName(item));
      _progress.remove(id);
    });
    _message('تم حذف النسخة المحلية فقط، وبقي الكتاب في الفهرس.');
  }

  String _fileName(Map<String, dynamic> item) =>
      (item['id'] ?? 'reference').toString().replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_').toLowerCase() + '.pdf';

  Future<File> _file(Map<String, dynamic> item) async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory(root.path + '/legal_references');
    await dir.create(recursive: true);
    return File(dir.path + '/' + _fileName(item));
  }

  Future<void> _refreshDownloaded() async {
    final found = <String>{};
    for (final item in _libraryItems) {
      if (await (await _file(item)).exists()) found.add(_fileName(item));
    }
    if (mounted) setState(() => _downloaded = found);
  }

  Future<void> _download(Map<String, dynamic> item) async {
    final file = await _file(item);
    if (await file.exists()) {
      _openPdf(file.path, (item['title'] ?? 'الكتاب').toString());
      return;
    }
    final pdfUrl = (item['pdf_url'] ?? item['download_url'] ?? '').toString().trim();
    final sourceUrl = (item['source_url'] ?? '').toString().trim();
    if (pdfUrl.isEmpty) {
      if (sourceUrl.isEmpty) {
        _message('النسخة الرقمية غير متوفرة حاليًا لهذا الكتاب.');
      } else {
        final ok = await launchUrl(Uri.parse(sourceUrl), mode: LaunchMode.externalApplication);
        if (!ok && mounted) _message('تعذر فتح مصدر الكتاب.');
      }
      return;
    }
    final id = (item['id'] ?? item['title'] ?? 'reference').toString();
    final temp = File(file.path + '.part');
    final existing = await temp.exists() ? await temp.length() : 0;
    final token = CancelToken();
    _tokens[id] = token;
    setState(() => _progress[id] = 0);
    try {
      final response = await _dio.get<List<int>>(
        pdfUrl,
        cancelToken: token,
        options: Options(
          responseType: ResponseType.bytes,
          followRedirects: true,
          maxRedirects: 5,
          headers: existing > 0 ? {'Range': 'bytes=' + existing.toString() + '-'} : null,
        ),
        onReceiveProgress: (received, total) {
          final base = existing > 0 ? existing : 0;
          final full = total > 0 ? base + total : 0;
          if (mounted && full > 0) setState(() => _progress[id] = (base + received) / full);
        },
      );
      final status = response.statusCode ?? 0;
      final bytes = response.data ?? const <int>[];
      if (existing > 0 && status == 206) {
        await temp.writeAsBytes(bytes, mode: FileMode.append, flush: true);
      } else {
        await temp.writeAsBytes(bytes, flush: true);
      }
      if (status != 200 && status != 206) throw const HttpException('download_status');
      final range = response.headers.value('content-range') ?? '';
      final totalText = range.contains('/') ? range.split('/').last : '';
      final expected = int.tryParse(totalText) ?? 0;
      if (expected > 0 && await temp.length() < expected) {
        throw const HttpException('partial_download');
      }
      if (await file.exists()) await file.delete();
      await temp.rename(file.path);
      _tokens.remove(id);
      setState(() {
        _progress.remove(id);
        _downloaded.add(_fileName(item));
        _reading.add(id);
      });
      await _saveFlags();
      _openPdf(file.path, (item['title'] ?? 'الكتاب').toString());
    } on DioException catch (e) {
      _tokens.remove(id);
      setState(() => _progress.remove(id));
      if (CancelToken.isCancel(e)) {
        _message('تم إيقاف التنزيل مؤقتًا. الملف الجزئي محفوظ ويمكن استئنافه.');
      } else {
        _message('توقف التنزيل بسبب الاتصال. الملف الجزئي محفوظ ويمكن استئنافه.');
      }
    } catch (_) {
      _tokens.remove(id);
      setState(() => _progress.remove(id));
      _message('تعذر إكمال التنزيل. الملف الجزئي محفوظ للاستئناف.');
    }
  }

  Future<void> _pause(Map<String, dynamic> item) async {
    final id = (item['id'] ?? item['title'] ?? 'reference').toString();
    _tokens[id]?.cancel('paused_by_user');
    _tokens.remove(id);
    if (mounted) setState(() => _progress.remove(id));
  }

  void _openPdf(String path, String title) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => Scaffold(
      backgroundColor: const Color(0xFF120D09),
      appBar: AppBar(title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis), backgroundColor: const Color(0xFF2A1A10)),
      body: PDFView(filePath: path),
    )));
  }

  void _message(String text) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
  );

  void _openSection(String title, bool sharia) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => _CategoryScreen(
      title: title,
      categories: sharia ? _shariaCategories : _legalCategories,
      items: _libraryItems,
      categoryOf: sharia ? _shariaCategory : _legalCategory,
      sharia: sharia,
      onDownload: _download,
      downloaded: _downloaded,
      progress: _progress,
      onInfo: _showInfo,
    )));
  }

  void _showInfo(Map<String, dynamic> item) {
    final id = (item['id'] ?? item['title'] ?? '').toString();
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _BookDetailsScreen(
        item: item,
        favorite: _favorites.contains(id),
        downloaded: _downloaded.contains(_fileName(item)),
        progress: _progress[id],
        onFavorite: () => _toggleFavorite(item),
        onDownload: () => _download(item),
        onDelete: () => _deleteLocal(item),
        onOpen: () async {
          final file = await _file(item);
          if (await file.exists() && mounted) _openPdf(file.path, (item['title'] ?? 'الكتاب').toString());
        },
      ),
    ));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF120D09),
    appBar: AppBar(
      backgroundColor: const Color(0xFF21150D), centerTitle: true,
      title: const Text('المكتبة', style: TextStyle(color: Color(0xFFE5BE72), fontWeight: FontWeight.bold)),
    ),
    body: _loading && _items.isEmpty
      ? const Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37)))
      : ListView(padding: const EdgeInsets.fromLTRB(14, 18, 14, 30), children: [
          _HeroCard(icon: Icons.library_books_rounded, title: 'المكتبة', subtitle: 'مراجع قانونية ومراجع شرعية مرتبة حسب الموضوع'),
          const SizedBox(height: 16),
          _TopCard(icon: Icons.balance_rounded, title: 'المكتبة القانونية', subtitle: 'شروح القوانين والكتب والدراسات والموسوعات القانونية', onTap: () => _openSection('المكتبة القانونية', false)),
          const SizedBox(height: 12),
          _TopCard(icon: Icons.menu_book_rounded, title: 'المكتبة الشرعية', subtitle: 'الفقه والمذاهب والفتاوى وأصول الفقه والمواريث', onTap: () => _openSection('المكتبة الشرعية', true)),
        ]),
  );
}

class _CategoryScreen extends StatelessWidget {
  final String title;
  final List<_LibraryCategory> categories;
  final List<Map<String, dynamic>> items;
  final String Function(Map<String, dynamic>) categoryOf;
  final bool sharia;
  final Future<void> Function(Map<String, dynamic>) onDownload;
  final Set<String> downloaded;
  final Map<String, double> progress;
  final void Function(Map<String, dynamic>) onInfo;

  const _CategoryScreen({
    required this.title, required this.categories, required this.items, required this.categoryOf,
    required this.sharia, required this.onDownload, required this.downloaded, required this.progress, required this.onInfo,
  });

  List<Map<String, dynamic>> _itemsFor(String category) => items.where((e) =>
      (sharia ? _shariaCategoryLocal(e) : _legalCategoryLocal(e)) == category).toList();

  String _text(Map<String, dynamic> e) => [e['title'], e['author'], e['category'], e['description'], e['full_summary']].join(' ').toLowerCase();
  bool _isSanhouri(Map<String, dynamic> e) => _text(e).contains('السنهوري') || _text(e).contains('سنهوري');

  String _legalCategoryLocal(Map<String, dynamic> e) {
    final t = _text(e);
    if (_isSanhouri(e) || t.contains('شرح') || t.contains('موسوعة') || t.contains('حاشية')) return 'الشروح والموسوعات';
    if (t.contains('قاموس') || t.contains('معجم') || t.contains('مصطلحات القانون')) return 'المعاجم والمداخل القانونية';
    if (t.contains('دراسة') || t.contains('بحث') || t.contains('أبحاث') || t.contains('دراسات')) return 'الدراسات والأبحاث';
    if (t.contains('دولي') || t.contains('مقارن') || t.contains('تنازع القوانين')) return 'القانون الدولي والمقارن';
    if (t.contains('أحوال شخصية') || t.contains('الزواج') || t.contains('الطلاق') || t.contains('الأسرة')) return 'الأحوال الشخصية';
    if (t.contains('عمل') || t.contains('عمال')) return 'قانون العمل';
    if (t.contains('إيجار') || t.contains('عقارات') || t.contains('ملكية') || t.contains('أراضي')) return 'العقارات والإيجارات';
    if (t.contains('تحكيم') || t.contains('إثبات') || t.contains('مرافعات') || t.contains('إجراءات')) return 'الإجراءات والإثبات والتحكيم';
    if (t.contains('تجاري') || t.contains('شركات') || t.contains('شركة') || t.contains('بحري')) return 'القانون التجاري والشركات';
    if (t.contains('جنائي') || t.contains('عقوبات') || t.contains('جريمة')) return 'القانون الجنائي والإجراءات الجزائية';
    if (t.contains('دستوري') || t.contains('إداري') || t.contains('الإدارة')) return 'القانون الدستوري والإداري';
    if (t.contains('طبي') || t.contains('صيدل') || t.contains('مهني') || t.contains('طب')) return 'القوانين المهنية والصحية';
    return 'القانون المدني';
  }

  String _shariaCategoryLocal(Map<String, dynamic> e) {
    final t = _text(e);
    if (t.contains('زيد')) return 'الفقه الزيدي';
    if (t.contains('شافعي')) return 'الفقه الشافعي';
    if (t.contains('حنفي')) return 'الفقه الحنفي';
    if (t.contains('مالكي')) return 'الفقه المالكي';
    if (t.contains('حنبلي')) return 'الفقه الحنبلي';
    if (t.contains('إمامي') || t.contains('شيعي') || t.contains('الخميني') || t.contains('جعفري')) return 'الفقه الإمامي';
    if (t.contains('أصول الفقه')) return 'أصول الفقه';
    if (t.contains('فرائض') || t.contains('مواريث')) return 'الفرائض والمواريث';
    if (t.contains('حديث')) return 'الحديث والفقه';
    if (t.contains('فتوى') || t.contains('فتاوى')) return 'الفتاوى';
    if (t.contains('معاملات') || t.contains('بيع') || t.contains('عقود')) return 'فقه المعاملات';
    if (t.contains('شرح') || t.contains('حاشية')) return 'الشروح والحواشي';
    if (t.contains('مقارن') || t.contains('مقارنة')) return 'الفقه المقارن';
    return 'التراث الإسلامي';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF120D09),
    appBar: AppBar(backgroundColor: const Color(0xFF21150D), centerTitle: true, title: Text(title, style: const TextStyle(color: Color(0xFFE5BE72), fontWeight: FontWeight.bold))),
    body: GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 420, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.55),
      itemCount: categories.length,
      itemBuilder: (_, i) {
        final c = categories[i];
        final count = _itemsFor(c.title).length;
        return _CategoryCard(category: c, count: count, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _BookListScreen(
          title: c.title, items: _itemsFor(c.title), onDownload: onDownload, downloaded: downloaded, progress: progress, onInfo: onInfo,
          isSanhouriHub: c.title == 'الشروح والموسوعات' && !sharia,
        ))));
      },
    ),
  );
}

class _BookListScreen extends StatefulWidget {
  final String title;
  final List<Map<String, dynamic>> items;
  final Future<void> Function(Map<String, dynamic>) onDownload;
  final Set<String> downloaded;
  final Map<String, double> progress;
  final void Function(Map<String, dynamic>) onInfo;
  final bool isSanhouriHub;

  const _BookListScreen({
    required this.title,
    required this.items,
    required this.onDownload,
    required this.downloaded,
    required this.progress,
    required this.onInfo,
    required this.isSanhouriHub,
  });

  @override
  State<_BookListScreen> createState() => _BookListScreenState();
}

class _BookListScreenState extends State<_BookListScreen> {
  String _query = '';
  String _filter = 'الكل';
  bool _grid = false;
  Set<String> _favorites = {};

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => _favorites = (prefs.getStringList('library_favorites_v1') ?? []).toSet());
  }

  String _id(Map<String, dynamic> e) => (e['id'] ?? e['title'] ?? '').toString();

  String _fileNameLocal(Map<String, dynamic> e) =>
      _id(e).replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_').toLowerCase() + '.pdf';

  bool _downloaded(Map<String, dynamic> e) => widget.downloaded.contains(_fileNameLocal(e));

  List<Map<String, dynamic>> get _filtered {
    final q = _query.trim().toLowerCase();
    final result = widget.items.where((e) {
      final text = [e['title'], e['author'], e['category'], e['description'], e['full_summary']].join(' ').toLowerCase();
      if (q.isNotEmpty && !text.contains(q)) return false;
      if (_filter == 'المفضلة' && !_favorites.contains(_id(e))) return false;
      if (_filter == 'غير مقروء' && _downloaded(e)) return false;
      if (_filter == 'قيد القراءة' && !_downloaded(e)) return false;
      return true;
    }).toList();
    result.sort((a, b) => (a['title'] ?? '').toString().compareTo((b['title'] ?? '').toString()));
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final all = _filtered;
    if (widget.isSanhouriHub) {
      final sanhouri = all.where((e) {
        final t = [e['title'], e['author'], e['description']].join(' ').toLowerCase();
        return t.contains('السنهوري') || t.contains('سنهوري');
      }).toList();
      final others = all.where((e) => !sanhouri.contains(e)).toList();
      return Scaffold(
        backgroundColor: const Color(0xFF120D09),
        appBar: AppBar(
          backgroundColor: const Color(0xFF21150D),
          centerTitle: true,
          title: Text(widget.title, style: const TextStyle(color: Color(0xFFE5BE72), fontWeight: FontWeight.bold)),
        ),
        body: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (sanhouri.isNotEmpty)
              _CollectionCard(
                title: 'السنهوري',
                subtitle: 'شروح السنهوري ومؤلفاته القانونية',
                count: sanhouri.length,
                icon: Icons.auto_stories_rounded,
                onTap: () => _pushBooks(context, 'السنهوري', sanhouri),
              ),
            if (others.isNotEmpty) ...[
              const SizedBox(height: 12),
              _CollectionCard(
                title: 'بقية الشروح والموسوعات',
                subtitle: 'الكتب القانونية الأخرى في هذا القسم',
                count: others.length,
                icon: Icons.library_books_rounded,
                onTap: () => _pushBooks(context, 'بقية الشروح والموسوعات', others),
              ),
            ],
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF120D09),
      appBar: AppBar(
        backgroundColor: const Color(0xFF21150D),
        centerTitle: true,
        title: Text(widget.title, style: const TextStyle(color: Color(0xFFE5BE72), fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            tooltip: _grid ? 'عرض قائمة' : 'عرض شبكة',
            onPressed: () => setState(() => _grid = !_grid),
            icon: Icon(_grid ? Icons.view_list_rounded : Icons.grid_view_rounded, color: const Color(0xFFD4AF37)),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 5),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              style: const TextStyle(color: Colors.white),
              textDirection: TextDirection.rtl,
              decoration: InputDecoration(
                hintText: 'ابحث باسم الكتاب أو المؤلف أو الموضوع',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.search, color: Color(0xFFD4AF37)),
                filled: true,
                fillColor: const Color(0xFF2A1A10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              ),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: ['الكل', 'غير مقروء', 'قيد القراءة', 'المفضلة'].map((label) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: ChoiceChip(
                  label: Text(label),
                  selected: _filter == label,
                  selectedColor: const Color(0xFFD4AF37),
                  backgroundColor: const Color(0xFF21150D),
                  labelStyle: TextStyle(color: _filter == label ? Colors.black : Colors.white70),
                  onSelected: (_) => setState(() => _filter = label),
                ),
              )).toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Row(
              textDirection: TextDirection.rtl,
              children: [
                Text(all.length.toString() + ' كتاب', style: const TextStyle(color: Color(0xFFE5BE72), fontWeight: FontWeight.bold)),
                const Spacer(),
                const Text('ترتيب: العنوان', style: TextStyle(color: Colors.white54)),
              ],
            ),
          ),
          Expanded(
            child: all.isEmpty
                ? const Center(child: Text('لا توجد كتب مطابقة حاليًا', style: TextStyle(color: Colors.white60)))
                : _grid
                    ? GridView.builder(
                        padding: const EdgeInsets.fromLTRB(10, 4, 10, 24),
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 320,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: .68,
                        ),
                        itemCount: all.length,
                        itemBuilder: (_, i) => _BookCard(
                          item: all[i],
                          downloaded: _downloaded(all[i]),
                          progress: widget.progress,
                          onDownload: widget.onDownload,
                          onInfo: widget.onInfo,
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(10, 4, 10, 24),
                        itemCount: all.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _BookCard(
                          item: all[i],
                          downloaded: _downloaded(all[i]),
                          progress: widget.progress,
                          onDownload: widget.onDownload,
                          onInfo: widget.onInfo,
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  void _pushBooks(BuildContext context, String title, List<Map<String, dynamic>> items) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _BookListScreen(
        title: title,
        items: items,
        onDownload: widget.onDownload,
        downloaded: widget.downloaded,
        progress: widget.progress,
        onInfo: widget.onInfo,
        isSanhouriHub: false,
      ),
    ));
  }
}

class _LibraryCategory {
  final String title;
  final IconData icon;
  const _LibraryCategory(this.title, this.icon);
}

class _HeroCard extends StatelessWidget {
  final IconData icon; final String title; final String subtitle;
  const _HeroCard({required this.icon, required this.title, required this.subtitle});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(color: const Color(0xA91F140D), borderRadius: BorderRadius.circular(24), border: Border.all(color: const Color(0x88D4AF37))),
    child: Row(textDirection: TextDirection.rtl, children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(title, textAlign: TextAlign.right, style: const TextStyle(color: Color(0xFFE5BE72), fontSize: 24, fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        Text(subtitle, textAlign: TextAlign.right, style: const TextStyle(color: Colors.white70, height: 1.5)),
      ])),
      const SizedBox(width: 12), Icon(icon, size: 58, color: Color(0xFFD4AF37)),
    ]),
  );
}

class _TopCard extends StatelessWidget {
  final IconData icon; final String title; final String subtitle; final VoidCallback onTap;
  const _TopCard({required this.icon, required this.title, required this.subtitle, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap, borderRadius: BorderRadius.circular(24),
    child: Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: const Color(0xB31F140D), borderRadius: BorderRadius.circular(24), border: Border.all(color: const Color(0x88D4AF37))),
      child: Row(textDirection: TextDirection.rtl, children: [
        const Icon(Icons.chevron_left_rounded, color: Color(0xFFD4AF37), size: 34),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(title, textAlign: TextAlign.right, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text(subtitle, textAlign: TextAlign.right, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.45)),
        ])),
        const SizedBox(width: 14), Icon(icon, size: 48, color: const Color(0xFFD4AF37)),
      ]),
    ),
  );
}

class _CategoryCard extends StatelessWidget {
  final _LibraryCategory category; final int count; final VoidCallback onTap;
  const _CategoryCard({required this.category, required this.count, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap, borderRadius: BorderRadius.circular(22),
    child: Container(padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: const Color(0xA91F140D), borderRadius: BorderRadius.circular(22), border: Border.all(color: const Color(0x66D4AF37))),
      child: Row(textDirection: TextDirection.rtl, children: [
        Icon(category.icon, color: const Color(0xFFD4AF37), size: 38), const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(category.title, textAlign: TextAlign.right, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, height: 1.35)),
          const SizedBox(height: 5), Text(count.toString() + ' كتاب', style: const TextStyle(color: Color(0xFFE5BE72), fontSize: 12)),
        ])),
      ]),
    ),
  );
}

class _CollectionCard extends StatelessWidget {
  final String title; final String subtitle; final int count; final IconData icon; final VoidCallback onTap;
  const _CollectionCard({required this.title, required this.subtitle, required this.count, required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap, borderRadius: BorderRadius.circular(22),
    child: Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: const Color(0xA91F140D), borderRadius: BorderRadius.circular(22), border: Border.all(color: const Color(0x88D4AF37))),
      child: Row(textDirection: TextDirection.rtl, children: [
        const Icon(Icons.chevron_left_rounded, color: Color(0xFFD4AF37), size: 32), const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(title, textAlign: TextAlign.right, style: const TextStyle(color: Color(0xFFE5BE72), fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 5), Text(subtitle, textAlign: TextAlign.right, style: const TextStyle(color: Colors.white70, height: 1.45)),
          const SizedBox(height: 6), Text(count.toString() + ' كتاب', style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ])),
        Icon(icon, size: 46, color: const Color(0xFFD4AF37)),
      ]),
    ),
  );
}

class _BookCard extends StatelessWidget {
  final Map<String, dynamic> item; final Set<String> downloaded; final Map<String, double> progress;
  final Future<void> Function(Map<String, dynamic>) onDownload; final void Function(Map<String, dynamic>) onInfo;
  const _BookCard({required this.item, required this.downloaded, required this.progress, required this.onDownload, required this.onInfo});

  String _fileName() => (item['id'] ?? 'reference').toString().replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_').toLowerCase() + '.pdf';

  @override
  Widget build(BuildContext context) {
    final id = (item['id'] ?? '').toString();
    final done = downloaded.contains(_fileName());
    final p = progress[id];
    final cover = (item['cover_image_url'] ?? '').toString().trim();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xB31F140D), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0x66D4AF37))),
      child: Row(textDirection: TextDirection.rtl, children: [
        SizedBox(width: 70, height: 94, child: cover.isEmpty ? const Icon(Icons.menu_book_rounded, size: 44, color: Color(0xFFD4AF37)) : ClipRRect(borderRadius: BorderRadius.circular(10), child: CachedNetworkImage(imageUrl: cover, fit: BoxFit.cover, errorWidget: (_, __, ___) => const Icon(Icons.menu_book_rounded, size: 44, color: Color(0xFFD4AF37))))),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text((item['title'] ?? 'كتاب').toString(), textAlign: TextAlign.right, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, height: 1.35)),
          if ((item['author'] ?? '').toString().trim().isNotEmpty) ...[
            const SizedBox(height: 5), Text(item['author'].toString(), textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFE5BE72), fontSize: 12)),
          ],
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            IconButton(tooltip: 'معلومات الكتاب', onPressed: () => onInfo(item), icon: const Icon(Icons.info_outline_rounded, color: Color(0xFFD4AF37))),
            if (p != null) SizedBox(width: 32, height: 32, child: CircularProgressIndicator(value: p, color: const Color(0xFFD4AF37), strokeWidth: 3))
            else IconButton(tooltip: done ? 'فتح الكتاب' : 'تنزيل الكتاب', onPressed: () => onDownload(item), icon: Icon(done ? Icons.menu_book_rounded : Icons.download_rounded, color: const Color(0xFFD4AF37))),
          ]),
        ])),
      ]),
    );
  }
}
