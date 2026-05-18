import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:provider/provider.dart';
import '../utils/storage.dart';
import '../utils/background_tracking_prep.dart';
import '../utils/session_manager.dart';
import '../services/duty_resume_service.dart';
import '../services/tracking_service.dart';
import '../widgets/app_logo.dart';
import 'login_screen.dart';
import 'dashboard_screen.dart';
import 'tracking_setup_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // Outer ring — slow spin
  late AnimationController _ringSlowCtrl;
  // Inner ring — faster, opposite direction
  late AnimationController _ringFastCtrl;
  // Logo scale + fade
  late AnimationController _logoCtrl;
  late Animation<double> _logoScale;
  late Animation<double> _logoOpacity;
  // Text slide + fade
  late AnimationController _textCtrl;
  late Animation<Offset> _textSlide;
  late Animation<double> _textFade;

  @override
  void initState() {
    super.initState();

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    // Spinning rings — loop forever
    _ringSlowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();

    _ringFastCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    // Logo appears at 300ms
    _logoCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _logoScale = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _logoCtrl, curve: Curves.elasticOut),
    );
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
          parent: _logoCtrl,
          curve: const Interval(0.0, 0.5, curve: Curves.easeIn)),
    );

    // Text appears 500ms after logo
    _textCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _textSlide = Tween<Offset>(
      begin: const Offset(0, 0.4),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _textCtrl, curve: Curves.easeOutCubic));
    _textFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _textCtrl, curve: Curves.easeIn),
    );

    // Data loading starts immediately — parallel with animation
    _navFuture = _loadNavData();
    _runSequence();
  }

  late Future<_NavData> _navFuture;

  Future<void> _runSequence() async {
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    _logoCtrl.forward();

    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    _textCtrl.forward();

    // Wait for animation window AND data — whichever finishes last
    await Future.wait([
      Future.delayed(const Duration(milliseconds: 1800)),
      _navFuture,
    ]);
    if (!mounted) return;
    _doNavigate(await _navFuture);
  }

  // Loads all data needed for navigation — runs in parallel with animation
  Future<_NavData> _loadNavData() async {
    final token = await Storage.getToken();
    if (token == null || token.isEmpty) return const _NavData(token: null);

    final sessionOk = await SessionManager.validateSingleDeviceSession();
    if (!sessionOk) return const _NavData(token: null, sessionInvalid: true);

    final activeDutyLogId = await Storage.getActiveDutyLogId();
    final activeDeploymentId = await Storage.getActiveDeploymentId();

    return _NavData(
      token: token,
      activeDutyLogId: activeDutyLogId,
      activeDeploymentId: activeDeploymentId,
    );
  }

  Future<void> _doNavigate(_NavData data) async {
    if (data.sessionInvalid) return; // SessionManager already redirected

    if (data.token == null) {
      Navigator.pushReplacement(context, _fadeRoute(const LoginScreen()));
      return;
    }

    final trackingService =
        Provider.of<TrackingService>(context, listen: false);
    await trackingService.configureAuthenticatedSession(token: data.token!);
    DutyResumeCandidate? candidate;
    if (mounted) {
      try {
        candidate = await DutyResumeService.findMountedDuty(
          data.token!,
          preferredDeploymentId: data.activeDeploymentId,
          preferredDutyLogId: data.activeDutyLogId,
        );
        if (candidate == null) {
          await trackingService.stopTracking('inactive_duty');
        }
      } catch (_) {
        await trackingService.stopTracking('inactive_duty');
      }
    }

    if (!mounted) return;
    final setupStatus = await readTrackingSetupStatus();
    if (!mounted) return;
    if (!setupStatus.isComplete) {
      Navigator.pushReplacement(
        context,
        _fadeRoute(
          TrackingSetupScreen(
            onSetupComplete: () async {
              final mountedDuty = candidate;
              if (mountedDuty == null) {
                return;
              }
              await trackingService.startTracking(
                mountedDuty.dutyLogId,
                data.token!,
                deploymentId: mountedDuty.deploymentId,
              );
            },
          ),
        ),
      );
      return;
    }

    if (candidate != null) {
      await trackingService.startTracking(
        candidate.dutyLogId,
        data.token!,
        deploymentId: candidate.deploymentId,
      );
    }
    if (!mounted) return;
    Navigator.pushReplacement(context, _fadeRoute(const DashboardScreen()));
  }

  // Smooth fade transition — no jarring slide
  PageRouteBuilder<void> _fadeRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (_, __, ___) => page,
      transitionDuration: const Duration(milliseconds: 500),
      transitionsBuilder: (_, animation, __, child) =>
          FadeTransition(opacity: animation, child: child),
    );
  }

  @override
  void dispose() {
    _ringSlowCtrl.dispose();
    _ringFastCtrl.dispose();
    _logoCtrl.dispose();
    _textCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF060E1E),
              Color(0xFF0D1F4A),
              Color(0xFF1A2B7A),
              Color(0xFF7B1111),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: [0.0, 0.35, 0.65, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // ── Glow blob top-right
            Positioned(
              top: -100,
              right: -80,
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF2563EB).withValues(alpha: 0.18),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            // ── Glow blob bottom-left
            Positioned(
              bottom: -80,
              left: -60,
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFFB91C1C).withValues(alpha: 0.2),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // ── Center content
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Spinning rings + logo
                  SizedBox(
                    width: 300,
                    height: 300,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Outer ring — slow clockwise, gold tint
                        AnimatedBuilder(
                          animation: _ringSlowCtrl,
                          builder: (_, __) => Transform.rotate(
                            angle: _ringSlowCtrl.value * 2 * math.pi,
                            child: CustomPaint(
                              size: const Size(300, 300),
                              painter: _DashedRingPainter(
                                color: const Color(0xFFD4AF37)
                                    .withValues(alpha: 0.5),
                                strokeWidth: 2,
                                dashCount: 20,
                                gapRatio: 0.42,
                              ),
                            ),
                          ),
                        ),
                        // Middle ring — faster counter-clockwise, blue
                        AnimatedBuilder(
                          animation: _ringFastCtrl,
                          builder: (_, __) => Transform.rotate(
                            angle: -_ringFastCtrl.value * 2 * math.pi,
                            child: CustomPaint(
                              size: const Size(252, 252),
                              painter: _DashedRingPainter(
                                color: const Color(0xFF2563EB)
                                    .withValues(alpha: 0.55),
                                strokeWidth: 1.5,
                                dashCount: 12,
                                gapRatio: 0.5,
                              ),
                            ),
                          ),
                        ),
                        // Soft glow behind logo
                        Container(
                          width: 200,
                          height: 200,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                const Color(0xFFD4AF37).withValues(alpha: 0.12),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                        // Logo — full badge, no clip
                        AnimatedBuilder(
                          animation: _logoCtrl,
                          builder: (_, __) => FadeTransition(
                            opacity: _logoOpacity,
                            child: ScaleTransition(
                              scale: _logoScale,
                              child: const AppLogo(
                                size: 190,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 28),

                  // ── Text
                  SlideTransition(
                    position: _textSlide,
                    child: FadeTransition(
                      opacity: _textFade,
                      child: Column(
                        children: [
                          const SizedBox(height: 6),
                          // Divider line with gradient
                          Container(
                            width: 160,
                            height: 1.5,
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.transparent,
                                  Color(0xFF2563EB),
                                  Color(0xFFEF4444),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'RAILWAY PROTECTION FORCE',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.55),
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Bottom dots loader
            Positioned(
              bottom: 44,
              left: 0,
              right: 0,
              child: FadeTransition(
                opacity: _textFade,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(3, (i) {
                    return AnimatedBuilder(
                      animation: _ringFastCtrl,
                      builder: (_, __) {
                        final phase = (_ringFastCtrl.value + i * 0.33) % 1.0;
                        final opacity =
                            (math.sin(phase * math.pi)).clamp(0.2, 1.0);
                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: opacity),
                          ),
                        );
                      },
                    );
                  }),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Custom painter for dashed ring
class _DashedRingPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final int dashCount;
  final double gapRatio;

  const _DashedRingPainter({
    required this.color,
    required this.strokeWidth,
    required this.dashCount,
    required this.gapRatio,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - strokeWidth;

    const fullCircle = 2 * math.pi;
    final dashAngle = (fullCircle / dashCount) * (1 - gapRatio);
    final gapAngle = (fullCircle / dashCount) * gapRatio;

    double startAngle = -math.pi / 2;
    for (int i = 0; i < dashCount; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        dashAngle,
        false,
        paint,
      );
      startAngle += dashAngle + gapAngle;
    }
  }

  @override
  bool shouldRepaint(_DashedRingPainter old) =>
      old.color != color || old.strokeWidth != strokeWidth;
}

class _NavData {
  final String? token;
  final bool sessionInvalid;
  final int? activeDutyLogId;
  final int? activeDeploymentId;

  const _NavData({
    required this.token,
    this.sessionInvalid = false,
    this.activeDutyLogId,
    this.activeDeploymentId,
  });
}
