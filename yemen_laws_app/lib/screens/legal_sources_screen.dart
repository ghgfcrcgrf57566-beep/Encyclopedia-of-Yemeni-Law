import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/models/law.dart';
import '../data/models/madda.dart';
import '../data/repositories/laws_repository.dart';

const _sourceGold = Color(0xFFD4AF6A);
const _sourcePanel = Color(0xFF171310);
const _sourceLine = Color(0xFF51412D);

class _LegalSourceRecord {
  final List<String> matchTerms;
  final String citation;
  final String url;
  final String authority;
  final String checkedAt;
  final String status;
  final String amendmentNote;

  const _LegalSourceRecord({
    required this.matchTerms,
    required this.citation,
    required this.url,
    required this.authority,
    required this.checkedAt,
    required this.status,
    required this.amendmentNote,
  });

  bool matches(Law law) {
    final name = '${law.name} ${law.shortName ?? ''}';
    return matchTerms.any((term) => name.contains(term));
  }
}

/// Source links are references for human review, not proof that the bundled
/// article text is the latest consolidated version.
const _sourceRecords = <_LegalSourceRecord>[
  _LegalSourceRecord(
    matchTerms: ['المرافعات والتنفيذ المدني'],
    citation: 'قانون رقم (40) لسنة 2002م بشأن المرافعات والتنفيذ المدني',
    url: 'https://www.agoye.gov.ye/page.php?id=478',
    authority: 'النيابة العامة – مجموعة التشريعات اليمنية',
    checkedAt: '15/10/2026',
    status: 'المصدر معروف؛ مطابقة النص المحلي والتعديلات غير مكتملة',
    amendmentNote: 'تشير مصادر وزارة العدل إلى تعديلات لاحقة، منها تعديلا 2010 و2021؛ يجب التحقق من النص الموحّد النافذ قبل بناء أي حاسبة مواعيد أو اختصاص.',
  ),
  _LegalSourceRecord(
    matchTerms: ['الإثبات'],
    citation: 'القرار الجمهوري بالقانون رقم (21) لسنة 1992م بشأن الإثبات',
    url: 'https://yemennic.net/archives/459',
    authority: 'المركز الوطني للمعلومات',
    checkedAt: '15/10/2026',
    status: 'المصدر معروف؛ مطابقة النص المحلي والتعديلات غير مكتملة',
    amendmentNote: 'تذكر صفحة المصدر وجود تعديل بالقانون رقم (20) لسنة 1996م؛ يلزم مطابقة المواد المعدلة مع النص المرفق بالتطبيق.',
  ),
  _LegalSourceRecord(
    matchTerms: ['العمل'],
    citation: 'القرار الجمهوري بالقانون رقم (5) لسنة 1995م بشأن قانون العمل',
    url: 'https://yemennic.net/archives/728',
    authority: 'المركز الوطني للمعلومات',
    checkedAt: '15/10/2026',
    status: 'المصدر معروف؛ مطابقة النص المحلي والتعديلات غير مكتملة',
    amendmentNote: 'توجد صفحات تعديلات لاحقة لقانون العمل؛ يجب تجميعها والتحقق من النص الموحّد قبل اعتماد أي استحقاق أو مدة.',
  ),
];

class LegalSourcesScreen extends StatefulWidget {
  const LegalSourcesScreen({super.key});

  @override
  State<LegalSourcesScreen> createState() => _LegalSourcesScreenState();
}

class _LegalSourcesScreenState extends State<LegalSourcesScreen> {
  final _repo = LawsRepository.instance;
  final _search = TextEditingController();
  List<Law> _laws = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final laws = await _repo.getAllLaws();
      if (!mounted) return;
      setState(() {
        _laws = laws;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'تعذر تحميل القوانين من قاعدة البيانات المحلية.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim();
    final visible = _laws.where((law) {
      if (query.isEmpty) return true;
      return law.name.contains(query) ||
          (law.shortName ?? '').contains(query) ||
          (law.category ?? '').contains(query);
    }).toList();

    final sourced = _laws.where((law) => _recordFor(law) != null).length;

    return Scaffold(
      appBar: AppBar(title: const Text('مصادر القواعد القانونية')),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: _sourceGold))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF302216), Color(0xFF17110C)],
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                      ),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: const Color(0xFF826235)),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.fact_check_rounded, color: _sourceGold, size: 32),
                        SizedBox(height: 10),
                        Text('سجل توثيق النصوص والتعديلات',
                            style: TextStyle(color: Color(0xFFF1D9A0), fontSize: 19, fontWeight: FontWeight.w900)),
                        SizedBox(height: 7),
                        Text(
                          'يفصل هذا السجل بين وجود رابط مرجعي وبين إثبات أن النص المحلي هو النص النافذ الموحّد. لم تُعتمد أي قاعدة حسابية متخصصة لمجرد العثور على صفحة القانون.',
                          style: TextStyle(color: Color(0xFFD0C4B4), height: 1.7, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: _SourceStat(label: 'القوانين المحلية', value: _laws.length.toString())),
                    const SizedBox(width: 8),
                    Expanded(child: _SourceStat(label: 'لها مصدر مرجعي أولي', value: sourced.toString())),
                    const SizedBox(width: 8),
                    const Expanded(child: _SourceStat(label: 'مطابقة مكتملة', value: '0')),
                  ]),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'ابحث عن اسم القانون...',
                      prefixIcon: const Icon(Icons.search_rounded),
                      filled: true,
                      fillColor: _sourcePanel,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: _sourceLine)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: _sourceLine)),
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                    ),
                  const SizedBox(height: 12),
                  for (final law in visible) _LawSourceCard(law: law, record: _recordFor(law)),
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: const Color(0xFF211B14), borderRadius: BorderRadius.circular(17), border: Border.all(color: const Color(0xFF5C472C))),
                    child: const Text(
                      'قاعدة اعتماد: لا تُنشر حاسبة قانونية إلا بعد توثيق رقم القانون وسنته، والمادة ونصها، ومصدر رسمي، والتعديلات ذات الصلة، وتاريخ المطابقة، وقاعدة احتساب المدة والاستثناءات. تاريخ فتح الرابط لا يعني أن النص جرى توحيده أو التحقق من نفاذه.',
                      style: TextStyle(color: Color(0xFFF1D9A0), fontSize: 12, height: 1.7),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

_LegalSourceRecord? _recordFor(Law law) {
  for (final record in _sourceRecords) {
    if (record.matches(law)) return record;
  }
  return null;
}

class _LawSourceCard extends StatelessWidget {
  final Law law;
  final _LegalSourceRecord? record;
  const _LawSourceCard({required this.law, required this.record});

  Future<void> _openSource(BuildContext context) async {
    final url = record?.url;
    if (url == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لم يُسجل مصدر موثوق لهذا القانون بعد.')),
      );
      return;
    }
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر فتح المصدر المرجعي.')),
      );
    }
  }

  Future<void> _showLocalText(BuildContext context) async {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => _LocalArticlesDialog(law: law, record: record),
    );
  }

  @override
  Widget build(BuildContext context) {
    final matched = record != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: _sourcePanel, borderRadius: BorderRadius.circular(18), border: Border.all(color: _sourceLine)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.menu_book_rounded, color: _sourceGold, size: 27),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(law.name, style: const TextStyle(color: Color(0xFFF1D9A0), fontWeight: FontWeight.w800, fontSize: 14, height: 1.5)),
              const SizedBox(height: 5),
              Text('عدد المواد في القاعدة: ${law.articlesCount}', style: const TextStyle(color: Color(0xFFB7AFA2), fontSize: 11.5)),
            ])),
          ]),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: matched ? const Color(0xFF2A2116) : const Color(0xFF282020),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: matched ? const Color(0xFF806139) : const Color(0xFF674343)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(matched ? record!.citation : 'لم يُربط بعد بمصدر مرجعي موثق',
                  style: const TextStyle(color: Color(0xFFF1D9A0), fontWeight: FontWeight.w700, fontSize: 12)),
              const SizedBox(height: 5),
              Text(matched ? record!.authority : 'يحتاج إلى تحديد مصدر رسمي ومراجعة التعديلات.',
                  style: const TextStyle(color: Color(0xFFC7BDAF), fontSize: 11.5)),
              if (matched) ...[
                const SizedBox(height: 7),
                Text('حالة المراجعة: ${record!.status}', style: const TextStyle(color: Color(0xFFE0B8A0), fontSize: 11.5, height: 1.5)),
                Text('آخر تحقق من صفحة المصدر: ${record!.checkedAt}', style: const TextStyle(color: Color(0xFFB7AFA2), fontSize: 10.5)),
                const SizedBox(height: 5),
                Text(record!.amendmentNote, style: const TextStyle(color: Color(0xFFD0C4B4), fontSize: 11, height: 1.6)),
              ],
            ]),
          ),
          const SizedBox(height: 9),
          Wrap(spacing: 8, runSpacing: 6, children: [
            OutlinedButton.icon(
              onPressed: () => _showLocalText(context),
              icon: const Icon(Icons.article_outlined, size: 17),
              label: const Text('مراجعة النص المحلي'),
              style: OutlinedButton.styleFrom(foregroundColor: _sourceGold, side: const BorderSide(color: _sourceLine)),
            ),
            if (matched)
              FilledButton.tonalIcon(
                onPressed: () => _openSource(context),
                icon: const Icon(Icons.open_in_new_rounded, size: 17),
                label: const Text('فتح المصدر'),
                style: FilledButton.styleFrom(foregroundColor: const Color(0xFFF1D9A0), backgroundColor: const Color(0xFF3A2A18)),
              ),
          ]),
        ]),
      ),
    );
  }
}

class _LocalArticlesDialog extends StatefulWidget {
  final Law law;
  final _LegalSourceRecord? record;
  const _LocalArticlesDialog({required this.law, required this.record});

  @override
  State<_LocalArticlesDialog> createState() => _LocalArticlesDialogState();
}

class _LocalArticlesDialogState extends State<_LocalArticlesDialog> {
  List<DocumentItem>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await LawsRepository.instance.getFullLawDocument(widget.law.id);
      if (!mounted) return;
      setState(() => _items = items);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'تعذر تحميل نص القانون.');
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: _sourcePanel,
    insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: _sourceLine)),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620, maxHeight: 760),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: Row(children: [
            const Icon(Icons.fact_check_rounded, color: _sourceGold),
            const SizedBox(width: 9),
            Expanded(child: Text(widget.law.name, style: const TextStyle(color: Color(0xFFF1D9A0), fontWeight: FontWeight.w800))),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
          ]),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: const Color(0xFF2A2116), borderRadius: BorderRadius.circular(11)),
          child: Text(
            widget.record == null
                ? 'هذا هو النص المخزن محليًا. لم يُربط بعد بمصدر مرجعي موثق، فلا تعتبره نسخة موحّدة نافذة.'
                : 'هذا هو النص المخزن محليًا. المرجع: ${widget.record!.citation}. حالة مطابقة التعديلات: غير مكتملة؛ لا تعتمد النص وحده لحساب مدة أو استحقاق.',
            style: const TextStyle(color: Color(0xFFF1D9A0), fontSize: 11.5, height: 1.6),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _items == null
              ? Center(child: _error == null ? const CircularProgressIndicator(color: _sourceGold) : Text(_error!))
              : ListView(
                  padding: const EdgeInsets.all(14),
                  children: [
                    for (final item in _items!)
                      if (item.isHeading)
                        Padding(
                          padding: const EdgeInsets.only(top: 13, bottom: 6),
                          child: Text(item.headingText ?? '', style: const TextStyle(color: _sourceGold, fontWeight: FontWeight.w800, fontSize: 14)),
                        )
                      else if (item.madda != null)
                        _ArticleTextCard(madda: item.madda!),
                    if (_items!.isEmpty) const Text('لا توجد مواد في هذا القانون بقاعدة البيانات.', style: TextStyle(color: Colors.white70)),
                  ],
                ),
        ),
      ]),
    ),
  );
}

class _ArticleTextCard extends StatelessWidget {
  final Madda madda;
  const _ArticleTextCard({required this.madda});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 9),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: const Color(0xFF201B15), borderRadius: BorderRadius.circular(13), border: Border.all(color: _sourceLine)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('مادة (${madda.number})', style: const TextStyle(color: Color(0xFFF1D9A0), fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      SelectableText(madda.body, style: const TextStyle(color: Color(0xFFE4DBCF), height: 1.75, fontSize: 12.5)),
      const SizedBox(height: 7),
      const Text('الحالة: نص محلي لم تُثبت مطابقته بعد بالنص الرسمي الموحّد.',
          style: TextStyle(color: Color(0xFFD9A18D), fontSize: 10.5, height: 1.5)),
    ]),
  );
}

class _SourceStat extends StatelessWidget {
  final String label;
  final String value;
  const _SourceStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(color: _sourcePanel, borderRadius: BorderRadius.circular(14), border: Border.all(color: _sourceLine)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(value, style: const TextStyle(color: Color(0xFFF1D9A0), fontSize: 20, fontWeight: FontWeight.w900)),
      const SizedBox(height: 4),
      Text(label, style: const TextStyle(color: Color(0xFFB7AFA2), fontSize: 10.5, height: 1.4)),
    ]),
  );
}
