import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/constants.dart';
import 'root_shell.dart';

/// شاشة الترحيب الرئيسية.
///
/// التصميم مبني كواجهة كاملة: خلفية المكتبة + تعتيم + ضبابية زجاجية
/// + هوية بصرية + مراحل تحميل + شريط تقدم متحرك.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _timer;

  static const _orange = Color(0xFFFF5A2A);
  static const _gold = Color(0xFFE8B84E);
  static const _white = Color(0xFFF7F2E9);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..forward();
    _timer = Timer(const Duration(milliseconds: 2700), _openHome);
  }

  void _openHome() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const RootShell()),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.black,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final h = constraints.maxHeight;
            final w = constraints.maxWidth;
            final compact = h < 720;
            final logoSize = compact ? 74.0 : 92.0;
            final cardWidth = (w - 72).clamp(280.0, 570.0);

            return Stack(
              fit: StackFit.expand,
              children: [
                const _LibraryBackground(),
                const _DarkOverlay(),
                SafeArea(
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) {
                      return Column(
                        children: [
                          SizedBox(height: compact ? 48 : h * .13),
                          _BrandHeader(
                            logoSize: logoSize,
                            orange: _orange,
                            white: _white,
                            gold: _gold,
                          ),
                          SizedBox(height: compact ? 28 : h * .045),
                          SizedBox(
                            width: cardWidth,
                            child: _StartupCard(
                              progress: _controller.value,
                              compact: compact,
                              orange: _orange,
                              gold: _gold,
                            ),
                          ),
                          const Spacer(),
                          _LoadingStatus(
                            progress: _controller.value,
                            compact: compact,
                            white: _white,
                          ),
                          SizedBox(height: compact ? 42 : h * .09),
                          _Copyright(white: _white, compact: compact),
                          SizedBox(height: compact ? 18 : 30),
                        ],
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LibraryBackground extends StatelessWidget {
  const _LibraryBackground();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/splash.jpg',
      fit: BoxFit.cover,
      alignment: Alignment.center,
      filterQuality: FilterQuality.high,
    );
  }
}

class _DarkOverlay extends StatelessWidget {
  const _DarkOverlay();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: .66),
            Colors.black.withValues(alpha: .54),
            Colors.black.withValues(alpha: .76),
          ],
        ),
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader({
    required this.logoSize,
    required this.orange,
    required this.white,
    required this.gold,
  });

  final double logoSize;
  final Color orange;
  final Color white;
  final Color gold;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: logoSize + 28,
          height: logoSize + 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: orange.withValues(alpha: .20),
                blurRadius: 34,
                spreadRadius: 8,
              ),
            ],
          ),
          child: Icon(Icons.gavel_rounded, color: orange, size: logoSize),
        ),
        Container(
          width: logoSize * .76,
          height: 5,
          margin: const EdgeInsets.only(top: 2),
          decoration: BoxDecoration(
            color: orange,
            borderRadius: BorderRadius.circular(99),
            boxShadow: [
              BoxShadow(
                color: orange.withValues(alpha: .42),
                blurRadius: 12,
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Text(
          AppConstants.appNameAr,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: white,
            fontSize: 25,
            fontWeight: FontWeight.w800,
            height: 1.15,
            shadows: const [Shadow(color: Colors.black87, blurRadius: 12)],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .22),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: gold, width: 1.5),
            boxShadow: [
              BoxShadow(color: gold.withValues(alpha: .16), blurRadius: 12),
            ],
          ),
          child: Text(
            'PRO  النسخة الاحترافية',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: gold,
              fontSize: 14,
              fontWeight: FontWeight.w800,
              letterSpacing: .2,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'إصدار 1.0.0',
          style: TextStyle(
            color: white.withValues(alpha: .50),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _StartupCard extends StatelessWidget {
  const _StartupCard({
    required this.progress,
    required this.compact,
    required this.orange,
    required this.gold,
  });

  final double progress;
  final bool compact;
  final Color orange;
  final Color gold;

  @override
  Widget build(BuildContext context) {
    const stages = [
      'الاتصال بالنظام السحابي',
      'إنشاء نفق اتصال آمن',
      'تهيئة قاعدة البيانات',
      'فحص الاتصال والنشاط',
      'تجهيز واجهة المستخدم',
    ];
    final active = (progress * stages.length)
        .floor()
        .clamp(0, stages.length - 1);

    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 22 : 28,
            vertical: compact ? 20 : 24,
          ),
          decoration: BoxDecoration(
            color: const Color(0xCC0D0C0B),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: Colors.white.withValues(alpha: .15),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .42),
                blurRadius: 30,
                offset: const Offset(0, 12),
              ),
              BoxShadow(
                color: gold.withValues(alpha: .035),
                blurRadius: 45,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            children: [
              for (var i = 0; i < stages.length; i++)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: compact ? 7 : 9),
                  child: _StartupStage(
                    title: stages[i],
                    active: i == active,
                    completed: i < active,
                    orange: orange,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StartupStage extends StatelessWidget {
  const _StartupStage({
    required this.title,
    required this.active,
    required this.completed,
    required this.orange,
  });

  final String title;
  final bool active;
  final bool completed;
  final Color orange;

  @override
  Widget build(BuildContext context) {
    final textColor = active
        ? const Color(0xFFEAB64D)
        : Colors.white.withValues(alpha: .43);

    return Row(
      textDirection: TextDirection.rtl,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: 23,
          height: 23,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: active || completed
                  ? orange.withValues(alpha: .85)
                  : Colors.white.withValues(alpha: .28),
              width: 2,
            ),
            color: completed
                ? orange.withValues(alpha: .18)
                : Colors.transparent,
            boxShadow: active
                ? [
                    BoxShadow(
                      color: orange.withValues(alpha: .22),
                      blurRadius: 10,
                    ),
                  ]
                : null,
          ),
          child: completed
              ? Icon(Icons.check_rounded, size: 14, color: orange)
              : null,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            title,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: textColor,
              fontSize: 16,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              height: 1.25,
            ),
          ),
        ),
        if (active)
          Container(
            width: 4,
            height: 4,
            margin: const EdgeInsets.only(left: 3),
            decoration: BoxDecoration(
              color: orange,
              borderRadius: BorderRadius.circular(99),
              boxShadow: [BoxShadow(color: orange, blurRadius: 7)],
            ),
          ),
      ],
    );
  }
}

class _LoadingStatus extends StatelessWidget {
  const _LoadingStatus({
    required this.progress,
    required this.compact,
    required this.white,
  });

  final double progress;
  final bool compact;
  final Color white;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: (MediaQuery.sizeOf(context).width - 176).clamp(230.0, 430.0),
          height: 7,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .15),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Align(
            alignment: Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: progress.clamp(.04, 1),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFFF5A2A),
                  borderRadius: BorderRadius.circular(99),
                  boxShadow: const [
                    BoxShadow(color: Color(0x99FF5A2A), blurRadius: 9),
                  ],
                ),
              ),
            ),
          ),
        ),
        SizedBox(height: compact ? 20 : 26),
        Text(
          'جاري فحص المسارات الآمنة...',
          style: TextStyle(
            color: white.withValues(alpha: .72),
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _Copyright extends StatelessWidget {
  const _Copyright({required this.white, required this.compact});

  final Color white;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          '© 2026  جميع الحقوق محفوظة',
          style: TextStyle(
            color: white.withValues(alpha: .48),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (!compact) const SizedBox(height: 8),
        Text(
          AppConstants.appNameAr,
          style: TextStyle(color: white.withValues(alpha: .38), fontSize: 11),
        ),
      ],
    );
  }
}
