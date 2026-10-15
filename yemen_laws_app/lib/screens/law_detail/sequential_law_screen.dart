import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../data/models/law.dart';
import '../../data/repositories/laws_repository.dart';
import '../article/article_detail_screen.dart';

/// "الخيار الثاني: عرض القانون كما هو في ملفات Word" — يعرض القانون كاملاً
/// في مستند واحد متصل، بنفس ترتيب الأبواب والفصول والمواد والعناوين
/// كما وردت في ملف Word الأصلي، دون قطعه إلى شاشات منفصلة.
class SequentialLawScreen extends StatefulWidget {
  final Law law;
  const SequentialLawScreen({super.key, required this.law});

  @override
  State<SequentialLawScreen> createState() => _SequentialLawScreenState();
}

class _SequentialLawScreenState extends State<SequentialLawScreen> {
  final _repo = LawsRepository.instance;
  final _searchController = TextEditingController();
  List<DocumentItem> _items = [];
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await _repo.getFullLawDocument(widget.law.id);
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _normalizeSearch(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[ً-ٟ]'), '')
      .replaceAll(RegExp(r'[إأآٱ]'), 'ا')
      .replaceAll('ى', 'ي')
      .replaceAll('ة', 'ه')
      .replaceAll('ـ', '')
      .trim();

  double _headingFontSize(String? level) {
    switch (level) {
      case 'كتاب':
        return 19;
      case 'قسم':
        return 17.5;
      case 'باب':
        return 16.5;
      default: // فصل
        return 15;
    }
  }

  @override
  Widget build(BuildContext context) {
    final articleIds = _items.where((i) => !i.isHeading).map((i) => i.madda!.id).toList();
    final query = _normalizeSearch(_query);
    final visibleItems = query.isEmpty
        ? _items
        : _items.where((item) {
            if (item.isHeading) return _normalizeSearch(item.headingText ?? '').contains(query);
            final article = item.madda!;
            return _normalizeSearch(article.number).contains(query) ||
                _normalizeSearch(article.body).contains(query);
          }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('القراءة التسلسلية', maxLines: 1, overflow: TextOverflow.ellipsis),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: TextField(
              controller: _searchController,
              textDirection: TextDirection.rtl,
              textInputAction: TextInputAction.search,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: 'ابحث داخل نص هذا القانون...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty ? null : IconButton(
                  tooltip: 'مسح البحث',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _query = '');
                  },
                ),
                isDense: true,
                filled: true,
                fillColor: context.surfaceAlt,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
           : visibleItems.isEmpty
              ? Center(child: Text(_query.trim().isEmpty ? 'لا يوجد محتوى' : 'لا توجد مواد مطابقة للبحث', style: TextStyle(color: context.textSecondary)))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
                  itemCount: visibleItems.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 18),
                        child: Text(
                          widget.law.name,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: context.accent,
                          ),
                        ),
                      );
                    }
                    final item = visibleItems[index - 1];
                    if (item.isHeading) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Text(
                          item.headingText ?? '',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: _headingFontSize(item.headingLevel),
                            fontWeight: FontWeight.w700,
                            color: context.textPrimary,
                          ),
                        ),
                      );
                    }
                    final m = item.madda!;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: InkWell(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ArticleDetailScreen(maddaId: m.id, siblingIds: articleIds),
                          ),
                        ),
                        child: RichText(
                          textAlign: TextAlign.right,
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: 'مادة (${m.number}): ',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                  color: context.accent,
                                ),
                              ),
                              TextSpan(
                                text: m.body,
                                style: TextStyle(
                                  fontSize: 14.5,
                                  height: 1.8,
                                  color: context.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
