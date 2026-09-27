import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/constants.dart';
import '../core/theme.dart';
import 'root_shell.dart';

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
        systemNavigationBarColor: Color(0xFF090A0B),
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF0A0B0C),
                Color(0xFF151311),
                Color(0xFF080909),
              ],
              stops: [0.0, 0.55, 1.0],
            ),
          ),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxHeight < 680;
                final horizontalPadding =
                    (constraints.maxWidth * 0.06).clamp(16.0, 32.0).toDouble();
                final availableWidth = (constraints.maxWidth -
                        horizontalPadding * 2)
                    .clamp(0.0, double.infinity);
                final logoSize = (availableWidth * 0.72)
                    .clamp(150.0, 270.0)
                    .toDouble();

                return Column(
                  children: [
                    Expanded(
                      child: Center(
                        child: SingleChildScrollView(
                          physics: const ClampingScrollPhysics(),
                          padding: EdgeInsets.symmetric(
                            horizontal: horizontalPadding,
                            vertical: compact ? 12 : 20,
                          ),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 520),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: logoSize,
                                  height: logoSize,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppColors.softGold
                                              .withValues(alpha: 0.16),
                                          blurRadius: 36,
                                          spreadRadius: 6,
                                        ),
                                        BoxShadow(
                                          color:
                                              Colors.black.withValues(alpha: 0.65),
                                          blurRadius: 22,
                                          offset: const Offset(0, 10),
                                        ),
                                      ],
                                    ),
                                    child: Padding(
                                      padding:
                                          EdgeInsets.all(logoSize * 0.04),
                                      child: Image.asset(
                                        'assets/icon/app_icon.png',
                                        fit: BoxFit.contain,
                                        filterQuality: FilterQuality.high,
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(height: compact ? 10 : 16),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: const Text(
                                    AppConstants.appNameAr,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Color(0xFFE5C77D),
                                      fontSize: 29,
                                      fontWeight: FontWeight.w800,
                                      height: 1.12,
                                      letterSpacing: 0.1,
                                      shadows: [
                                        Shadow(
                                          color: Colors.black87,
                                          blurRadius: 12,
                                          offset: Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: const Text(
                                    AppConstants.appNameEn,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Color(0xFFD4C29A),
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                      letterSpacing: 0.7,
                                    ),
                                  ),
                                ),
                                SizedBox(height: compact ? 14 : 20),
                                SizedBox(
                                  width: (availableWidth * 0.52).clamp(
                                    130.0,
                                    180.0,
                                  ),
                                  height: 4,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(99),
                                    child: const LinearProgressIndicator(
                                      minHeight: 4,
                                      backgroundColor: Color(0x332F2B24),
                                      valueColor:
                                          AlwaysStoppedAnimation<Color>(
                                        AppColors.antiqueBronze,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        horizontalPadding,
                        8,
                        horizontalPadding,
                        compact ? 10 : 18,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'أسامة المقبلي',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFFE5C77D),
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              shadows: [
                                Shadow(
                                  color: Colors.black87,
                                  blurRadius: 8,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 5),
                          const Text(
                            'حقوق الطبع محفوظة 2026',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFFA9A092),
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
