import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

const kLegalReferencesMergedIndexUrl = 'https://raw.githubusercontent.com/ghgfcrcgrf57566-beep/Encyclopedia-of-Yemeni-Law/main/legal_references/merged_books.json';

const _sections = <String>[
  'مراجع قانونية',
  'مراجع شرعية',
  'شروح وموسوعات',
  'دراسات مقارنة ودراسات وأبحاث',
];

class LegalReferencesScreen extends StatefulWidget {
  const LegalReferencesScreen({super.key});

  @override
  State<LegalReferencesScreen> createState() => _LegalReferencesScreenState();
}

class _LegalReferencesScreenState extends State<LegalReferencesScreen> {
  static const _cacheKey = 'cached_legal_references_json_v11';
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 90),
    responseType: ResponseType.plain,
  ));
  final _search = TextEditingController();
  List<Map<String, dynamic>> _items = [];
  Set<String> _downloaded = {};
  final Map<String, double> _progress = {};
  bool _loading = true;
  String _query = '';
  String _section = _sections.first;

  @override
  void initState() {
    super.initState();
    _loadIndex();
  }

  @override
  void dispose() {
    _search.dispose();
    _dio.close(force: true);
    super.dispose();
  }

  List<Map<String, dynamic>> _parse(String raw) {
    try {
      final value = jsonDecode(raw);
      if (value is! List) return [];
      return value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) {
      return [];
    }
  }

  bool _valid(Map<String, dynamic> item) {
    final pdf = '${item['pdf_url'] ?? ''}'.trim();
    final source = '${item['source_url'] ?? ''}'.trim();
    final url = pdf.isNotEmpty ? pdf : source;
    return url.isNotEmpty && Uri.tryParse(url)?.hasScheme == true;
  }

  List<Map<String, dynamic>> _merge(List<List<Map<String, dynamic>>> groups) {
    final result = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final group in groups) {
      for (final item in group) {
        if (!_valid(item)) continue;
        final id = '${item['id'] ?? ''}'.trim();
        if (id.isNotEmpty && seen.add(id)) result.add(item);
      }
    }
    return result;
  }

  String _sectionOf(Map<String, dynamic> item) {
    final id = '${item['id'] ?? ''}'.toLowerCase();
    final text = [item['title'], item['author'], item['category'], item['description'], item['full_summary'], id]
        .join(' ')
        .toLowerCase();

    if (text.contains('مقارن') || text.contains('مقارنة') || text.contains('دراسة مقارنة') ||
        text.contains('دراسات مقارنة') || text.contains('أبحاث') || text.contains('بحث مقارن') ||
        id.contains('comparative') || id.contains('philosophy_legislation')) {
      return 'دراسات مقارنة ودراسات وأبحاث';
    }

    if (text.contains('شرح') || text.contains('شروح') || text.contains('موسوعة') ||
        text.contains('موسوعات') || text.contains('حاشية') || text.contains('مجموع شرح') ||
        text.contains('مرآة العقول') || text.contains('كشف الأسرار')) {
      return 'شروح وموسوعات';
    }

    const religious = <String>[
      'فقه', 'شرعي', 'الشريعة', 'إسلام', 'الإسلام', 'المذاهب', 'مذهب', 'أوقاف', 'وقف',
      'حديث', 'أصول الفقه', 'قواعد فقهية', 'فتاوى', 'الفرائض', 'المواريث', 'الحلال والحرام',
      'التشريع الإسلامي', 'الشيعة', 'السنة', 'السنّة', 'جعفر الصادق', 'الفقه الإمامي', 'الإمامية',
    ];
    if (religious.any(text.contains)) return 'مراجع شرعية';
    return 'مراجع قانونية';
  }

  List<Map<String, dynamic>> get _visible => _items.where((item) {
    if (_sectionOf(item) != _section) return false;
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return [item['title'], item['author'], item['category'], item['description'], item['full_summary']]
        .join(' ')
        .toLowerCase()
        .contains(q);
  }).toList();

  Future<void> _loadIndex() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_cacheKey);
    if (cached != null) {
      final value = _merge([_parse(cached)]);
      if (value.isNotEmpty && mounted) setState(() => _items = value);
    }

    try {
      final response = await _dio.get<String>(kLegalReferencesMergedIndexUrl);
      if (response.statusCode == 200 && response.data != null) {
        final merged = _merge([_parse(response.data!)]);
        if (merged.isNotEmpty) {
          await prefs.setString(_cacheKey, jsonEncode(merged));
          if (mounted) setState(() => _items = merged);
        }
      }
    } catch (_) {}

    await _refreshDownloaded();
    if (mounted) setState(() => _loading = false);
  }

  String _fileName(Map<String, dynamic> item) =>
      '${item['id'] ?? 'reference'}'.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_').toLowerCase() + '.pdf';

  Future<File> _file(Map<String, dynamic> item) async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory('${root.path}/legal_references');
    await dir.create(recursive: true);
    return File('${dir.path}/${_fileName(item)}');
  }

  Future<void> _refreshDownloaded() async {
    final found = <String>{};
    for (final item in _items) {
      if (await (await _file(item)).exists()) found.add(_fileName(item));
    }
    if (mounted) setState(() => _downloaded = found);
  }

  Future<void> _download(Map<String, dynamic> item) async {
    final file = await _file(item);
    if (await file.exists()) {
      _openPdf(file.path, '${item['title'] ?? 'المرجع'}');
      return;
    }
    final pdfUrl = '${item['pdf_url'] ?? ''}'.trim();
    final sourceUrl = '${item['source_url'] ?? ''}'.trim();
    final url = pdfUrl.isNotEmpty ? pdfUrl : sourceUrl;
    if (url.isEmpty) return _message('لا يوجد مصدر متاح لهذا المرجع.');
    if (pdfUrl.isEmpty) {
      final ok = await launchUrl(Uri.parse(sourceUrl), mode: LaunchMode.externalApplication);
      if (!ok && mounted) _message('تعذر فتح مصدر الكتاب.');
      return;
    }
    final id = '${item['id']}';
    final temp = File('${file.path}.part');
    setState(() => _progress[id] = 0);
    try {
      await _dio.download(url, temp.path, deleteOnError: true,
          options: Options(followRedirects: true, maxRedirects: 5),
          onReceiveProgress: (received, total) {
            if (mounted && total > 0) setState(() => _progress[id] = received / total);
          });
      if (!await temp.exists()) throw const FileSystemException('download_failed');
      if (await file.exists()) await file.delete();
      await temp.rename(file.path);
      if (mounted) setState(() { _progress.remove(id); _downloaded.add(_fileName(item)); });
      _openPdf(file.path, '${item['title'] ?? 'المرجع'}');
    } catch (_) {
      if (await temp.exists()) await temp.delete();
      if (mounted) setState(() => _progress.remove(id));
      _message('تعذر تنزيل المرجع من المصدر حاليًا.');
    }
  }

  void _openPdf(String path, String title) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => Scaffold(
      backgroundColor: const Color(0xFF120D09),
      appBar: AppBar(title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis), backgroundColor: const Color(0xFF2A1A10)),
      body: PDFView(filePath: path),
    )));
  }

  void _message(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));

  void _showInfo(Map<String, dynamic> item) {
    final title = '${item['title'] ?? 'المرجع'}';
    final summary = '${item['full_summary'] ?? item['description'] ?? ''}'.trim();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF21150D),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .62,
        minChildSize: .35,
        maxChildSize: .9,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          children: [
            Center(child: Container(width: 42, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(8)))),
            const SizedBox(height: 20),
            Text(title, textAlign: TextAlign.right, style: const TextStyle(color: Color(0xFFE5BE72), fontSize: 21, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            _infoRow('المؤلف', '${item['author'] ?? 'غير محدد'}'),
            _infoRow('القسم', _sectionOf(item)),
            if (summary.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('نبذة عن الكتاب', textAlign: TextAlign.right, style: TextStyle(color: Color(0xFFE5BE72), fontWeight: FontWeight.w800)),
              const SizedBox(height: 7),
              Text(summary, textAlign: TextAlign.right, style: const TextStyle(color: Colors.white70, height: 1.65, fontSize: 14)),
            ],
            const SizedBox(height: 22),
            FilledButton.icon(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close), label: const Text('إغلاق'), style: FilledButton.styleFrom(backgroundColor: const Color(0xFFD4AF37), foregroundColor: Colors.black)),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: Text(value, textAlign: TextAlign.right, style: const TextStyle(color: Colors.white70, fontSize: 13))),
      const SizedBox(width: 10),
      Text('$label: ', style: const TextStyle(color: Color(0xFFE5BE72), fontWeight: FontWeight.bold)),
    ]),
  );

  Widget _cover(Map<String, dynamic> item) {
    final url = '${item['cover_image_url'] ?? ''}'.trim();
    if (url.isEmpty) return const Icon(Icons.menu_book_rounded, size: 42, color: Color(0xFFD4AF37));
    return ClipRRect(borderRadius: BorderRadius.circular(10), child: CachedNetworkImage(
      imageUrl: url, width: 72, height: 96, fit: BoxFit.cover,
      placeholder: (_, __) => const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFD4AF37))),
      errorWidget: (_, __, ___) => const Icon(Icons.menu_book_rounded, size: 42, color: Color(0xFFD4AF37)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    return Scaffold(
      backgroundColor: const Color(0xFF120D09),
      appBar: AppBar(
        backgroundColor: const Color(0xFF21150D),
        centerTitle: true,
        title: const Text('المراجع القانونية', style: TextStyle(color: Color(0xFFE5BE72), fontWeight: FontWeight.bold)),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: TextField(
            controller: _search,
            onChanged: (v) => setState(() => _query = v),
            style: const TextStyle(color: Colors.white),
            textDirection: TextDirection.rtl,
            decoration: InputDecoration(
              hintText: 'ابحث باسم الكتاب أو المؤلف أو الموضوع',
              hintStyle: const TextStyle(color: Colors.white38),
              prefixIcon: const Icon(Icons.search, color: Color(0xFFD4AF37)),
              filled: true, fillColor: const Color(0xFF2A1A10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            ),
          ),
        ),
        SizedBox(
          height: 46,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            scrollDirection: Axis.horizontal,
            itemCount: _sections.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) => ChoiceChip(
              label: Text(_sections[i]),
              selected: _section == _sections[i],
              onSelected: (_) => setState(() => _section = _sections[i]),
              selectedColor: const Color(0xFFD4AF37),
              backgroundColor: const Color(0xFF2A1A10),
              labelStyle: TextStyle(
                color: _section == _sections[i] ? Colors.black : Colors.white70,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        Expanded(
          child: _loading && _items.isEmpty
            ? const Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37)))
            : visible.isEmpty
              ? Center(child: Text('لا توجد نتائج مطابقة في هذا القسم', style: TextStyle(color: Colors.white.withOpacity(.65))))
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 700 ? 3 : 2;
                    return GridView.builder(
                      padding: const EdgeInsets.fromLTRB(10, 10, 10, 24),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: columns == 2 ? .76 : .88,
                      ),
                      itemCount: visible.length,
                      itemBuilder: (_, i) => _bookCard(visible[i]),
                    );
                  },
                ),
        ),
      ]),
    );
  }

  Widget _bookCard(Map<String, dynamic> item) {
    final id = '${item['id']}';
    final downloaded = _downloaded.contains(_fileName(item));
    final progress = _progress[id];
    return Container(
      margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xB31F140D), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0x88D4AF37))),
      child: Row(children: [
        SizedBox(width: 72, height: 96, child: _cover(item)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${item['title'] ?? 'مرجع قانوني'}', textAlign: TextAlign.right, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, height: 1.35)),
          const SizedBox(height: 5),
          Text('${item['author'] ?? ''}', textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFE5BE72), fontSize: 12)),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            IconButton(tooltip: 'معلومات الكتاب', onPressed: () => _showInfo(item), icon: const Icon(Icons.info_outline_rounded, color: Color(0xFFD4AF37))),
            if (progress != null) SizedBox(width: 34, height: 34, child: CircularProgressIndicator(value: progress, color: const Color(0xFFD4AF37), strokeWidth: 3))
            else IconButton(tooltip: downloaded ? 'فتح الكتاب' : 'تنزيل الكتاب', onPressed: () => _download(item), icon: Icon(downloaded ? Icons.menu_book_rounded : Icons.download_rounded, color: const Color(0xFFD4AF37))),
          ]),
        ])),
      ]),
    );
  }
}
