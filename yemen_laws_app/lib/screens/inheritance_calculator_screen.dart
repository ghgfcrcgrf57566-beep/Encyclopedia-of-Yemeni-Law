import 'package:flutter/material.dart';

class InheritanceCalculatorScreen extends StatefulWidget {
  const InheritanceCalculatorScreen({super.key});

  @override
  State<InheritanceCalculatorScreen> createState() => _InheritanceCalculatorScreenState();
}

class _InheritanceCalculatorScreenState extends State<InheritanceCalculatorScreen> {
  final _amountController = TextEditingController();
  String _deceasedGender = 'male';
  int _wives = 0;
  int _husband = 0;
  int _father = 0;
  int _mother = 0;
  int _grandfather = 0;
  int _grandmother = 0;
  int _sons = 0;
  int _daughters = 0;
  int _sonsOfSon = 0;
  int _daughtersOfSon = 0;
  int _fullBrothers = 0;
  int _fullSisters = 0;
  int _paternalBrothers = 0;
  int _paternalSisters = 0;
  int _maternalSiblings = 0;
  int _fullUncles = 0;
  int _paternalUncles = 0;
  int _fullMaleCousins = 0;
  int _paternalMaleCousins = 0;
  bool _showResult = false;
  InheritanceResult? _result;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _calculate() {
    final estate = double.tryParse(_amountController.text.trim().replaceAll(',', ''));
    if (estate == null || estate <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أدخل قيمة صحيحة للتركة.')));
      return;
    }
    final input = InheritanceInput(
      estate: estate,
      deceasedMale: _deceasedGender == 'male',
      wives: _deceasedGender == 'male' ? _wives : 0,
      husband: _deceasedGender == 'female' && _husband > 0,
      father: _father > 0,
      mother: _mother > 0,
      grandfather: _grandfather > 0,
      grandmother: _grandmother > 0,
      sons: _sons,
      daughters: _daughters,
      sonsOfSon: _sonsOfSon,
      daughtersOfSon: _daughtersOfSon,
      fullBrothers: _fullBrothers,
      fullSisters: _fullSisters,
      paternalBrothers: _paternalBrothers,
      paternalSisters: _paternalSisters,
      maternalSiblings: _maternalSiblings,
      fullUncles: _fullUncles,
      paternalUncles: _paternalUncles,
      fullMaleCousins: _fullMaleCousins,
      paternalMaleCousins: _paternalMaleCousins,
    );
    setState(() {
      _result = InheritanceEngine.calculate(input);
      _showResult = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2A2A2A),
        centerTitle: true,
        title: const Text('حاسبة المواريث والتركات', style: TextStyle(color: Color(0xFFD4AF37), fontWeight: FontWeight.bold)),
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _accordion('بيانات التركة والمتوفى', Icons.account_balance_wallet_rounded, [
            TextField(controller: _amountController, keyboardType: const TextInputType.numberWithOptions(decimal: true), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold), decoration: _inputDecoration('قيمة التركة بعد التجهيز والدين والوصية', Icons.account_balance_wallet_outlined)),
            const SizedBox(height: 14),
            Row(children: [Expanded(child: _gender('ذكر', 'male', Icons.male)), const SizedBox(width: 10), Expanded(child: _gender('أنثى', 'female', Icons.female))]),
          ]),
          _accordion('الأصول والزوج / الزوجات', Icons.family_restroom_rounded, [
            if (_deceasedGender == 'male') _counter('عدد الزوجات', _wives, (v) => setState(() => _wives = v.clamp(0, 4).toInt()))
            else _counter('الزوج', _husband, (v) => setState(() => _husband = v.clamp(0, 1).toInt())),
            _counter('الأب', _father, (v) => setState(() => _father = v.clamp(0, 1).toInt())),
            _counter('الأم', _mother, (v) => setState(() => _mother = v.clamp(0, 1).toInt())),
            _counter('الجد الصحيح', _grandfather, (v) => setState(() => _grandfather = v.clamp(0, 1).toInt())),
            _counter('الجدة', _grandmother, (v) => setState(() => _grandmother = v.clamp(0, 1).toInt())),
          ]),
          _accordion('الفروع والإخوة', Icons.groups_rounded, [
            _counter('الأبناء الذكور', _sons, (v) => setState(() => _sons = v.clamp(0, 50).toInt())),
            _counter('البنات', _daughters, (v) => setState(() => _daughters = v.clamp(0, 50).toInt())),
            _counter('أبناء الابن', _sonsOfSon, (v) => setState(() => _sonsOfSon = v.clamp(0, 50).toInt())),
            _counter('بنات الابن', _daughtersOfSon, (v) => setState(() => _daughtersOfSon = v.clamp(0, 50).toInt())),
            _counter('الإخوة الأشقاء', _fullBrothers, (v) => setState(() => _fullBrothers = v.clamp(0, 50).toInt())),
            _counter('الأخوات الشقيقات', _fullSisters, (v) => setState(() => _fullSisters = v.clamp(0, 50).toInt())),
            _counter('الإخوة لأب', _paternalBrothers, (v) => setState(() => _paternalBrothers = v.clamp(0, 50).toInt())),
            _counter('الأخوات لأب', _paternalSisters, (v) => setState(() => _paternalSisters = v.clamp(0, 50).toInt())),
            _counter('الإخوة والأخوات لأم', _maternalSiblings, (v) => setState(() => _maternalSiblings = v.clamp(0, 50).toInt())),
          ]),
          _accordion('الأعمام والعصبات', Icons.account_tree_rounded, [
            _counter('العم الشقيق', _fullUncles, (v) => setState(() => _fullUncles = v.clamp(0, 50).toInt())),
            _counter('العم لأب', _paternalUncles, (v) => setState(() => _paternalUncles = v.clamp(0, 50).toInt())),
            _counter('ابن العم الشقيق', _fullMaleCousins, (v) => setState(() => _fullMaleCousins = v.clamp(0, 50).toInt())),
            _counter('ابن العم لأب', _paternalMaleCousins, (v) => setState(() => _paternalMaleCousins = v.clamp(0, 50).toInt())),
          ]),
          const SizedBox(height: 8),
          SizedBox(height: 52, child: ElevatedButton.icon(onPressed: _calculate, icon: const Icon(Icons.calculate_rounded, color: Colors.black), label: const Text('احسب الأنصبة الشرعية', style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold)), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD4AF37), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))))),
          const SizedBox(height: 20),
          if (_showResult && _result != null) _resultCard(_result!),
        ]),
      ),
      ),
    );
  }

  Widget _accordion(String title, IconData icon, List<Widget> children) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    decoration: BoxDecoration(color: const Color(0xFF252525), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
    child: Theme(data: Theme.of(context).copyWith(dividerColor: Colors.transparent), child: ExpansionTile(initiallyExpanded: false, tilePadding: const EdgeInsets.symmetric(horizontal: 14), childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12), leading: Icon(icon, color: const Color(0xFFD4AF37)), title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), children: children)),
  );

  InputDecoration _inputDecoration(String hint, IconData icon) => InputDecoration(
    hintText: hint, hintStyle: const TextStyle(color: Colors.white38, fontSize: 13), filled: true, fillColor: const Color(0xFF2A2A2A),
    prefixIcon: Icon(icon, color: const Color(0xFFD4AF37)), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white10)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFD4AF37))),
  );

  Widget _header(String text) => Padding(padding: const EdgeInsets.only(bottom: 7), child: Text(text, style: const TextStyle(color: Color(0xFFD4AF37), fontSize: 15, fontWeight: FontWeight.bold)));

  Widget _gender(String label, String value, IconData icon) {
    final selected = _deceasedGender == value;
    return InkWell(onTap: () => setState(() => _deceasedGender = value), child: Container(
      padding: const EdgeInsets.symmetric(vertical: 13), decoration: BoxDecoration(color: selected ? const Color(0xFFD4AF37).withOpacity(.18) : const Color(0xFF2A2A2A), borderRadius: BorderRadius.circular(10), border: Border.all(color: selected ? const Color(0xFFD4AF37) : Colors.white10)),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, color: selected ? const Color(0xFFD4AF37) : Colors.white54), const SizedBox(width: 7), Text(label, style: TextStyle(color: selected ? Colors.white : Colors.white54, fontWeight: FontWeight.bold))]),
    ));
  }

  Widget _counter(String label, int count, ValueChanged<int> onChanged) => Container(
    margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: const Color(0xFF2A2A2A), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white10)),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: const TextStyle(color: Colors.white, fontSize: 14)), Row(children: [IconButton(onPressed: count > 0 ? () => onChanged(count - 1) : null, icon: const Icon(Icons.remove_circle_outline, color: Color(0xFFD4AF37))), Text('$count', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), IconButton(onPressed: () => onChanged(count + 1), icon: const Icon(Icons.add_circle_outline, color: Color(0xFFD4AF37)))])]),
  );


  Widget _buildShareRow(HeirShare s) {
    final header = Row(children: [
      Expanded(child: Text(s.heir, style: TextStyle(color: s.amount == 0 ? Colors.white54 : Colors.white, fontWeight: FontWeight.w600))),
      Text(s.fraction, style: TextStyle(color: s.amount == 0 ? Colors.redAccent : const Color(0xFFD4AF37), fontSize: 12, fontWeight: FontWeight.bold)),
      const SizedBox(width: 10),
      Text(s.amount == 0 ? 'محجوب' : '${s.amount.toStringAsFixed(2)} ريال', style: TextStyle(color: s.amount == 0 ? Colors.redAccent : Colors.white, fontWeight: FontWeight.bold)),
    ]);
    if (s.details.isEmpty) {
      return Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: header);
    }
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(10)),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 8),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          title: header,
          trailing: const Icon(Icons.expand_more, color: Color(0xFFD4AF37)),
          children: s.details.map((detail) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              const Icon(Icons.person_outline, size: 16, color: Color(0xFFD4AF37)),
              const SizedBox(width: 7),
              Expanded(child: Text(detail, style: const TextStyle(color: Colors.white70, fontSize: 13))),
            ]),
          )).toList(),
        ),
      ),
    );
  }

  Widget _switch(String label, bool value, ValueChanged<bool> onChanged) => Container(
    margin: const EdgeInsets.only(bottom: 6), decoration: BoxDecoration(color: const Color(0xFF2A2A2A), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white10)),
    child: SwitchListTile(value: value, onChanged: onChanged, activeColor: const Color(0xFFD4AF37), title: Text(label, style: const TextStyle(color: Colors.white, fontSize: 14)), contentPadding: const EdgeInsets.symmetric(horizontal: 8),
    ));

  Widget _resultCard(InheritanceResult result) => Container(
    padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: const Color(0xFF2A2A2A), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFD4AF37), width: 1.3)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: const [Icon(Icons.account_balance_rounded, color: Color(0xFFD4AF37)), SizedBox(width: 8), Expanded(child: Text('نتيجة قسمة التركة', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)))]),
      const Divider(color: Colors.white24, height: 22),
      if (result.steps.isNotEmpty) ...[
        Text(result.status, style: const TextStyle(color: Color(0xFFD4AF37), fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
      ],
      ...result.shares.map(_buildShareRow),
      const SizedBox(height: 8),
      Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)), child: Text(result.note, style: const TextStyle(color: Colors.white60, fontSize: 11, height: 1.5))),
    ]),
  );
}

class InheritanceInput {
  final double estate;
  final bool deceasedMale, husband, father, mother, grandfather, grandmother;
  final int wives, sons, daughters, sonsOfSon, daughtersOfSon, fullBrothers, fullSisters, paternalBrothers, paternalSisters, maternalSiblings, fullUncles, paternalUncles, fullMaleCousins, paternalMaleCousins;
  const InheritanceInput({required this.estate, required this.deceasedMale, required this.wives, required this.husband, required this.father, required this.mother, required this.grandfather, required this.grandmother, required this.sons, required this.daughters, required this.sonsOfSon, required this.daughtersOfSon, required this.fullBrothers, required this.fullSisters, required this.paternalBrothers, required this.paternalSisters, required this.maternalSiblings, required this.fullUncles, required this.paternalUncles, required this.fullMaleCousins, required this.paternalMaleCousins});
}

class HeirShare {
  final String heir, fraction;
  final double amount;
  final List<String> details;
  const HeirShare(this.heir, this.fraction, this.amount, {this.details = const []});
}

class InheritanceResult {
  final List<HeirShare> shares;
  final String status, note;
  final List<String> steps;
  const InheritanceResult({required this.shares, required this.status, required this.note, required this.steps});
}

class _Bucket {
  double share = 0;
  String fraction = '';
  String reason = '';
  _Bucket(this.share, this.fraction, this.reason);
}

class InheritanceEngine {
  static InheritanceResult calculate(InheritanceInput i) {
    final shares = <String, _Bucket>{};
    final notes = <String>[];
    final hasDesc = i.sons + i.daughters + i.sonsOfSon + i.daughtersOfSon > 0;
    final hasMaleDesc = i.sons + i.sonsOfSon > 0;
    final siblingCount = i.fullBrothers + i.fullSisters + i.paternalBrothers + i.paternalSisters + i.maternalSiblings;

    void add(String key, double value, String fraction, String reason) {
      if (value > 0) shares[key] = _Bucket(value, fraction, reason);
    }

    // موانع وحجب الفروع المتقدمة وفق مواد 323 و324 من قانون الأحوال الشخصية اليمني.
    if (i.deceasedMale) {
      if (i.wives > 0) add('الزوجات (${i.wives})', hasDesc ? 1 / 8 : 1 / 4, hasDesc ? '1/8' : '1/4', 'فرض الزوجات');
    } else if (i.husband) {
      add('الزوج', hasDesc ? 1 / 4 : 1 / 2, hasDesc ? '1/4' : '1/2', 'فرض الزوج');
    }

    if (i.mother) {
      final special = !hasDesc && siblingCount == 0 && (i.father || i.grandfather) && (i.husband || i.wives > 0);
      final value = special ? 1 / 3 : ((hasDesc || siblingCount >= 2) ? 1 / 6 : 1 / 3);
      add('الأم', value, special ? '1/3 من الباقي' : (value == 1 / 6 ? '1/6' : '1/3'), 'فرض الأم');
    }

    if (i.father) {
      if (hasDesc) add('الأب', 1 / 6, '1/6', 'فرض الأب مع الفرع الوارث');
      // مع بنت/بنات فقط يأخذ الأب السدس والباقي تعصيباً، يعالج الباقي أدناه.
    } else if (i.grandfather && !i.father) {
      if (hasDesc) add('الجد الصحيح', 1 / 6, '1/6', 'فرض الجد');
    }

    if (i.grandmother && i.mother) notes.add('الجدة محجوبة بوجود الأم.');
    if (i.grandmother && !i.mother) add('الجدة', 1 / 6, '1/6', 'فرض الجدة');

    // الإخوة لأم: يحجبون بالفرع الوارث وبالأب/الجد.
    if (i.maternalSiblings > 0 && !hasDesc && !i.father && !i.grandfather) {
      add('الإخوة والأخوات لأم (${i.maternalSiblings})', i.maternalSiblings == 1 ? 1 / 6 : 1 / 3, i.maternalSiblings == 1 ? '1/6' : '1/3', 'فرض الإخوة لأم');
    } else if (i.maternalSiblings > 0) {
      notes.add('الإخوة والأخوات لأم محجوبون بالفرع الوارث أو الأصل الذكر.');
    }

    // البنات مع الأبناء: عصبة للذكر مثل حظ الأنثيين.
    if (i.sons > 0) {
      add('الأبناء والبنات (${i.sons + i.daughters})', 0, 'عصبة', 'للذكر مثل حظ الأنثيين');
    } else if (i.daughters == 1) {
      add('البنت', 1 / 2, '1/2', 'فرض البنت');
    } else if (i.daughters > 1) {
      add('البنات (${i.daughters})', 2 / 3, '2/3', 'فرض البنات');
    }

    // بنت الابن: تسقط بالابن، وتكمل الثلثين مع بنت واحدة عند عدم وجود معصب.
    if (i.sons == 0 && i.daughtersOfSon > 0) {
      if (i.daughters >= 2 && i.sonsOfSon == 0) {
        notes.add('بنات الابن محجوبات بالبنتين فأكثر لعدم وجود معصب.');
      } else if (i.sonsOfSon > 0) {
        // يعاملن مع أبناء الابن كعصبة، ويضاف الباقي لاحقاً.
      } else if (i.daughters == 1) {
        add('بنات الابن (${i.daughtersOfSon})', 1 / 6, '1/6', 'تكملة الثلثين مع بنت واحدة');
      } else {
        add('بنات الابن (${i.daughtersOfSon})', 2 / 3, '2/3', 'فرض بنات الابن');
      }
    }

    // الأخوات الشقيقات/لأب: يحجبهن الفرع الذكر والأب، وتصبح الأخوات الشقيقات عصبة مع البنات عند عدم وجود أخ شقيق.
    final fullBlocked = hasMaleDesc || i.father || i.grandfather;
    if (i.fullBrothers > 0 && !fullBlocked) {
      // يأخذون الباقي كعصبة بعد الفروض.
    } else if (i.fullSisters > 0 && !fullBlocked && i.daughters == 0 && i.daughtersOfSon == 0) {
      if (i.fullSisters == 1) add('الأخت الشقيقة', 1 / 2, '1/2', 'فرض الأخت الشقيقة');
      else add('الأخوات الشقيقات (${i.fullSisters})', 2 / 3, '2/3', 'فرض الأخوات الشقيقات');
    }

    final paternalBlocked = fullBlocked || i.fullBrothers > 0 || i.fullSisters >= 2;
    if (i.paternalSisters > 0 && !paternalBlocked && i.paternalBrothers == 0 && i.daughters == 0 && i.daughtersOfSon == 0) {
      if (i.paternalSisters == 1) add('الأخت لأب', 1 / 2, '1/2', 'فرض الأخت لأب');
      else add('الأخوات لأب (${i.paternalSisters})', 2 / 3, '2/3', 'فرض الأخوات لأب');
    }

    // الأم الخاصة في مسألتي زوج/أبوين أو زوجة/أبوين: ثلث الباقي لا ثلث جميع التركة.
    if (i.mother && !hasDesc && siblingCount == 0 && (i.father || i.grandfather) && (i.husband || i.wives > 0)) {
      final spouse = shares.values.where((b) => b.reason == 'فرض الزوج' || b.reason == 'فرض الزوجات').fold(0.0, (a, b) => a + b.share);
      shares['الأم'] = _Bucket((1 - spouse) / 3, '1/3 من الباقي', 'ثلث الباقي في مسألة الأبوين');
    }

    var fixed = shares.values.fold(0.0, (a, b) => a + b.share);
    var remainder = 1 - fixed;
    var status = 'قسمة أصلية';

    if (fixed > 1.0000001) {
      // العول: تخفيض جميع أصحاب الفروض بنسبة مجموع فروضهم.
      final factor = 1 / fixed;
      for (final b in shares.values) b.share *= factor;
      remainder = 0;
      status = 'المسألة عالت: خُفّضت فروض أصحابها بنسبة العول.';
      notes.add('تم تطبيق العول لأن مجموع الفروض تجاوز أصل التركة.');
    } else if (remainder > 0) {
      final residueGroup = _residuary(i, hasDesc, hasMaleDesc, shares, remainder);
      if (residueGroup != null) {
        final weights = residueGroup.weights;
        final totalWeight = weights.values.fold(0, (a, b) => a + b);
        for (final entry in weights.entries) {
          final amount = remainder * entry.value / totalWeight;
          final old = shares[entry.key];
          shares[entry.key] = _Bucket((old?.share ?? 0) + amount, 'عصبة', residueGroup.reason);
        }
        remainder = 0;
        notes.add(residueGroup.reason);
      } else {
        // الرد في القانون اليمني يكون على أصحاب الفروض غير الزوجين عند عدم وجود عاصب.
        final eligible = shares.entries.where((e) => e.key != 'الزوج' && !e.key.startsWith('الزوجات')).toList();
        final eligibleTotal = eligible.fold(0.0, (a, e) => a + e.value.share);
        if (eligibleTotal > 0) {
          for (final e in eligible) {
            e.value.share += remainder * e.value.share / eligibleTotal;
          }
          status = 'رَدّ: أُعيد الباقي إلى أصحاب الفروض غير الزوجين بنسبة فروضهم.';
          notes.add('تم تطبيق الرد وفق المادة 325.');
          remainder = 0;
        }
      }
    }

    // عرض الحجب بعد الحساب فقط: لا نخفي أي وارث أثناء الإدخال.
    final output = <HeirShare>[];

    List<String> individualDetails(String name, double totalAmount) {
      String money(double value) => '${value.toStringAsFixed(2)} ريال';
      if (i.deceasedMale && name.startsWith('الزوجات (') && i.wives > 0) {
        final each = totalAmount / i.wives;
        return List.generate(i.wives, (index) => 'الزوجة ${index + 1}: ${money(each)}');
      }
      if (name.startsWith('الأبناء والبنات (') && (i.sons > 0 || i.daughters > 0)) {
        final totalShares = i.sons * 2 + i.daughters;
        final unit = totalShares == 0 ? 0 : totalAmount / totalShares;
        return [
          ...List.generate(i.sons, (index) => 'الابن ${index + 1}: ${money(unit * 2)} — سهمان'),
          ...List.generate(i.daughters, (index) => 'البنت ${index + 1}: ${money(unit)} — سهم واحد'),
        ];
      }
      if (name.startsWith('أبناء وبنات الابن (') && (i.sonsOfSon > 0 || i.daughtersOfSon > 0)) {
        final totalShares = i.sonsOfSon * 2 + i.daughtersOfSon;
        final unit = totalShares == 0 ? 0 : totalAmount / totalShares;
        return [
          ...List.generate(i.sonsOfSon, (index) => 'ابن الابن ${index + 1}: ${money(unit * 2)} — سهمان'),
          ...List.generate(i.daughtersOfSon, (index) => 'بنت الابن ${index + 1}: ${money(unit)} — سهم واحد'),
        ];
      }
      if (name.startsWith('الإخوة والأخوات الأشقاء (') && (i.fullBrothers > 0 || i.fullSisters > 0)) {
        final totalShares = i.fullBrothers * 2 + i.fullSisters;
        final unit = totalShares == 0 ? 0 : totalAmount / totalShares;
        return [
          ...List.generate(i.fullBrothers, (index) => 'الأخ الشقيق ${index + 1}: ${money(unit * 2)} — سهمان'),
          ...List.generate(i.fullSisters, (index) => 'الأخت الشقيقة ${index + 1}: ${money(unit)} — سهم واحد'),
        ];
      }
      if (name.startsWith('الإخوة والأخوات لأب (') && (i.paternalBrothers > 0 || i.paternalSisters > 0)) {
        final totalShares = i.paternalBrothers * 2 + i.paternalSisters;
        final unit = totalShares == 0 ? 0 : totalAmount / totalShares;
        return [
          ...List.generate(i.paternalBrothers, (index) => 'الأخ لأب ${index + 1}: ${money(unit * 2)} — سهمان'),
          ...List.generate(i.paternalSisters, (index) => 'الأخت لأب ${index + 1}: ${money(unit)} — سهم واحد'),
        ];
      }
      if (name.startsWith('الإخوة والأخوات لأم (') && i.maternalSiblings > 0) {
        final each = totalAmount / i.maternalSiblings;
        return List.generate(i.maternalSiblings, (index) => 'الوارث لأم ${index + 1}: ${money(each)} — سهم واحد');
      }
      if (name.startsWith('الأخوات الشقيقات (') && i.fullSisters > 0) {
        final each = totalAmount / i.fullSisters;
        return List.generate(i.fullSisters, (index) => 'الأخت الشقيقة ${index + 1}: ${money(each)}');
      }
      if (name.startsWith('الأخوات لأب (') && i.paternalSisters > 0) {
        final each = totalAmount / i.paternalSisters;
        return List.generate(i.paternalSisters, (index) => 'الأخت لأب ${index + 1}: ${money(each)}');
      }
      return const [];
    }

    shares.forEach((name, b) {
      if (b.share > 0.0000001) {
        final amount = i.estate * b.share;
        output.add(HeirShare(name, b.fraction, amount, details: individualDetails(name, amount)));
      }
    });
    final blocked = <HeirShare>[];
    void blockedIf(bool condition, String name, String reason) {
      if (condition) blocked.add(HeirShare('$name — $reason', 'محجوب', 0));
    }
    if (i.sons > 0) {
      blockedIf(i.fullUncles > 0, 'العم الشقيق', 'محجوب بالابن الذكر.');
      blockedIf(i.paternalUncles > 0, 'العم لأب', 'محجوب بالابن الذكر.');
      blockedIf(i.fullMaleCousins > 0, 'ابن العم الشقيق', 'محجوب بالابن الذكر.');
      blockedIf(i.paternalMaleCousins > 0, 'ابن العم لأب', 'محجوب بالابن الذكر.');
      blockedIf(i.fullBrothers > 0, 'الإخوة الأشقاء', 'محجوبون بالابن الذكر.');
      blockedIf(i.paternalBrothers > 0, 'الإخوة لأب', 'محجوبون بالابن الذكر.');
    } else {
      blockedIf(i.fullUncles > 0 && (i.father || i.grandfather), 'العم الشقيق', 'محجوب بالأب أو الجد الصحيح.');
      blockedIf(i.paternalUncles > 0 && (i.father || i.grandfather || i.fullUncles > 0), 'العم لأب', 'محجوب بالأب أو الجد الصحيح أو العم الشقيق.');
      blockedIf(i.fullMaleCousins > 0 && (i.father || i.grandfather || i.fullUncles > 0), 'ابن العم الشقيق', 'محجوب بمن هو أقرب منه من العصبات.');
      blockedIf(i.paternalMaleCousins > 0 && (i.father || i.grandfather || i.fullUncles > 0 || i.fullMaleCousins > 0 || i.paternalUncles > 0), 'ابن العم لأب', 'محجوب بمن هو أقرب منه من العصبات.');
    }
    if (i.father || i.grandfather) {
      blockedIf(i.fullBrothers > 0, 'الإخوة الأشقاء', 'محجوبون بالأب أو الجد الصحيح.');
      blockedIf(i.paternalBrothers > 0, 'الإخوة لأب', 'محجوبون بالأب أو الجد الصحيح.');
    }
    if (i.mother) blockedIf(i.grandmother, 'الجدة', 'محجوبة بالأم.');
    if (i.maternalSiblings > 0 && (hasDesc || i.father || i.grandfather)) {
      blockedIf(true, 'الإخوة والأخوات لأم', 'محجوبون بالفرع الوارث أو الأصل الذكر.');
    }
    output.addAll(blocked);
    output.sort((a, b) {
      if (a.amount == 0 && b.amount != 0) return 1;
      if (a.amount != 0 && b.amount == 0) return -1;
      return b.amount.compareTo(a.amount);
    });

    if (remainder > 0.000001) notes.add('بقي جزء من التركة دون وارث مُدخل في الحاسبة؛ أضف بقية الورثة إن وجدوا.');
    final note = notes.isEmpty
        ? 'الحساب مبني على الورثة الذين أدخلتهم. يلزم التحقق من جميع الورثة والموانع والوصايا والديون قبل اعتماد القسمة.'
        : notes.join('\n');

    return InheritanceResult(shares: output, status: status, note: note, steps: notes);
  }

  static _Residue? _residuary(InheritanceInput i, bool hasDesc, bool hasMaleDesc, Map<String, _Bucket> shares, double remainder) {
    if (i.sons > 0) {
      final map = <String, int>{'الأبناء والبنات (${i.sons + i.daughters})': i.sons * 2 + i.daughters};
      return _Residue(map, 'الباقي للأبناء والبنات تعصيباً، للذكر مثل حظ الأنثيين.');
    }
    if (i.sonsOfSon > 0) {
      final map = <String, int>{'أبناء وبنات الابن (${i.sonsOfSon + i.daughtersOfSon})': i.sonsOfSon * 2 + i.daughtersOfSon};
      return _Residue(map, 'الباقي لأبناء الابن وبناته تعصيباً، للذكر مثل حظ الأنثيين.');
    }
    if (i.father) {
      // الأب يأخذ الباقي بعد فرضه عند وجود بنات/بنات ابن، أو كل المال عند انفراده.
      final old = shares['الأب'];
      if (old != null) return _Residue({'الأب': 1}, 'الباقي للأب تعصيباً بعد الفرض.');
      return _Residue({'الأب': 1}, 'الأب عاصب بنفسه.');
    }
    if (i.grandfather && !i.father) {
      final old = shares['الجد الصحيح'];
      if (old != null || !hasDesc) return _Residue({'الجد الصحيح': 1}, 'الباقي للجد الصحيح تعصيباً.');
    }
    if (i.fullBrothers > 0 && !hasMaleDesc && !i.father && !i.grandfather) {
      final map = <String, int>{'الإخوة والأخوات الأشقاء (${i.fullBrothers + i.fullSisters})': i.fullBrothers * 2 + i.fullSisters};
      return _Residue(map, 'الباقي للإخوة والأخوات الأشقاء تعصيباً، للذكر مثل حظ الأنثيين.');
    }
    if (i.paternalBrothers > 0 && !hasMaleDesc && !i.father && !i.grandfather && i.fullBrothers == 0) {
      final map = <String, int>{'الإخوة والأخوات لأب (${i.paternalBrothers + i.paternalSisters})': i.paternalBrothers * 2 + i.paternalSisters};
      return _Residue(map, 'الباقي للإخوة والأخوات لأب تعصيباً.');
    }
    if (i.fullSisters > 0 && !hasMaleDesc && !i.father && !i.grandfather && (i.daughters > 0 || i.daughtersOfSon > 0)) {
      return _Residue({'الأخوات الشقيقات (${i.fullSisters})': i.fullSisters}, 'الأخوات الشقيقات عصبة مع الغير مع البنات.');
    }
    if (i.paternalSisters > 0 && !hasMaleDesc && !i.father && !i.grandfather && i.fullSisters == 0 && (i.daughters > 0 || i.daughtersOfSon > 0)) {
      return _Residue({'الأخوات لأب (${i.paternalSisters})': i.paternalSisters}, 'الأخوات لأب عصبة مع الغير مع البنات عند تحقق شروط الحجب.');
    }
    return null;
  }
}

class _Residue {
  final Map<String, int> weights;
  final String reason;
  const _Residue(this.weights, this.reason);
}
