import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../core/theme.dart';
import '../../services/chat_history_db.dart';
import '../../services/legal_ai_service.dart';
import '../article/article_detail_screen.dart';

class LegalAiScreen extends StatefulWidget {
  const LegalAiScreen({super.key});
  @override
  State<LegalAiScreen> createState() => _LegalAiScreenState();
}

enum _AnswerMode { direct, explain }

class _LegalAiScreenState extends State<LegalAiScreen> {
  final c = TextEditingController();
  final scroll = ScrollController();
  final service = LegalAiService.instance;
  final historyDb = ChatHistoryDb.instance;
  final speech = stt.SpeechToText();
  final messages = <_Msg>[];

  bool loading = false;
  bool listening = false;
  bool online = true;
  bool showDisclaimer = true;
  String? conversationId;
  int requestToken = 0;
  _AnswerMode answerMode = _AnswerMode.explain;
  String selectedLaw = 'الكل';

  static const lawFilters = <String>[
    'الكل',
    'القانون المدني',
    'الأحوال الشخصية',
    'الجرائم والعقوبات',
    'الإجراءات الجزائية',
    'قانون العمل',
  ];

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    _checkConnection();
    Connectivity().onConnectivityChanged.listen((results) {
      if (!mounted) return;
      setState(() => online = results.any((r) => r != ConnectivityResult.none));
    });
  }

  @override
  void dispose() {
    speech.stop();
    c.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> _loadPreferences() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      showDisclaimer = !(p.getBool('legal_ai_disclaimer_closed') ?? false);
      answerMode = (p.getString('legal_ai_answer_mode') == 'direct')
          ? _AnswerMode.direct
          : _AnswerMode.explain;
    });
  }

  Future<void> _checkConnection() async {
    final result = await Connectivity().checkConnectivity();
    if (!mounted) return;
    setState(() => online = result.any((r) => r != ConnectivityResult.none));
  }

  Future<void> ask() async {
    if (loading) return;
    final q = c.text.trim();
    if (q.isEmpty) return;
    await _sendQuestion(q, addUserMessage: true);
  }

  Future<void> _retry(String q) async {
    if (loading || q.trim().isEmpty) return;
    await _sendQuestion(q.trim(), addUserMessage: false);
  }

  String _questionForService(String q) {
    final mode = answerMode == _AnswerMode.direct
        ? 'أجب في وضع الإجابة المباشرة: اعرض النصوص القانونية المحلية ذات الصلة دون شرح أو تبسيط أو استنتاج زائد.'
        : 'أجب في وضع الشرح والتبسيط: اعرض النصوص القانونية المحلية ذات الصلة ثم اشرحها بلغة واضحة، مع التمييز بين النص والتحليل.';
    final law = selectedLaw == 'الكل'
        ? ''
        : '\nنطاق البحث الإلزامي: ابحث في $selectedLaw فقط، ولا تستخدم مواد من قانون آخر إلا إذا ذكرت صراحة أن القانون المطلوب غير موجود في قاعدة البيانات.';
    return '$mode$law\n\nالسؤال القانوني: $q';
  }

  Future<void> _sendQuestion(String q, {required bool addUserMessage}) async {
    final token = ++requestToken;
    final previousMessages = messages
        .where((m) => m.role == 'user' || m.role == 'assistant')
        .toList();
    final recentMessages = previousMessages.length > 12
        ? previousMessages.skip(previousMessages.length - 12)
        : previousMessages;
    final history = recentMessages
        .map((m) => {'role': m.role, 'content': m.text})
        .toList();

    setState(() {
      if (addUserMessage) {
        messages.add(_Msg.user(q));
        c.clear();
      } else {
        final index = messages.lastIndexWhere((m) => m.role == 'error');
        if (index != -1) messages.removeAt(index);
      }
      loading = true;
    });
    _end();

    try {
      final r = await service.ask(
        question: _questionForService(q),
        conversationId: conversationId,
        history: history,
      );
      if (!mounted || token != requestToken) return;
      conversationId ??= r.conversationId;
      setState(() => messages.add(_Msg.answer(r)));
    } catch (e) {
      if (!mounted || token != requestToken) return;
      setState(() => messages.add(_Msg.error(e.toString(), q)));
    } finally {
      if (mounted && token == requestToken) {
        setState(() => loading = false);
        _end();
      }
    }
  }

  void stopGeneration() {
    if (!loading) return;
    requestToken++;
    setState(() => loading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم إيقاف عرض الإجابة.')),
    );
  }

  Future<void> _startVoice() async {
    if (loading) return;
    if (listening) {
      await speech.stop();
      if (mounted) setState(() => listening = false);
      return;
    }

    final available = await speech.initialize(
      onStatus: (status) {
        if (!mounted) return;
        if (status == 'done' || status == 'notListening') {
          setState(() => listening = false);
        }
      },
      onError: (_) {
        if (mounted) setState(() => listening = false);
      },
    );

    if (!available) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الإملاء الصوتي غير متاح على هذا الجهاز.')),
      );
      return;
    }

    setState(() => listening = true);
    await speech.listen(
      onResult: (result) {
        if (!mounted) return;
        setState(() => c.text = result.recognizedWords);
        c.selection = TextSelection.collapsed(offset: c.text.length);
      },
    );
  }

  void clearChat() {
    if (loading) return;
    setState(() {
      messages.clear();
      conversationId = null;
      c.clear();
    });
  }

  Future<void> _closeDisclaimer() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('legal_ai_disclaimer_closed', true);
    if (mounted) setState(() => showDisclaimer = false);
  }

  Future<void> _setMode(_AnswerMode mode) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('legal_ai_answer_mode', mode == _AnswerMode.direct ? 'direct' : 'explain');
    if (mounted) setState(() => answerMode = mode);
  }

  Future<void> _showSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 22),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('إعدادات الإجابة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: context.textPrimary)),
            const SizedBox(height: 10),
            RadioListTile<_AnswerMode>(
              value: _AnswerMode.direct,
              groupValue: answerMode,
              title: const Text('الإجابة المباشرة'),
              subtitle: const Text('النصوص القانونية دون تفسير.'),
              onChanged: (v) { if (v != null) { _setMode(v); Navigator.pop(sheet); } },
            ),
            RadioListTile<_AnswerMode>(
              value: _AnswerMode.explain,
              groupValue: answerMode,
              title: const Text('الشرح والتبسيط'),
              subtitle: const Text('النص القانوني مع شرح مبسط وتحليل.'),
              onChanged: (v) { if (v != null) { _setMode(v); Navigator.pop(sheet); } },
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _showHistory() async {
    if (loading) return;
    try {
      final entries = await historyDb.getHistory(limit: 50);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheetContext) {
          if (entries.isEmpty) {
            return const SafeArea(child: Padding(padding: EdgeInsets.all(28), child: Center(child: Text('لا يوجد سجل بحوث حتى الآن.'))));
          }
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.of(sheetContext).size.height * .72,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 20),
                itemCount: entries.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (_, index) {
                  final entry = entries[index];
                  return Card(child: ListTile(
                    title: Text(entry.query, textAlign: TextAlign.right, maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text(entry.response.isEmpty ? entry.sourceLabel : '${entry.sourceLabel} — ${entry.response}', textAlign: TextAlign.right, maxLines: 3, overflow: TextOverflow.ellipsis),
                    trailing: Icon(entry.source == 'local_db' ? Icons.menu_book_rounded : Icons.auto_awesome_rounded, color: context.accent),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      c.text = entry.query;
                      if (entry.response.isNotEmpty) {
                        setState(() {
                          messages..clear()..add(_Msg.user(entry.query))..add(_Msg.answer(LegalAiResult(answer: entry.response, sources: const [], conversationId: null, responseSource: entry.source)));
                        });
                        _end();
                      }
                    },
                  ));
                },
              ),
            ),
          );
        },
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر فتح سجل البحوث حالياً.')));
    }
  }

  void _end() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (scroll.hasClients) scroll.animateTo(scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('مساعد موسوعة القوانين'),
      centerTitle: true,
      actions: [
        IconButton(tooltip: 'مسح المحادثة', onPressed: loading ? null : clearChat, icon: const Icon(Icons.delete_outline_rounded)),
        IconButton(tooltip: 'إعدادات الإجابة', onPressed: loading ? null : _showSettings, icon: const Icon(Icons.settings_outlined)),
        IconButton(tooltip: 'سجل البحوث', onPressed: loading ? null : _showHistory, icon: const Icon(Icons.history_rounded)),
      ],
    ),
    body: SafeArea(child: Column(children: [
      if (!online) _OfflineNotice(onClose: _checkConnection),
      if (messages.isEmpty) _Intro(showDisclaimer: showDisclaimer, onClose: _closeDisclaimer),
      if (messages.isEmpty) _LawFilters(selected: selectedLaw, onSelected: (v) => setState(() => selectedLaw = v)),
      Expanded(child: messages.isEmpty
          ? _Empty(onTap: (q) { c.text = q; ask(); })
          : ListView.builder(controller: scroll, padding: const EdgeInsets.all(14), itemCount: messages.length, itemBuilder: (_, i) => _Message(m: messages[i], onRetry: messages[i].retryQuestion == null ? null : () => _retry(messages[i].retryQuestion!)))),
      if (loading) Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5), child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        Text('جاري تحليل النصوص القانونية...', style: TextStyle(color: context.textSecondary, fontSize: 12)),
        const SizedBox(width: 8),
        SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: context.accent)),
        const SizedBox(width: 8),
        TextButton.icon(onPressed: stopGeneration, icon: const Icon(Icons.stop_rounded, size: 18), label: const Text('إيقاف')),
      ])),
      Container(
        padding: const EdgeInsets.fromLTRB(4, 5, 4, 9),
        decoration: BoxDecoration(color: context.surfaceAlt, border: Border(top: BorderSide(color: context.divider))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          IconButton(tooltip: loading ? 'إيقاف التوليد' : 'إرسال', onPressed: loading ? stopGeneration : ask, icon: Icon(loading ? Icons.stop_rounded : Icons.send_rounded, color: context.accent)),
          Expanded(child: TextField(controller: c, enabled: !loading, minLines: 1, maxLines: 5, textAlign: TextAlign.right, decoration: const InputDecoration(hintText: 'اكتب سؤالك القانوني هنا...', border: InputBorder.none), onSubmitted: (_) => ask())),
          IconButton(tooltip: listening ? 'إيقاف الإملاء' : 'إملاء صوتي', onPressed: _startVoice, icon: Icon(listening ? Icons.mic_rounded : Icons.mic_none_rounded, color: listening ? Colors.redAccent : context.accent)),
        ]),
      ),
    ])),
  );
}

class _Intro extends StatelessWidget {
  final bool showDisclaimer;
  final VoidCallback onClose;
  const _Intro({required this.showDisclaimer, required this.onClose});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(14, 14, 14, 8),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: context.surfaceAlt, borderRadius: BorderRadius.circular(22), border: Border.all(color: context.accent.withOpacity(.35))),
    child: Column(children: [
      Row(children: [
        Icon(Icons.balance_rounded, color: context.accent, size: 38), const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('مساعد موسوعة القوانين اليمنية', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: context.textPrimary)),
          const SizedBox(height: 4),
          Text('اسأل عن نص قانوني أو مادة محددة، وسأبحث في المواد المتاحة في الموسوعة وأعرض مصادر الإجابة.', textAlign: TextAlign.right, style: TextStyle(color: context.textSecondary, height: 1.45)),
        ])),
      ]),
      if (showDisclaimer) ...[
        const SizedBox(height: 10),
        Container(padding: const EdgeInsets.fromLTRB(10, 8, 6, 8), decoration: BoxDecoration(color: context.surface, borderRadius: BorderRadius.circular(12)), child: Row(children: [
          Icon(Icons.info_outline_rounded, size: 18, color: context.accent), const SizedBox(width: 6),
          Expanded(child: Text('للمعلومات العامة والاستئناس، وليس بديلاً عن مراجعة النص الرسمي أو استشارة مختص قانوني.', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, color: context.textSecondary, height: 1.4))),
          IconButton(tooltip: 'إغلاق التنبيه', onPressed: onClose, icon: const Icon(Icons.close_rounded, size: 18)),
        ])),
      ],
    ]),
  );
}

class _OfflineNotice extends StatelessWidget {
  final VoidCallback onClose;
  const _OfflineNotice({required this.onClose});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(14, 8, 14, 0),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(color: Colors.orange.withOpacity(.10), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.orange.withOpacity(.25))),
    child: Row(children: [
      const Icon(Icons.wifi_off_rounded, size: 18, color: Colors.orange), const SizedBox(width: 7),
      Expanded(child: Text('لا يوجد اتصال بالإنترنت. يمكن مواصلة تصفح القوانين المحلية، أما المساعد الذكي فقد لا يعمل حتى عودة الاتصال.', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, color: context.textSecondary))),
      IconButton(onPressed: onClose, icon: const Icon(Icons.refresh_rounded, size: 18)),
    ]),
  );
}

class _LawFilters extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelected;
  const _LawFilters({required this.selected, required this.onSelected});
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 52,
    child: ListView.separated(
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      scrollDirection: Axis.horizontal,
      itemCount: _LegalAiScreenState.lawFilters.length,
      separatorBuilder: (_, __) => const SizedBox(width: 7),
      itemBuilder: (_, i) {
        final law = _LegalAiScreenState.lawFilters[i];
        return ChoiceChip(label: Text(law), selected: selected == law, onSelected: (_) => onSelected(law), selectedColor: context.accent.withOpacity(.22));
      },
    ),
  );
}

class _Empty extends StatelessWidget {
  final ValueChanged<String> onTap;
  const _Empty({required this.onTap});
  @override
  Widget build(BuildContext context) {
    const qs = ['ما هي شروط الطلاق؟', 'ما عقوبة السرقة؟', 'ما المادة المتعلقة بالنفقة؟', 'اشرح لي المادة 15 بطريقة بسيطة.', 'ما الفرق بين النصين القانونيين؟'];
    return ListView(padding: const EdgeInsets.fromLTRB(16, 2, 16, 16), children: [
      Text('أسئلة مقترحة', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w800, color: context.textPrimary)),
      const SizedBox(height: 10),
      for (final q in qs) Card(margin: const EdgeInsets.only(bottom: 8), child: ListTile(leading: Icon(Icons.arrow_back_ios_new_rounded, size: 15, color: context.accent), title: Text(q, textAlign: TextAlign.right), onTap: () => onTap(q))),
    ]);
  }
}

class _Msg {
  final String role, text;
  final LegalAiResult? result;
  final String? retryQuestion;
  const _Msg(this.role, this.text, this.result, this.retryQuestion);
  factory _Msg.user(String t) => _Msg('user', t, null, null);
  factory _Msg.answer(LegalAiResult r) => _Msg('assistant', r.answer, r, null);
  factory _Msg.error(String t, String q) => _Msg('error', t, null, q);
}

class _Message extends StatefulWidget {
  final _Msg m;
  final VoidCallback? onRetry;
  const _Message({required this.m, this.onRetry});
  @override
  State<_Message> createState() => _MessageState();
}

class _MessageState extends State<_Message> {
  String? feedback;

  Future<void> _feedback(String value) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('legal_ai_feedback_${widget.m.text.hashCode}', value);
    if (mounted) setState(() => feedback = value);
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.m;
    final user = m.role == 'user', err = m.role == 'error';
    return Align(
      alignment: user ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 760),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: user ? context.accent.withOpacity(.12) : err ? Colors.red.withOpacity(.08) : context.surfaceAlt, borderRadius: BorderRadius.circular(18), border: Border.all(color: err ? Colors.red.withOpacity(.25) : context.divider)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            if (!user && !err) Icon(Icons.balance_rounded, size: 16, color: context.accent),
            if (!user && !err) const SizedBox(width: 5),
            Text(user ? 'سؤالك' : err ? 'تنبيه' : 'المساعد', style: TextStyle(fontWeight: FontWeight.w900, color: err ? Colors.redAccent : context.accent)),
          ]),
          const SizedBox(height: 7),
          SelectableText(m.text, textAlign: TextAlign.right, style: TextStyle(color: context.textPrimary, height: 1.7)),
          if (err && widget.onRetry != null) ...[
            const SizedBox(height: 10),
            Align(alignment: Alignment.centerRight, child: OutlinedButton.icon(onPressed: widget.onRetry, icon: const Icon(Icons.refresh_rounded, size: 18), label: const Text('إعادة الإرسال'))),
          ],
          if (m.result != null) ...[
            const SizedBox(height: 8),
            _AnswerActions(result: m.result!, feedback: feedback, onFeedback: _feedback),
            if (m.result!.sources.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text('المواد القانونية المستخدمة', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w900, color: context.textPrimary)),
              const SizedBox(height: 8),
              for (final s in m.result!.sources) _Source(s: s),
            ],
          ],
        ]),
      ),
    );
  }
}

class _AnswerActions extends StatelessWidget {
  final LegalAiResult result;
  final String? feedback;
  final ValueChanged<String> onFeedback;
  const _AnswerActions({required this.result, required this.feedback, required this.onFeedback});
  @override
  Widget build(BuildContext context) => Wrap(alignment: WrapAlignment.end, spacing: 2, runSpacing: 2, children: [
    IconButton(tooltip: 'نسخ', onPressed: () async { await Clipboard.setData(ClipboardData(text: result.answer)); if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نسخ الإجابة.'))); }, icon: const Icon(Icons.copy_rounded, size: 19)),
    IconButton(tooltip: 'مشاركة', onPressed: () => Share.share(result.answer), icon: const Icon(Icons.share_rounded, size: 19)),
    if (result.sources.isNotEmpty) IconButton(tooltip: 'الانتقال إلى المادة', onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ArticleDetailScreen(maddaId: result.sources.first.articleId))), icon: const Icon(Icons.menu_book_rounded, size: 19)),
    IconButton(tooltip: 'إجابة مفيدة', onPressed: () => onFeedback('up'), icon: Icon(Icons.thumb_up_alt_outlined, size: 19, color: feedback == 'up' ? context.accent : null)),
    IconButton(tooltip: 'إجابة غير مفيدة', onPressed: () => onFeedback('down'), icon: Icon(Icons.thumb_down_alt_outlined, size: 19, color: feedback == 'down' ? Colors.redAccent : null)),
  ]);
}

class _Source extends StatelessWidget {
  final LegalAiSource s;
  const _Source({required this.s});
  @override
  Widget build(BuildContext context) => Card(child: InkWell(
    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ArticleDetailScreen(maddaId: s.articleId))),
    child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Text(s.lawName, textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w800, color: context.accent)),
      if (s.reference.trim().isNotEmpty) ...[const SizedBox(height: 4), Text(s.reference, textAlign: TextAlign.right, style: TextStyle(color: context.textSecondary, fontSize: 11))],
      const SizedBox(height: 4),
      Text('المادة: ${s.articleNumber}', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w700, color: context.textPrimary)),
      const SizedBox(height: 7),
      Text(s.articleText, maxLines: 5, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right, style: TextStyle(color: context.textSecondary, height: 1.5)),
      const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.start, children: [Text('فتح المادة في الموسوعة', style: TextStyle(color: context.accent, fontWeight: FontWeight.w700)), const SizedBox(width: 5), Icon(Icons.open_in_new_rounded, size: 16, color: context.accent)]),
    ])),
  ));
}
