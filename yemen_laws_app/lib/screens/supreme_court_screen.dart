import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const kSupremeCourtIndexUrl =
    'https://raw.githubusercontent.com/ghgfcrcgrf57566-beep/Encyclopedia-of-Yemeni-Law/main/sc_books.json';

const _gold = Color(0xFFD4AF37);
const _goldLight = Color(0xFFF0D78A);
const _goldDark = Color(0xFF8A671C);
const _bg = Color(0xFF121212);
const _surface = Color(0xFF1A1A1A);

class SupremeCourtScreen extends StatefulWidget {
  const SupremeCourtScreen({super.key});

  @override
  State<SupremeCourtScreen> createState() => _SupremeCourtScreenState();
}

class _SupremeCourtScreenState extends State<SupremeCourtScreen> {
  static const _cacheKey = 'cached_sc_books_json_v2';

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 60),
      responseType: ResponseType.plain,
    ),
  );

  final _search = TextEditingController();
  List<Map<String, dynamic>> _books = [];
  List<Map<String, dynamic>> _filtered = [];
  final Set<String> _downloaded = {};
  final Map<String, double> _progress = {};
  String _query = '';
  String _source = '';
  bool _loading = true;

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
      return value
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return [];
    }
  }

  int _part(Map<String, dynamic> book) {
    final match = RegExp(r'(\d+)').firstMatch('${book['id'] ?? ''}');
    return match == null ? 999 : int.tryParse(match.group(1)!) ?? 999;
  }

  String _partLabel(Map<String, dynamic> book) =>
      'الجزء ${_part(book).toString().padLeft(2, '0')}';

  void _applyBooks(List<Map<String, dynamic>> books) {
    books.sort((a, b) => _part(a).compareTo(_part(b)));
    if (!mounted) return;
    setState(() {
      _books = books;
      _filtered = _filter(_query);
    });
  }

  List<Map<String, dynamic>> _filter(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return List<Map<String, dynamic>>.from(_books);
    return _books.where((book) {
      final text = [
        book['id'],
        book['title'],
        book['subtitle'],
        book['description'],
        book['file_name'],
        _partLabel(book),
      ].map((e) => '$e').join(' ').toLowerCase();
      return text.contains(q);
    }).toList();
  }

  Future<void> _loadIndex() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_cacheKey);

    if (cached != null) {
      final parsed = _parse(cached);
      if (parsed.isNotEmpty) {
        _applyBooks(parsed);
        _source = 'نسخة محفوظة محليًا';
      }
    }

    try {
      final response = await _dio.get<String>(kSupremeCourtIndexUrl);
      if (response.statusCode == 200 && response.data != null) {
        final parsed = _parse(response.data!);
        if (parsed.isNotEmpty) {
          await prefs.setString(_cacheKey, jsonEncode(parsed));
          _applyBooks(parsed);
          _source = 'محدّث من GitHub';
        }
      }
    } catch (_) {}

    await _refreshDownloaded();
    if (mounted) setState(() => _loading = false);
  }

  Future<Directory> _booksDir() async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory('${root.path}/supreme_court');
    await dir.create(recursive: true);
    return dir;
  }

  String _safeFileName(String name) {
    final clean = name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
    return clean.toLowerCase().endsWith('.pdf') ? clean : '$clean.pdf';
  }

  Future<File> _localFile(Map<String, dynamic> book) async {
    final dir = await _booksDir();
    final name = _safeFileName('${book['file_name'] ?? book['id'] ?? 'book.pdf'}');
    return File('${dir.path}/$name');
  }

  Future<void> _refreshDownloaded() async {
    final found = <String>{};
    for (final book in _books) {
      final file = await _localFile(book);
      if (await file.exists()) {
        found.add(_safeFileName('${book['file_name'] ?? book['id']}'));
      }
    }
    if (!mounted) return;
    setState(() {
      _downloaded
        ..clear()
        ..addAll(found);
    });
  }

  void _onSearch(String value) {
    setState(() {
      _query = value;
      _filtered = _filter(value);
    });
  }

  Future<void> _download(Map<String, dynamic> book,
      void Function(void Function()) sheetSetState, BuildContext sheetContext) async {
    final file = await _localFile(book);
    if (await file.exists()) {
      if (!sheetContext.mounted) return;
      Navigator.pop(sheetContext);
      if (mounted) _openPdf(file.path, '${book['title'] ?? ''}');
      return;
    }
    final url = '${book['download_url'] ?? ''}'.trim();
    if (url.isEmpty) {
      _showMessage('لا يوجد رابط تنزيل لهذا الكتاب.');
      return;
    }
    final id = '${book['id'] ?? book['file_name']}';
    final temp = File('${file.path}.part');
    try {
      sheetSetState(() => _progress[id] = 0);
      await _dio.download(url, temp.path, deleteOnError: true,
          options: Options(followRedirects: true, maxRedirects: 5),
          onReceiveProgress: (received, total) {
        if (total <= 0) return;
        final value = received / total;
        sheetSetState(() => _progress[id] = value);
        if (mounted) setState(() => _progress[id] = value);
      });
      if (!await temp.exists()) throw const FileSystemException('download_failed');
      if (await file.exists()) await file.delete();
      await temp.rename(file.path);
      _downloaded.add(_safeFileName('${book['file_name'] ?? book['id']}'));
      if (!sheetContext.mounted) return;
      Navigator.pop(sheetContext);
      if (mounted) _openPdf(file.path, '${book['title'] ?? ''}');
    } catch (_) {
      if (await temp.exists()) await temp.delete();
      _showMessage('تعذر تنزيل الملف. تأكد من الاتصال بالإنترنت.');
    }
  }

  Future<void> _downloadFromCard(Map<String, dynamic> book) async {
    final file = await _localFile(book);
    if (await file.exists()) {
      _downloaded.add(_safeFileName('${book['file_name'] ?? book['id']}'));
      if (mounted) {
        setState(() {});
        _openPdf(file.path, '${book['title'] ?? ''}');
      }
      return;
    }
    final url = '${book['download_url'] ?? ''}'.trim();
    if (url.isEmpty) {
      _showMessage('لا يوجد رابط تنزيل لهذا الكتاب.');
      return;
    }
    final id = '${book['id'] ?? book['file_name']}';
    final temp = File('${file.path}.part');
    if (mounted) setState(() => _progress[id] = 0);
    try {
      await _dio.download(url, temp.path, deleteOnError: true,
          options: Options(followRedirects: true, maxRedirects: 5),
          onReceiveProgress: (received, total) {
        if (!mounted || total <= 0) return;
        setState(() => _progress[id] = received / total);
      });
      if (!await temp.exists()) throw const FileSystemException('download_failed');
      if (await file.exists()) await file.delete();
      await temp.rename(file.path);
      _downloaded.add(_safeFileName('${book['file_name'] ?? book['id']}'));
      if (!mounted) return;
      setState(() => _progress[id] = 1);
      _openPdf(file.path, '${book['title'] ?? ''}');
    } catch (_) {
      if (await temp.exists()) await temp.delete();
      if (mounted) {
        setState(() => _progress.remove(id));
        _showMessage('تعذر تنزيل الملف. تأكد من الاتصال بالإنترنت.');
      }
    }
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text, textAlign: TextAlign.right),
      backgroundColor: const Color(0xFF2A2113),
    ));
  }

  void _openPdf(String path, String title) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SupremeCourtPdfViewer(filePath: path, title: title),
    ));
  }

  Future<void> _showBook(Map<String, dynamic> book) async {
    final file = await _localFile(book);
    final downloaded = await file.exists();
    if (!mounted) return;
    final id = '${book['id'] ?? book['file_name']}';
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: StatefulBuilder(
          builder: (context, sheetSetState) {
            final progress = _progress[id] ?? 0;
            final downloading = progress > 0 && progress < 1;
            return Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              decoration: const BoxDecoration(
                color: Color(0xFF1B1713),
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                border: Border(top: BorderSide(color: _gold)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Center(child: Container(width: 50, height: 5,
                      decoration: BoxDecoration(color: Colors.white24,
                          borderRadius: BorderRadius.circular(99)))),
                  const SizedBox(height: 18),
                  Row(children: [
                    const _GoldBadge(icon: Icons.gavel_rounded),
                    const SizedBox(width: 12),
                    Expanded(child: Text('${book['title'] ?? 'الكتاب'}', textAlign: TextAlign.right,
                        style: const TextStyle(color: Color(0xFFF2E6CE), fontSize: 18, fontWeight: FontWeight.w800))),
                  ]),
                  const SizedBox(height: 8),
                  Text(_partLabel(book), style: const TextStyle(color: _gold, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  Text('${book['description'] ?? 'لا يوجد وصف متوفر.'}', textAlign: TextAlign.right,
                      style: const TextStyle(color: Colors.white60, height: 1.6, fontSize: 13.5)),
                  const SizedBox(height: 18),
                  if (downloading) ...[
                    ClipRRect(borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(value: progress, minHeight: 7,
                          backgroundColor: Colors.white12, color: _gold)),
                    const SizedBox(height: 8),
                    Center(child: Text('جاري التنزيل: ${(progress * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(color: Colors.white70))),
                  ] else
                    SizedBox(width: double.infinity, height: 50,
                      child: ElevatedButton.icon(
                        onPressed: () => _download(book, sheetSetState, sheetContext),
                        style: ElevatedButton.styleFrom(backgroundColor: _gold, foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                        icon: Icon(downloaded ? Icons.menu_book_rounded : Icons.download_rounded),
                        label: Text(downloaded ? 'قراءة الكتاب' : 'تنزيل وقراءة PDF',
                            style: const TextStyle(fontWeight: FontWeight.w800)),
                      )),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        title: const Text('أحكام المحكمة العليا', style: TextStyle(color: _goldLight, fontWeight: FontWeight.w800)),
        centerTitle: true,
        iconTheme: const IconThemeData(color: _gold),
      ),
      body: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            controller: _search, onChanged: _onSearch, textAlign: TextAlign.right,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'ابحث باسم الكتاب أو رقم الجزء أو الوصف...',
              hintStyle: const TextStyle(color: Colors.white38),
              prefixIcon: const Icon(Icons.search_rounded, color: _gold),
              suffixIcon: _query.isEmpty ? null : IconButton(onPressed: () { _search.clear(); _onSearch(''); },
                  icon: const Icon(Icons.clear_rounded, color: Colors.white54)),
              filled: true, fillColor: _surface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Colors.white10)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Colors.white10)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _gold)),
            ),
          )),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 3),
          child: Row(children: [
            Expanded(child: Text('${_filtered.length} من أصل ${_books.length} كتاب', style: const TextStyle(color: Colors.white54, fontSize: 12))),
            Text(_source, style: const TextStyle(color: _gold, fontSize: 11.5)),
          ])),
        Expanded(child: _loading
          ? const Center(child: CircularProgressIndicator(color: _gold))
          : _filtered.isEmpty ? const _EmptyState()
          : RefreshIndicator(
              color: _gold, onRefresh: _loadIndex,
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: _filtered.length,
                itemBuilder: (context, index) {
                  final book = _filtered[index];
                  final key = _safeFileName('${book['file_name'] ?? book['id']}');
                  return Padding(padding: const EdgeInsets.only(bottom: 10),
                    child: _BookCard(
                      book: book,
                      downloaded: _downloaded.contains(key),
                      partLabel: _partLabel(book),
                      progress: _progress['${book['id'] ?? book['file_name']}'],
                      onTap: () => _showBook(book),
                      onDownload: () => _downloadFromCard(book),
                    ));
                },
              ),
            )),
      ]),
    );
  }
}

class _BookCard extends StatelessWidget {
  final Map<String, dynamic> book;
  final bool downloaded;
  final String partLabel;
  final double? progress;
  final VoidCallback onTap;
  final VoidCallback onDownload;
  const _BookCard({required this.book, required this.downloaded, required this.partLabel, required this.progress, required this.onTap, required this.onDownload});

  @override
  Widget build(BuildContext context) {
    final value = (progress ?? 0).clamp(0.0, 1.0).toDouble();
    final downloading = value > 0 && value < 1;
    return Card(
      color: _surface, margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: downloaded ? _gold.withValues(alpha: 0.55) : Colors.white10)),
      child: InkWell(
        borderRadius: BorderRadius.circular(18), onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(12),
          child: Directionality(textDirection: TextDirection.rtl,
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 46, height: 46,
                child: downloading
                  ? Stack(alignment: Alignment.center, children: [
                      CircularProgressIndicator(value: value, strokeWidth: 3, color: _gold, backgroundColor: Colors.white12),
                      Text('${(value * 100).round()}%', style: const TextStyle(color: _goldLight, fontSize: 9, fontWeight: FontWeight.w800)),
                    ])
                  : IconButton(
                      tooltip: downloaded ? 'قراءة الكتاب' : 'تنزيل الكتاب', onPressed: onDownload,
                      icon: Icon(downloaded ? Icons.menu_book_rounded : Icons.download_rounded, color: _gold, size: 27),
                      style: IconButton.styleFrom(backgroundColor: _gold.withValues(alpha: 0.08), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    )),
              const SizedBox(width: 8),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('${book['title'] ?? 'الكتاب'}', maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 4),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.menu_book_rounded, color: _gold, size: 16),
                  const SizedBox(width: 5),
                  Text(partLabel, style: const TextStyle(color: _gold, fontWeight: FontWeight.w700, fontSize: 12.5)),
                ]),
                const SizedBox(height: 5),
                Text('${book['description'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right,
                    style: const TextStyle(color: Colors.white54, height: 1.45, fontSize: 11.5)),
              ])),
            ]),
          )),
      ),
    );
  }
}

class _GoldBadge extends StatelessWidget {
  final IconData icon;
  const _GoldBadge({required this.icon});
  @override
  Widget build(BuildContext context) {
    return Container(width: 52, height: 52,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(15), gradient: const LinearGradient(colors: [_goldLight, _goldDark], begin: Alignment.topLeft, end: Alignment.bottomRight)),
      child: Icon(icon, color: Colors.black87, size: 28));
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.search_off_rounded, color: _gold, size: 54),
      SizedBox(height: 12),
      Text('لا توجد نتائج مطابقة', style: TextStyle(color: Colors.white70, fontSize: 16)),
    ]));
  }
}

class SupremeCourtPdfViewer extends StatefulWidget {
  final String filePath;
  final String title;
  const SupremeCourtPdfViewer({super.key, required this.filePath, required this.title});
  @override
  State<SupremeCourtPdfViewer> createState() => _SupremeCourtPdfViewerState();
}

class _SupremeCourtPdfViewerState extends State<SupremeCourtPdfViewer> {
  PDFViewController? _controller;
  int? _pages;
  int _page = 0;
  String? _error;
  bool _scrubbing = false;

  double get _pageFraction {
    final total = _pages ?? 1;
    if (total <= 1) return 0;
    return (_page / (total - 1)).clamp(0.0, 1.0).toDouble();
  }

  Future<void> _setPage(int page) async {
    final controller = _controller;
    final pages = _pages;
    if (controller == null || pages == null || pages < 1) return;
    final target = page.clamp(0, pages - 1).toInt();
    await controller.setPage(target);
  }

  Future<void> _showGoToPageDialog() async {
    final pages = _pages;
    if (pages == null || pages < 1) return;
    final controller = TextEditingController();
    final target = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('الانتقال إلى صفحة', style: TextStyle(color: _goldLight)),
        content: TextField(
          controller: controller, keyboardType: TextInputType.number, textAlign: TextAlign.center,
          autofocus: true, style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(hintText: 'أدخل رقم الصفحة', hintStyle: const TextStyle(color: Colors.white38), suffixText: 'من $pages', suffixStyle: const TextStyle(color: _gold)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء', style: TextStyle(color: Colors.white60))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _gold, foregroundColor: Colors.black),
            onPressed: () {
              final value = int.tryParse(controller.text.trim());
              if (value == null || value < 1 || value > pages) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(const SnackBar(content: Text('رقم الصفحة غير موجود')));
                return;
              }
              Navigator.pop(dialogContext, value);
            },
            child: const Text('انتقال'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (target != null && mounted) await _setPage(target - 1);
  }

  void _scrubTo(Offset localPosition, double height) {
    final pages = _pages;
    if (pages == null || pages < 2 || height <= 0) return;
    final fraction = (localPosition.dy / height).clamp(0.0, 1.0);
    final target = (fraction * (pages - 1)).round();
    if (target != _page) _setPage(target);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        title: Text(widget.title, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 15)),
        iconTheme: const IconThemeData(color: _gold),
        actions: [IconButton(tooltip: 'الانتقال إلى صفحة', onPressed: _showGoToPageDialog, icon: const Icon(Icons.find_in_page_rounded))],
      ),
      body: Stack(
        children: [
          PDFView(
            filePath: widget.filePath,
            enableSwipe: true,
            swipeHorizontal: false,
            autoSpacing: true,
            pageFling: true,
            showScrollIndicators: true,
            backgroundColor: _bg,
            onViewCreated: (controller) => _controller = controller,
            onRender: (pages) { if (mounted) setState(() => _pages = pages); },
            onPageChanged: (page, total) {
              if (!mounted) return;
              setState(() { _page = page ?? 0; _pages = total ?? _pages; });
            },
            onError: (error) { if (mounted) setState(() => _error = error.toString()); },
            onPageError: (page, error) {
              if (mounted) setState(() => _error = 'خطأ في صفحة ${(page ?? 0) + 1}: $error');
            },
          ),
          PositionedDirectional(
            end: 2, top: 20, bottom: 60,
            child: LayoutBuilder(builder: (context, constraints) {
              final height = constraints.maxHeight;
              const trackTop = 42.0;
              const trackBottom = 42.0;
              final trackHeight = (height - trackTop - trackBottom).clamp(80.0, double.infinity).toDouble();
              final thumbTop = trackTop + (_pageFraction * trackHeight);
              return GestureDetector(
                onVerticalDragStart: (_) { setState(() => _scrubbing = true); },
                onVerticalDragUpdate: (details) {
                  final local = Offset(0, (details.localPosition.dy - trackTop).clamp(0.0, trackHeight).toDouble());
                  _scrubTo(local, trackHeight);
                },
                onVerticalDragEnd: (_) { setState(() => _scrubbing = false); },
                onTapUp: (details) {
                  final local = Offset(0, (details.localPosition.dy - trackTop).clamp(0.0, trackHeight));
                  _scrubTo(local, trackHeight);
                },
                child: SizedBox(width: 58, height: height,
                  child: Stack(children: [
                    Positioned(top: trackTop, bottom: trackBottom, left: 28,
                      child: Container(width: 4, decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(99)))),
                    Positioned(top: 0, left: 15,
                      child: IconButton(tooltip: 'أول صفحة', onPressed: () => _setPage(0), icon: const Icon(Icons.keyboard_arrow_up_rounded, color: _goldLight))),
                    Positioned(top: thumbTop, left: 19,
                      child: Container(width: 20, height: 20,
                        decoration: const BoxDecoration(shape: BoxShape.circle, color: _gold,
                          boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 8)]))),
                    if (_scrubbing) Positioned(top: (thumbTop - 14).clamp(0.0, height - 34).toDouble(), left: 0,
                      child: Container(width: 52, padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                        decoration: BoxDecoration(color: const Color(0xEE1B1713), borderRadius: BorderRadius.circular(9), border: Border.all(color: _gold.withValues(alpha: 0.7))),
                        child: Text((_page + 1).toString(), textAlign: TextAlign.center,
                          style: const TextStyle(color: _goldLight, fontWeight: FontWeight.w800, fontSize: 11)))),
                    Positioned(bottom: 0, left: 15,
                      child: IconButton(tooltip: 'آخر صفحة', onPressed: () { final pages = _pages; if (pages != null) _setPage(pages - 1); },
                        icon: const Icon(Icons.keyboard_arrow_down_rounded, color: _goldLight))),
                  ]),
                ),
              );
            }),
          ),
          Positioned(left: 18, right: 18, bottom: 10,
            child: IgnorePointer(child: Center(child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(color: const Color(0xDD1A1A1A), borderRadius: BorderRadius.circular(99), border: Border.all(color: _gold.withValues(alpha: 0.55))),
              child: Text(_pages == null ? 'جاري تحميل الصفحات...' : 'صفحة ${_page + 1} من ${_pages}',
                style: const TextStyle(color: _goldLight, fontSize: 12, fontWeight: FontWeight.w700)),
            ))),
          ),
          if (_error != null) Align(alignment: Alignment.topCenter,
            child: Container(margin: const EdgeInsets.all(12), padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xEE2A1515), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0x88D58D8D))),
              child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)))),
        ],
      ),
    );
  }
}
