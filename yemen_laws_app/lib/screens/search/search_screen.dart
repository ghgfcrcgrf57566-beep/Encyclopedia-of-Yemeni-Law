import 'dart:async';
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models/law.dart';
import '../../data/models/madda.dart';
import '../../data/repositories/laws_repository.dart';
import '../law_detail/widgets/section_tile.dart';
import '../article/article_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  final int? initialLawId;
  const SearchScreen({super.key, this.initialLawId});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _repo = LawsRepository.instance;
  final _controller = TextEditingController();
  Timer? _debounce;

  List<Law> _laws = [];
  int? _selectedLawId; // null = كل القوانين

  List<Madda> _results = [];
  bool _searched = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _selectedLawId = widget.initialLawId;
    _loadLaws();
  }

  Future<void> _loadLaws() async {
    final laws = await _repo.getAllLaws();
    if (!mounted) return;
    setState(() {
      _laws = laws;
      if (_selectedLawId != null && !laws.any((law) => law.id == _selectedLawId)) {
        _selectedLawId = null;
      }
    });
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _runSearch());
  }

  Future<void> _runSearch() async {
    final query = _controller.text.trim();
    if (query.isEmpty) {
      setState(() {
        _results = [];
        _searched = false;
      });
      return;
    }
    setState(() => _loading = true);
    final results = await _repo.search(query, lawId: _selectedLawId);
    unawaited(_repo.recordSearch(query));
    if (!mounted) return;
    setState(() {
      _results = results;
      _searched = true;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('البحث في القوانين')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _controller,
                textAlign: TextAlign.right,
                onChanged: _onChanged,
                onSubmitted: (_) => _runSearch(),
                decoration: InputDecoration(
                  hintText: 'اكتب كلمة أو رقم مادة...',
                  prefixIcon: Icon(Icons.search, color: context.textSecondary),
                  suffixIcon: _controller.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _controller.clear();
                            setState(() {
                              _results = [];
                              _searched = false;
                            });
                          },
                        )
                      : null,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: double.infinity,
                child: DropdownButtonFormField<int?>(
                  value: _laws.any((law) => law.id == _selectedLawId) ? _selectedLawId : null,
                  isExpanded: true,
                  decoration: InputDecoration(
                    prefixIcon: Icon(Icons.filter_list, color: context.textSecondary),
                  ),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('كل القوانين')),
                    ..._laws.map((l) => DropdownMenuItem<int?>(value: l.id, child: Text(l.name))),
                  ],
                  onChanged: (value) {
                    setState(() => _selectedLawId = value);
                    _runSearch();
                  },
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (!_searched) {
      return const _SearchHint();
    }
    if (_results.isEmpty) {
      return Center(
        child: Text('لا توجد نتائج', style: TextStyle(color: context.textSecondary)),
      );
    }
    final resultIds = _results.map((e) => e.id).toList();
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: _results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final m = _results[index];
        return SectionTile(
          icon: Icons.description_outlined,
          title: 'مادة (${m.number}) — ${m.lawName ?? ''}',
          subtitle: m.body,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ArticleDetailScreen(maddaId: m.id, siblingIds: resultIds),
            ),
          ),
        );
      },
    );
  }
}

class _SearchHint extends StatelessWidget {
  const _SearchHint();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.travel_explore, size: 56, color: context.textSecondary.withOpacity(0.5)),
            const SizedBox(height: 12),
            Text(
              'ابحث بكلمة داخل نصوص جميع القوانين، أو برقم المادة مباشرة',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
