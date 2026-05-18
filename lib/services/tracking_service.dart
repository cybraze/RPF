import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../config/app_config.dart';
import '../utils/storage.dart';
import 'tracking_handler.dart';

class TrackingService extends ChangeNotifier with WidgetsBindingObserver {
  TrackingService();

  bool _isActive = false;
  int? _dutyLogId;
  int? _deploymentId;
  int? _userId;
  bool _gpsRequired = false;
  final List<String> _realtimeLogs = [];
  DateTime? _lastSentAt;
  double? _lastSentLat;
  double? _lastSentLng;

  bool get isActive => _isActive;
  int? get dutyLogId => _dutyLogId;
  int? get deploymentId => _deploymentId;
  bool get gpsRequired => _gpsRequired;
  List<String> get realtimeLogs => List.unmodifiable(_realtimeLogs);
  DateTime? get lastSentAt => _lastSentAt;
  double? get lastSentLat => _lastSentLat;
  double? get lastSentLng => _lastSentLng;

  void initCallbacks() {
    WidgetsBinding.instance.addObserver(this);
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
  }

  Future<void> configureAuthenticatedSession({
    required String token,
    int? userId,
  }) async {
    _userId = userId ?? await Storage.getUserId();
    _pushRealtimeLog(
      'REST tracking session ready for user ${_userId ?? 'unknown'}',
    );
    notifyListeners();
  }

  Future<void> clearAuthenticatedSession() async {
    _userId = null;
  }

  void _onTaskData(Object data) {
    if (data is! Map) return;
    final event = data['event'] as String?;
    if (event == 'stop' || event == 'stopped') {
      _isActive = false;
      _dutyLogId = null;
      _deploymentId = null;
      _gpsRequired = false;
      _pushRealtimeLog('Tracking stopped (${event ?? 'unknown'})');
      notifyListeners();
      return;
    }
    if (event == 'tracking_sent') {
      _lastSentAt =
          DateTime.tryParse((data['tracked_at'] as String?) ?? '')?.toLocal();
      _lastSentLat = (data['latitude'] as num?)?.toDouble();
      _lastSentLng = (data['longitude'] as num?)?.toDouble();
      final count = (data['count'] as num?)?.toInt() ?? 1;
      final mode = (data['mode'] as String?) ?? 'movement';
      final status = (data['status'] as String?) ?? 'unknown';
      _pushRealtimeLog(
        'API sent $count point(s) [$mode/$status] @ '
        '${_lastSentLat?.toStringAsFixed(5) ?? '-'}, '
        '${_lastSentLng?.toStringAsFixed(5) ?? '-'}',
      );
      notifyListeners();
      return;
    }
    if (event == 'tracking_failed') {
      final rawReason = (data['reason'] as String?) ?? 'unknown';
      final reason = rawReason.length <= 80
          ? rawReason
          : '${rawReason.substring(0, 80)}...';
      _pushRealtimeLog('API send failed: $reason');
      notifyListeners();
      return;
    }
    if (event == 'gps_disabled') {
      _gpsRequired = true;
      _pushRealtimeLog('GPS disabled while duty tracking is active');
      notifyListeners();
      return;
    }
    if (event == 'gps_restored') {
      _gpsRequired = false;
      _pushRealtimeLog('GPS restored');
      notifyListeners();
    }
  }

  Future<void> startTracking(
    int dutyLogId,
    String token, {
    int? userId,
    int? deploymentId,
  }) async {
    if (_isActive && _dutyLogId == dutyLogId) {
      return;
    }

    await configureAuthenticatedSession(token: token, userId: userId);

    if (_isActive) {
      await stopTracking('restarted');
    }

    _dutyLogId = dutyLogId;
    _deploymentId = deploymentId;
    _userId = userId ?? _userId;
    _gpsRequired = false;
    _lastSentAt = null;
    _lastSentLat = null;
    _lastSentLng = null;
    _pushRealtimeLog('Starting tracking for duty_log_id=$dutyLogId');
    await Storage.saveActiveDutyLogId(
      dutyLogId,
      deploymentId: deploymentId,
    );

    final notifPerm = await FlutterForegroundTask.checkNotificationPermission();
    if (notifPerm != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    final wasRunning = await FlutterForegroundTask.isRunningService;
    if (wasRunning) {
      await FlutterForegroundTask.stopService();
      await Future.delayed(const Duration(milliseconds: 400));
    }

    final result = await FlutterForegroundTask.startService(
      serviceId: 1001,
      notificationTitle: 'RPF Duty Tracking Active',
      notificationText: 'Preparing live location...',
      callback: startTrackingCallback,
    );
    if (result is ServiceRequestFailure) {
      _log('Foreground service failed to start: ${result.error}');
      _pushRealtimeLog('Foreground service failed to start');
      _isActive = false;
      notifyListeners();
      return;
    }

    _isActive = true;
    _pushRealtimeLog('Foreground tracking active');
    notifyListeners();
  }

  Future<void> stopTracking(
    String reason, {
    bool waitForCompletion = true,
  }) async {
    final isRunning = await FlutterForegroundTask.isRunningService;

    if (isRunning) {
      _pushRealtimeLog('Stopping tracking: $reason');
      FlutterForegroundTask.sendDataToTask(
          {'action': 'stop', 'reason': reason});
      if (waitForCompletion) {
        await Future.delayed(const Duration(seconds: 4));
        await FlutterForegroundTask.stopService();
      }
    }

    _isActive = false;
    _dutyLogId = null;
    _deploymentId = null;
    _gpsRequired = false;
    await Storage.clearActiveDutyLogId();
    await Storage.clearActiveDutyGeofence();
    notifyListeners();
  }

  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) {
      final isRunning = await FlutterForegroundTask.isRunningService;
      if (isRunning != _isActive) {
        _isActive = isRunning;
      }
      _pushRealtimeLog('App resumed, tracking service state checked');
      notifyListeners();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
    super.dispose();
  }

  void _log(String message) {
    if (kDebugMode && AppConfig.debugTrackingLogs) {
      debugPrint('[TrackingService] $message');
    }
  }

  void _pushRealtimeLog(String message) {
    final ts = DateTime.now().toLocal().toIso8601String();
    _realtimeLogs.insert(0, '$ts  $message');
    if (_realtimeLogs.length > 12) {
      _realtimeLogs.removeRange(12, _realtimeLogs.length);
    }
  }
}
