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
];

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  static const _cacheKey = 'cached_legal_references_json_v14';
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
    final section = (item['section'] ?? '').toString().trim().toLowerCase();
    final category = (item['category'] ?? '').toString().trim().toLowerCase();
    final text = _text(item);

    // التصنيف الصريح للمكتبة الشرعية له الأولوية ولا نستثني منه الأصول
    // أو المواريث أو الحديث أو المعاملات؛ فهذه موضوعات شرعية أصيلة.
    if (section == 'sharia' || section.contains('مراجع شرعية')) return true;

    // بعض السجلات القديمة وُسمت خطأً بأنها قانونية وفقهية؛ نعيد فحص
    // عنوانها ووصفها قبل اعتماد القسم القانوني.
    final mixedLegacyCategory = category.contains('مراجع قانونية وفقهية');
    if (section == 'legal' ||
        section.contains('مراجع قانونية') ||
        section.contains('شروح وموسوعات') ||
        section.contains('دراسات مقارنة') ||
        section.contains('دراسات وأبحاث')) {
      if (!mixedLegacyCategory) return false;
    }

    const shariaTerms = [
      'فقه زيدي', 'الزيدية', 'فقه شافعي', 'الشافعي', 'فقه حنفي', 'الحنفي',
      'فقه مالكي', 'المالكي', 'فقه حنبلي', 'الحنبلي', 'الفقه الإمامي',
      'الإمامية', 'الجعفري', 'شيعي', 'أصول الفقه', 'أصول الفقة',
      'الفرائض', 'المواريث', 'الحديث', 'فتاوى', 'الفتاوى', 'قواعد فقهية',
      'الشريعة', 'فقه إسلامي', 'الفقه الإسلامي', 'الأحكام السلطانية',
      'البحر الزخار', 'التاج المذهب', 'شرح الأزهار', 'الروض النضير',
      'المحلى بالآثار', 'المغني', 'الموافقات', 'بداية المجتهد',
      'تحفة المحتاج', 'روضة الطالبين', 'سبل السلام', 'نهاية المحتاج',
      'مغني المحتاج', 'نيل الأوطار', 'الرسالة', 'الأم',
      'الاعتصام بحبل الله', 'الطرق الحكمية'
    ];
    if (shariaTerms.any(text.contains)) return true;

    if (category.contains('فقه زيدي') ||
        category.contains('فقه شافعي') ||
        category.contains('فقه حنفي') ||
        category.contains('فقه مالكي') ||
        category.contains('فقه حنبلي') ||
        category.contains('فقه إمامي') ||
        category.contains('أصول الفقه') ||
        category.contains('الفرائض') ||
        category.contains('فتاوى') ||
        category.contains('حديث وفقه')) return true;

    if (section == 'legal' ||
        section.contains('مراجع قانونية') ||
        section.contains('شروح وموسوعات') ||
        section.contains('دراسات مقارنة') ||
        section.contains('دراسات وأبحاث')) return false;

    return false;
  }

  bool _isSanhouri(Map<String, dynamic> item) {
    final text = _text(item);
    return text.contains('السنهوري') || text.contains('سنهوري');
  }

  String _legalCategory(Map<String, dynamic> item) {
    final explicit = (item['category'] ?? '').toString().trim();
    const known = _legalCategories;
    for (final category in known) {
      if (explicit == category.title) return category.title;
    }
    final text = _text(item);
    if (_isSanhouri(item) || text.contains('شرح') || text.contains('موسوعة') || text.contains('حاشية')) return 'الشروح والموسوعات';
    if (text.contains('قاموس') || text.contains('معجم') || text.contains('مصطلحات القانون')) return 'المعاجم والمداخل القانونية';
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
    final explicit = (item['category'] ?? '').toString().trim();
    const known = _shariaCategories;
    for (final category in known) {
      if (explicit == category.title) return category.title;
    }
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
    if (text.contains('تاريخ التشريع') || text.contains('تاريخ') || text.contains('سيرة') || text.contains('تراث')) return 'الفقه المقارن';
    return 'الفقه المقارن';
  }

  List<Map<String, dynamic>> get _libraryItems {
    final seenIds = <String>{};
    final seenTitles = <String>{};
    final unique = <Map<String, dynamic>>[];
    for (final item in _items) {
      if (_isSupremeCourt(item)) continue;
      final id = (item['id'] ?? '').toString().trim();
      final title = (item['title'] ?? '').toString().toLowerCase()
          .replaceAll(RegExp(r'[ـًٌٍَُِّْٰ]'), '')
          .replaceAll(RegExp(r'[أإآ]'), 'ا')
          .replaceAll(RegExp(r'[^\\p{L}\\p{N}]+', unicode: true), ' ')
          .trim()
          .replaceAll(RegExp(r'\\s+'), ' ');
      if ((id.isNotEmpty && !seenIds.add(id)) ||
          (title.isNotEmpty && !seenTitles.add(title))) {
        continue;
      }
      unique.add(item);
    }
    return unique;
  }

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
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _PdfReaderScreen(path: path, title: title),
    ));
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
      onPause: _pause,
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
      actions: [
        IconButton(
          tooltip: 'مدير التنزيلات',
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => _DownloadManagerScreen(
              items: _libraryItems,
              downloaded: _downloaded,
              progress: _progress,
              onDownload: _download,
              onPause: _pause,
              onDelete: _deleteLocal,
              onOpen: (item) async {
                final file = await _file(item);
                if (await file.exists() && mounted) _openPdf(file.path, (item['title'] ?? 'الكتاب').toString());
              },
            ),
          )),
          icon: const Icon(Icons.download_for_offline_rounded, color: Color(0xFFD4AF37)),
        ),
      ],
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
  final Future<void> Function(Map<String, dynamic>) onPause;
  final Set<String> downloaded;
  final Map<String, double> progress;
  final void Function(Map<String, dynamic>) onInfo;

  const _CategoryScreen({
    required this.title, required this.categories, required this.items, required this.categoryOf,
    required this.sharia, required this.onDownload, required this.onPause, required this.downloaded, required this.progress, required this.onInfo,
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
          title: c.title, items: _itemsFor(c.title), onDownload: onDownload, onPause: onPause, downloaded: downloaded, progress: progress, onInfo: onInfo,
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
  final Future<void> Function(Map<String, dynamic>) onPause;
  final Set<String> downloaded;
  final Map<String, double> progress;
  final void Function(Map<String, dynamic>) onInfo;
  final bool isSanhouriHub;

  const _BookListScreen({
    required this.title,
    required this.items,
    required this.onDownload,
    required this.onPause,
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
                          onPause: widget.onPause,
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
                          onPause: widget.onPause,
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
        onPause: widget.onPause,
        downloaded: widget.downloaded,
        progress: widget.progress,
        onInfo: widget.onInfo,
        isSanhouriHub: false,
      ),
    ));
  }
}

class _DownloadManagerScreen extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final Set<String> downloaded;
  final Map<String, double> progress;
  final Future<void> Function(Map<String, dynamic>) onDownload;
  final Future<void> Function(Map<String, dynamic>) onPause;
  final Future<void> Function(Map<String, dynamic>) onDelete;
  final Future<void> Function(Map<String, dynamic>) onOpen;

  const _DownloadManagerScreen({
    required this.items,
    required this.downloaded,
    required this.progress,
    required this.onDownload,
    required this.onPause,
    required this.onDelete,
    required this.onOpen,
  });

  String _fileName(Map<String, dynamic> item) =>
      (item['id'] ?? item['title'] ?? 'reference').toString().replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_').toLowerCase() + '.pdf';

  @override
  Widget build(BuildContext context) {
    final active = items.where((e) {
      final id = (e['id'] ?? e['title'] ?? '').toString();
      return downloaded.contains(_fileName(e)) || progress.containsKey(id);
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF120D09),
      appBar: AppBar(
        backgroundColor: const Color(0xFF21150D),
        centerTitle: true,
        title: const Text('مدير التنزيلات'),
      ),
      body: active.isEmpty
          ? const Center(child: Text('لا توجد تنزيلات نشطة أو كتب محفوظة', style: TextStyle(color: Colors.white60)))
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: active.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final item = active[i];
                final id = (item['id'] ?? item['title'] ?? '').toString();
                final p = progress[id];
                final done = downloaded.contains(_fileName(item));
                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xB31F140D),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0x66D4AF37)),
                  ),
                  child: Row(
                    textDirection: TextDirection.rtl,
                    children: [
                      const Icon(Icons.picture_as_pdf_rounded, color: Color(0xFFD4AF37), size: 38),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          (item['title'] ?? 'كتاب').toString(),
                          textAlign: TextAlign.right,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (p != null)
                        SizedBox(
                          width: 38,
                          height: 38,
                          child: CircularProgressIndicator(value: p, color: const Color(0xFFD4AF37), strokeWidth: 3),
                        ),
                      IconButton(
                        onPressed: p != null ? () => onPause(item) : done ? () => onOpen(item) : () => onDownload(item),
                        icon: Icon(p != null ? Icons.pause_rounded : done ? Icons.menu_book_rounded : Icons.download_rounded, color: const Color(0xFFD4AF37)),
                      ),
                      if (done)
                        IconButton(
                          onPressed: () => onDelete(item),
                          icon: const Icon(Icons.delete_outline_rounded, color: Colors.white54),
                        ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class _BookDetailsScreen extends StatelessWidget {
  final Map<String, dynamic> item;
  final bool favorite;
  final bool downloaded;
  final double? progress;
  final VoidCallback onFavorite;
  final VoidCallback onDownload;
  final VoidCallback onDelete;
  final VoidCallback onOpen;

  const _BookDetailsScreen({
    required this.item,
    required this.favorite,
    required this.downloaded,
    required this.progress,
    required this.onFavorite,
    required this.onDownload,
    required this.onDelete,
    required this.onOpen,
  });

  String _value(String key) {
    final v = (item[key] ?? '').toString().trim();
    return v.isEmpty ? 'غير متوفر' : v;
  }

  @override
  Widget build(BuildContext context) {
    final cover = (item['cover_url'] ?? item['cover_image_url'] ?? '').toString().trim();
    final pdf = (item['pdf_url'] ?? item['download_url'] ?? '').toString().trim();
    final summary = (item['full_summary'] ?? item['description'] ?? '').toString().trim();
    return Scaffold(
      backgroundColor: const Color(0xFF120D09),
      appBar: AppBar(
        backgroundColor: const Color(0xFF21150D),
        centerTitle: true,
        title: Text((item['title'] ?? 'تفاصيل الكتاب').toString(), maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            textDirection: TextDirection.rtl,
            children: [
              _DetailCover(url: cover),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text((item['title'] ?? 'كتاب').toString(), textAlign: TextAlign.right, style: const TextStyle(color: Color(0xFFE5BE72), fontSize: 20, fontWeight: FontWeight.w900, height: 1.4)),
                    const SizedBox(height: 10),
                    Text('المؤلف: ' + _value('author'), textAlign: TextAlign.right, style: const TextStyle(color: Colors.white70)),
                    const SizedBox(height: 6),
                    Text('التصنيف: ' + _value('category'), textAlign: TextAlign.right, style: const TextStyle(color: Colors.white70)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: onFavorite,
                icon: Icon(favorite ? Icons.star_rounded : Icons.star_border_rounded, color: const Color(0xFFD4AF37)),
                label: const Text('المفضلة'),
              ),
              if (downloaded)
                OutlinedButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.menu_book_rounded, color: Color(0xFFD4AF37)),
                  label: const Text('قراءة'),
                )
              else if (pdf.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: onDownload,
                  icon: const Icon(Icons.download_rounded, color: Color(0xFFD4AF37)),
                  label: const Text('تنزيل'),
                ),
              if (downloaded)
                OutlinedButton.icon(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.white54),
                  label: const Text('حذف النسخة'),
                ),
            ],
          ),
          if (progress != null) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(value: progress, color: const Color(0xFFD4AF37), backgroundColor: Colors.white12),
            const SizedBox(height: 5),
            Text((progress! * 100).round().toString() + '%', textAlign: TextAlign.right, style: const TextStyle(color: Color(0xFFE5BE72))),
          ],
          const SizedBox(height: 18),
          _DetailSection('بيانات الكتاب', [
            _DetailRow('العنوان', _value('title')),
            _DetailRow('المؤلف', _value('author')),
            _DetailRow('سنة الوفاة', _value('author_death_year')),
            _DetailRow('الناشر', _value('publisher')),
            _DetailRow('الطبعة', _value('edition')),
            _DetailRow('عدد الصفحات', _value('pages_count')),
            _DetailRow('مطابقة المطبوع', _value('print_matching')),
            _DetailRow('الحجم', _value('file_size')),
            _DetailRow('تاريخ الإضافة', _value('date_added')),
          ]),
          if (summary.isNotEmpty) ...[
            const SizedBox(height: 14),
            _DetailSection('نبذة', [_DetailRow('', summary)]),
          ],
          const SizedBox(height: 14),
          _DetailSection('حالة النسخة', [
            _DetailRow('', downloaded
                ? 'النسخة محفوظة داخل التطبيق ويمكن قراءتها دون إعادة التنزيل.'
                : pdf.isNotEmpty
                    ? 'تتوفر نسخة PDF للتنزيل.'
                    : 'النسخة الرقمية غير متوفرة حاليًا؛ بقيت بيانات الكتاب في الفهرس.'),
          ]),
        ],
      ),
    );
  }
}

class _DetailCover extends StatelessWidget {
  final String url;
  const _DetailCover({required this.url});

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return Container(
        width: 130,
        height: 180,
        decoration: BoxDecoration(
          color: const Color(0xFF2A1A10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0x66D4AF37)),
        ),
        child: const Icon(Icons.menu_book_rounded, size: 52, color: Color(0xFFD4AF37)),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: CachedNetworkImage(
        imageUrl: url,
        width: 130,
        height: 180,
        fit: BoxFit.cover,
        fadeInDuration: const Duration(milliseconds: 250),
        placeholder: (_, __) => const SizedBox(
          width: 130,
          height: 180,
          child: Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37))),
        ),
        errorWidget: (_, __, ___) => const SizedBox(
          width: 130,
          height: 180,
          child: Center(child: Icon(Icons.menu_book_rounded, size: 52, color: Color(0xFFD4AF37))),
        ),
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  final String title;
  final List<_DetailRow> rows;
  const _DetailSection(this.title, this.rows);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xB31F140D),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0x44D4AF37)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(title, textAlign: TextAlign.right, style: const TextStyle(color: Color(0xFFE5BE72), fontWeight: FontWeight.w900, fontSize: 17)),
        const SizedBox(height: 8),
        ...rows.map((row) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            textDirection: TextDirection.rtl,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (row.label.isNotEmpty)
                SizedBox(width: 105, child: Text(row.label, textAlign: TextAlign.right, style: const TextStyle(color: Color(0xFFE5BE72), fontWeight: FontWeight.bold, fontSize: 12))),
              if (row.label.isNotEmpty) const SizedBox(width: 8),
              Expanded(child: Text(row.value, textAlign: TextAlign.right, style: const TextStyle(color: Colors.white70, height: 1.45))),
            ],
          ),
        )),
      ],
    ),
  );
}

class _DetailRow {
  final String label;
  final String value;
  const _DetailRow(this.label, this.value);
}

class _PdfReaderScreen extends StatefulWidget {
  final String path;
  final String title;
  const _PdfReaderScreen({required this.path, required this.title});

  @override
  State<_PdfReaderScreen> createState() => _PdfReaderScreenState();
}

class _PdfReaderScreenState extends State<_PdfReaderScreen> {
  PDFViewController? _controller;
  SharedPreferences? _prefs;
  int _page = 0;
  int _pages = 0;
  Set<int> _bookmarks = {};

  String get _key {
    final name = widget.path.split('/').last.replaceAll('.pdf', '');
    return 'library_reader_' + name;
  }

  @override
  void initState() {
    super.initState();
    _loadReaderState();
  }

  Future<void> _loadReaderState() async {
    final prefs = await SharedPreferences.getInstance();
    final page = prefs.getInt(_key + '_page') ?? 0;
    final marks = prefs.getStringList(_key + '_bookmarks') ?? [];
    if (!mounted) return;
    setState(() {
      _prefs = prefs;
      _page = page;
      _bookmarks = marks.map(int.tryParse).whereType<int>().toSet();
    });
  }

  Future<void> _savePage(int page) async {
    _page = page;
    await _prefs?.setInt(_key + '_page', page);
    if (mounted) setState(() {});
  }

  Future<void> _toggleBookmark() async {
    if (_bookmarks.contains(_page)) {
      _bookmarks.remove(_page);
    } else {
      _bookmarks.add(_page);
    }
    await _prefs?.setStringList(_key + '_bookmarks', _bookmarks.map((e) => e.toString()).toList());
    if (mounted) setState(() {});
  }

  Future<void> _jumpToPage() async {
    if (_pages <= 0 || _controller == null) return;
    final controller = TextEditingController(text: (_page + 1).toString());
    final value = await showDialog<int>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF21150D),
        title: const Text('الانتقال إلى صفحة', textAlign: TextAlign.right),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          textDirection: TextDirection.rtl,
          decoration: InputDecoration(hintText: 'من 1 إلى ' + _pages.toString()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () {
              final p = int.tryParse(controller.text.trim());
              if (p == null || p < 1 || p > _pages) return;
              Navigator.pop(context, p);
            },
            child: const Text('انتقال'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null) await _controller?.setPage(value - 1);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: const Color(0xFF21150D),
      title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      actions: [
        IconButton(
          tooltip: 'الانتقال إلى صفحة',
          onPressed: _jumpToPage,
          icon: const Icon(Icons.input_rounded, color: Color(0xFFD4AF37)),
        ),
        IconButton(
          tooltip: _bookmarks.contains(_page) ? 'إزالة العلامة' : 'حفظ العلامة',
          onPressed: _toggleBookmark,
          icon: Icon(
            _bookmarks.contains(_page) ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
            color: const Color(0xFFD4AF37),
          ),
        ),
        PopupMenuButton<int>(
          tooltip: 'العلامات المحفوظة',
          icon: const Icon(Icons.bookmarks_rounded, color: Color(0xFFD4AF37)),
          onSelected: (p) => _controller?.setPage(p),
          itemBuilder: (_) {
            final marks = _bookmarks.toList()..sort();
            if (marks.isEmpty) {
              return const [PopupMenuItem(enabled: false, value: -1, child: Text('لا توجد علامات محفوظة'))];
            }
            return marks.map((p) => PopupMenuItem(value: p, child: Text('صفحة ' + (p + 1).toString()))).toList();
          },
        ),
      ],
    ),
    body: Stack(
      children: [
        PDFView(
          filePath: widget.path,
          defaultPage: _page,
          enableSwipe: true,
          swipeHorizontal: false,
          autoSpacing: true,
          pageFling: true,
          pageSnap: true,
          showScrollIndicators: true,
          fitPolicy: FitPolicy.BOTH,
          backgroundColor: Colors.black,
          onViewCreated: (controller) async {
            _controller = controller;
            final count = await controller.getPageCount() ?? 0;
            if (!mounted) return;
            setState(() => _pages = count);
            if (_page < count) await controller.setPage(_page);
          },
          onRender: (pages) {
            if (mounted && pages != null) setState(() => _pages = pages);
          },
          onPageChanged: (page, total) {
            if (page == null) return;
            _savePage(page);
            if (total != null && mounted) setState(() => _pages = total);
          },
          onError: (_) {},
          onPageError: (_, __) {},
        ),
        if (_pages > 1)
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: Material(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(16),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _page > 0 ? () => _controller?.setPage(_page - 1) : null,
                    icon: const Icon(Icons.chevron_left_rounded, color: Color(0xFFD4AF37)),
                  ),
                  Expanded(
                    child: Slider(
                      value: _page.clamp(0, _pages - 1).toDouble(),
                      min: 0,
                      max: (_pages - 1).toDouble(),
                      divisions: _pages - 1,
                      activeColor: const Color(0xFFD4AF37),
                      onChanged: (value) => _controller?.setPage(value.round()),
                    ),
                  ),
                  Text((_page + 1).toString() + '/' + _pages.toString(), style: const TextStyle(color: Colors.white)),
                  IconButton(
                    onPressed: _page < _pages - 1 ? () => _controller?.setPage(_page + 1) : null,
                    icon: const Icon(Icons.chevron_right_rounded, color: Color(0xFFD4AF37)),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
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
  final Map<String, dynamic> item;
  final bool downloaded;
  final Map<String, double> progress;
  final Future<void> Function(Map<String, dynamic>) onDownload;
  final Future<void> Function(Map<String, dynamic>) onPause;
  final void Function(Map<String, dynamic>) onInfo;

  const _BookCard({
    required this.item,
    required this.downloaded,
    required this.progress,
    required this.onDownload,
    required this.onPause,
    required this.onInfo,
  });

  @override
  Widget build(BuildContext context) {
    final id = (item['id'] ?? '').toString();
    final p = progress[id];
    final cover = (item['cover_image_url'] ?? item['cover_url'] ?? '').toString().trim();
    final title = (item['title'] ?? 'كتاب').toString();
    final author = (item['author'] ?? '').toString().trim();

    Widget coverWidget() {
      if (cover.isEmpty) {
        return Container(
          color: const Color(0xFF21150D),
          child: const Icon(Icons.menu_book_rounded, size: 42, color: Color(0xFFD4AF37)),
        );
      }
      return CachedNetworkImage(
        imageUrl: cover,
        fit: BoxFit.cover,
        placeholder: (_, __) => const Center(
          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFD4AF37)),
        ),
        errorWidget: (_, __, ___) => const Center(
          child: Icon(Icons.menu_book_rounded, size: 42, color: Color(0xFFD4AF37)),
        ),
      );
    }

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => onInfo(item),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          textDirection: TextDirection.rtl,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 88,
              height: 118,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: coverWidget(),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    textAlign: TextAlign.right,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      height: 1.35,
                    ),
                  ),
                  if (author.isNotEmpty) ...[
                    const SizedBox(height: 7),
                    Text(
                      author,
                      textAlign: TextAlign.right,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 15,
                        height: 1.3,
                      ),
                    ),
                  ],
                  if (p != null) ...[
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: p,
                      minHeight: 3,
                      backgroundColor: Colors.white12,
                      color: const Color(0xFFD4AF37),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 54,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'معلومات الكتاب',
                    onPressed: () => onInfo(item),
                    icon: const Icon(
                      Icons.info_rounded,
                      color: Color(0xFF8D99AE),
                      size: 34,
                    ),
                  ),
                  if (p != null)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'إيقاف التنزيل',
                      onPressed: () => onPause(item),
                      icon: const Icon(
                        Icons.pause_rounded,
                        color: Color(0xFFD4AF37),
                        size: 34,
                      ),
                    )
                  else
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: downloaded ? 'فتح الكتاب' : 'تحميل الكتاب',
                      onPressed: () => onDownload(item),
                      icon: Icon(
                        downloaded ? Icons.menu_book_rounded : Icons.download_rounded,
                        color: const Color(0xFFD4AF37),
                        size: 36,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
