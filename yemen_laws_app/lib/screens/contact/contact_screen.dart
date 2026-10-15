import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';

const _contactGold = Color(0xFFD4AF37);
const _contactPanel = Color(0xFF1A1A1A);
const _contactWhatsApp = Color(0xFF25D366);
const _contactFacebook = Color(0xFF1877F2);

class ContactScreen extends StatelessWidget {
  const ContactScreen({super.key});

  Future<void> _openExternal(BuildContext context, String urlString) async {
    final uri = Uri.parse(urlString);
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && context.mounted) {
        _showMessage(context, 'تعذر فتح الرابط. تحقق من اتصال الإنترنت.');
      }
    } catch (_) {
      if (context.mounted) _showMessage(context, 'تعذر فتح الرابط. حاول مرة أخرى.');
    }
  }

  Future<void> _callPhone(BuildContext context) async {
    final uri = Uri(scheme: 'tel', path: AppConstants.contactPhone);
    try {
      final opened = await launchUrl(uri);
      if (!opened && context.mounted) _showMessage(context, 'تعذر فتح تطبيق الاتصال.');
    } catch (_) {
      if (context.mounted) _showMessage(context, 'تعذر فتح تطبيق الاتصال.');
    }
  }

  Future<void> _copyPhone(BuildContext context) async {
    await Clipboard.setData(const ClipboardData(text: AppConstants.contactPhone));
    if (!context.mounted) return;
    _showMessage(context, 'تم نسخ رقم التواصل');
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('التواصل والاستشارات'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        foregroundColor: _contactGold,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: _contactPanel,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: _contactGold.withOpacity(0.48)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.18),
                      blurRadius: 16,
                      offset: const Offset(0, 7),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      width: 84,
                      height: 84,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [Color(0xFFF4D989), Color(0xFF9A741F)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: const Icon(Icons.gavel_rounded, color: Colors.black87, size: 46),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      AppConstants.contactName,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFFF0D78A),
                        fontSize: 23,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'محاماة • استشارات قانونية • تحرير عقود',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, height: 1.7, fontSize: 14),
                    ),
                    const SizedBox(height: 22),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _SocialContactButton(
                          label: 'واتساب',
                          icon: Icons.chat_rounded,
                          color: _contactWhatsApp,
                          onPressed: () => _openExternal(context, 'https://wa.me/967777001515'),
                        ),
                        _SocialContactButton(
                          label: 'فيسبوك',
                          icon: Icons.facebook_rounded,
                          color: _contactFacebook,
                          onPressed: () => _openExternal(context, 'https://www.facebook.com/AlMqbly'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsetsDirectional.fromSTEB(8, 6, 8, 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF101010),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _contactGold.withOpacity(0.38)),
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: 'نسخ الرقم',
                            onPressed: () => _copyPhone(context),
                            icon: const Icon(Icons.copy_rounded, color: _contactGold, size: 20),
                          ),
                          Expanded(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => _callPhone(context),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.phone_in_talk_rounded, color: _contactGold, size: 21),
                                    SizedBox(width: 10),
                                    Flexible(
                                      child: Text(
                                        AppConstants.contactPhone,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 18,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 1,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'اتصال مباشر',
                            onPressed: () => _callPhone(context),
                            icon: const Icon(Icons.call_rounded, color: _contactGold, size: 21),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      'اضغط على الرقم للاتصال أو على أيقونة النسخ لحفظه',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF181512),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0x554A3B27)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          'عن التطبيق',
                          style: TextStyle(
                            color: context.accent,
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(width: 9),
                        Icon(Icons.info_outline_rounded, color: context.accent),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      AppConstants.dedicationText,
                      textAlign: TextAlign.right,
                      style: TextStyle(color: context.textSecondary, height: 1.9, fontSize: 14),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      '© ' + AppConstants.copyrightText,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SocialContactButton extends StatelessWidget {
  const _SocialContactButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, color: Colors.white, size: 20),
      label: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        minimumSize: const Size(132, 46),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
