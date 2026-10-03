import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

const kLegalReferencesIndexUrl = 'https://raw.githubusercontent.com/ghgfcrcgrf57566-beep/Encyclopedia-of-Yemeni-Law/main/legal_references.json';
const kLegalReferencesAdditionalIndexUrl = 'https://raw.githubusercontent.com/ghgfcrcgrf57566-beep/Encyclopedia-of-Yemeni-Law/main/legal_references_additional.json';

class LegalReferencesScreen extends StatefulWidget {
  const LegalReferencesScreen({super.key});

  @override
  State<LegalReferencesScreen> createState() => _LegalReferencesScreenState();
}

class _LegalReferencesScreenState extends State<LegalReferencesScreen> {
  static const _cacheKey = 'cached_legal_references_json_v3';
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 60),
    responseType: ResponseType.plain,
  ));
  final _search = TextEditingController();
  List<Map<String, dynamic>> _items = [], _filtered = [];
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
      final v = jsonDecode(raw);
      if (v is! List) return [];
      return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) {
      return [];
    }
  }

  List<Map<String, dynamic>> _mergeUnique(
    List<Map<String, dynamic>> base,
    List<Map<String, dynamic>> extra,
  ) {
    final out = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final item in [...base, ...extra]) {
      final id = '${item['id'] ?? ''}'.trim();
      if (id.isEmpty || seen.add(id)) out.add(item);
    }
    return out;
  }

  void _apply(List<Map<String, dynamic>> v) {
    if (!mounted) return;
    setState(() {
      _items = v;
      _filtered = _filter(_query);
    });
  }

  List<Map<String, dynamic>> _filter(String q) {
    q = q.trim().toLowerCase();
    if (q.isEmpty) return List.from(_items);
    return _items
        .where((x) => [
              x['id'],
              x['title'],
              x['author'],
              x['category'],
              x['description'],
              x['source'],
            ].join(' ').toLowerCase().contains(q))
        .toList();
  }

  String _name(Map<String, dynamic> x) =>
      ('${x['id'] ?? 'reference'}')
          .replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_')
          .toLowerCase() +
      '.pdf';

  Future<File> _file(Map<String, dynamic> x) async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory(root.path + '/legal_references');
    await dir.create(recursive: true);
    return File(dir.path + '/' + _name(x));
  }

  Future<void> _loadIndex() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_cacheKey);
    if (cached != null) {
      final v = _parse(cached);
      if (v.isNotEmpty) {
        _apply(v);
        _source = 'نسخة محفوظة محليًا';
      }
    }

    try {
      final results = await Future.wait([
        _dio.get<String>(kLegalReferencesIndexUrl),
        _dio.get<String>(kLegalReferencesAdditionalIndexUrl),
      ]);
      final base = results[0].statusCode == 200 && results[0].data != null
          ? _parse(results[0].data!)
          : <Map<String, dynamic>>[];
      final extra = results[1].statusCode == 200 && results[1].data != null
          ? _parse(results[1].data!)
          : <Map<String, dynamic>>[];
      final merged = _mergeUnique(base, extra);
      if (merged.isNotEmpty) {
        await prefs.setString(_cacheKey, jsonEncode(merged));
        _apply(merged);
        _source = 'محدّث من GitHub';
      }
    } catch (_) {
      try {
        final r = await _dio.get<String>(kLegalReferencesIndexUrl);
        if (r.statusCode == 200 && r.data != null) {
          final v = _parse(r.data!);
          if (v.isNotEmpty) {
            await prefs.setString(_cacheKey, jsonEncode(v));
            _apply(v);
            _source = 'محدّث من GitHub';
          }
        }
      } catch (_) {}
    }

    await _refreshDownloaded();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _refreshDownloaded() async {
    final f = <String>{};
    for (final x in _items) {
      if (await (await _file(x)).exists()) f.add(_name(x));
    }
    if (mounted) {
      setState(() {
        _downloaded
          ..clear()
          ..addAll(f);
      });
    }
  }

  Future<void> _download(Map<String, dynamic> x) async {
    final file = await _file(x);
    if (await file.exists()) {
      _open(file.path, '${x['title'] ?? 'المرجع'}');
      return;
    }
    final url = '${x['pdf_url'] ?? ''}'.trim();
    if (url.isEmpty) {
      _message('لا يوجد رابط مباشر للملف.');
      return;
    }
    final id = '${x['id']}';
    final temp = File(file.path + '.part');
    if (mounted) setState(() => _progress[id] = 0);
    try {
      await _dio.download(
        url,
        temp.path,
        deleteOnError: true,
        options: Options(followRedirects: true, maxRedirects: 5),
        onReceiveProgress: (a, b) {
          if (mounted && b > 0) setState(() => _progress[id] = a / b);
        },
      );
      if (!await temp.exists()) throw const FileSystemException('download_failed');
      if (await file.exists()) await file.delete();
      await temp.rename(file.path);
      if (mounted) {
        setState(() {
          _progress.remove(id);
          _downloaded.add(_name(x));
        });
      }
      _open(file.path, '${x['title'] ?? 'المرجع'}');
    } catch (_) {
      if (await temp.exists()) await temp.delete();
      if (mounted) setState(() => _progress.remove(id));
      _message('تعذر تنزيل المرجع من المصدر. يمكنك فتح المصدر الأصلي والمحاولة منه.');
    }
  }

  Future<void> _openSource(Map<String, dynamic> x) async {
    final raw = '${x['source_url'] ?? ''}'.trim();
    if (raw.isEmpty) {
      _message('لا يوجد رابط للمصدر.');
      return;
    }
    final uri = Uri.tryParse(raw);
    if (uri == null || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _message('تعذر فتح المصدر.');
    }
  }

  void _open(String path, String title) =>
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => _ReferencePdfViewer(filePath: path, title: title),
      ));

  void _message(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(s, textAlign: TextAlign.right)),
    );
  }

  Widget _bookIcon({required bool downloaded}) {
    const gold = Color(0xFFD4AF37);
    return Container(
      width: 58,
      height: 70,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4A321D), Color(0xFF1E1711)],
        ),
        border: Border.all(color: gold.withValues(alpha: 0.55)),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 8, offset: Offset(2, 3)),
        ],
      ),
      child: Icon(
        downloaded ? Icons.menu_book_rounded : Icons.auto_stories_rounded,
        color: gold,
        size: 31,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFD4AF37);
    const surface = Color(0xFF1A1A1A);

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: surface,
        title: const Text(
          'المراجع القانونية',
          style: TextStyle(color: Color(0xFFF0D78A), fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
        iconTheme: const IconThemeData(color: gold),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _search,
              onChanged: (v) => setState(() {
                _query = v;
                _filtered = _filter(v);
              }),
              textAlign: TextAlign.right,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'ابحث باسم المرجع أو المؤلف أو التصنيف...',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.search_rounded, color: gold),
                filled: true,
                fillColor: surface,
                border: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(16)),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 3),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${_filtered.length} من أصل ${_items.length} مرجع',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ),
                Text(_source, style: const TextStyle(color: gold, fontSize: 11.5)),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: gold))
                : _filtered.isEmpty
                    ? const Center(
                        child: Text('لا توجد نتائج مطابقة', style: TextStyle(color: Colors.white70)),
                      )
                    : RefreshIndicator(
                        color: gold,
                        onRefresh: _loadIndex,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          itemCount: _filtered.length,
                          itemBuilder: (_, i) {
                            final x = _filtered[i];
                            final id = '${x['id']}';
                            final p = _progress[id];
                            final d = _downloaded.contains(_name(x));
                            return Card(
                              color: surface,
                              margin: const EdgeInsets.only(bottom: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                                side: const BorderSide(color: Colors.white10),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Row(
                                  children: [
                                    _bookIcon(downloaded: d),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            '${x['title'] ?? ''}',
                                            textAlign: TextAlign.right,
                                            maxLines: 3,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${x['author'] ?? ''} — ${x['category'] ?? ''}',
                                            textAlign: TextAlign.right,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            '${x['description'] ?? ''}',
                                            textAlign: TextAlign.right,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(color: Colors.white38, height: 1.4, fontSize: 11.5),
                                          ),
                                          if ('${x['source'] ?? ''}'.isNotEmpty)
                                            Padding(
                                              padding: const EdgeInsets.only(top: 5),
                                              child: Text(
                                                'المصدر: ${x['source']}',
                                                textAlign: TextAlign.right,
                                                style: const TextStyle(color: gold, fontSize: 10.5),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    if (p != null)
                                      SizedBox(
                                        width: 40,
                                        height: 40,
                                        child: CircularProgressIndicator(value: p, color: gold, strokeWidth: 3),
                                      )
                                    else
                                      Column(
                                        children: [
                                          IconButton(
                                            tooltip: d ? 'قراءة المرجع' : 'تنزيل المرجع',
                                            onPressed: () => _download(x),
                                            icon: Icon(
                                              d ? Icons.menu_book_rounded : Icons.download_rounded,
                                              color: gold,
                                            ),
                                          ),
                                          if ('${x['source_url'] ?? ''}'.isNotEmpty)
                                            IconButton(
                                              tooltip: 'فتح المصدر الأصلي',
                                              onPressed: () => _openSource(x),
                                              icon: const Icon(Icons.public_rounded, color: Colors.white54, size: 21),
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
  final String filePath, title;
  const _ReferencePdfViewer({required this.filePath, required this.title});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(title, overflow: TextOverflow.ellipsis),
          centerTitle: true,
        ),
        body: PDFView(
          filePath: filePath,
          enableSwipe: true,
          swipeHorizontal: false,
          autoSpacing: true,
          pageFling: true,
          showScrollIndicators: true,
        ),
      );
}
