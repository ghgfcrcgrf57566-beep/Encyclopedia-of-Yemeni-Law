import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/constants.dart';
import '../core/theme.dart';
import '../providers/settings_provider.dart';
import 'coming_soon_screen.dart';
import 'contact/contact_screen.dart';
import 'favorites/favorites_screen.dart';
import 'feedback/feedback_screen.dart';
import 'inheritance_calculator_screen.dart';
import 'laws/laws_home_screen.dart';
import 'supreme_court_screen.dart';
import 'library_screen.dart';
import 'legal_ai/legal_ai_screen.dart';

class RootShell extends StatelessWidget {
  const RootShell({super.key});

  List<_SectionData> _sections() => [
        _SectionData(icon: Icons.auto_awesome_rounded, title: 'اسأل موسوعة القوانين اليمنية', subtitle: 'مساعد ذكي يبحث أولاً في نصوص القوانين', builder: (_) => const LegalAiScreen(), fullWidth: true),
        _SectionData(icon: Icons.menu_book_rounded, title: 'المكتبة', subtitle: 'المكتبة القانونية والمكتبة الشرعية', builder: (_) => const LibraryScreen()),
        _SectionData(icon: Icons.balance_rounded, title: 'القوانين اليمنية', subtitle: 'نصوص القوانين والمواد', builder: (_) => const LawsHomeScreen()),
        _SectionData(icon: Icons.description_rounded, title: 'المذكرات والنماذج القانونية', subtitle: 'صحائف وعقود وإنذارات ونماذج', builder: (_) => const ComingSoonScreen(title: 'المذكرات والنماذج القانونية')),
        _SectionData(icon: Icons.account_balance_rounded, title: 'أحكام المحكمة العليا', subtitle: 'القواعد والمبادئ والأحكام القضائية', builder: (_) => const SupremeCourtScreen()),
        _SectionData(icon: Icons.calculate_rounded, title: 'حاسبة المواريث والتركات', subtitle: 'حساب الأنصبة والحجب والعول والرد', builder: (_) => const InheritanceCalculatorScreen()),
        _SectionData(icon: Icons.star_rounded, title: 'المفضلة', subtitle: 'المواد والعناصر المحفوظة', builder: (_) => const FavoritesScreen()),
        _SectionData(icon: Icons.support_agent_rounded, title: 'التواصل والاستشارات', subtitle: 'للاستشارات القانونية والتواصل', builder: (_) => const ContactScreen(), fullWidth: true),
      ];

  @override
  Widget build(BuildContext context) {
    final sections = _sections();
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || !context.mounted) return;
        final shouldExit = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: const Color(0xFF1A1410),
            title: const Text('تأكيد الخروج', style: TextStyle(color: Color(0xFFE2BA70)), textAlign: TextAlign.right),
            content: const Text('هل تريد الخروج من التطبيق؟', style: TextStyle(color: Colors.white70), textAlign: TextAlign.right),
            actions: [
              TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('إلغاء', style: TextStyle(color: Colors.white60))),
              FilledButton(style: FilledButton.styleFrom(backgroundColor: const Color(0xFFD4AF37), foregroundColor: Colors.black), onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('خروج')),
            ],
          ),
        );
        if (shouldExit == true && context.mounted) SystemNavigator.pop();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: context.isDark ? Brightness.light : Brightness.dark,
          statusBarBrightness: context.isDark ? Brightness.dark : Brightness.light,
          systemNavigationBarColor: context.isDark ? AppColors.darkBackground : AppColors.lightBackground,
          systemNavigationBarIconBrightness: context.isDark ? Brightness.light : Brightness.dark,
        ),
        child: Scaffold(
          backgroundColor: context.isDark ? AppColors.darkBackground : AppColors.lightBackground,
          body: Stack(fit: StackFit.expand, children: [
            ColorFiltered(
              colorFilter: context.isDark ? const ColorFilter.mode(Colors.transparent, BlendMode.dst) : ColorFilter.mode(Colors.white.withOpacity(.72), BlendMode.screen),
              child: const _LibraryBackground(),
            ),
            Container(color: context.isDark ? const Color(0x8F120A06) : const Color(0x331A1208)),
            SafeArea(
              child: LayoutBuilder(builder: (context, constraints) {
                final horizontalPadding = constraints.maxWidth >= 700 ? 26.0 : 12.0;
                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(horizontalPadding, 10, horizontalPadding, 14),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Column(children: [
                        const SizedBox(height: 4),
                        const _HomeTitle(),
                        const SizedBox(height: 14),
                        LayoutBuilder(builder: (context, gridConstraints) {
                          final cardWidth = (gridConstraints.maxWidth - 12) / 2;
                          final cardHeight = (cardWidth * .77).clamp(150.0, 245.0);
                          return Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              for (final section in sections)
                                SizedBox(
                                  width: section.fullWidth ? gridConstraints.maxWidth : cardWidth,
                                  height: section.fullWidth ? 184 : cardHeight,
                                  child: _GlassSectionCard(data: section, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: section.builder))),
                                ),
                            ],
                          );
                        }),
                        const SizedBox(height: 10),
                        const _FeedbackFooterButton(),
                        const SizedBox(height: 10),
                        const _HomeFooter(),
                      ]),
                    ),
                  ),
                );
              }),
            ),
          ]),
        ),
      ),
    );
  }
}

class _HomeTitle extends StatelessWidget {
  const _HomeTitle();

  Future<void> _chooseTheme(BuildContext context) async {
    final settings = context.read<SettingsProvider>();
    final selected = await showModalBottomSheet<ThemeMode>(
      context: context,
      backgroundColor: context.isDark ? AppColors.darkSurface : AppColors.lightSurface,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 12), child: Align(alignment: Alignment.centerRight, child: Text('مظهر التطبيق', style: TextStyle(color: sheetContext.isDark ? AppColors.softGold : AppColors.bronzeOnLight, fontSize: 18, fontWeight: FontWeight.w800)))),
        _ThemeChoice(icon: Icons.dark_mode_rounded, title: 'الوضع الليلي', subtitle: 'خلفية داكنة مريحة للقراءة', mode: ThemeMode.dark, selected: settings.themeMode == ThemeMode.dark),
        _ThemeChoice(icon: Icons.light_mode_rounded, title: 'الوضع النهاري', subtitle: 'خلفية فاتحة دافئة', mode: ThemeMode.light, selected: settings.themeMode == ThemeMode.light),
        const SizedBox(height: 10),
      ])),
    );
    if (selected != null) await settings.setThemeMode(selected);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    return Row(textDirection: TextDirection.rtl, children: [
      IconButton(
        tooltip: 'اختيار الوضع: ليلي / نهاري',
        onPressed: () => _chooseTheme(context),
        icon: Icon(isDark ? Icons.nightlight_round : Icons.wb_sunny_rounded, size: 26, color: isDark ? AppColors.softGold : AppColors.bronzeOnLight),
        style: IconButton.styleFrom(backgroundColor: isDark ? const Color(0x441A100B) : const Color(0xCCFFFFFF), side: BorderSide(color: isDark ? const Color(0x88E1C28C) : AppColors.lightDivider), shape: const CircleBorder(), padding: const EdgeInsets.all(10)),
      ),
      Expanded(child: Text(AppConstants.appNameAr, textAlign: TextAlign.center, style: TextStyle(color: isDark ? const Color(0xFFE2BA70) : AppColors.bronzeOnLight, fontSize: 27, fontWeight: FontWeight.w800, height: 1.1, letterSpacing: .2, shadows: isDark ? const [Shadow(color: Colors.black87, blurRadius: 10, offset: Offset(0, 4)), Shadow(color: Color(0x663A210C), blurRadius: 18)] : const []))),
      const SizedBox(width: 48),
    ]);
  }
}

class _ThemeChoice extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final ThemeMode mode;
  final bool selected;
  const _ThemeChoice({required this.icon, required this.title, required this.subtitle, required this.mode, required this.selected});
  @override
  Widget build(BuildContext context) {
    final accent = context.isDark ? AppColors.softGold : AppColors.bronzeOnLight;
    return ListTile(onTap: () => Navigator.of(context).pop(mode), leading: Icon(icon, color: accent), title: Text(title, textAlign: TextAlign.right, style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.w700)), subtitle: Text(subtitle, textAlign: TextAlign.right, style: TextStyle(color: context.textSecondary)), trailing: selected ? Icon(Icons.check_circle_rounded, color: accent) : const SizedBox(width: 24));
  }
}

class _GlassSectionCard extends StatelessWidget {
  final _SectionData data;
  final VoidCallback onTap;
  const _GlassSectionCard({required this.data, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: Material(color: Colors.transparent, child: InkWell(
          onTap: onTap,
          splashColor: const Color(0x22E3BD78),
          highlightColor: const Color(0x18E3BD78),
          child: DecoratedBox(
            decoration: BoxDecoration(color: context.isDark ? const Color(0xA91A100B) : const Color(0xE8FFFFFF), borderRadius: BorderRadius.circular(28), border: Border.all(color: context.isDark ? const Color(0xD8E1C28C) : AppColors.lightDivider, width: 1.5), boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 18, offset: Offset(0, 8))]),
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              _GoldIcon(data.icon),
              const SizedBox(height: 10),
              Text(data.title, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFF1E6D2), fontSize: 16, fontWeight: FontWeight.w800, height: 1.35, shadows: [Shadow(color: Colors.black, blurRadius: 7, offset: Offset(0, 2))])),
              const SizedBox(height: 6),
              Text(data.subtitle, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xD6DBCDB9), fontSize: 11.5, height: 1.35)),
            ])),
          ),
        )),
      ),
    );
  }
}

class _GoldIcon extends StatelessWidget {
  final IconData icon;
  const _GoldIcon(this.icon);
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 74,
      height: 74,
      decoration: BoxDecoration(shape: BoxShape.circle, gradient: const RadialGradient(center: Alignment(-.25, -.3), radius: .95, colors: [Color(0xFFFBE9B7), Color(0xFFD6AB57), Color(0xFF8E652D)]), border: Border.all(color: const Color(0xFFE7C77F)), boxShadow: const [BoxShadow(color: Color(0x8F000000), blurRadius: 12, offset: Offset(0, 7)), BoxShadow(color: Color(0x665E3B10), blurRadius: 4, spreadRadius: 1)]),
      child: Center(child: ShaderMask(shaderCallback: (rect) => const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFFF1C6), Color(0xFFD5A956), Color(0xFF6E461C)]).createShader(rect), child: icon == Icons.support_agent_rounded ? const Stack(alignment: Alignment.center, children: [Icon(Icons.phone_in_talk_rounded, size: 43, color: Colors.white), Positioned(bottom: 6, right: 7, child: Icon(Icons.balance_rounded, size: 22, color: Colors.white))]) : Icon(icon, size: 46, color: Colors.white, shadows: const [Shadow(color: Color(0xAA2A1808), blurRadius: 5, offset: Offset(1, 3))]))),
    );
  }
}

class _FeedbackFooterButton extends StatelessWidget {
  const _FeedbackFooterButton();
  @override
  Widget build(BuildContext context) {
    final color = context.isDark ? const Color(0xFFE2BA70) : AppColors.bronzeOnLight;
    return TextButton.icon(
      onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FeedbackScreen())),
      icon: Icon(Icons.feedback_outlined, size: 17, color: color),
      label: Text('ملاحظات واقتراحات', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5)),
    );
  }
}

class _HomeFooter extends StatelessWidget {
  const _HomeFooter();
  @override
  Widget build(BuildContext context) => Text('${AppConstants.contactShortName} - ${AppConstants.contactTitleShort} - ${AppConstants.contactPhone}', textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFF0E4D0), fontSize: 15, fontWeight: FontWeight.w700, height: 1.4));
}

class _SectionData {
  final IconData icon;
  final String title;
  final String subtitle;
  final WidgetBuilder builder;
  final bool fullWidth;
  const _SectionData({required this.icon, required this.title, required this.subtitle, required this.builder, this.fullWidth = false});
}

class _LibraryBackground extends StatelessWidget {
  const _LibraryBackground();
  @override
  Widget build(BuildContext context) => CustomPaint(painter: _LibraryPainter(), child: const SizedBox.expand());
}

class _LibraryPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF5A3219), Color(0xFF24150D), Color(0xFF100A07)]).createShader(rect));
    final shelfPaint = Paint()..color = const Color(0x663C2110);
    for (double y = size.height * .17; y < size.height; y += 150) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 9), shelfPaint);
    }
    final bookColors = [const Color(0x663F2715), const Color(0x664F3219), const Color(0x665E3C1D), const Color(0x66352619)];
    var seed = 7;
    for (double y = size.height * .02; y < size.height; y += 150) {
      var x = -20.0;
      while (x < size.width) {
        final w = 25.0 + ((seed * 13) % 34);
        final h = 70.0 + ((seed * 17) % 60);
        final p = Paint()..color = bookColors[seed % bookColors.length];
        canvas.drawRect(Rect.fromLTWH(x, y + 8, w, h), p);
        x += w + 5;
        seed++;
      }
    }
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
