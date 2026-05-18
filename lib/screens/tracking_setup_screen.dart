import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';

import '../services/device_settings_service.dart';
import '../utils/background_tracking_prep.dart';
import 'dashboard_screen.dart';

class TrackingSetupScreen extends StatefulWidget {
  static bool isVisible = false;

  final Future<void> Function()? onSetupComplete;
  final bool returnResult;

  const TrackingSetupScreen({
    super.key,
    this.onSetupComplete,
    this.returnResult = false,
  });

  @override
  State<TrackingSetupScreen> createState() => _TrackingSetupScreenState();
}

class _TrackingSetupScreenState extends State<TrackingSetupScreen>
    with WidgetsBindingObserver {
  TrackingSetupStatus? _status;
  bool _loading = true;
  bool _continuing = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    TrackingSetupScreen.isVisible = true;
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refreshStatus(autoContinue: true));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    TrackingSetupScreen.isVisible = false;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshStatus(autoContinue: true));
    }
  }

  Future<void> _refreshStatus({bool autoContinue = false}) async {
    setState(() {
      _loading = true;
      _message = null;
    });
    final status = await readTrackingSetupStatus();
    if (!mounted) {
      return;
    }
    setState(() {
      _status = status;
      _loading = false;
    });
    if (autoContinue && status.isComplete) {
      unawaited(_continue());
    }
  }

  Future<void> _continue() async {
    if (_continuing) {
      return;
    }
    final status = _status ?? await readTrackingSetupStatus();
    if (!status.isComplete) {
      setState(() {
        _message =
            'The app will continue after all tracking checks are complete.';
      });
      return;
    }

    setState(() {
      _continuing = true;
      _message = null;
    });
    await widget.onSetupComplete?.call();
    if (!mounted) {
      return;
    }
    if (widget.returnResult) {
      Navigator.pop(context, true);
      return;
    }
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const DashboardScreen()),
    );
  }

  Future<void> _handleNotification() async {
    final permission =
        await FlutterForegroundTask.requestNotificationPermission();
    if (permission != NotificationPermission.granted) {
      await DeviceSettingsService.openNotificationSettings();
    }
    await Future.delayed(const Duration(milliseconds: 500));
    await _refreshStatus();
  }

  Future<void> _handleLocationPermission() async {
    final permission = await Geolocator.checkPermission();
    if (permission != LocationPermission.always) {
      final opened = await DeviceSettingsService.openAppDetailsSettings();
      if (!opened) {
        await Geolocator.openAppSettings();
      }
    }
    await Future.delayed(const Duration(milliseconds: 500));
    await _refreshStatus();
  }

  Future<void> _handleLocationService() async {
    await Geolocator.openLocationSettings();
    await Future.delayed(const Duration(milliseconds: 500));
    await _refreshStatus();
  }

  Future<void> _handleBattery() async {
    await DeviceSettingsService.requestIgnoreBatteryOptimizations();
    await Future.delayed(const Duration(milliseconds: 700));
    await _refreshStatus();
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final allReady = status?.isComplete ?? false;

    return PopScope(
      canPop: widget.returnResult,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !widget.returnResult) {
          setState(() {
            _message = 'Complete the setup to continue.';
          });
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F6FA),
        body: SafeArea(
          child: Column(
            children: [
              _Header(complete: allReady),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () => _refreshStatus(),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                    children: [
                      _SetupRow(
                        title: 'Notification permission',
                        subtitle:
                            'Keeps the foreground tracking notification visible.',
                        icon: Icons.notifications_active_rounded,
                        complete: status?.notificationAllowed ?? false,
                        loading: _loading,
                        actionLabel: 'Allow',
                        onPressed: _handleNotification,
                      ),
                      const SizedBox(height: 10),
                      _SetupRow(
                        title: 'All-time location',
                        subtitle:
                            'Open Permissions > Location and choose Allow all the time.',
                        icon: Icons.location_on_rounded,
                        complete: status?.locationAlwaysAllowed ?? false,
                        loading: _loading,
                        actionLabel: 'Open',
                        onPressed: _handleLocationPermission,
                      ),
                      const SizedBox(height: 10),
                      _SetupRow(
                        title: 'Phone location switch',
                        subtitle: 'Turn on the phone GPS/Location switch.',
                        icon: Icons.gps_fixed_rounded,
                        complete: status?.locationServiceEnabled ?? false,
                        loading: _loading,
                        actionLabel: 'Turn on',
                        onPressed: _handleLocationService,
                      ),
                      const SizedBox(height: 10),
                      _SetupRow(
                        title: 'Battery unrestricted',
                        subtitle:
                            'Allow unrestricted battery usage from the system popup.',
                        icon: Icons.battery_saver_rounded,
                        complete: status?.batteryUnrestricted ?? false,
                        loading: _loading,
                        actionLabel: 'Allow',
                        onPressed: _handleBattery,
                      ),
                      if (_message != null) ...[
                        const SizedBox(height: 14),
                        Text(
                          _message!,
                          style: const TextStyle(
                            color: Color(0xFFB42318),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: allReady && !_continuing ? _continue : null,
                    icon: _continuing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.arrow_forward_rounded),
                    label: Text(allReady ? 'Continue' : 'Complete setup'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E3A8A),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFFD0D5DD),
                      disabledForegroundColor: const Color(0xFF667085),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final bool complete;

  const _Header({required this.complete});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1E3A8A), Color(0xFFB91C1C)],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(22),
          bottomRight: Radius.circular(22),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              complete ? Icons.verified_rounded : Icons.security_rounded,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tracking setup',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'The app continues once every check turns green.',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SetupRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool complete;
  final bool loading;
  final String actionLabel;
  final Future<void> Function() onPressed;

  const _SetupRow({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.complete,
    required this.loading,
    required this.actionLabel,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final color = complete ? const Color(0xFF039855) : const Color(0xFFB42318);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: complete ? const Color(0xFFA6F4C5) : const Color(0xFFFECDCA),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF101828),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF667085),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (loading)
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (complete)
            const Icon(Icons.check_circle_rounded, color: Color(0xFF039855))
          else
            TextButton(
              onPressed: onPressed,
              child: Text(actionLabel),
            ),
        ],
      ),
    );
  }
}
