import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/storage.dart';
import '../services/api_service.dart';
import 'duty_detail_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Design tokens (same as duty_detail_screen)
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

class TodayDutyScreen extends StatefulWidget {
  const TodayDutyScreen({super.key});

  @override
  State<TodayDutyScreen> createState() => _TodayDutyScreenState();
}

class _TodayDutyScreenState extends State<TodayDutyScreen> {
  late Future<List<dynamic>> _dutiesFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _dutiesFuture = Storage.getToken().then((token) async {
        return ApiService.getDutyList(token!);
      });
    });
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
            child: FutureBuilder<List<dynamic>>(
              future: _dutiesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: _C.indigo),
                        const SizedBox(height: 14),
                        const Text("Loading duties...",
                            style: TextStyle(color: _C.textSec, fontSize: 14)),
                      ],
                    ),
                  );
                }

                if (snapshot.hasError) {
                  return _buildError(snapshot.error.toString());
                }

                final duties = snapshot.data ?? [];

                if (duties.isEmpty) {
                  return _buildEmpty();
                }

                return RefreshIndicator(
                  onRefresh: () async => _load(),
                  color: _C.indigo,
                  child: ListView.builder(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    itemCount: duties.length,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _DutyCard(
                          item: duties[index],
                          isDark: isDark,
                          onReturn: _load,
                        ),
                      );
                    },
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
    final now = DateTime.now();
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final dateStr =
        "${days[now.weekday - 1]}, ${now.day} ${months[now.month - 1]} ${now.year}";

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
          8, MediaQuery.of(context).padding.top + 8, 16, 24),
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
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios_new,
                color: Colors.white, size: 18),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Duty",
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3)),
                const SizedBox(height: 2),
                Text(dateStr,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 12)),
              ],
            ),
          ),
          // Refresh
          GestureDetector(
            onTap: _load,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.refresh_rounded,
                  color: Colors.white, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  // ── Empty state ───────────────────────────────────────────────────────────
  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: _C.indigo.withValues(alpha: 0.07),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.event_busy_rounded,
                  size: 48, color: _C.indigo.withValues(alpha: 0.5)),
            ),
            const SizedBox(height: 20),
            const Text("No Duties Found",
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: _C.textPri)),
            const SizedBox(height: 8),
            const Text("You have no duty assignments for the selected period.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: _C.textSec)),
          ],
        ),
      ),
    );
  }

  // ── Error state ───────────────────────────────────────────────────────────
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
                  color: _C.danger.withValues(alpha: 0.1),
                  shape: BoxShape.circle),
              child: Icon(Icons.wifi_off_rounded, color: _C.danger, size: 40),
            ),
            const SizedBox(height: 16),
            const Text("Could not load duties",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(msg,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _C.textSec, fontSize: 13)),
            const SizedBox(height: 20),
            SizedBox(
              width: 140,
              child: ElevatedButton.icon(
                onPressed: _load,
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
}

// ─────────────────────────────────────────────────────────────────────────────
// Duty Card Widget
// ─────────────────────────────────────────────────────────────────────────────
class _DutyCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final bool isDark;
  final VoidCallback onReturn;

  const _DutyCard(
      {required this.item, required this.isDark, required this.onReturn});

  Color _statusColor(String c) {
    switch (c) {
      case 'green':
        return _C.success;
      case 'blue':
        return _C.indigo;
      case 'purple':
        return _C.purple;
      case 'orange':
        return _C.warning;
      default:
        return _C.textSec;
    }
  }

  IconData _statusIcon(int status) {
    switch (status) {
      case 0:
        return Icons.login_rounded;
      case 1:
        return Icons.verified_user_outlined;
      case 2:
        return Icons.directions_run_rounded;
      case 3:
        return Icons.pause_circle_outline;
      case 4:
        return Icons.task_alt_rounded;
      default:
        return Icons.help_outline;
    }
  }

  int? _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  String _firstText(List<Object?> values, {String fallback = '-'}) {
    for (final value in values) {
      final text = value?.toString().trim();
      if (text != null && text.isNotEmpty) return text;
    }
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    final dep = item['deployment'] as Map<String, dynamic>? ?? {};
    final ui = item['ui'] as Map<String, dynamic>? ?? {};
    final beat = dep['beat'] as Map? ?? {};
    final shift = dep['shift'] as Map? ?? {};

    final statusLabel = _firstText(
      [ui['status_label'], item['status_label']],
      fallback: 'Pending',
    );
    final statusColorStr = _firstText(
      [ui['status_color'], item['status_color']],
      fallback: 'orange',
    );
    final statusVal = _readInt(ui['status'] ?? item['status']) ?? 0;
    final color = _statusColor(statusColorStr);

    final deploymentId = _readInt(dep['id'] ?? item['deployment_id']);
    final dutyDate = _firstText([dep['duty_date'], item['duty_date']]);
    final startTime = _firstText(
      [dep['start_time'], item['start_time'], item['duty_start_time']],
      fallback: '',
    );
    final endTime = _firstText(
      [dep['end_time'], item['end_time'], item['duty_end_time']],
      fallback: '',
    );
    final beatName =
        _firstText([beat['name'], item['beat_name'], item['name']]);
    final shiftName = _firstText([shift['name'], item['shift_name']]);

    void openDetail() {
      if (deploymentId == null) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DutyDetailScreen(deploymentId: deploymentId),
        ),
      ).then((_) => onReturn());
    }

    return GestureDetector(
      onTap: deploymentId == null ? null : openDetail,
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? _C.cardDark : _C.cardLight,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: isDark ? Colors.white12 : _C.border),
          boxShadow: isDark
              ? []
              : [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 4))
                ],
        ),
        child: Column(
          children: [
            // ── Top colored strip ──────────────────────────────────────────
            Container(
              height: 4,
              decoration: BoxDecoration(
                color: color,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(18)),
              ),
            ),

            // ── Card body ─────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Row 1: Beat name + status badge
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Beat / Patrol",
                          style: TextStyle(
                              color: _C.textSec,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.5)),
                      const SizedBox(height: 3),
                      Text(
                        beatName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: isDark ? Colors.white : _C.textPri,
                            fontSize: 15,
                            fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(14),
                          border:
                              Border.all(color: color.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 1),
                              child: Icon(
                                _statusIcon(statusVal),
                                color: color,
                                size: 13,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                statusLabel,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: color,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  height: 1.2,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),
                  Divider(
                      color: isDark ? Colors.white12 : _C.border, height: 1),
                  const SizedBox(height: 12),

                  // Row 2: Info chips
                  Row(
                    children: [
                      _chip(isDark, Icons.calendar_today_outlined, dutyDate),
                      const SizedBox(width: 12),
                      _chip(isDark, Icons.access_time_rounded, shiftName),
                      const SizedBox(width: 12),
                      _chip(isDark, Icons.schedule_rounded,
                          "$startTime–$endTime"),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // Row 3: View details button
                  SizedBox(
                    width: double.infinity,
                    height: 42,
                    child: ElevatedButton.icon(
                      onPressed: deploymentId == null ? null : openDetail,
                      icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                      label: Text(
                        deploymentId == null
                            ? "Details Unavailable"
                            : "View Duty",
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: color,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(bool isDark, IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: _C.textSec),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                color: isDark ? Colors.white70 : _C.textSec,
                fontSize: 11,
                fontWeight: FontWeight.w500)),
      ],
    );
  }
}
