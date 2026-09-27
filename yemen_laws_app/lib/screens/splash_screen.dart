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
                final logoSize = (constraints.maxWidth * 0.54)
                    .clamp(180.0, 270.0)
                    .toDouble();

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      const Spacer(flex: 2),
                      SizedBox(
                        width: logoSize,
                        height: logoSize,
                        child: Center(
                          child: Container(
                            width: logoSize * 0.92,
                            height: logoSize * 0.92,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.softGold.withValues(alpha: 0.16),
                                  blurRadius: 42,
                                  spreadRadius: 8,
                                ),
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.65),
                                  blurRadius: 24,
                                  offset: const Offset(0, 12),
                                ),
                              ],
                            ),
                            child: Image.asset(
                              'assets/icon/app_icon.jpg',
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.high,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: compact ? 12 : 18),
                      const Text(
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
                      const SizedBox(height: 7),
                      const Text(
                        AppConstants.appNameEn,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFFD4C29A),
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.7,
                        ),
                      ),
                      SizedBox(height: compact ? 16 : 22),
                      SizedBox(
                        width: 180,
                        height: 4,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: const LinearProgressIndicator(
                            minHeight: 4,
                            backgroundColor: Color(0x332F2B24),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              AppColors.antiqueBronze,
                            ),
                          ),
                        ),
                      ),
                      const Spacer(flex: 3),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              AppConstants.contactShortName,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Color(0xFFE0D6C5),
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${AppConstants.contactTitleShort} • ${AppConstants.contactPhone}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFFC9C0AF),
                                fontSize: 11.5,
                              ),
                            ),
                            const SizedBox(height: 7),
                            const Text(
                              'حقوق الطبع محفوظة 2026',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Color(0xFFA9A092),
                                fontSize: 10.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
