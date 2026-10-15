import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme.dart';
import '../../core/constants.dart';
import '../../data/repositories/laws_repository.dart';

class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final _repo = LawsRepository.instance;
  final _controller = TextEditingController();
  bool _saving = false;
  bool _reporting = false;
  String _reportType = 'إجابة غير دقيقة أو غير مرتبطة بالسؤال';

  static const _privacyPolicyUrl =
      'https://github.com/ghgfcrcgrf57566-beep/Encyclopedia-of-Yemeni-Law/blob/main/privacy-policy.html';
  static const _reportEmail = 'ghgfcrcgrf57566@gmail.com';

  Future<void> _saveFeedbackLocally() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اكتب ملاحظتك أولاً.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await _repo.addFeedbackNote(text);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _controller.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('حُفظت ملاحظتك على هذا الجهاز فقط، ولم تُرسل إلى المطوّر.'),
          duration: Duration(seconds: 4),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر حفظ الملاحظة على الجهاز. حاول مرة أخرى.')),
      );
    }
  }

  Future<void> _reportAnswer() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اكتب تفاصيل البلاغ أو نص الإجابة أولاً.')),
      );
      return;
    }

    setState(() => _reporting = true);
    final subject = Uri.encodeComponent('بلاغ عن إجابة من مساعد موسوعة القانون اليمني');
    final body = Uri.encodeComponent(
      'نوع البلاغ: $_reportType\n\nتفاصيل البلاغ أو نص الإجابة:\n$text\n\nأُعد هذا البلاغ من تطبيق موسوعة القانون اليمني.',
    );
    final uri = Uri.parse('mailto:$_reportEmail?subject=$subject&body=$body');

    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!mounted) return;
      setState(() => _reporting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            launched
                ? 'فُتح تطبيق البريد برسالة جاهزة. راجع محتواها واضغط «إرسال» بنفسك؛ لم يُرسل التطبيق البلاغ تلقائيًا.'
                : 'تعذر فتح تطبيق البريد. يمكنك مراسلة $_reportEmail يدويًا.',
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _reporting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر فتح تطبيق البريد. يمكنك مراسلة $_reportEmail يدويًا.')),
      );
    }
  }

  Future<void> _openPrivacyPolicy() async {
    final uri = Uri.parse(_privacyPolicyUrl);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر فتح سياسة الخصوصية حالياً.')),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ملاحظات واقتراحات')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.edit_note_outlined, color: context.accent, size: 26),
                const SizedBox(width: 8),
                Text('ملاحظات واقتراحات', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: context.textPrimary)),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              AppConstants.feedbackIntro,
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 13.5, height: 1.7, color: context.textSecondary),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _controller,
              textAlign: TextAlign.right,
              maxLines: 6,
              decoration: const InputDecoration(hintText: 'اكتب ملاحظتك أو تفاصيل البلاغ هنا...'),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _saving ? null : _saveFeedbackLocally,
              icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined),
              label: const Text('حفظ الملاحظة على الجهاز'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.antiqueBronze, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
            const SizedBox(height: 26),
            Divider(color: context.divider),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.flag_outlined, color: context.accent, size: 25),
                const SizedBox(width: 8),
                Text('الإبلاغ عن إجابة المساعد', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: context.textPrimary)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'يفتح هذا الخيار تطبيق البريد برسالة جاهزة إلى $_reportEmail. راجع الرسالة ومحتواها ثم أرسلها بنفسك. قد تتضمن الرسالة النص الذي كتبته هنا؛ لا تضف بيانات سرية أو شخصية غير لازمة.',
              textAlign: TextAlign.right,
              style: TextStyle(height: 1.6, color: context.textSecondary),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _reportType,
              decoration: const InputDecoration(labelText: 'نوع البلاغ'),
              items: const [
                DropdownMenuItem(value: 'إجابة غير دقيقة أو غير مرتبطة بالسؤال', child: Text('إجابة غير دقيقة أو غير مرتبطة بالسؤال')),
                DropdownMenuItem(value: 'محتوى غير مناسب', child: Text('محتوى غير مناسب')),
                DropdownMenuItem(value: 'مشكلة تقنية في المساعد', child: Text('مشكلة تقنية في المساعد')),
              ],
              onChanged: (v) => setState(() => _reportType = v ?? _reportType),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _reporting ? null : _reportAnswer,
              icon: _reporting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.mail_outline),
              label: const Text('فتح بلاغ في تطبيق البريد'),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: _openPrivacyPolicy,
              icon: const Icon(Icons.privacy_tip_outlined),
              label: const Text('سياسة الخصوصية'),
            ),
          ],
        ),
      ),
    );
  }
}
