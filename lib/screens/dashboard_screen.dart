import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/user_profile.dart';
import '../models/beat_sector_models.dart';
import '../services/api_service.dart';
import '../services/network_status_service.dart';
import '../services/duty_reminder_service.dart';
import '../services/duty_resume_service.dart';
import '../services/tracking_service.dart';
import '../utils/background_tracking_prep.dart';
import '../utils/session_manager.dart';
import '../utils/storage.dart';
import '../utils/theme_provider.dart';
import '../widgets/app_logo.dart';
import 'beat_sector_screen.dart';
import 'history_screen.dart';
import 'inspection_tasks_screen.dart';
import 'profile_screen.dart';
import 'today_duty_screen.dart';
import 'tracking_setup_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  late Future<_DashboardViewData> _dashboardFuture;
  bool _checkingSession = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _dashboardFuture = _loadDashboardData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkSessionOnResume();
    }
  }

  Future<void> _checkSessionOnResume() async {
    if (_checkingSession) {
      return;
    }
    _checkingSession = true;
    try {
      await SessionManager.validateSingleDeviceSession();
      if (!mounted) {
        return;
      }
      final token = await Storage.getToken();
      if (token == null || token.isEmpty) {
        await SessionManager.forceLogoutToLogin();
        return;
      }
      final tracking = Provider.of<TrackingService>(context, listen: false);
      if (tracking.isActive) {
        return;
      }
      final candidate = await DutyResumeService.findMountedDuty(
        token,
        preferredDeploymentId: await Storage.getActiveDeploymentId(),
        preferredDutyLogId: await Storage.getActiveDutyLogId(),
      );
      if (candidate == null || !mounted) {
        return;
      }

      final setupStatus = await readTrackingSetupStatus();
      if (!mounted) {
        return;
      }
      if (!setupStatus.isComplete) {
        final ready = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => TrackingSetupScreen(
              returnResult: true,
              onSetupComplete: () => tracking.startTracking(
                candidate.dutyLogId,
                token,
                deploymentId: candidate.deploymentId,
              ),
            ),
          ),
        );
        if (ready != true) {
          return;
        }
      } else {
        await tracking.startTracking(
          candidate.dutyLogId,
          token,
          deploymentId: candidate.deploymentId,
        );
      }
    } finally {
      _checkingSession = false;
    }
  }

  Future<_DashboardViewData> _loadDashboardData() async {
    final token = await Storage.getToken();
    final cachedProfile = await Storage.getUserProfile();
    if (token == null || token.isEmpty) {
      return _DashboardViewData(
        profile: cachedProfile,
        stats: const _DashboardStats.empty(),
        canViewInspectionTasks: _canViewInspectionTasks(cachedProfile),
        inspectionPendingCount: 0,
        canViewBeatSector: false,
        beatSectorHome: null,
      );
    }

    final dashboard = await ApiService.getDashboard(token);

    var profile = cachedProfile;
    try {
      final fetched = await ApiService.getCurrentUserProfile(token);
      if (fetched != null) {
        // Photo comes from dashboard response; name/designation from auth API
        final photoUrl = dashboard['profile_photo_url']?.toString().trim();
        debugPrint('=== PHOTO DEBUG ===');
        debugPrint('dashboard profile_photo_url: $photoUrl');
        debugPrint('fetched.photoUrl: ${fetched.photoUrl}');
        debugPrint('dashboard keys: ${dashboard.keys.toList()}');
        profile = UserProfile(
          id: fetched.id,
          name: fetched.name,
          designation: fetched.designation,
          photoUrl: (photoUrl != null && photoUrl.isNotEmpty)
              ? photoUrl
              : fetched.photoUrl,
          role: fetched.role,
        );
        debugPrint('final photoUrl used: ${profile.photoUrl}');
      }
    } catch (_) {
      profile = cachedProfile;
    }
    if (profile != null) {
      await Storage.saveUserProfile(profile);
    }
    final canViewInspectionTasks = _canViewInspectionTasks(profile);
    var todayDutyCount = (dashboard['today_dutys'] as num?)?.toInt() ??
        (dashboard['today_duties'] as num?)?.toInt() ??
        0;
    try {
      final todayItems = await ApiService.getDutyList(token);
      todayDutyCount = todayItems.length;
      unawaited(DutyReminderService.scheduleFromDutyList(todayItems));
    } catch (_) {}

    var inspectionPendingCount = 0;
    var canViewBeatSector = false;
    BeatSectorHomeData? beatSectorHome;
    try {
      final bootstrap = await ApiService.getAppBootstrap(token);
      canViewBeatSector = bootstrap.canViewBeatSector;
      if (canViewBeatSector) {
        beatSectorHome = await ApiService.getBeatSectorHome(token);
      }
    } catch (_) {
      canViewBeatSector = false;
    }

    if (canViewInspectionTasks) {
      try {
        final taskPage = await ApiService.getInspectionTasks(
          token,
          status: 'pending',
          perPage: 1,
        );
        inspectionPendingCount = taskPage.pendingCount;
      } catch (_) {
        inspectionPendingCount = 0;
      }
    }

    return _DashboardViewData(
      profile: profile,
      stats: _DashboardStats(
        totalDuties: (dashboard['total_dutys'] as num?)?.toInt() ?? 0,
        todayDuties: todayDutyCount,
        completedDuties: (dashboard['complete_dutys'] as num?)?.toInt() ?? 0,
        missedDuties: (dashboard['missed_dutys'] as num?)?.toInt() ?? 0,
        activityCount: (dashboard['total_activitys'] as num?)?.toInt() ?? 0,
      ),
      canViewInspectionTasks: canViewInspectionTasks,
      inspectionPendingCount: inspectionPendingCount,
      canViewBeatSector: canViewBeatSector,
      beatSectorHome: beatSectorHome,
    );
  }

  bool _canViewInspectionTasks(UserProfile? profile) {
    // Role is the system-level field (admin cannot change it via designation).
    // Fall back to designation only when role is absent from the API response.
    final checkStr = (profile?.role?.trim().isNotEmpty == true
            ? profile!.role
            : profile?.designation)
        ?.trim();
    if (checkStr == null || checkStr.isEmpty) return false;

    final upper = checkStr.toUpperCase();
    final compact = upper.replaceAll(RegExp(r'[^A-Z0-9]+'), '');
    if (upper.contains('ASSISTANT SUB INSPECTOR') ||
        upper.contains('SUB INSPECTOR') ||
        compact.contains('ASSISTANTSUBINSPECTOR') ||
        compact.contains('SUBINSPECTOR')) {
      return true;
    }

    final tokens = upper.split(RegExp(r'[^A-Z0-9]+'));
    return tokens.contains('ASI') ||
        tokens.contains('SI') ||
        compact == 'ASI' ||
        compact == 'SI';
  }

  void _refreshDashboard() {
    setState(() {
      _dashboardFuture = _loadDashboardData();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isOnline = context.watch<NetworkStatusService>().isOnline;
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor:
          isDark ? const Color(0xFF0B1F3A) : const Color(0xFFF4F6FA),
      body: FutureBuilder<_DashboardViewData>(
        future: _dashboardFuture,
        builder: (context, snapshot) {
          final data = snapshot.data ??
              _DashboardViewData(
                profile: null,
                stats: const _DashboardStats.empty(),
                canViewInspectionTasks: false,
                inspectionPendingCount: 0,
                canViewBeatSector: false,
                beatSectorHome: null,
              );

          return Column(
            children: [
              _buildHeader(context, isDark, data.profile),
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                height: isOnline ? 0 : 52,
                width: double.infinity,
                padding: isOnline
                    ? EdgeInsets.zero
                    : const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                color: const Color(0xFFF97316),
                alignment: Alignment.centerLeft,
                child: isOnline
                    ? null
                    : const Row(
                        children: [
                          Icon(
                            Icons.wifi_off_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'No internet. Will sync when connected.',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isDark
                          ? [
                              const Color(0xFF0B1F3A),
                              const Color(0xFF111827),
                            ]
                          : [
                              const Color(0xFFF4F6FA),
                              const Color(0xFFE5E7EB),
                            ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  child: RefreshIndicator(
                    onRefresh: () async => _refreshDashboard(),
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          sectionTitle("Quick Actions", isDark),
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const TodayDutyScreen(),
                                ),
                              ).then((_) => _refreshDashboard());
                            },
                            child: mainCard(
                              title: "Today's Duty",
                              subtitle: data.stats.todayDuties == 0
                                  ? "No duties assigned"
                                  : "",
                              icon: Icons.assignment,
                              badgeText: data.stats.todayDuties.toString(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (data.canViewBeatSector) ...[
                            GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => BeatSectorHomeScreen(
                                      initialHome: data.beatSectorHome,
                                    ),
                                  ),
                                ).then((_) => _refreshDashboard());
                              },
                              child: mainCard(
                                title: 'Beat Sector',
                                icon: Icons.route_rounded,
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (data.canViewInspectionTasks) ...[
                                Expanded(
                                  child: actionCard(
                                    title: "My Task",
                                    icon: Icons.assignment_turned_in_rounded,
                                    isDark: isDark,
                                    badgeText: data.inspectionPendingCount > 0
                                        ? data.inspectionPendingCount.toString()
                                        : null,
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              const InspectionTasksScreen(),
                                        ),
                                      ).then((_) => _refreshDashboard());
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ],
                              Expanded(
                                child: actionCard(
                                  title: "My Report",
                                  icon: Icons.history_rounded,
                                  isDark: isDark,
                                  wide: !data.canViewInspectionTasks,
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => const HistoryScreen(),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          sectionTitle("Performance", isDark),
                          Row(
                            children: [
                              Expanded(
                                child: statCard(
                                  "Total Duties",
                                  data.stats.totalDuties.toString(),
                                  isDark,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: statCard(
                                  "Completed",
                                  data.stats.completedDuties.toString(),
                                  isDark,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: statCard(
                                  "Missed",
                                  data.stats.missedDuties.toString(),
                                  isDark,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: statCard(
                                  "Activity",
                                  data.stats.activityCount.toString(),
                                  isDark,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF1F2937)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Completion Rate",
                                  style: TextStyle(
                                    color: isDark ? Colors.white : Colors.black,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                LinearProgressIndicator(
                                  value: data.stats.completionRate,
                                  color: Colors.greenAccent,
                                  backgroundColor: Colors.white12,
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  "${(data.stats.completionRate * 100).round()}% Completed",
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.white70
                                        : Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    bool isDark,
    UserProfile? profile,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 50, 16, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF1E3A8A),
            Color(0xFFB91C1C),
          ],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(25),
          bottomRight: Radius.circular(25),
        ),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ProfileScreen(),
                ),
              ).then((_) => _refreshDashboard());
            },
            borderRadius: BorderRadius.circular(24),
            child: _ProfileAvatar(photoUrl: profile?.photoUrl),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile?.name?.trim().isNotEmpty == true
                      ? profile!.name!
                      : "RPF User",
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  profile?.designation?.trim().isNotEmpty == true
                      ? profile!.designation!
                      : "Duty Staff",
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
          Consumer<ThemeProvider>(
            builder: (context, themeProvider, child) {
              return IconButton(
                onPressed: themeProvider.toggleTheme,
                icon: Icon(
                  themeProvider.isDark ? Icons.dark_mode : Icons.light_mode,
                  color: Colors.white,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget sectionTitle(String text, bool isDark) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          text,
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget mainCard({
    required String title,
    String subtitle = '',
    required IconData icon,
    String? badgeText,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 21),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E3A8A), Color(0xFF2563EB)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (subtitle.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (badgeText != null) ...[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.22),
                ),
              ),
              child: Text(
                badgeText,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
          const SizedBox(width: 10),
          const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 16),
        ],
      ),
    );
  }

  Widget actionCard({
    required String title,
    required IconData icon,
    required bool isDark,
    required VoidCallback onTap,
    String? badgeText,
    bool wide = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        height: wide ? 76 : 86,
        padding: EdgeInsets.symmetric(
          horizontal: wide ? 14 : 8,
          vertical: wide ? 12 : 10,
        ),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1F2937) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: (isDark ? Colors.white : const Color(0xFF1D4ED8))
                .withValues(alpha: 0.08),
          ),
        ),
        child: wide
            ? Row(
                children: [
                  _actionIcon(icon, isDark, badgeText),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 15,
                    color: isDark ? Colors.white54 : Colors.black38,
                  ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _actionIcon(icon, isDark, badgeText),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _actionIcon(IconData icon, bool isDark, String? badgeText) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: (isDark ? Colors.white : const Color(0xFF1D4ED8))
                .withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            size: 20,
            color: isDark ? Colors.white : const Color(0xFF1D4ED8),
          ),
        ),
        if (badgeText != null)
          Positioned(
            top: -7,
            right: -8,
            child: Container(
              constraints: const BoxConstraints(minWidth: 20),
              padding: const EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 3,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFDC2626),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(
                  color: isDark ? const Color(0xFF1F2937) : Colors.white,
                  width: 1.5,
                ),
              ),
              child: Text(
                badgeText,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget statCard(String title, String value, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F2937) : Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            title,
            style: TextStyle(
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardViewData {
  final UserProfile? profile;
  final _DashboardStats stats;
  final bool canViewInspectionTasks;
  final int inspectionPendingCount;
  final bool canViewBeatSector;
  final BeatSectorHomeData? beatSectorHome;

  const _DashboardViewData({
    required this.profile,
    required this.stats,
    required this.canViewInspectionTasks,
    required this.inspectionPendingCount,
    required this.canViewBeatSector,
    required this.beatSectorHome,
  });
}

class _DashboardStats {
  final int totalDuties;
  final int todayDuties;
  final int completedDuties;
  final int missedDuties;
  final int activityCount;

  const _DashboardStats({
    required this.totalDuties,
    required this.todayDuties,
    required this.completedDuties,
    required this.missedDuties,
    required this.activityCount,
  });

  const _DashboardStats.empty()
      : totalDuties = 0,
        todayDuties = 0,
        completedDuties = 0,
        missedDuties = 0,
        activityCount = 0;

  int get pendingDuties => todayDuties;

  int get mountedDuties => 0;

  int get incompleteDuties => missedDuties;

  int get trackPointCount => 0;

  int get breachCount => 0;

  double get completionRate {
    if (totalDuties == 0) {
      return 0;
    }
    return completedDuties / totalDuties;
  }
}

class _ProfileAvatar extends StatelessWidget {
  final String? photoUrl;

  const _ProfileAvatar({this.photoUrl});

  @override
  Widget build(BuildContext context) {
    final trimmed = photoUrl?.trim() ?? '';
    if (trimmed.isEmpty) {
      return CircleAvatar(
        radius: 22,
        backgroundColor: Colors.white,
        child: AppLogo(
          size: 28,
          padding: const EdgeInsets.all(2),
        ),
      );
    }

    return ClipOval(
      child: Container(
        width: 44,
        height: 44,
        color: Colors.white,
        child: Image.network(
          trimmed,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) {
            return Center(
              child: AppLogo(
                size: 28,
                padding: const EdgeInsets.all(2),
              ),
            );
          },
          loadingBuilder: (context, child, progress) {
            if (progress == null) {
              return child;
            }
            return const Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          },
        ),
      ),
    );
  }
}
