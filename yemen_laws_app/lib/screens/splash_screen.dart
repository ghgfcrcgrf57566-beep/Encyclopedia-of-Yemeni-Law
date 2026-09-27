import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/constants.dart';
import 'root_shell.dart';

/// شاشة ترحيبية مرسومة بالكامل داخل Flutter؛ لا تعتمد على صورة منخفضة الدقة.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 2400), _openHome);
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
        backgroundColor: const Color(0xFF121416),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxHeight < 700;
              return Stack(
                children: [
                  const _SplashGlow(),
                  Center(
                    child: SingleChildScrollView(
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(height: compact ? 8 : 28),
                          SizedBox(
                            width: compact ? 190 : 245,
                            height: compact ? 190 : 245,
                            child: const CustomPaint(painter: _ScalesPainter()),
                          ),
                          SizedBox(height: compact ? 18 : 30),
                          const Text(
                            AppConstants.appNameAr,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFFE7C77A),
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              height: 1.25,
                              shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
                            ),
                          ),
                          const SizedBox(height: 7),
                          const Text(
                            'Yemen Law Encyclopedia',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFFD8C4A0),
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              letterSpacing: .2,
                            ),
                          ),
                          SizedBox(height: compact ? 34 : 56),
                          const _LoadingBar(),
                          SizedBox(height: compact ? 32 : 58),
                          const Text(
                            AppConstants.contactName,
                            style: TextStyle(
                              color: Color(0xFFDCC79E),
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            '${AppConstants.contactPhone}  •  ${AppConstants.contactTitleShort}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Color(0xFFBDAA8A),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            AppConstants.copyrightText,
                            style: TextStyle(color: Colors.white38, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SplashGlow extends StatelessWidget {
  const _SplashGlow();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -.18),
            radius: 1.05,
            colors: const [Color(0x243D3425), Color(0x00121416)],
            stops: const [0, .72],
          ),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _LoadingBar extends StatelessWidget {
  const _LoadingBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      height: 12,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: const Color(0xFF292A28),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: const Color(0xFFB08D57), width: 1.2),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 8)],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: const LinearProgressIndicator(
          minHeight: 7,
          backgroundColor: Colors.transparent,
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE3BD70)),
        ),
      ),
    );
  }
}

class _ScalesPainter extends CustomPainter {
  const _ScalesPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 245;
    canvas.scale(scale);
    final gold = Paint()
      ..color = const Color(0xFFD2A957)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = const Color(0xFFD2A957);
    final shadow = Paint()..color = const Color(0x55000000);

    canvas.drawOval(const Rect.fromLTWH(48, 207, 149, 14), shadow);
    canvas.drawOval(const Rect.fromLTWH(58, 196, 129, 20), fill);
    canvas.drawRRect(const RRect.fromRectAndRadius(Rect.fromLTWH(116, 71, 13, 131), Radius.circular(6)), fill);
    canvas.drawCircle(const Offset(122.5, 58), 9, fill);
    canvas.drawLine(const Offset(47, 64), const Offset(198, 64), gold);
    canvas.drawLine(const Offset(122.5, 33), const Offset(122.5, 64), gold);
    canvas.drawLine(const Offset(47, 64), const Offset(47, 119), gold);
    canvas.drawLine(const Offset(198, 64), const Offset(198, 119), gold);
    canvas.drawLine(const Offset(47, 64), const Offset(23, 119), gold);
    canvas.drawLine(const Offset(47, 64), const Offset(71, 119), gold);
    canvas.drawLine(const Offset(198, 64), const Offset(174, 119), gold);
    canvas.drawLine(const Offset(198, 64), const Offset(222, 119), gold);
    canvas.drawOval(const Rect.fromLTWH(16, 116, 62, 15), gold);
    canvas.drawOval(const Rect.fromLTWH(167, 116, 62, 15), gold);
    canvas.drawPath(Path()..moveTo(82, 64)..quadraticBezierTo(122, 42, 163, 64), gold);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
