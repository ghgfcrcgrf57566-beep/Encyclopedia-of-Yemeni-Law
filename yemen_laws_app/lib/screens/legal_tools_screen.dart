import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const gold = Color(0xFFD4AF6A);
const goldLight = Color(0xFFF1D9A0);
const panel = Color(0xFF171310);
const line = Color(0xFF51412D);

class LegalToolsScreen extends StatelessWidget {
  const LegalToolsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final items = [
      _Tool(Icons.calendar_month_rounded, 'حاسبة المدد والمبالغ', 'حساب تاريخ بعد مدة أو نسبة من مبلغ، مع توضيح المعادلة.', const LegalCalculatorScreen(), 'حسابات'),
      _Tool(Icons.account_balance_rounded, 'دليل الإجراءات القضائية', 'قوائم تحقق لتنظيم خطوات العمل في ملف الدعوى.', const JudicialProceduresScreen(), 'دليل عملي'),
      _Tool(Icons.folder_special_rounded, 'إدارة القضايا', 'سجل محلي للقضايا والجلسات والملاحظات الخاصة.', const LegalCaseManagerScreen(), 'مساحة شخصية'),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('الأدوات القانونية')),
      body: Directionality(textDirection: TextDirection.rtl, child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _Hero(icon: Icons.gavel_rounded, eyebrow: 'مساحة العمل القانوني', title: 'أدوات عملية للمحامي والباحث',
            body: 'احسب، وتحقق من خطوات الإجراء، ونظّم قضاياك في مكان واحد. لا تُعرض أي قاعدة على أنها حكم قانوني إلا بعد توثيق مصدرها.'),
          const SizedBox(height: 18),
          const Text('الأدوات المتاحة', style: TextStyle(color: goldLight, fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          ...items.map((item) => Padding(padding: const EdgeInsets.only(bottom: 12), child: _ToolCard(item: item))),
          const _Notice(title: 'التحقق قبل الاعتماد', body: 'قد تتأثر المواعيد والاختصاصات والاستحقاقات بنصوص خاصة أو تعديلات أو وقائع الدعوى. راجع النص النافذ ومصدره قبل اتخاذ إجراء أو اعتماد نتيجة حسابية.', icon: Icons.verified_user_outlined),
        ],
      )),
    );
  }
}

class _Tool {
  final IconData icon;
  final String title;
  final String body;
  final Widget page;
  final String tag;
  const _Tool(this.icon, this.title, this.body, this.page, this.tag);
}

class _ToolCard extends StatelessWidget {
  final _Tool item;
  const _ToolCard({required this.item});
  @override
  Widget build(BuildContext context) => Material(
    color: panel, borderRadius: BorderRadius.circular(21),
    child: InkWell(
      borderRadius: BorderRadius.circular(21),
      onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => item.page)),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(21), border: Border.all(color: line)),
        child: Row(children: [
          Container(width: 58, height: 58, decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [goldLight, gold, Color(0xFF805A2D)]),
          ), child: Icon(item.icon, color: const Color(0xFF27190A), size: 30)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.title, style: const TextStyle(color: goldLight, fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 5),
            Text(item.body, style: const TextStyle(color: Color(0xFFC7BDAF), fontSize: 12, height: 1.6)),
            const SizedBox(height: 8),
            Text(item.tag + '  ←', style: const TextStyle(color: gold, fontSize: 11, fontWeight: FontWeight.w800)),
          ])),
        ]),
      ),
    ),
  );
}

class LegalCalculatorScreen extends StatefulWidget {
  const LegalCalculatorScreen({super.key});
  @override
  State<LegalCalculatorScreen> createState() => _LegalCalculatorScreenState();
}

class _LegalCalculatorScreenState extends State<LegalCalculatorScreen> {
  final _days = TextEditingController(text: '15');
  final _amount = TextEditingController();
  final _rate = TextEditingController();
  final _source = TextEditingController();
  DateTime _start = DateTime.now();
  DateTime? _dateResult;
  double? _percentResult;
  bool _includeStart = false;
  String _tab = 'dates';

  @override
  void dispose() {
    _days.dispose(); _amount.dispose(); _rate.dispose(); _source.dispose();
    super.dispose();
  }

  Future<void> _chooseDate() async {
    final picked = await showDatePicker(
      context: context, initialDate: _start, firstDate: DateTime(1950), lastDate: DateTime(2200),
      helpText: 'اختر تاريخ البداية', confirmText: 'اعتماد', cancelText: 'إلغاء',
    );
    if (picked != null && mounted) setState(() { _start = DateTime(picked.year, picked.month, picked.day); _dateResult = null; });
  }

  void _dateCalc() {
    final number = int.tryParse(_days.text.trim());
    if (number == null || number < 1 || number > 36500) {
      _message('أدخل عدد أيام صحيحًا بين 1 و36500.');
      return;
    }
    setState(() => _dateResult = _start.add(Duration(days: _includeStart ? number - 1 : number)));
  }

  void _amountCalc() {
    final amount = double.tryParse(_amount.text.trim().replaceAll(',', ''));
    final rate = double.tryParse(_rate.text.trim().replaceAll(',', ''));
    if (amount == null || !amount.isFinite || amount < 0) {
      _message('أدخل مبلغًا أساسيًا صحيحًا غير سالب.');
      return;
    }
    if (rate == null || !rate.isFinite || rate < 0 || rate > 100000) {
      _message('أدخل نسبة صحيحة غير سالبة.');
      return;
    }
    setState(() => _percentResult = amount * rate / 100);
  }

  void _message(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('حاسبة المدد والمبالغ')),
    body: Directionality(textDirection: TextDirection.rtl, child: ListView(padding: const EdgeInsets.all(16), children: [
      const _Intro(title: 'حساب واضح ومراجعته مسؤوليتك', body: 'أدخل المدة أو النسبة بعد مراجعة النص القانوني الذي ينطبق على حالتك.'),
      const SizedBox(height: 12),
      Wrap(spacing: 8, children: [
        _Pill('المدد والتواريخ', _tab == 'dates', () => setState(() { _tab = 'dates'; _dateResult = null; _percentResult = null; })),
        _Pill('المبالغ والنسب', _tab == 'amounts', () => setState(() { _tab = 'amounts'; _dateResult = null; _percentResult = null; })),
      ]),
      const SizedBox(height: 12),
      if (_tab == 'dates') _dateForm(),
      if (_tab == 'amounts') _amountForm(),
      const SizedBox(height: 12),
      const _Notice(icon: Icons.info_outline_rounded, title: 'تنبيه قانوني مهم', body: 'هذه حاسبة حسابية عامة وليست تقويمًا قضائيًا معتمدًا. لا تحتسب العطلات أو الوقف أو الانقطاع أو الاستثناءات الخاصة، ولا تتحقق من انطباق المادة. راجع النص النافذ والوقائع قبل اعتماد أي تاريخ أو مبلغ.'),
    ])),
  );

  Widget _dateForm() => _FormPanel(title: 'حساب تاريخ بعد مدة', description: 'الحساب بالأيام فقط؛ لا تُطبق قاعدة قانونية تلقائيًا.', children: [
    const _Label('تاريخ بداية الحساب'),
    OutlinedButton.icon(onPressed: _chooseDate, icon: const Icon(Icons.calendar_month_rounded), label: Text(_date(_start)),
      style: OutlinedButton.styleFrom(foregroundColor: goldLight, side: const BorderSide(color: line), padding: const EdgeInsets.symmetric(vertical: 13))),
    const SizedBox(height: 12),
    const _Label('عدد الأيام'),
    TextField(controller: _days, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: 'مثال: 15', suffixIcon: Icon(Icons.numbers_rounded))),
    SwitchListTile(
      contentPadding: EdgeInsets.zero, activeColor: gold, value: _includeStart,
      onChanged: (v) => setState(() { _includeStart = v; _dateResult = null; }),
      title: const Text('احتساب يوم البداية ضمن المدة', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
      subtitle: Text(_includeStart ? 'يُعامل يوم البداية حسابيًا على أنه اليوم الأول.' : 'يبدأ العد الحسابي من اليوم التالي.', style: const TextStyle(color: Color(0xFFB7AFA2), fontSize: 11.5)),
    ),
    _GoldAction('احسب التاريخ', Icons.event_available_rounded, _dateCalc),
    if (_dateResult != null) ...[
      const SizedBox(height: 12),
      _Result(title: 'التاريخ الناتج حسابيًا', result: _date(_dateResult!), detail: 'البداية: ' + _date(_start) + '؛ عدد الأيام: ' + _days.text.trim() + (_includeStart ? ' مع احتساب يوم البداية.' : ' دون احتساب يوم البداية.'), source: ''),
    ],
  ]);

  Widget _amountForm() => _FormPanel(title: 'حساب نسبة من مبلغ', description: 'الأداة لا تقترح نسبًا نظامية؛ أدخل النسبة بعد التحقق من مصدرها.', children: [
    const _Label('المبلغ الأساسي'),
    TextField(controller: _amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(hintText: '0.00', suffixIcon: Icon(Icons.account_balance_wallet_outlined))),
    const SizedBox(height: 12),
    const _Label('النسبة المئوية المعتمدة لديك'),
    TextField(controller: _rate, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(hintText: 'مثال: 5', suffixIcon: Icon(Icons.percent_rounded))),
    const SizedBox(height: 12),
    const _Label('مصدر النسبة: القانون ورقم المادة'),
    TextField(controller: _source, maxLines: 2, decoration: const InputDecoration(hintText: 'اسم القانون / المادة / إصدار النص', suffixIcon: Icon(Icons.menu_book_rounded))),
    _GoldAction('احسب النسبة', Icons.functions_rounded, _amountCalc),
    if (_percentResult != null) ...[
      const SizedBox(height: 12),
      _Result(title: 'قيمة النسبة حسابيًا', result: _money(_percentResult!), detail: _money(double.parse(_amount.text.trim().replaceAll(',', ''))) + ' × ' + _rate.text.trim() + ' ÷ 100 = ' + _money(_percentResult!), source: _source.text.trim()),
    ],
  ]);
}

class JudicialProceduresScreen extends StatefulWidget {
  const JudicialProceduresScreen({super.key});
  @override
  State<JudicialProceduresScreen> createState() => _JudicialProceduresScreenState();
}

class _JudicialProceduresScreenState extends State<JudicialProceduresScreen> {
  final Map<String, Set<int>> _checked = {};
  static const steps = <_Step>[
    _Step('1. توصيف النزاع والطلبات', 'رتّب الوقائع والطلب قبل إعداد ملف الدعوى.', ['تدوين الوقائع بالتواريخ والأطراف.', 'تحديد الطلبات بصورة واضحة.', 'تمييز الوقائع الثابتة عن المسائل التي تحتاج إلى إثبات.', 'حصر الأدلة والمستندات المتاحة وما ينقص الملف.'], 'لا تُدخل وقائع غير متحققة ولا تُغفل واقعة قد تؤثر في الطلب أو الدفاع.'),
    _Step('2. مراجعة الاختصاص والصفة', 'تحقق من المحكمة المختصة ومن صفة الأطراف قبل التقديم.', ['مراجعة الاختصاص النوعي والمكاني وأي اختصاص خاص محتمل.', 'التحقق من الصفة والمصلحة والأهلية والوكالة.', 'فحص وجود شرط أو إجراء سابق يؤثر في طريق التقاضي.', 'مراجعة النصوص الخاصة بنوع النزاع.'], 'لا يحدد التطبيق المحكمة المختصة تلقائيًا؛ يتوقف ذلك على النزاع والنصوص والوقائع.'),
    _Step('3. تجهيز ملف الدعوى', 'نظّم صحيفة الدعوى والمرفقات وفق متطلبات الإجراء المعني.', ['إعداد مسودة الطلبات والوقائع وأسانيدها.', 'مطابقة أسماء الأطراف وصفاتهم في المستندات.', 'ترتيب الأدلة والمرفقات وفهرستها.', 'الاحتفاظ بنسخ واضحة وأصول المستندات عند الحاجة.'], 'هذه قائمة تنظيمية وليست نموذجًا رسميًا أو بديلًا عن متطلبات المحكمة.'),
    _Step('4. الإيداع والتبليغ', 'تحقق من قناة الإيداع والمتطلبات والإجراءات اللاحقة.', ['مراجعة طريقة تقديم الدعوى لدى الجهة المختصة.', 'التحقق مما إذا كانت رسوم أو مستندات إضافية مطلوبة.', 'حفظ إثبات الإيداع ورقم القيد وتاريخه.', 'متابعة إعلان الخصوم وإثباته في الملف.'], 'لم تُدرج رسوم أو مدد محددة؛ ارجع إلى النص النافذ والجهة القضائية المعنية.'),
    _Step('5. إدارة الجلسات والمواعيد', 'أنشئ سجلًا لكل جلسة وما صدر فيها وما يلزم بعدها.', ['تسجيل موعد الجلسة ومكانها ورقم القضية.', 'تدوين ما طلبته المحكمة وما تقرر تأجيله.', 'تحديد الإجراء التالي والموعد المستهدف والمسؤول عنه.', 'حفظ المحاضر والقرارات والمستندات المستلمة.'], 'التذكير داخل التطبيق ليس تبليغًا قضائيًا أو إثباتًا رسميًا للحضور.'),
    _Step('6. ما بعد الحكم والتنفيذ', 'راجع منطوق الحكم وحدد الخطوة التالية بعد التحقق من وضعه.', ['الحصول على نسخة الحكم والمحاضر ذات الصلة.', 'مراجعة طرق الطعن وشروطها ومواعيدها في النص النافذ.', 'التحقق من وصف الحكم وقابليته للتنفيذ ومتطلباته.', 'حفظ ما يثبت الطلبات والإجراءات ونتائجها.'], 'لا يفترض الدليل أن الحكم نهائي أو واجب التنفيذ؛ افحص كل حالة على حدة.'),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('دليل الإجراءات القضائية')),
    body: Directionality(textDirection: TextDirection.rtl, child: ListView(padding: const EdgeInsets.all(16), children: [
      const _Hero(icon: Icons.account_balance_rounded, eyebrow: 'مسار عمل منظم', title: 'من دراسة النزاع إلى متابعة ما بعد الحكم',
        body: 'قائمة تحقق عملية لترتيب ملف الدعوى وعدم إغفال المهام. لا تتضمن هذه النسخة مددًا قانونية أو تحديدًا آليًا للاختصاص قبل توثيق القواعد من النصوص اليمنية النافذة.'),
      const SizedBox(height: 12),
      ...steps.map(_stepCard),
      const _Notice(icon: Icons.menu_book_rounded, title: 'التوثيق القانوني', body: 'قبل اعتماد القسم كمرجع إجرائي، ينبغي ربط كل خطوة بالقانون اليمني النافذ ورقم المادة والنص وتاريخ آخر مراجعة. لا تُعرض المدد أو الرسوم أو قواعد الاختصاص كحقائق نهائية ما لم توثّق.'),
    ])),
  );

  Widget _stepCard(_Step step) {
    final checked = _checked.putIfAbsent(step.title, () => <int>{});
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(18), border: Border.all(color: line)),
      child: ExpansionTile(
        leading: const Icon(Icons.checklist_rounded, color: gold),
        title: Text(step.title, style: const TextStyle(color: goldLight, fontWeight: FontWeight.w800, fontSize: 14)),
        subtitle: Text(step.summary, style: const TextStyle(color: Color(0xFFC7BDAF), fontSize: 12, height: 1.5)),
        iconColor: gold, collapsedIconColor: gold,
        children: [
          for (var i = 0; i < step.items.length; i++)
            CheckboxListTile(
              value: checked.contains(i), activeColor: gold, checkColor: Colors.black, dense: true,
              controlAffinity: ListTileControlAffinity.leading, contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              onChanged: (value) => setState(() { if (value == true) { checked.add(i); } else { checked.remove(i); } }),
              title: Text(step.items[i], style: const TextStyle(color: Color(0xFFE5DDD0), fontSize: 12.5, height: 1.5)),
            ),
          Container(
            margin: const EdgeInsets.fromLTRB(12, 4, 12, 14), padding: const EdgeInsets.all(11), width: double.infinity,
            decoration: BoxDecoration(color: const Color(0xFF302116), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF6C4B25))),
            child: Text(step.caution, style: const TextStyle(color: goldLight, height: 1.55, fontSize: 11.5)),
          ),
        ],
      ),
    );
  }
}

class _Step {
  final String title;
  final String summary;
  final List<String> items;
  final String caution;
  const _Step(this.title, this.summary, this.items, this.caution);
}

class LegalCaseManagerScreen extends StatefulWidget {
  const LegalCaseManagerScreen({super.key});
  @override
  State<LegalCaseManagerScreen> createState() => _LegalCaseManagerScreenState();
}

class _LegalCaseManagerScreenState extends State<LegalCaseManagerScreen> {
  static const key = 'legal_case_records_v1';
  List<_CaseRecord> _cases = [];
  bool _loading = true;
  String _filter = 'all';

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      final data = raw == null ? <dynamic>[] : jsonDecode(raw) as List<dynamic>;
      final values = data.whereType<Map<String, dynamic>>().map(_CaseRecord.fromJson).toList();
      if (!mounted) return;
      setState(() { _cases = values; _loading = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      _toast('تعذر قراءة السجل المحلي.');
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(_cases.map((c) => c.toJson()).toList()));
  }

  Future<void> _create() async {
    final result = await showDialog<_CaseRecord>(context: context, barrierDismissible: false, builder: (_) => const _CaseEditor());
    if (result == null || !mounted) return;
    setState(() => _cases = [..._cases, result]);
    await _save();
    if (mounted) _toast('تم حفظ السجل على الجهاز.');
  }

  Future<void> _edit(_CaseRecord item) async {
    final result = await showDialog<_CaseRecord>(context: context, barrierDismissible: false, builder: (_) => _CaseEditor(existing: item));
    if (result == null || !mounted) return;
    setState(() => _cases = _cases.map((c) => c.id == result.id ? result : c).toList());
    await _save();
    if (mounted) _toast('تم تحديث بيانات القضية.');
  }

  Future<void> _delete(_CaseRecord item) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('حذف سجل القضية'),
      content: Text('حذف «' + item.title + '» من هذا الجهاز؟ لا يمكن التراجع عن الحذف.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(backgroundColor: const Color(0xFFA84C4C)), child: const Text('حذف')),
      ],
    ));
    if (ok != true || !mounted) return;
    setState(() => _cases = _cases.where((c) => c.id != item.id).toList());
    await _save();
    if (mounted) _toast('تم حذف سجل القضية.');
  }

  void _toast(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    final visible = _cases.where((c) => _filter == 'all' || (_filter == 'closed' ? c.status == 'مغلقة' : c.status != 'مغلقة')).toList()
      ..sort((a, b) => (a.session ?? DateTime(2200)).compareTo(b.session ?? DateTime(2200)));
    return Scaffold(
      appBar: AppBar(title: const Text('إدارة القضايا'), actions: [IconButton(onPressed: _create, tooltip: 'إضافة قضية', icon: const Icon(Icons.add_circle_outline_rounded))]),
      floatingActionButton: FloatingActionButton.extended(onPressed: _create, icon: const Icon(Icons.add_rounded), label: const Text('قضية جديدة')),
      body: Directionality(textDirection: TextDirection.rtl, child: _loading
        ? const Center(child: CircularProgressIndicator(color: gold))
        : ListView(padding: const EdgeInsets.fromLTRB(16, 10, 16, 100), children: [
          const _Hero(icon: Icons.folder_special_rounded, eyebrow: 'سجل شخصي', title: 'ملفاتك القانونية في مكان واحد',
            body: 'أنشئ سجلًا لكل قضية، وحدّث حالتها واحفظ الجلسات والملاحظات. لا تتم مزامنة البيانات إلى خادم في هذه النسخة.'),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _Stat('إجمالي السجلات', _cases.length.toString(), Icons.folder_open_rounded)),
            const SizedBox(width: 8),
            Expanded(child: _Stat('قضايا نشطة', _cases.where((c) => c.status != 'مغلقة').length.toString(), Icons.pending_actions_rounded)),
            const SizedBox(width: 8),
            Expanded(child: _Stat('مغلقة', _cases.where((c) => c.status == 'مغلقة').length.toString(), Icons.task_alt_rounded)),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [
            _Pill('الكل', _filter == 'all', () => setState(() => _filter = 'all')),
            _Pill('نشطة', _filter == 'open', () => setState(() => _filter = 'open')),
            _Pill('مغلقة', _filter == 'closed', () => setState(() => _filter = 'closed')),
          ]),
          const SizedBox(height: 12),
          if (visible.isEmpty) _EmptyCases(onCreate: _create)
          else ...visible.map((c) => _CaseCard(item: c, onTap: () => _edit(c), onDelete: () => _delete(c))),
          const _Notice(icon: Icons.lock_outline_rounded, title: 'الخصوصية', body: 'يُحفظ السجل داخل مساحة التطبيق على الجهاز ولا تتم مزامنته تلقائيًا. هذه النسخة لا تقدم تشفيرًا مستقلًا لسجلات القضايا؛ فعّل قفل الجهاز ولا تحفظ بيانات شديدة الحساسية قبل تقييم وسائل الحماية والنسخ الاحتياطي.'),
        ]),
      ),
    );
  }
}

class _CaseRecord {
  final String id, title, number, court, category, status, time, notes;
  final DateTime? session;
  const _CaseRecord({required this.id, required this.title, required this.number, required this.court, required this.category, required this.status, required this.session, required this.time, required this.notes});

  factory _CaseRecord.fromJson(Map<String, dynamic> j) => _CaseRecord(
    id: j['id']?.toString() ?? DateTime.now().microsecondsSinceEpoch.toString(),
    title: j['title']?.toString() ?? '', number: j['number']?.toString() ?? '',
    court: j['court']?.toString() ?? '', category: j['category']?.toString() ?? 'أخرى',
    status: j['status']?.toString() ?? 'نشطة', session: DateTime.tryParse(j['session']?.toString() ?? ''),
    time: j['time']?.toString() ?? '', notes: j['notes']?.toString() ?? '',
  );

  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'number': number, 'court': court, 'category': category, 'status': status, 'session': session?.toIso8601String(), 'time': time, 'notes': notes};
}

class _CaseEditor extends StatefulWidget {
  final _CaseRecord? existing;
  const _CaseEditor({this.existing});
  @override
  State<_CaseEditor> createState() => _CaseEditorState();
}

class _CaseEditorState extends State<_CaseEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _title, _number, _court, _time, _notes;
  String _category = 'مدنية', _status = 'نشطة';
  DateTime? _session;
  static const categories = ['مدنية', 'تجارية', 'أحوال شخصية', 'جنائية', 'إدارية', 'تنفيذ', 'أخرى'];
  static const statuses = ['نشطة', 'بانتظار إجراء', 'مؤجلة', 'مغلقة'];

  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    _title = TextEditingController(text: c?.title ?? '');
    _number = TextEditingController(text: c?.number ?? '');
    _court = TextEditingController(text: c?.court ?? '');
    _time = TextEditingController(text: c?.time ?? '');
    _notes = TextEditingController(text: c?.notes ?? '');
    _category = categories.contains(c?.category) ? c!.category : 'مدنية';
    _status = statuses.contains(c?.status) ? c!.status : 'نشطة';
    _session = c?.session;
  }

  @override
  void dispose() { _title.dispose(); _number.dispose(); _court.dispose(); _time.dispose(); _notes.dispose(); super.dispose(); }

  Future<void> _pickSession() async {
    final picked = await showDatePicker(context: context, initialDate: _session ?? DateTime.now(), firstDate: DateTime(1950), lastDate: DateTime(2200), helpText: 'موعد الجلسة القادمة', confirmText: 'اعتماد', cancelText: 'إلغاء');
    if (picked != null && mounted) setState(() => _session = picked);
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    final c = widget.existing;
    Navigator.pop(context, _CaseRecord(
      id: c?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      title: _title.text.trim(), number: _number.text.trim(), court: _court.text.trim(),
      category: _category, status: _status, session: _session, time: _time.text.trim(), notes: _notes.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: panel, insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: const BorderSide(color: line)),
    child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560, maxHeight: 700), child: Form(
      key: _form,
      child: ListView(padding: const EdgeInsets.all(18), shrinkWrap: true, children: [
        Text(widget.existing == null ? 'إضافة قضية جديدة' : 'تعديل القضية', style: const TextStyle(color: goldLight, fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 14),
        const _Label('عنوان القضية *'),
        TextFormField(controller: _title, validator: (v) => v == null || v.trim().isEmpty ? 'عنوان القضية مطلوب.' : null, decoration: const InputDecoration(hintText: 'مثال: مطالبة بمبلغ')),
        const SizedBox(height: 10),
        const _Label('رقم القضية'),
        TextField(controller: _number, decoration: const InputDecoration(hintText: 'رقم القيد أو الملف')),
        const SizedBox(height: 10),
        const _Label('المحكمة أو الجهة'),
        TextField(controller: _court, decoration: const InputDecoration(hintText: 'اسم المحكمة أو الجهة')),
        const SizedBox(height: 10),
        const _Label('تصنيف القضية'),
        DropdownButtonFormField<String>(value: _category, items: categories.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(), onChanged: (v) { if (v != null) setState(() => _category = v); }),
        const SizedBox(height: 10),
        const _Label('حالة الملف'),
        DropdownButtonFormField<String>(value: _status, items: statuses.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(), onChanged: (v) { if (v != null) setState(() => _status = v); }),
        const SizedBox(height: 10),
        const _Label('موعد الجلسة القادمة'),
        OutlinedButton.icon(onPressed: _pickSession, icon: const Icon(Icons.event_rounded), label: Text(_session == null ? 'لم يحدد موعد' : _date(_session!)), style: OutlinedButton.styleFrom(foregroundColor: goldLight, side: const BorderSide(color: line))),
        TextButton.icon(onPressed: _session == null ? null : () => setState(() => _session = null), icon: const Icon(Icons.event_busy_rounded, size: 17), label: const Text('إزالة موعد الجلسة')),
        const SizedBox(height: 4),
        const _Label('وقت الجلسة (اختياري)'),
        TextField(controller: _time, decoration: const InputDecoration(hintText: 'مثال: 09:30 صباحًا')),
        const SizedBox(height: 10),
        const _Label('ملاحظات المتابعة'),
        TextField(controller: _notes, maxLines: 4, decoration: const InputDecoration(hintText: 'الإجراء التالي، المستند الناقص، نقاط الجلسة...')),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), style: OutlinedButton.styleFrom(foregroundColor: goldLight, side: const BorderSide(color: line)), child: const Text('إلغاء'))),
          const SizedBox(width: 10),
          Expanded(child: FilledButton.icon(onPressed: _submit, icon: const Icon(Icons.save_rounded), label: const Text('حفظ'), style: FilledButton.styleFrom(backgroundColor: gold, foregroundColor: Colors.black))),
        ]),
      ]),
    )),
  );
}

class _CaseCard extends StatelessWidget {
  final _CaseRecord item;
  final VoidCallback onTap, onDelete;
  const _CaseCard({required this.item, required this.onTap, required this.onDelete});
  @override
  Widget build(BuildContext context) {
    final metadata = [if (item.number.isNotEmpty) 'رقم: ' + item.number, item.category, if (item.court.isNotEmpty) item.court].join(' • ');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(18), border: Border.all(color: line)),
      child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(18), child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.folder_copy_rounded, color: gold, size: 29),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.title, style: const TextStyle(color: goldLight, fontWeight: FontWeight.w800, fontSize: 14)),
              const SizedBox(height: 4),
              Text(metadata, style: const TextStyle(color: Color(0xFFB7AFA2), fontSize: 11.5, height: 1.5)),
            ])),
            IconButton(onPressed: onDelete, tooltip: 'حذف سجل القضية', icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFC7796D))),
          ]),
          Wrap(spacing: 7, runSpacing: 7, children: [
            _Tag(item.status),
            if (item.session != null) _Tag('الجلسة: ' + _date(item.session!) + (item.time.isNotEmpty ? ' • ' + item.time : '')),
          ]),
          if (item.notes.trim().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 9), child: Text(item.notes, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFE0D7C9), fontSize: 12, height: 1.6))),
          const SizedBox(height: 7),
          const Align(alignment: Alignment.centerLeft, child: Text('عرض وتعديل  ✎', style: TextStyle(color: gold, fontSize: 11.5, fontWeight: FontWeight.w800))),
        ]),
      )),
    );
  }
}

class _EmptyCases extends StatelessWidget {
  final VoidCallback onCreate;
  const _EmptyCases({required this.onCreate});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(25),
    decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(20), border: Border.all(color: line)),
    child: Column(children: [
      const Icon(Icons.folder_open_rounded, size: 48, color: gold),
      const SizedBox(height: 12),
      const Text('لا توجد قضايا في هذا العرض', style: TextStyle(color: goldLight, fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      const Text('أضف أول سجل، ثم حدّث الجلسات والملاحظات كلما استجد إجراء.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFFB7AFA2), height: 1.6, fontSize: 12)),
      const SizedBox(height: 14),
      FilledButton.icon(onPressed: onCreate, icon: const Icon(Icons.add_rounded), label: const Text('إضافة أول قضية'), style: FilledButton.styleFrom(backgroundColor: gold, foregroundColor: Colors.black)),
    ]),
  );
}

class _Hero extends StatelessWidget {
  final IconData icon;
  final String eyebrow, title, body;
  const _Hero({required this.icon, required this.eyebrow, required this.title, required this.body});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(23),
      gradient: const LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [Color(0xFF302216), Color(0xFF17110C), Color(0xFF100D0A)]),
      border: Border.all(color: const Color(0xFF826235)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 44, height: 44, decoration: BoxDecoration(color: gold.withOpacity(.14), borderRadius: BorderRadius.circular(14), border: Border.all(color: gold.withOpacity(.4))), child: Icon(icon, color: goldLight)),
        const SizedBox(width: 10),
        Expanded(child: Text(eyebrow.toUpperCase(), style: const TextStyle(color: gold, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: .7))),
        const _Tag('YEMEN LAW'),
      ]),
      const SizedBox(height: 15),
      Text(title, style: const TextStyle(color: goldLight, fontSize: 20, fontWeight: FontWeight.w900, height: 1.35)),
      const SizedBox(height: 8),
      Text(body, style: const TextStyle(color: Color(0xFFD0C4B4), fontSize: 12.5, height: 1.75)),
    ]),
  );
}

class _Intro extends StatelessWidget {
  final String title, body;
  const _Intro({required this.title, required this.body});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(17), border: Border.all(color: line)),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Icon(Icons.calculate_rounded, color: gold, size: 25), const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(color: goldLight, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(body, style: const TextStyle(color: Color(0xFFC7BDAF), fontSize: 12, height: 1.6)),
      ])),
    ]),
  );
}

class _FormPanel extends StatelessWidget {
  final String title, description;
  final List<Widget> children;
  const _FormPanel({required this.title, required this.description, required this.children});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(21), border: Border.all(color: line)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(color: goldLight, fontSize: 17, fontWeight: FontWeight.w800)),
      const SizedBox(height: 5),
      Text(description, style: const TextStyle(color: Color(0xFFB7AFA2), fontSize: 11.5, height: 1.55)),
      const SizedBox(height: 14),
      ...children,
    ]),
  );
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(text, style: const TextStyle(color: Color(0xFFE5DDD0), fontSize: 12.5, fontWeight: FontWeight.w700)));
}

class _GoldAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _GoldAction(this.label, this.icon, this.onTap);
  @override
  Widget build(BuildContext context) => SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: onTap, icon: Icon(icon), label: Text(label), style: FilledButton.styleFrom(backgroundColor: gold, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 13))));
}

class _Result extends StatelessWidget {
  final String title, result, detail, source;
  const _Result({required this.title, required this.result, required this.detail, required this.source});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFF2A2116), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFF98733C))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(color: goldLight, fontSize: 12, fontWeight: FontWeight.w700)),
      const SizedBox(height: 5),
      Text(result, style: const TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w900)),
      const SizedBox(height: 7),
      Text(detail, style: const TextStyle(color: Color(0xFFE1D2BD), fontSize: 11.5, height: 1.6)),
      if (source.trim().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text('المصدر الذي أدخله المستخدم: ' + source.trim(), style: const TextStyle(color: goldLight, fontSize: 11.5, height: 1.5))),
      const SizedBox(height: 8),
      const Text('إدخال مصدر لا يعني أن الأداة تحققت من نفاذه أو انطباقه.', style: TextStyle(color: Color(0xFFB7AFA2), fontSize: 10.5, height: 1.5)),
    ]),
  );
}

class _Notice extends StatelessWidget {
  final IconData icon;
  final String title, body;
  const _Notice({required this.icon, required this.title, required this.body});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 12), padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: const Color(0xFF211B14), borderRadius: BorderRadius.circular(17), border: Border.all(color: const Color(0xFF5C472C))),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: gold, size: 23), const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(color: goldLight, fontWeight: FontWeight.w800, fontSize: 12.5)),
        const SizedBox(height: 5),
        Text(body, style: const TextStyle(color: Color(0xFFC7BDAF), fontSize: 11.5, height: 1.65)),
      ])),
    ]),
  );
}

class _Pill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Pill(this.label, this.selected, this.onTap);
  @override
  Widget build(BuildContext context) => ChoiceChip(
    label: Text(label), selected: selected, onSelected: (_) => onTap(),
    selectedColor: gold, backgroundColor: panel,
    labelStyle: TextStyle(color: selected ? Colors.black : goldLight, fontSize: 11.5, fontWeight: FontWeight.w700),
    side: BorderSide(color: selected ? gold : line), checkmarkColor: Colors.black,
  );
}

class _Tag extends StatelessWidget {
  final String text;
  const _Tag(this.text);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(color: gold.withOpacity(.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: gold.withOpacity(.28))),
    child: Text(text, style: const TextStyle(color: goldLight, fontSize: 9.5, fontWeight: FontWeight.w800)),
  );
}

class _Stat extends StatelessWidget {
  final String label, value;
  final IconData icon;
  const _Stat(this.label, this.value, this.icon);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(15), border: Border.all(color: line)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: gold, size: 20), const SizedBox(height: 8),
      Text(value, style: const TextStyle(color: goldLight, fontSize: 20, fontWeight: FontWeight.w900)),
      const SizedBox(height: 3), Text(label, style: const TextStyle(color: Color(0xFFB7AFA2), fontSize: 10.5)),
    ]),
  );
}

String _date(DateTime d) => d.day.toString().padLeft(2, '0') + '/' + d.month.toString().padLeft(2, '0') + '/' + d.year.toString();
String _money(double value) {
  final fixed = value.toStringAsFixed(2);
  return fixed.endsWith('.00') ? fixed.substring(0, fixed.length - 3) : fixed;
}
