import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme.dart';
import '../../core/constants.dart';
import '../../core/connectivity_service.dart';
import '../../data/repositories/laws_repository.dart';

class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final _repo = LawsRepository.instance;
  final _controller = TextEditingController();
  bool _sending = false;
  bool _reporting = false;
  String _reportType = 'إجابة غير دقيقة أو غير مرتبطة بالسؤال';

  static const _privacyPolicyUrl =
      'https://github.com/ghgfcrcgrf57566-beep/Encyclopedia-of-Yemeni-Law/blob/main/privacy-policy.html';
  static const _reportEmail = 'ghgfcrcgrf57566@gmail.com';

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() => _sending = true);
    final id = await _repo.addFeedbackNote(text);
    final hasInternet = await ConnectivityService.hasConnection();

    if (!mounted) return;
    if (!hasInternet) {
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: const Text(AppConstants.noInternetMessage), backgroundColor: AppColors.danger),
      );
      return;
    }

    await _repo.markFeedbackSent(id);
    if (!mounted) return;
    setState(() {
      _sending = false;
      _controller.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم حفظ ملاحظتك، شكرًا لك')),
    );
  }

  Future<void> _reportAnswer() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اكتب نص الإجابة أو تفاصيل المشكلة أولاً.')),
      );
      return;
    }

    setState(() => _reporting = true);
    final subject = Uri.encodeComponent('بلاغ عن إجابة من مساعد موسوعة القانون اليمني');
    final body = Uri.encodeComponent(
      'نوع البلاغ: $_reportType\n\nتفاصيل البلاغ أو نص الإجابة:\n$text\n\nأرسل البلاغ من داخل تطبيق موسوعة القانون اليمني.',
    );
    final uri = Uri.parse('mailto:$_reportEmail?subject=$subject&body=$body');
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted) return;
    setState(() => _reporting = false);
    if (!launched) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر فتح تطبيق البريد لإرسال البلاغ.')),
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
            Text(AppConstants.feedbackIntro, textAlign: TextAlign.right, style: TextStyle(fontSize: 13.5, height: 1.7, color: context.textSecondary)),
            const SizedBox(height: 20),
            TextField(
              controller: _controller,
              textAlign: TextAlign.right,
              maxLines: 6,
              decoration: const InputDecoration(hintText: 'اكتب ملاحظتك أو اقتراحك هنا...'),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _sending ? null : _submit,
              icon: _sending ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send_outlined),
              label: const Text('إرسال الملاحظة'),
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
            Text('إذا كانت إجابة المساعد غير دقيقة أو غير مرتبطة بسؤالك أو تحتوي على محتوى غير مناسب، يمكنك الإبلاغ عنها من داخل التطبيق.', textAlign: TextAlign.right, style: TextStyle(height: 1.6, color: context.textSecondary)),
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
              icon: _reporting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.flag_outlined),
              label: const Text('إرسال بلاغ عن الإجابة عبر البريد'),
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
