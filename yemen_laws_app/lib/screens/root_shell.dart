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
import 'laws/laws_home_screen.dart';
import 'supreme_court_screen.dart';
import 'legal_references_screen.dart';
import 'legal_ai/legal_ai_screen.dart';

class RootShell extends StatelessWidget {
  const RootShell({super.key});

  List<_SectionData> _sections() => [
        _SectionData(
          icon: Icons.auto_awesome_rounded,
          title: 'اسأل موسوعة القوانين اليمنية',
          subtitle: 'مساعد ذكي يبحث أولاً في نصوص القوانين',
          builder: (_) => const LegalAiScreen(),
          fullWidth: true,
        ),
        _SectionData(
          icon: Icons.menu_book_rounded,
          title: 'المراجع القانونية',
          subtitle: 'كتب وشروحات وأبحاث قانونية',
          builder: (_) => const LegalReferencesScreen(),
        ),
        _SectionData(
          icon: Icons.balance_rounded,
          title: 'القوانين اليمنية',
          subtitle: 'نصوص القوانين والمواد',
          builder: (_) => const LawsHomeScreen(),
        ),
        _SectionData(
          icon: Icons.description_rounded,
          title: 'المذكرات والنماذج القانونية',
          subtitle: 'صحائف وعقود وإنذارات ونماذج',
          builder: (_) => const ComingSoonScreen(title: 'المذكرات والنماذج القانونية'),
        ),
        _SectionData(
          icon: Icons.account_balance_rounded,
          title: 'أحكام المحكمة العليا',
          subtitle: 'القواعد والمبادئ والأحكام القضائية',
          builder: (_) => const SupremeCourtScreen(),
        ),
        _SectionData(
          icon: Icons.edit_note_rounded,
          title: 'ملاحظات واقتراحات',
          subtitle: 'شاركنا رأيك ومقترحاتك',
          builder: (_) => const FeedbackScreen(),
        ),
        _SectionData(
          icon: Icons.star_rounded,
          title: 'المفضلة',
          subtitle: 'المواد والعناصر المحفوظة',
          builder: (_) => const FavoritesScreen(),
        ),
        _SectionData(
          icon: Icons.support_agent_rounded,
          title: 'التواصل والاستشارات',
          subtitle: 'للاستشارات القانونية والتواصل',
          builder: (_) => const ContactScreen(),
          fullWidth: true,
        ),
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
            title: const Text(
              'تأكيد الخروج',
              style: TextStyle(color: Color(0xFFE2BA70)),
              textAlign: TextAlign.right,
            ),
            content: const Text(
              'هل تريد الخروج من التطبيق؟',
              style: TextStyle(color: Colors.white70),
              textAlign: TextAlign.right,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text(
                  'إلغاء',
                  style: TextStyle(color: Colors.white60),
                ),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Color(0xFFD4AF37),
                  foregroundColor: Colors.black,
                ),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('خروج'),
              ),
            ],
          ),
        );
        if (shouldExit == true && context.mounted) {
          SystemNavigator.pop();
        }
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: context.isDark ? Brightness.light : Brightness.dark,
          statusBarBrightness: context.isDark ? Brightness.dark : Brightness.light,
          systemNavigationBarColor: context.isDark
              ? AppColors.darkBackground
              : AppColors.lightBackground,
          systemNavigationBarIconBrightness:
              context.isDark ? Brightness.light : Brightness.dark,
        ),
        child: Scaffold(
        backgroundColor: context.isDark
            ? AppColors.darkBackground
            : AppColors.lightBackground,
        body: Stack(
          fit: StackFit.expand,
          children: [
            ColorFiltered(
              colorFilter: context.isDark
                  ? const ColorFilter.mode(Colors.transparent, BlendMode.dst)
                  : ColorFilter.mode(
                      Colors.white.withOpacity(0.72),
                      BlendMode.screen,
                    ),
              child: const _LibraryBackground(),
            ),
            Container(
              color: context.isDark
                  ? const Color(0x8F120A06)
                  : const Color(0x331A1208),
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final horizontalPadding =
                      constraints.maxWidth >= 700 ? 26.0 : 12.0;
                  return SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      10,
                      horizontalPadding,
                      14,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: Column(
                          children: [
                            const SizedBox(height: 4),
                            const _HomeTitle(),
                            const SizedBox(height: 14),
                            LayoutBuilder(
                              builder: (context, gridConstraints) {
                                final cardWidth =
                                    (gridConstraints.maxWidth - 12) / 2;
                                final cardHeight =
                                    (cardWidth * 0.77).clamp(150.0, 245.0);
                                return Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  children: [
                                    for (final section in sections)
                                      SizedBox(
                                        width: section.fullWidth
                                            ? gridConstraints.maxWidth
                                            : cardWidth,
                                        height: section.fullWidth
                                            ? 184
                                            : cardHeight,
                                        child: _GlassSectionCard(
                                          data: section,
                                          onTap: () =>
                                              Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: section.builder,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 12),
                            const _HomeFooter(),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
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
      backgroundColor: context.isDark
          ? AppColors.darkSurface
          : AppColors.lightSurface,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'مظهر التطبيق',
                    style: TextStyle(
                      color: sheetContext.isDark
                          ? AppColors.softGold
                          : AppColors.bronzeOnLight,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              _ThemeChoice(
                icon: Icons.dark_mode_rounded,
                title: 'الوضع الليلي',
                subtitle: 'خلفية داكنة مريحة للقراءة',
                mode: ThemeMode.dark,
                selected: settings.themeMode == ThemeMode.dark,
              ),
              _ThemeChoice(
                icon: Icons.light_mode_rounded,
                title: 'الوضع النهاري',
                subtitle: 'خلفية فاتحة دافئة',
                mode: ThemeMode.light,
                selected: settings.themeMode == ThemeMode.light,
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
    if (selected != null) {
      await settings.setThemeMode(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final modeIcon = isDark
        ? Icons.nightlight_round
        : Icons.wb_sunny_rounded;

    return Row(
      textDirection: TextDirection.rtl,
      children: [
        IconButton(
          tooltip: 'اختيار الوضع: ليلي / نهاري',
          onPressed: () => _chooseTheme(context),
          icon: Icon(
            modeIcon,
            size: 26,
            color: isDark ? AppColors.softGold : AppColors.bronzeOnLight,
          ),
          style: IconButton.styleFrom(
            backgroundColor: isDark
                ? const Color(0x441A100B)
                : const Color(0xCCFFFFFF),
            side: BorderSide(
              color: isDark
                  ? const Color(0x88E1C28C)
                  : AppColors.lightDivider,
              width: 1,
            ),
            shape: const CircleBorder(),
            padding: const EdgeInsets.all(10),
          ),
        ),
        Expanded(
          child: Text(
            AppConstants.appNameAr,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isDark
                  ? const Color(0xFFE2BA70)
                  : AppColors.bronzeOnLight,
              fontSize: 27,
              fontWeight: FontWeight.w800,
              height: 1.1,
              letterSpacing: 0.2,
              shadows: isDark
                  ? const [
                      Shadow(
                        color: Colors.black87,
                        blurRadius: 10,
                        offset: Offset(0, 4),
                      ),
                      Shadow(
                        color: Color(0x663A210C),
                        blurRadius: 18,
                      ),
                    ]
                  : const [],
            ),
          ),
        ),
        const SizedBox(width: 48),
      ],
    );
  }
}

class _ThemeChoice extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final ThemeMode mode;
  final bool selected;

  const _ThemeChoice({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.mode,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    final accent = context.isDark
        ? AppColors.softGold
        : AppColors.bronzeOnLight;

    return ListTile(
      onTap: () => Navigator.of(context).pop(mode),
      leading: Icon(icon, color: accent),
      title: Text(
        title,
        textAlign: TextAlign.right,
        style: TextStyle(
          color: context.textPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        subtitle,
        textAlign: TextAlign.right,
        style: TextStyle(color: context.textSecondary),
      ),
      trailing: selected
          ? Icon(Icons.check_circle_rounded, color: accent)
          : const SizedBox(width: 24),
    );
  }
}

class _GlassSectionCard extends StatelessWidget {
  final _SectionData data;
  final VoidCallback onTap;

  const _GlassSectionCard({
    required this.data,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 5.0, sigmaY: 5.0),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            splashColor: const Color(0x22E3BD78),
            highlightColor: const Color(0x18E3BD78),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: context.isDark ? const Color(0xA91A100B) : const Color(0xE8FFFFFF),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: context.isDark ? const Color(0xD8E1C28C) : AppColors.lightDivider,
                  width: 1.5,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x66000000),
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _GoldIcon(data.icon),
                    const SizedBox(height: 10),
                    Text(
                      data.title,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFF1E6D2),
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        height: 1.35,
                        shadows: [
                          Shadow(
                            color: Colors.black,
                            blurRadius: 7,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      data.subtitle,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xD6DBCDB9),
                        fontSize: 11.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
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
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          center: Alignment(-0.25, -0.3),
          radius: 0.95,
          colors: [
            Color(0xFFFBE9B7),
            Color(0xFFD6AB57),
            Color(0xFF8E652D),
          ],
        ),
        border: Border.all(
          color: const Color(0xFFE7C77F),
          width: 1.0,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x8F000000),
            blurRadius: 12,
            offset: Offset(0, 7),
          ),
          BoxShadow(
            color: Color(0x665E3B10),
            blurRadius: 4,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Center(
        child: ShaderMask(
          shaderCallback: (rect) => const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFFFF1C6),
              Color(0xFFD5A956),
              Color(0xFF6E461C),
            ],
          ).createShader(rect),
          child: icon == Icons.support_agent_rounded
              ? const Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      Icons.phone_in_talk_rounded,
                      size: 43,
                      color: Colors.white,
                    ),
                    Positioned(
                      bottom: 6,
                      right: 7,
                      child: Icon(
                        Icons.balance_rounded,
                        size: 22,
                        color: Colors.white,
                      ),
                    ),
                  ],
                )
              : Icon(
                  icon,
                  size: 46,
                  color: Colors.white,
                  shadows: const [
                    Shadow(
                      color: Color(0xAA2A1808),
                      blurRadius: 5,
                      offset: Offset(1, 3),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _HomeFooter extends StatelessWidget {
  const _HomeFooter();

  @override
  Widget build(BuildContext context) {
    return Text(
      '${AppConstants.contactShortName} - ${AppConstants.contactTitleShort} - ${AppConstants.contactPhone}',
      textAlign: TextAlign.center,
      style: TextStyle(
        color: const Color(0xFFF0E4D0),
        fontSize: 15,
        fontWeight: FontWeight.w700,
        height: 1.4,
        shadows: [
          Shadow(color: context.isDark ? Colors.black : Colors.white, blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
    );
  }
}

class _SectionData {
  final IconData icon;
  final String title;
  final String subtitle;
  final WidgetBuilder builder;
  final bool fullWidth;

  const _SectionData({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.builder,
    this.fullWidth = false,
  });
}

class _LibraryBackground extends StatelessWidget {
  const _LibraryBackground();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _LibraryPainter(),
      child: const SizedBox.expand(),
    );
  }
}

class _LibraryPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    final background = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF2B170C),
          Color(0xFF1D0F08),
          Color(0xFF0D0907),
        ],
      ).createShader(rect);
    canvas.drawRect(rect, background);

    final panelPaint = Paint()..style = PaintingStyle.fill;
    final panelWidth = size.width / 8;
    for (int i = 0; i < 8; i++) {
      panelPaint.color =
          i.isEven ? const Color(0xFF3A1E0F) : const Color(0xFF2C160B);
      final x = i * panelWidth;
      canvas.drawRect(Rect.fromLTWH(x, 0, panelWidth - 2, size.height), panelPaint);
    }

    final seam = Paint()
      ..color = const Color(0x553D1F10)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += panelWidth) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), seam);
    }

    final shelf = Paint()
      ..color = const Color(0xFF170C07)
      ..style = PaintingStyle.fill;
    final shelfEdge = Paint()
      ..color = const Color(0x805B351A)
      ..style = PaintingStyle.fill;

    final shelfTop = size.height * 0.09;
    for (int row = 0; row < 7; row++) {
      final y = shelfTop + row * size.height * 0.14;
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 7), shelf);
      canvas.drawRect(Rect.fromLTWH(0, y + 7, size.width, 4), shelfEdge);
    }

    final bookColors = <Color>[
      const Color(0xFF6B3B1A),
      const Color(0xFF4A2B17),
      const Color(0xFF7A4B24),
      const Color(0xFF2C241D),
      const Color(0xFF5B2D18),
      const Color(0xFF8A5E32),
    ];
    final randomWidths = <double>[18, 25, 14, 29, 21, 17, 26];

    for (int row = 0; row < 7; row++) {
      final baseY = shelfTop + row * size.height * 0.14 - 2;
      var x = 8.0;
      var i = 0;
      while (x < size.width * 0.36) {
        final w = randomWidths[(i + row) % randomWidths.length];
        final h = 55.0 + ((i * 7 + row * 3) % 26);
        final p = Paint()..color = bookColors[(i + row) % bookColors.length];
        canvas.drawRect(Rect.fromLTWH(x, baseY - h, w, h), p);
        x += w + 3;
        i++;
      }

      x = size.width * 0.64;
      i = 0;
      while (x < size.width - 8) {
        final w = randomWidths[(i + 2 * row) % randomWidths.length];
        final h = 52.0 + ((i * 5 + row * 4) % 32);
        final p = Paint()..color = bookColors[(i + row + 2) % bookColors.length];
        canvas.drawRect(Rect.fromLTWH(x, baseY - h, w, h), p);
        x += w + 3;
        i++;
      }
    }

    final glowRect = Rect.fromCircle(
      center: Offset(size.width / 2, size.height * 0.57),
      radius: size.width * 0.55,
    );
    final glow = Paint()
      ..shader = const RadialGradient(
        colors: [
          Color(0x55D8A954),
          Color(0x16120B06),
          Color(0x00120B06),
        ],
      ).createShader(glowRect);
    canvas.drawCircle(
      Offset(size.width / 2, size.height * 0.57),
      size.width * 0.55,
      glow,
    );

    final cx = size.width / 2;
    final topY = size.height * 0.12;
    final baseY = size.height * 0.78;
    final brass = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFFF7DA91),
          Color(0xFFB57C33),
          Color(0xFF6D431A),
          Color(0xFFE8BE67),
        ],
      ).createShader(Rect.fromLTWH(cx - 5, topY, 10, baseY - topY));

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - 6, topY, 12, baseY - topY),
        const Radius.circular(8),
      ),
      brass,
    );

    final beamPaint = Paint()
      ..shader = const LinearGradient(
        colors: [
          Color(0xFFF5D78F),
          Color(0xFF8C5A22),
          Color(0xFFDDB05C),
        ],
      ).createShader(
        Rect.fromLTWH(cx - size.width * 0.34, topY, size.width * 0.68, 18),
      );

    final beam = Path()
      ..moveTo(cx - size.width * 0.30, topY + 20)
      ..quadraticBezierTo(cx, topY - 6, cx + size.width * 0.30, topY + 20)
      ..lineTo(cx + size.width * 0.28, topY + 31)
      ..quadraticBezierTo(cx, topY + 11, cx - size.width * 0.28, topY + 31)
      ..close();
    canvas.drawPath(beam, beamPaint);

    final panY = topY + 112;
    final leftPanX = cx - size.width * 0.26;
    final rightPanX = cx + size.width * 0.26;
    final panPaint = Paint()
      ..shader = const RadialGradient(
        colors: [
          Color(0xFFF1CA7A),
          Color(0xFF9A6223),
        ],
      ).createShader(
        Rect.fromCenter(center: const Offset(0, 0), width: 100, height: 60),
      );

    void drawPan(double x) {
      final chain = Paint()
        ..color = const Color(0xFFC8923D)
        ..strokeWidth = 2.2;
      canvas.drawLine(Offset(x, topY + 34), Offset(x, panY - 6), chain);
      canvas.drawLine(Offset(x - 34, topY + 48), Offset(x, panY - 2), chain);
      canvas.drawLine(Offset(x + 34, topY + 48), Offset(x, panY - 2), chain);

      final pan = Path()
        ..moveTo(x - 40, panY)
        ..quadraticBezierTo(x, panY + 23, x + 40, panY)
        ..lineTo(x + 33, panY + 11)
        ..quadraticBezierTo(x, panY + 27, x - 33, panY + 11)
        ..close();
      canvas.drawPath(pan, panPaint);
    }

    drawPan(leftPanX);
    drawPan(rightPanX);

    final base = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFFF3D78E),
          Color(0xFF8E5A22),
          Color(0xFF4F2E13),
        ],
      ).createShader(
        Rect.fromLTWH(cx - 75, baseY - 34, 150, 40),
      );

    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, baseY + 4), width: 152, height: 20),
      base,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - 16, baseY - 45, 32, 50),
        const Radius.circular(12),
      ),
      base,
    );

    final vignette = Paint()
      ..shader = const RadialGradient(
        center: Alignment(0, -0.05),
        radius: 0.92,
        colors: [
          Color(0x00110A06),
          Color(0x55110A06),
          Color(0xCC080604),
        ],
        stops: [0.40, 0.76, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, vignette);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
