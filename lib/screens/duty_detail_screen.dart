import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../models/active_duty_geofence.dart';
import '../utils/storage.dart';
import '../utils/app_error_message.dart';
import '../utils/background_tracking_prep.dart';
import '../utils/location_sampler.dart';
import '../services/api_service.dart';
import '../services/tracking_service.dart';
import 'duty_location_map_screen.dart';
import 'tracking_setup_screen.dart';
import 'package:geolocator/geolocator.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Location helper
// ─────────────────────────────────────────────────────────────────────────────
Future<Position> getLocation() async {
  bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled)
    throw Exception("GPS is off. Please enable location services.");

  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied)
    permission = await Geolocator.requestPermission();
  if (permission == LocationPermission.deniedForever)
    throw Exception(
        "Location permission is permanently denied. Please allow it from Settings.");
  if (permission == LocationPermission.denied)
    throw Exception("Location permission was not granted.");

  // 20 s per sample: gives GPS chip time to warm up and get a real fix
  // instead of falling back to the inaccurate network/WiFi location.
  return LocationSampler.getBestEffortPosition(
    perSampleTimeout: const Duration(seconds: 20),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Design tokens
// ─────────────────────────────────────────────────────────────────────────────
class _C {
  static const navy = Color(0xFF1A2B4A);
  static const navyLight = Color(0xFF243660);
  static const indigo = Color(0xFF3B5BDB);
  static const success = Color(0xFF12B76A);
  static const warning = Color(0xFFF79009);
  static const danger = Color(0xFFF04438);
  static const purple = Color(0xFF7C3AED);
  static const bgLight = Color(0xFFF8FAFC);
  static const cardLight = Colors.white;
  static const textPri = Color(0xFF101828);
  static const textSec = Color(0xFF667085);
  static const border = Color(0xFFE4E7EC);
  static const bgDark = Color(0xFF0D1B2E);
  static const cardDark = Color(0xFF1A2B4A);
}

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────
class DutyDetailScreen extends StatefulWidget {
  final int deploymentId;
  const DutyDetailScreen({super.key, required this.deploymentId});

  @override
  State<DutyDetailScreen> createState() => _DutyDetailScreenState();
}

class _DutyDetailScreenState extends State<DutyDetailScreen> {
  bool _showActivityForm = false;
  bool _loading = false;
  bool _savingActivity = false;
  bool _checkingGeo = false;
  late Future<Map<String, dynamic>> _dutyFuture;
  Map<String, dynamic>? _lastDutyData;
  Position? _localPosition;
  String? _geoStatusMessage;

  // Activity form state
  List<Map<String, dynamic>> _categories = [];
  Map<String, dynamic>? _selectedCat;
  Map<String, dynamic>? _selectedSub;
  final _remarkCtrl = TextEditingController();
  File? _activityPhoto;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadDuty();
  }

  void _loadDuty() {
    // Build the future OUTSIDE setState — setState callback must be synchronous
    final future = Storage.getToken().then((token) async {
      final detail =
          await ApiService.getDutyDetail(token!, widget.deploymentId);
      final deployment =
          detail['deployment'] as Map<String, dynamic>? ?? const {};
      await Storage.saveActiveDutyGeofence(
        ActiveDutyGeofence.fromDeployment(deployment),
      );
      // Auto-start tracking if duty is already mounted and tracking is not active
      final status = (detail['current_log']?['status'] as int?) ?? 0;
      final logId = (detail['current_log']?['id'] as num?)?.toInt();
      if (status == 2 && logId != null && mounted) {
        final tracking = Provider.of<TrackingService>(context, listen: false);
        final setupReady = await _ensureTrackingSetup(
          onSetupComplete: () => tracking.startTracking(
            logId,
            token,
            deploymentId: widget.deploymentId,
          ),
        );
        if (!setupReady || !mounted) {
          return detail;
        }
        if (!tracking.isActive) {
          tracking.startTracking(
            logId,
            token,
            deploymentId: widget.deploymentId,
          );
        }
      }
      return detail;
    });
    future.then((detail) {
      if (!mounted) {
        return;
      }
      _lastDutyData = detail;
      unawaited(_refreshLocalGeo(detail));
    });
    setState(() {
      _dutyFuture = future;
    });
  }

  Future<void> _refreshLocalGeo([Map<String, dynamic>? detail]) async {
    final source = detail ?? _lastDutyData;
    if (source == null || _checkingGeo) {
      return;
    }

    setState(() {
      _checkingGeo = true;
      _geoStatusMessage = null;
    });

    try {
      final pos = await getLocation();
      if (!mounted) {
        return;
      }
      setState(() {
        _localPosition = pos;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _geoStatusMessage = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _checkingGeo = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    return Scaffold(
      backgroundColor: isDark ? _C.bgDark : _C.bgLight,
      body: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: FutureBuilder<Map<String, dynamic>>(
              future: _dutyFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: _C.indigo),
                        const SizedBox(height: 14),
                        Text("Loading duty...",
                            style: TextStyle(color: _C.textSec, fontSize: 14)),
                      ],
                    ),
                  );
                }

                if (snapshot.hasError) {
                  return _buildError(snapshot.error.toString());
                }

                final data = snapshot.data!;
                final deployment =
                    data['deployment'] as Map<String, dynamic>? ?? {};
                final log = data['current_log'] as Map<String, dynamic>?;
                final status = (log?['status'] as int?) ?? 0;
                final activities = data['activities'] as List<dynamic>? ?? [];
                final hasActivities = activities.isNotEmpty;

                return SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildDeploymentCard(isDark, deployment, status),
                      const SizedBox(height: 16),
                      _buildStatusCard(isDark, log, status),
                      const SizedBox(height: 16),
                      _buildStepProgress(isDark, status),
                      const SizedBox(height: 20),
                      _buildActionButton(status),
                      const SizedBox(height: 16),
                      if (status == 2)
                        _buildActivitySection(isDark, log?['id'] as int? ?? 0),
                      if (status >= 2 || hasActivities)
                        _buildActivityHistory(isDark, activities),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
          8, MediaQuery.of(context).padding.top + 8, 16, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_C.navy, _C.navyLight],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
        boxShadow: [
          BoxShadow(
              color: Color(0x301A2B4A), blurRadius: 20, offset: Offset(0, 6)),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios_new,
                color: Colors.white, size: 18),
          ),
          const SizedBox(width: 4),
          const Text("Duty Details",
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3)),
          const Spacer(),
          _buildRefreshBtn(),
        ],
      ),
    );
  }

  Widget _buildRefreshBtn() {
    return GestureDetector(
      onTap: _loadDuty,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.refresh_rounded, color: Colors.white, size: 18),
      ),
    );
  }

  // ── Error State ───────────────────────────────────────────────────────────
  Widget _buildError(String msg) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _C.danger.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.wifi_off_rounded, color: _C.danger, size: 40),
            ),
            const SizedBox(height: 16),
            const Text("Something went wrong",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(msg,
                textAlign: TextAlign.center,
                style: TextStyle(color: _C.textSec, fontSize: 13)),
            const SizedBox(height: 20),
            SizedBox(
              width: 140,
              child: ElevatedButton.icon(
                onPressed: _loadDuty,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text("Retry"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _C.indigo,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Deployment Info Card ──────────────────────────────────────────────────
  Widget _buildDeploymentCard(
      bool isDark, Map<String, dynamic> dep, int status) {
    final beat = dep['beat'] as Map? ?? {};
    final post = dep['post'] as Map? ?? {};
    final shift = dep['shift'] as Map? ?? {};
    final geoSummary = _buildGeoSummary(dep);

    return _card(
      isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _C.indigo.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.shield_outlined,
                    color: _C.indigo, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Beat / Patrol Area",
                        style: TextStyle(
                            color: _C.textSec,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.5)),
                    const SizedBox(height: 2),
                    Text(beat['name'] ?? "-",
                        style: TextStyle(
                            color: isDark ? Colors.white : _C.textPri,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ],
          ),
          if (post['name'] != null || shift['name'] != null) ...[
            const SizedBox(height: 14),
            Divider(color: isDark ? Colors.white12 : _C.border, height: 1),
            const SizedBox(height: 14),
            Row(
              children: [
                if (post['name'] != null)
                  Expanded(
                      child: _infoChip(isDark, Icons.location_on_outlined,
                          "Post", post['name'])),
                if (shift['name'] != null)
                  Expanded(
                      child: _infoChip(isDark, Icons.access_time_rounded,
                          "Shift", shift['name'])),
              ],
            ),
          ],
          if (dep['duty_date'] != null) ...[
            const SizedBox(height: 12),
            _infoRow(isDark, Icons.calendar_today_outlined, "Date",
                "${dep['duty_date']}  •  ${dep['start_time'] ?? ''} – ${dep['end_time'] ?? ''}"),
          ],
          const SizedBox(height: 14),
          Divider(color: isDark ? Colors.white12 : _C.border, height: 1),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.05) : _C.bgLight,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: isDark ? Colors.white12 : _C.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Location Map",
                        style: TextStyle(
                          color: isDark ? Colors.white : _C.textPri,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _geoStatusMessage ??
                            geoSummary.messageForStatus(status) ??
                            "View post, beat & your location.",
                        style: TextStyle(
                          color: isDark ? Colors.white70 : _C.textSec,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () => _openLocationMap(dep),
                  icon: const Icon(Icons.map_outlined, size: 18),
                  label: const Text("View Map"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _C.indigo,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoChip(bool isDark, IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 14, color: _C.textSec),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    color: _C.textSec,
                    fontSize: 10,
                    fontWeight: FontWeight.w500)),
            Text(value,
                style: TextStyle(
                    color: isDark ? Colors.white : _C.textPri,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ],
    );
  }

  Widget _infoRow(bool isDark, IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 14, color: _C.textSec),
        const SizedBox(width: 8),
        Text("$label: ", style: TextStyle(color: _C.textSec, fontSize: 12)),
        Text(value,
            style: TextStyle(
                color: isDark ? Colors.white70 : _C.textPri,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      ],
    );
  }

  // ── Status Card ───────────────────────────────────────────────────────────
  Widget _buildStatusCard(bool isDark, Map<String, dynamic>? log, int status) {
    final configs = [
      {
        'label': 'Pending Login',
        'icon': Icons.login_rounded,
        'color': _C.warning
      },
      {
        'label': 'Logged In',
        'icon': Icons.verified_user_outlined,
        'color': _C.indigo
      },
      {
        'label': 'On Duty',
        'icon': Icons.directions_run_rounded,
        'color': _C.success
      },
      {
        'label': 'Dismounted',
        'icon': Icons.pause_circle_outline,
        'color': _C.purple
      },
      {
        'label': 'Completed',
        'icon': Icons.task_alt_rounded,
        'color': _C.success
      },
    ];

    final cfg = configs[status.clamp(0, 4)];
    final color = cfg['color'] as Color;
    final icon = cfg['icon'] as IconData;
    final label = cfg['label'] as String;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Current Status",
                    style: TextStyle(
                        color: _C.textSec,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.4)),
                const SizedBox(height: 2),
                Text(label,
                    style: TextStyle(
                        color: color,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          if (log?['login_time'] != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text("Login",
                    style: TextStyle(color: _C.textSec, fontSize: 10)),
                Text(_formatTime(log!['login_time']),
                    style: TextStyle(
                        color: isDark ? Colors.white : _C.textPri,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ],
            ),
        ],
      ),
    );
  }

  // ── Step Progress ─────────────────────────────────────────────────────────
  Widget _buildStepProgress(bool isDark, int status) {
    return _card(
      isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Duty Progress",
              style: TextStyle(
                  color: _C.textSec,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5)),
          const SizedBox(height: 16),
          Row(
            children: [
              _stepDot("Login", stepIndex: 0, status: status, isDark: isDark),
              _stepConnector(status >= 1),
              _stepDot("Mount", stepIndex: 1, status: status, isDark: isDark),
              _stepConnector(status >= 2),
              _stepDot("Dismount",
                  stepIndex: 2, status: status, isDark: isDark),
              _stepConnector(status >= 3),
              _stepDot("Logout", stepIndex: 3, status: status, isDark: isDark),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stepDot(String label,
      {required int stepIndex, required int status, required bool isDark}) {
    final bool done = status > stepIndex;
    final bool active = status == stepIndex;

    Color color;
    Widget inner;

    if (done) {
      color = _C.success;
      inner = const Icon(Icons.check_rounded, color: Colors.white, size: 14);
    } else if (active) {
      color = _C.warning;
      inner = Container(
          width: 8,
          height: 8,
          decoration:
              const BoxDecoration(color: Colors.white, shape: BoxShape.circle));
    } else {
      color = isDark ? const Color(0xFF374151) : _C.border;
      inner = Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
              color: isDark ? Colors.white24 : _C.textSec.withOpacity(0.3),
              shape: BoxShape.circle));
    }

    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          width: 36,
          height: 36,
          decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: done || active
                  ? [
                      BoxShadow(
                          color: color.withOpacity(0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 3))
                    ]
                  : []),
          child: Center(child: inner),
        ),
        const SizedBox(height: 6),
        Text(label,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: done ? _C.success : (active ? _C.warning : _C.textSec))),
      ],
    );
  }

  Widget _stepConnector(bool filled) {
    return Expanded(
      child: Container(
        height: 3,
        margin: const EdgeInsets.only(bottom: 22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(2),
          color: filled ? _C.success : _C.border,
        ),
      ),
    );
  }

  // ── Action Button ─────────────────────────────────────────────────────────
  Widget _buildActionButton(int status) {
    if (status >= 4) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _C.success.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _C.success.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.task_alt_rounded, color: _C.success, size: 22),
            const SizedBox(width: 10),
            const Text("Duty Completed",
                style: TextStyle(
                    color: _C.success,
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      );
    }

    final configs = {
      0: {
        'label': 'Duty Login',
        'icon': Icons.login_rounded,
        'color': _C.indigo
      },
      1: {
        'label': 'Mount Duty',
        'icon': Icons.directions_run_rounded,
        'color': _C.warning
      },
      2: {
        'label': 'Dismount Duty',
        'icon': Icons.pause_circle_outline,
        'color': _C.danger
      },
      3: {
        'label': 'Duty Logout',
        'icon': Icons.logout_rounded,
        'color': _C.success
      },
    };

    final cfg = configs[status]!;
    final color = cfg['color'] as Color;
    final label = cfg['label'] as String;
    final icon = cfg['icon'] as IconData;

    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton.icon(
        onPressed: _loading ? null : () => _handleAction(status),
        icon: _loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2))
            : Icon(icon, size: 20),
        label: Text(_loading ? "Processing..." : label,
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 0.3)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          disabledBackgroundColor: color.withOpacity(0.5),
          elevation: 0,
          shadowColor: color.withOpacity(0.4),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ).copyWith(
          elevation: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.pressed) ? 0 : 4),
        ),
      ),
    );
  }

  // ── Force GPS on before mount ─────────────────────────────────────────────
  // Returns true if GPS is now enabled, false if user cancelled
  // ── Action Handler ────────────────────────────────────────────────────────
  Future<void> _handleAction(int status) async {
    setState(() => _loading = true);
    try {
      final token = await Storage.getToken();
      if (token == null)
        throw Exception("Session expired. Please login again.");
      final deployment =
          _lastDutyData?['deployment'] as Map<String, dynamic>? ?? const {};

      if (status == 0) {
        // Duty Login
        final pos = await _getValidatedPositionForAction(status, deployment);
        await ApiService.loginDuty(
            token, widget.deploymentId, pos.latitude, pos.longitude);
      } else if (status == 1) {
        // Mount — force GPS on, then mount, then start tracking
        if (!mounted) return;
        final setupReady = await _ensureTrackingSetup();
        if (!setupReady) {
          if (mounted) {
            _showSnack(
              'Complete tracking setup before continuing mount duty.',
              isError: true,
            );
          }
          return;
        }
        if (!mounted) return;
        final pos = await _getValidatedPositionForAction(status, deployment);
        final mountData = await ApiService.mountDuty(
            token, widget.deploymentId, pos.latitude, pos.longitude);
        final logId = _extractDutyLogId(mountData);
        await Storage.saveActiveDutyGeofence(
          ActiveDutyGeofence.fromDeployment(deployment),
        );

        if (logId != null && mounted) {
          final tracking = Provider.of<TrackingService>(context, listen: false);
          await tracking.startTracking(
            logId,
            token,
            deploymentId: widget.deploymentId,
          );
        }

        _loadDuty();
        return;
      } else if (status == 2) {
        // Dismount — local beat check first, then stop tracking + API
        final pos = await _getValidatedPositionForAction(status, deployment);
        if (mounted) {
          final tracking = Provider.of<TrackingService>(context, listen: false);
          unawaited(
            tracking.stopTracking(
              'dismounted',
              waitForCompletion: false,
            ),
          );
        }
        await ApiService.dismountDuty(
            token, widget.deploymentId, pos.latitude, pos.longitude);
      } else if (status == 3) {
        // Duty Logout — local post check first, then stop tracking + API
        final pos = await _getValidatedPositionForAction(status, deployment);
        if (mounted) {
          final tracking = Provider.of<TrackingService>(context, listen: false);
          unawaited(
            tracking.stopTracking(
              'logged_out',
              waitForCompletion: false,
            ),
          );
        }
        await ApiService.logoutDuty(
            token, widget.deploymentId, pos.latitude, pos.longitude);
      }

      _loadDuty();
    } catch (e) {
      if (mounted) {
        _showSnack(userFriendlyErrorMessage(e), isError: true);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _ensureTrackingSetup({
    Future<void> Function()? onSetupComplete,
  }) async {
    final setupStatus = await readTrackingSetupStatus();
    if (setupStatus.isComplete) {
      await onSetupComplete?.call();
      return true;
    }
    if (!mounted) {
      return false;
    }

    final ready = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => TrackingSetupScreen(
          returnResult: true,
          onSetupComplete: onSetupComplete,
        ),
      ),
    );
    return ready == true;
  }

  Future<Position> _getValidatedPositionForAction(
    int status,
    Map<String, dynamic> deployment,
  ) async {
    final position = await getLocation();
    if (mounted) {
      setState(() {
        _localPosition = position;
        _geoStatusMessage = null;
      });
    } else {
      _localPosition = position;
      _geoStatusMessage = null;
    }

    final localCheck = _runLocalGateCheck(
      status,
      deployment,
      positionOverride: position,
    );
    if (localCheck != null) {
      throw Exception(localCheck);
    }
    return position;
  }

  int? _extractDutyLogId(Map<String, dynamic> payload) {
    final candidates = [
      payload['duty_log_id'],
      payload['log_id'],
      payload['current_log_id'],
      (payload['current_log'] as Map<String, dynamic>?)?['id'],
      (payload['log'] as Map<String, dynamic>?)?['id'],
      (payload['item'] as Map<String, dynamic>?)?['duty_log_id'],
    ];

    for (final candidate in candidates) {
      final id = (candidate as num?)?.toInt();
      if (id != null && id > 0) {
        return id;
      }
    }
    return null;
  }

  String? _runLocalGateCheck(
    int status,
    Map<String, dynamic> deployment, {
    Position? positionOverride,
  }) {
    final position = positionOverride ?? _localPosition;
    if (position == null) {
      return null;
    }

    final summary = _buildGeoSummary(
      deployment,
      positionOverride: position,
    );
    if (status == 0 && !summary.postOk && summary.postMessage != null) {
      return summary.postMessage;
    }
    if (status == 1 && !summary.beatOk && summary.beatMessage != null) {
      return summary.beatMessage;
    }
    if (status == 2 && !summary.beatOk && summary.beatMessage != null) {
      return summary.beatMessage;
    }
    if (status == 3 && !summary.postOk && summary.postMessage != null) {
      return summary.postMessage;
    }
    return null;
  }

  void _openLocationMap(Map<String, dynamic> deployment) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DutyLocationMapScreen(
          deployment: deployment,
          currentLog: _lastDutyData?['current_log'] as Map<String, dynamic>?,
          userLatitude: _localPosition?.latitude,
          userLongitude: _localPosition?.longitude,
        ),
      ),
    );
  }

  _GeoSummary _buildGeoSummary(
    Map<String, dynamic> deployment, {
    Position? positionOverride,
  }) {
    final flags = deployment['flags'] as Map<String, dynamic>? ?? const {};
    final post = deployment['post'] as Map<String, dynamic>? ?? const {};
    final beat = deployment['beat'] as Map<String, dynamic>? ?? const {};
    final position = positionOverride ?? _localPosition;

    String? postMessage;
    var postOk = true;
    if ((flags['is_post_location_req'] as num?)?.toInt() == 1 &&
        position != null &&
        post.isNotEmpty) {
      final postLat = _asDouble(post['latitude'] ?? post['lat']);
      final postLng = _asDouble(post['longitude'] ?? post['lng']);
      final postRadius = _asDouble(post['radius_meter'] ?? post['radius']);
      if (postLat != null && postLng != null && postRadius != null) {
        final distance = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          postLat,
          postLng,
        );
        postOk = distance <= postRadius;
        postMessage = postOk
            ? '${distance.round()}m from post · within ${postRadius.round()}m limit'
            : '${distance.round()}m from post · limit ${postRadius.round()}m';
      }
    }

    String? beatMessage;
    var beatOk = true;
    if ((flags['is_mount_location_req'] as num?)?.toInt() == 1 &&
        position != null &&
        beat.isNotEmpty) {
      final locationType =
          beat['location_type']?.toString().toLowerCase() ?? 'circle';
      if (locationType == 'polygon') {
        final corners = (beat['polygon_corners'] as List?) ?? const [];
        final inside = _isInsidePolygon(position, corners);
        beatOk = inside;
        beatMessage = inside
            ? 'Inside beat area.'
            : 'Outside beat area. Reach the assigned beat to continue.';
      } else if (locationType == 'polyline') {
        final points = (beat['polyline_points'] as List?) ?? const [];
        final beatRadius = _asDouble(beat['radius_meter'] ?? beat['radius']);
        final distance = _distanceToPolyline(position, points);
        if (distance != null && beatRadius != null) {
          beatOk = distance <= beatRadius;
          beatMessage = beatOk
              ? '${distance.round()}m from beat · within ${beatRadius.round()}m limit'
              : '${distance.round()}m from beat · limit ${beatRadius.round()}m';
        }
      } else {
        final beatLat = _asDouble(beat['latitude'] ?? beat['lat']);
        final beatLng = _asDouble(beat['longitude'] ?? beat['lng']);
        final beatRadius = _asDouble(beat['radius_meter'] ?? beat['radius']);
        if (beatLat != null && beatLng != null && beatRadius != null) {
          final distance = Geolocator.distanceBetween(
            position.latitude,
            position.longitude,
            beatLat,
            beatLng,
          );
          beatOk = distance <= beatRadius;
          beatMessage = beatOk
              ? '${distance.round()}m from beat · within ${beatRadius.round()}m limit'
              : '${distance.round()}m from beat · limit ${beatRadius.round()}m';
        }
      }
    }

    return _GeoSummary(
      postOk: postOk,
      postMessage: postMessage,
      beatOk: beatOk,
      beatMessage: beatMessage,
    );
  }

  bool _isInsidePolygon(Position position, List corners) {
    final points = corners
        .whereType<Map>()
        .map((corner) {
          final lat = _asDouble(corner['latitude'] ?? corner['lat']);
          final lng = _asDouble(corner['longitude'] ?? corner['lng']);
          if (lat == null || lng == null) {
            return null;
          }
          return Offset(lng, lat);
        })
        .whereType<Offset>()
        .toList();

    if (points.length < 3) {
      return false;
    }

    final testX = position.longitude;
    final testY = position.latitude;
    var inside = false;

    for (int i = 0, j = points.length - 1; i < points.length; j = i++) {
      final xi = points[i].dx;
      final yi = points[i].dy;
      final xj = points[j].dx;
      final yj = points[j].dy;

      final intersect = ((yi > testY) != (yj > testY)) &&
          (testX <
              (xj - xi) *
                      (testY - yi) /
                      ((yj - yi).abs() < 1e-12 ? 1e-12 : (yj - yi)) +
                  xi);

      if (intersect) {
        inside = !inside;
      }
    }

    return inside;
  }

  double? _distanceToPolyline(Position position, List points) {
    final linePoints = points
        .whereType<Map>()
        .map((point) {
          final lat = _asDouble(point['latitude'] ?? point['lat']);
          final lng = _asDouble(point['longitude'] ?? point['lng']);
          if (lat == null || lng == null) {
            return null;
          }
          return _GeoPoint(lat, lng);
        })
        .whereType<_GeoPoint>()
        .toList();

    if (linePoints.length < 2) {
      return null;
    }

    double? best;
    for (var i = 0; i < linePoints.length - 1; i++) {
      final start = linePoints[i];
      final end = linePoints[i + 1];
      final distance = ActiveDutyGeofence.distanceToSegmentMeters(
        position.latitude,
        position.longitude,
        start.latitude,
        start.longitude,
        end.latitude,
        end.longitude,
      );
      if (best == null || distance < best) {
        best = distance;
      }
    }
    return best;
  }

  double? _asDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '');
  }

  // ── Activity Section ──────────────────────────────────────────────────────
  Widget _buildActivitySection(bool isDark, int dutyLogId) {
    return Column(
      children: [
        _card(
          isDark,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _C.indigo.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.add_task_rounded,
                        color: _C.indigo, size: 18),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text("Activity Entry",
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700)),
                  ),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _showActivityForm = !_showActivityForm;
                        if (!_showActivityForm) _resetActivityForm();
                      });
                      if (_showActivityForm && _categories.isEmpty) {
                        _loadCategories();
                      }
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: _showActivityForm
                            ? _C.danger.withOpacity(0.1)
                            : _C.indigo.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        _showActivityForm
                            ? Icons.close_rounded
                            : Icons.add_rounded,
                        color: _showActivityForm ? _C.danger : _C.indigo,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),

              // Form
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 300),
                crossFadeState: _showActivityForm
                    ? CrossFadeState.showFirst
                    : CrossFadeState.showSecond,
                firstChild: _buildActivityForm(isDark, dutyLogId),
                secondChild: const SizedBox.shrink(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  // ── Load categories from API ───────────────────────────────────────────────
  Future<void> _loadCategories() async {
    try {
      final token = await Storage.getToken();
      if (token == null) return;
      final list = await ApiService.getActivityCategories(token);
      if (mounted) {
        setState(() {
          _categories = list.cast<Map<String, dynamic>>();
        });
      }
    } catch (_) {}
  }

  void _resetActivityForm() {
    _selectedCat = null;
    _selectedSub = null;
    _activityPhoto = null;
    _remarkCtrl.clear();
  }

  // ── Activity Form (real dropdowns + camera) ────────────────────────────────
  Widget _buildActivityForm(bool isDark, int dutyLogId) {
    final List<Map<String, dynamic>> subList = (_selectedCat != null)
        ? (_selectedCat!['subs'] as List? ?? []).cast<Map<String, dynamic>>()
        : [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Divider(color: isDark ? Colors.white12 : _C.border, height: 1),
        const SizedBox(height: 16),

        // ── Camera / Photo ──────────────────────────────────────────────────
        if (_activityPhoto != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(_activityPhoto!,
                width: double.infinity, height: 180, fit: BoxFit.cover),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickPhoto,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text("Retake"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _C.indigo,
                    side: const BorderSide(color: _C.indigo),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _activityPhoto = null),
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text("Remove"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _C.danger,
                    side: const BorderSide(color: _C.danger),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ] else
          OutlinedButton.icon(
            onPressed: _pickPhoto,
            icon: const Icon(Icons.camera_alt_outlined, size: 18),
            label: const Text("Open Camera  (optional)"),
            style: OutlinedButton.styleFrom(
              foregroundColor: _C.indigo,
              side: const BorderSide(color: _C.indigo),
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),

        const SizedBox(height: 14),

        // ── Select Activity dropdown ────────────────────────────────────────
        _buildDropdown<Map<String, dynamic>>(
          isDark: isDark,
          hint:
              _categories.isEmpty ? "Loading activities..." : "Select Activity",
          value: _selectedCat,
          items: _categories,
          labelBuilder: (c) => c['name'] as String? ?? '',
          onChanged: _categories.isEmpty
              ? null
              : (val) => setState(() {
                    _selectedCat = val;
                    _selectedSub = null; // sub reset
                  }),
        ),

        const SizedBox(height: 10),

        // ── Select Sub Activity dropdown ────────────────────────────────────
        _buildDropdown<Map<String, dynamic>>(
          isDark: isDark,
          hint: _selectedCat == null
              ? "Select activity first"
              : subList.isEmpty
                  ? "No sub-activities"
                  : "Select Sub Activity",
          value: _selectedSub,
          items: subList,
          labelBuilder: (s) => s['name'] as String? ?? '',
          onChanged: subList.isEmpty
              ? null
              : (val) => setState(() => _selectedSub = val),
        ),

        const SizedBox(height: 10),

        // ── Remark ─────────────────────────────────────────────────────────
        TextField(
          controller: _remarkCtrl,
          maxLines: 3,
          style: TextStyle(
              color: isDark ? Colors.white : _C.textPri, fontSize: 14),
          decoration: InputDecoration(
            hintText: "Enter remark...",
            hintStyle: const TextStyle(color: _C.textSec, fontSize: 13),
            filled: true,
            fillColor: isDark ? Colors.white.withOpacity(0.05) : _C.bgLight,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _C.border)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _C.border)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _C.indigo, width: 1.5)),
            contentPadding: const EdgeInsets.all(14),
          ),
        ),

        const SizedBox(height: 14),

        // ── Save button ─────────────────────────────────────────────────────
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: (_savingActivity ||
                    _selectedCat == null ||
                    _selectedSub == null)
                ? null
                : () => _saveActivity(dutyLogId),
            style: ElevatedButton.styleFrom(
              backgroundColor: _C.indigo,
              foregroundColor: Colors.white,
              disabledBackgroundColor: _C.indigo.withOpacity(0.4),
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: _savingActivity
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Text("Save Activity",
                    style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  // ── Dropdown builder ───────────────────────────────────────────────────────
  Widget _buildDropdown<T>({
    required bool isDark,
    required String hint,
    required T? value,
    required List<T> items,
    required String Function(T) labelBuilder,
    required ValueChanged<T?>? onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : _C.bgLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: value != null ? _C.indigo : _C.border,
            width: value != null ? 1.5 : 1),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          hint: Text(hint,
              style: const TextStyle(color: _C.textSec, fontSize: 13)),
          isExpanded: true,
          dropdownColor: isDark ? const Color(0xFF1F2937) : Colors.white,
          icon:
              const Icon(Icons.keyboard_arrow_down_rounded, color: _C.textSec),
          style: TextStyle(
              color: isDark ? Colors.white : _C.textPri,
              fontSize: 14,
              fontWeight: FontWeight.w500),
          onChanged: onChanged,
          items: items
              .map((item) => DropdownMenuItem<T>(
                    value: item,
                    child: Text(labelBuilder(item)),
                  ))
              .toList(),
        ),
      ),
    );
  }

  // ── Camera ─────────────────────────────────────────────────────────────────
  Future<void> _pickPhoto() async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 80,
        maxWidth: 1280,
      );
      if (photo != null && mounted) {
        setState(() => _activityPhoto = File(photo.path));
      }
    } catch (e) {
      if (mounted) {
        _showSnack(userFriendlyErrorMessage(e), isError: true);
      }
    }
  }

  // ── Save Activity ──────────────────────────────────────────────────────────
  Future<void> _saveActivity(int dutyLogId) async {
    if (_selectedCat == null) {
      _showSnack("Select an activity.", isError: true);
      return;
    }
    if (_selectedSub == null) {
      _showSnack("Select a sub-activity.", isError: true);
      return;
    }
    setState(() => _savingActivity = true);
    try {
      final token = await Storage.getToken();
      if (token == null) throw Exception("Session expired");

      // GPS required by server
      final pos = await getLocation();

      await ApiService.saveActivityLog(
        token: token,
        dutyLogId: dutyLogId,
        mainCategoryId: _selectedCat!['id'] as int,
        subCategoryId: _selectedSub!['id'] as int,
        latitude: pos.latitude,
        longitude: pos.longitude,
        remarks: _remarkCtrl.text.trim(),
        photoPath: _activityPhoto?.path,
      );

      if (mounted) {
        _showSnack("Activity saved successfully!");
        setState(() {
          _showActivityForm = false;
          _resetActivityForm();
        });
        _loadDuty(); // history refresh
      }
    } catch (e) {
      if (mounted) {
        _showSnack(
          userFriendlyErrorMessage(e, action: 'activity_upload'),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _savingActivity = false);
    }
  }

  // ── Activity History ──────────────────────────────────────────────────────
  Widget _buildActivityHistory(bool isDark, List<dynamic> activities) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Row(
            children: [
              const Icon(Icons.history_rounded, size: 16, color: _C.textSec),
              const SizedBox(width: 6),
              Text("Activity History",
                  style: TextStyle(
                      color: _C.textSec,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5)),
              const Spacer(),
              Text("${activities.length} records",
                  style: TextStyle(color: _C.textSec, fontSize: 11)),
            ],
          ),
        ),
        if (activities.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isDark ? _C.cardDark : _C.cardLight,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isDark ? Colors.white12 : _C.border),
            ),
            child: Column(
              children: [
                Icon(Icons.inbox_outlined,
                    size: 36, color: _C.textSec.withOpacity(0.4)),
                const SizedBox(height: 8),
                Text("No activities recorded",
                    style: TextStyle(color: _C.textSec, fontSize: 13)),
              ],
            ),
          )
        else
          ...activities.asMap().entries.map((e) {
            final a = e.value as Map;
            final title = (a['activity_name'] ??
                    a['sub_activity_name'] ??
                    a['sub_category_name'] ??
                    a['main_category_name'] ??
                    a['category_name'] ??
                    a['name'] ??
                    "Activity")
                .toString();
            final remark = (a['remark'] ?? a['remarks'] ?? '').toString();
            final photoUrl = _resolvePhotoUrl(a);
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? _C.cardDark : _C.cardLight,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: isDark ? Colors.white12 : _C.border),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _C.success.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.task_alt_rounded,
                        color: _C.success, size: 16),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: TextStyle(
                                color: isDark ? Colors.white : _C.textPri,
                                fontSize: 14,
                                fontWeight: FontWeight.w600)),
                        if (remark.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(remark,
                              style:
                                  TextStyle(color: _C.textSec, fontSize: 12)),
                        ],
                        if (photoUrl.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed: () => _showPhotoDialog(photoUrl),
                            icon: const Icon(Icons.remove_red_eye_outlined,
                                size: 18),
                            label: const Text("View Photo"),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _C.indigo,
                              side: const BorderSide(color: _C.indigo),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  Widget _card(bool isDark, {required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? _C.cardDark : _C.cardLight,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isDark ? Colors.white12 : _C.border),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 4))
              ],
      ),
      child: child,
    );
  }

  String _formatTime(String? iso) {
    if (iso == null) return "-";
    try {
      final dt = DateTime.parse(iso).toLocal();
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return "$h:$m";
    } catch (_) {
      return "-";
    }
  }

  String _resolvePhotoUrl(Map activity) {
    final raw = (activity['photo_url'] ?? activity['photo_path'] ?? '')
        .toString()
        .trim();
    if (raw.isEmpty) return '';
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return raw;
    }

    final normalized = raw.startsWith('storage/')
        ? raw
        : raw.startsWith('/')
            ? raw.substring(1)
            : 'storage/$raw';

    final base = ApiService.baseUrl.replaceFirst('/api', '');
    return '$base/public/$normalized';
  }

  void _showPhotoDialog(String photoUrl) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              InteractiveViewer(
                minScale: 0.8,
                maxScale: 4,
                child: Image.network(
                  photoUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Container(
                    padding: const EdgeInsets.all(24),
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text("Photo could not be loaded"),
                        const SizedBox(height: 12),
                        SelectableText(
                          photoUrl,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 10,
                right: 10,
                child: Material(
                  color: Colors.black54,
                  shape: const CircleBorder(),
                  child: IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(isError ? Icons.error_outline : Icons.check_circle_outline,
                color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(msg, style: const TextStyle(fontSize: 13))),
          ],
        ),
        backgroundColor: isError ? _C.danger : _C.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }
}

class _GeoSummary {
  final bool postOk;
  final String? postMessage;
  final bool beatOk;
  final String? beatMessage;

  const _GeoSummary({
    required this.postOk,
    required this.postMessage,
    required this.beatOk,
    required this.beatMessage,
  });

  String? get primaryMessage => beatMessage ?? postMessage;

  // status 0/3 = post required (login/logout); status 1/2 = beat required (mount/dismount)
  String? messageForStatus(int status) {
    switch (status) {
      case 0:
      case 3:
        return postMessage ?? beatMessage;
      case 1:
      case 2:
        return beatMessage ?? postMessage;
      default:
        return primaryMessage;
    }
  }
}

class _GeoPoint {
  final double latitude;
  final double longitude;

  const _GeoPoint(this.latitude, this.longitude);
}
