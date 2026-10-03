import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const kLegalReferencesIndexUrl = 'https://raw.githubusercontent.com/ghgfcrcgrf57566-beep/Encyclopedia-of-Yemeni-Law/main/legal_references.json';
const kLegalReferencesAdditionalIndexUrl = 'https://raw.githubusercontent.com/ghgfcrcgrf57566-beep/Encyclopedia-of-Yemeni-Law/main/legal_references_additional.json';
const kLegalReferencesReligiousIndexUrl = 'https://raw.githubusercontent.com/ghgfcrcgrf57566-beep/Encyclopedia-of-Yemeni-Law/main/legal_references_religious.json';

class LegalReferencesScreen extends StatefulWidget {
  const LegalReferencesScreen({super.key});

  @override
  State<LegalReferencesScreen> createState() => _LegalReferencesScreenState();
}

class _LegalReferencesScreenState extends State<LegalReferencesScreen> {
  static const _cacheKey = 'cached_legal_references_json_v5';
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 90),
    responseType: ResponseType.plain,
  ));
  final _search = TextEditingController();
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _filtered = [];
  final Set<String> _downloaded = {};
  final Map<String, double> _progress = {};
  bool _loading = true;
  String _query = '';
  String _source = '';

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

  bool _isValidReference(Map<String, dynamic> item) {
    final pdf = '${item['pdf_url'] ?? ''}'.trim();
    final source = '${item['source_url'] ?? item['source'] ?? ''}'.trim();
    if (pdf.isEmpty && source.isEmpty) return false;
    if (pdf.isEmpty) return false;
    return Uri.tryParse(pdf)?.hasScheme == true;
  }

  List<Map<String, dynamic>> _mergeUnique(List<List<Map<String, dynamic>>> groups) {
    final result = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final group in groups) {
      for (final item in group) {
        if (!_isValidReference(item)) continue;
        final id = '${item['id'] ?? ''}'.trim();
        if (id.isNotEmpty && seen.add(id)) result.add(item);
      }
    }
    return result;
  }

  void _apply(List<Map<String, dynamic>> value) {
    if (!mounted) return;
    setState(() {
      _items = value;
      _filtered = _filter(_query);
    });
  }

  List<Map<String, dynamic>> _filter(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return List<Map<String, dynamic>>.from(_items);
    return _items.where((item) {
      return [
        item['id'],
        item['title'],
        item['author'],
        item['category'],
        item['description'],
        item['full_summary'],
      ].join(' ').toLowerCase().contains(q);
    }).toList();
  }

  String _fileName(Map<String, dynamic> item) =>
      '${item['id'] ?? 'reference'}'.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_').toLowerCase() + '.pdf';

  Future<File> _file(Map<String, dynamic> item) async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory('${root.path}/legal_references');
    await dir.create(recursive: true);
    return File('${dir.path}/${_fileName(item)}');
  }

  Future<void> _loadIndex() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_cacheKey);
    if (cached != null) {
      final value = _mergeUnique([_parse(cached)]);
      if (value.isNotEmpty) {
        _apply(value);
        _source = 'نسخة محفوظة محليًا';
      }
    }

    try {
      final responses = await Future.wait([
        _dio.get<String>(kLegalReferencesIndexUrl),
        _dio.get<String>(kLegalReferencesAdditionalIndexUrl),
        _dio.get<String>(kLegalReferencesReligiousIndexUrl),
      ]);
      final groups = responses.map((response) {
        if (response.statusCode == 200 && response.data != null) return _parse(response.data!);
        return <Map<String, dynamic>>[];
      }).toList();
      final merged = _mergeUnique(groups);
      if (merged.isNotEmpty) {
        await prefs.setString(_cacheKey, jsonEncode(merged));
        _apply(merged);
        _source = 'محدّث من GitHub';
      }
    } catch (_) {
      // النسخة المحلية تستمر بالعمل عند انقطاع الإنترنت.
    }

    await _refreshDownloaded();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _refreshDownloaded() async {
    final found = <String>{};
    for (final item in _items) {
      final file = await _file(item);
      if (await file.exists()) found.add(_fileName(item));
    }
    if (mounted) {
      setState(() {
        _downloaded
          ..clear()
          ..addAll(found);
      });
    }
  }

  Future<void> _download(Map<String, dynamic> item) async {
    final file = await _file(item);
    if (await file.exists()) {
      _openPdf(file.path, '${item['title'] ?? 'المرجع'}');
      return;
    }

    final url = '${item['pdf_url'] ?? ''}'.trim();
    if (url.isEmpty) {
      _message('لا يوجد ملف PDF مباشر لهذا المرجع.');
      return;
    }

    final id = '${item['id']}';
    final temp = File('${file.path}.part');
    if (mounted) setState(() => _progress[id] = 0);

    try {
      await _dio.download(
        url,
        temp.path,
        deleteOnError: true,
        options: Options(followRedirects: true, maxRedirects: 5),
        onReceiveProgress: (received, total) {
          if (mounted && total > 0) setState(() => _progress[id] = received / total);
        },
      );
      if (!await temp.exists()) throw const FileSystemException('download_failed');
      if (await file.exists()) await file.delete();
      await temp.rename(file.path);
      if (mounted) {
        setState(() {
          _progress.remove(id);
          _downloaded.add(_fileName(item));
        });
      }
      _openPdf(file.path, '${item['title'] ?? 'المرجع'}');
    } catch (_) {
      if (await temp.exists()) await temp.delete();
      if (mounted) setState(() => _progress.remove(id));
      _message('تعذر تنزيل المرجع من المصدر حاليًا.');
    }
  }

  void _showBookSummary(BuildContext context, Map<String, dynamic> item) {
    final title = '${item['title'] ?? 'المرجع'}';
    final author = '${item['author'] ?? ''}'.trim();
    final category = '${item['category'] ?? ''}'.trim();
    final summary = '${item['full_summary'] ?? item['description'] ?? 'لا توجد نبذة تفصيلية متاحة حاليًا.'}'.trim();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.72,
        minChildSize: 0.45,
        maxChildSize: 0.92,
        expand: false,
        builder: (_, controller) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1E1A16),
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          ),
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4)),
                ),
              ),
              Row(
                textDirection: TextDirection.rtl,
                children: [
                  _cover(item, width: 52, height: 64),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      textAlign: TextAlign.right,
                      style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800, height: 1.35),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (author.isNotEmpty || category.isNotEmpty)
                Text(
                  [author, category].where((e) => e.isNotEmpty).join(' — '),
                  textAlign: TextAlign.right,
                  style: const TextStyle(color: Color(0xFFD4AF37), fontSize: 14, fontWeight: FontWeight.w700),
                ),
              const SizedBox(height: 18),
              const Text('نبذة عن المرجع ومحتوياته', textAlign: TextAlign.right, style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              Text(summary, textAlign: TextAlign.right, style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.8)),
              const SizedBox(height: 22),
              SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.pop(sheetContext),
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('إغلاق'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD4AF37),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cover(Map<String, dynamic> item, {double width = 58, double height = 70}) {
    const gold = Color(0xFFD4AF37);
    final url = '${item['cover_image_url'] ?? ''}'.trim();
    final hasUrl = url.isNotEmpty && Uri.tryParse(url)?.hasScheme == true;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: width,
        height: height,
        color: const Color(0xFF302319),
        child: hasUrl
            ? CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                fadeInDuration: const Duration(milliseconds: 180),
                placeholder: (_, __) => const Center(
                  child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: gold)),
                ),
                errorWidget: (_, __, ___) => const Icon(Icons.menu_book_rounded, color: gold, size: 30),
              )
            : const Icon(Icons.menu_book_rounded, color: gold, size: 30),
      ),
    );
  }

  void _openPdf(String path, String title) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => _ReferencePdfViewer(filePath: path, title: title)));
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text, textAlign: TextAlign.right)));
  }

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFD4AF37);
    const surface = Color(0xFF1A1A1A);

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: surface,
        title: const Text('المراجع القانونية', style: TextStyle(color: Color(0xFFF0D78A), fontWeight: FontWeight.w800)),
        centerTitle: true,
        iconTheme: const IconThemeData(color: gold),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _search,
              onChanged: (value) => setState(() {
                _query = value;
                _filtered = _filter(value);
              }),
              textAlign: TextAlign.right,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'ابحث باسم المرجع أو المؤلف أو التصنيف...',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.search_rounded, color: gold),
                filled: true,
                fillColor: surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 3),
            child: Row(
              children: [
                Expanded(child: Text('${_filtered.length} من أصل ${_items.length} مرجع', style: const TextStyle(color: Colors.white54, fontSize: 12))),
                Text(_source, style: const TextStyle(color: gold, fontSize: 11.5)),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: gold))
                : _filtered.isEmpty
                    ? const Center(child: Text('لا توجد نتائج مطابقة', style: TextStyle(color: Colors.white70)))
                    : RefreshIndicator(
                        color: gold,
                        onRefresh: _loadIndex,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          itemCount: _filtered.length,
                          itemBuilder: (_, index) {
                            final item = _filtered[index];
                            final id = '${item['id']}';
                            final progress = _progress[id];
                            final downloaded = _downloaded.contains(_fileName(item));
                            final author = '${item['author'] ?? ''}'.trim();
                            final category = '${item['category'] ?? ''}'.trim();
                            return Card(
                              color: surface,
                              margin: const EdgeInsets.only(bottom: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Colors.white10)),
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _cover(item),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text('${item['title'] ?? ''}', textAlign: TextAlign.right, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, height: 1.35)),
                                          if (author.isNotEmpty || category.isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Text([author, category].where((e) => e.isNotEmpty).join(' — '), textAlign: TextAlign.right, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: gold, fontSize: 12.5, height: 1.3)),
                                          ],
                                          const SizedBox(height: 5),
                                          Text('${item['description'] ?? ''}', textAlign: TextAlign.right, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white60, fontSize: 12, height: 1.35)),
                                          if (progress != null) ...[
                                            const SizedBox(height: 8),
                                            LinearProgressIndicator(value: progress, color: gold, backgroundColor: Colors.white12, minHeight: 3),
                                            const SizedBox(height: 3),
                                            Text('${(progress * 100).round()}%', style: const TextStyle(color: Colors.white54, fontSize: 10)),
                                          ],
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Column(
                                      children: [
                                        IconButton(
                                          tooltip: 'نبذة عن المرجع',
                                          icon: const Icon(Icons.info_outline_rounded, color: gold),
                                          onPressed: () => _showBookSummary(context, item),
                                        ),
                                        IconButton(
                                          tooltip: downloaded ? 'فتح المرجع' : 'تنزيل المرجع',
                                          icon: Icon(downloaded ? Icons.menu_book_rounded : Icons.file_download_outlined, color: gold),
                                          onPressed: progress == null ? () => _download(item) : null,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _ReferencePdfViewer extends StatelessWidget {
  final String filePath;
  final String title;

  const _ReferencePdfViewer({required this.filePath, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFF0D78A), fontSize: 15)),
        iconTheme: const IconThemeData(color: Color(0xFFD4AF37)),
      ),
      body: PDFView(
        filePath: filePath,
        enableSwipe: true,
        swipeHorizontal: false,
        autoSpacing: true,
        pageFling: true,
        fitPolicy: FitPolicy.BOTH,
      ),
    );
  }
}
