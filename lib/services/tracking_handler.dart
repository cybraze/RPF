import 'dart:async';

import 'dart:math' as math;

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_activity_recognition/flutter_activity_recognition.dart'
    as activity_recognition;
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import '../config/app_config.dart';
import '../models/active_duty_geofence.dart';
import '../models/tracking_api_models.dart';
import '../models/tracking_point.dart';
import 'device_settings_service.dart';
import 'duty_resume_service.dart';
import '../utils/location_sampler.dart';
import 'tracking_api_service.dart';

@pragma('vm:entry-point')
void startTrackingCallback() {
  FlutterForegroundTask.setTaskHandler(TrackingTaskHandler());
}

class TrackingTaskHandler extends TaskHandler {
  static const _movementThresholdMeters = 50.0;
  static const _heartbeatEveryTicks = 6;
  static const _dutyValidationEveryTicks = 6;
  static const _maxAcceptedAccuracyMeters = 20.0;
  static const _maxRenderableAccuracyMeters = 80.0;
  static const _hardRejectAccuracyMeters = 200.0;
  static const _fallbackRenderableAccuracyMeters = 120.0;
  static const _fallbackHardRejectAccuracyMeters = 250.0;
  static const _streamFreshFor = Duration(seconds: 15);
  static const _streamRestartAfter = Duration(seconds: 35);
  static const _maxBatchSize = 6;
  static const _maxOfflineQueueSize = 120;
  static const _streamDistanceFilterMeters = 15;

  // Adaptive interval: how many consecutive real ticks (~10s each) of
  // near-zero movement before we treat the device as stationary.
  static const _stationaryConfirmTicks = 3;
  // While stationary, only run a real GPS tick every Nth 10s repeat event
  // (6 -> effectively every ~60s) instead of every tick.
  static const _stationaryTickSkip = 6;
  static const _stationarySpeedMps = 0.5;

  final TrackingApiService _trackingApi = const TrackingApiService();
  final Battery _battery = Battery();

  int? _dutyLogId;
  int? _deploymentId;
  String? _token;

  final List<TrackingPoint> _pendingPoints = [];
  TrackingPoint? _lastCollectedPoint;
  ActiveDutyGeofence? _activeGeofence;
  StreamSubscription<Position>? _positionSubscription;
  Position? _latestStreamPosition;
  DateTime? _latestStreamPositionAt;
  LocationAccuracy? _streamAccuracyMode;

  StreamSubscription<activity_recognition.Activity>? _activitySubscription;
  activity_recognition.Activity? _latestActivity;
  int _stationaryStreak = 0;
  int _repeatEventCounter = 0;

  bool _isTicking = false;
  bool _stopping = false;
  bool? _lastGpsEnabled;
  int _tickCounter = 0;

  bool get _isStationary {
    final activity = _latestActivity;
    if (activity != null) {
      final movingTypes = {
        activity_recognition.ActivityType.WALKING,
        activity_recognition.ActivityType.RUNNING,
        activity_recognition.ActivityType.IN_VEHICLE,
        activity_recognition.ActivityType.ON_BICYCLE,
      };
      if (movingTypes.contains(activity.type)) {
        return false;
      }
      if (activity.type == activity_recognition.ActivityType.STILL &&
          activity.confidence != activity_recognition.ActivityConfidence.LOW) {
        return true;
      }
    }
    return _stationaryStreak >= _stationaryConfirmTicks;
  }

  LocationAccuracy get _currentAccuracy =>
      _isStationary ? LocationAccuracy.high : LocationAccuracy.bestForNavigation;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    final prefs = await SharedPreferences.getInstance();
    _dutyLogId = prefs.getInt('active_duty_log_id');
    _deploymentId = prefs.getInt('active_deployment_id');
    _token = prefs.getString('token');
    _activeGeofence = ActiveDutyGeofence.fromJsonString(
      prefs.getString('active_duty_geofence'),
    );

    final queueJson = prefs.getString('tracking_queue') ?? '';
    if (queueJson.isNotEmpty) {
      _pendingPoints.addAll(
        TrackingPoint.listFromJsonString(
          queueJson,
        ).map((point) => point.sanitizedForApi()),
      );
      if (_pendingPoints.isNotEmpty) {
        _lastCollectedPoint = _pendingPoints.last;
      }
    }

    if (_dutyLogId == null || _deploymentId == null || _token == null) {
      _log(
          'Tracking start skipped; missing token, deployment_id, or duty_log_id.');
      await _stopServiceSilently(
        'missing_config',
        clearPersistedState: true,
      );
      return;
    }

    FlutterForegroundTask.updateService(
      notificationTitle: 'RPF Tracking',
      notificationText: 'Foreground tracking started, checking GPS...',
    );
    await _startPositionStream();
    await _startActivityRecognition();

    try {
      await _trackingApi.startTracking(
        token: _token!,
        request: TrackingStartRequest(dutyLogId: _dutyLogId!),
      );
    } catch (error) {
      _log('tracking/start failed: $error');
    }

    // Do one immediate sample so the notification and first payload do not
    // wait for the first 10-second repeat tick.
    try {
      await _tick();
    } catch (error) {
      _log('initial tracking tick failed: $error');
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    if (_isTicking || _stopping) {
      return;
    }

    _repeatEventCounter++;
    final requiredSkip = _isStationary ? _stationaryTickSkip : 1;
    if (_repeatEventCounter < requiredSkip) {
      return;
    }
    _repeatEventCounter = 0;

    _isTicking = true;
    _tick().whenComplete(() => _isTicking = false);
  }

  Future<void> _startPositionStream({LocationAccuracy? accuracy}) async {
    final resolvedAccuracy = accuracy ?? _currentAccuracy;
    if (_positionSubscription != null &&
        _streamAccuracyMode == resolvedAccuracy) {
      return;
    }
    await _positionSubscription?.cancel();
    _streamAccuracyMode = resolvedAccuracy;
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: LocationSampler.trackingSettings(
        accuracy: resolvedAccuracy,
        distanceFilter: _streamDistanceFilterMeters,
      ),
    ).listen(
      (position) {
        _latestStreamPosition = position;
        _latestStreamPositionAt = DateTime.now().toUtc();
      },
      onError: (error) {
        _log('position stream error: $error');
      },
    );
  }

  Future<void> _startActivityRecognition() async {
    try {
      var permission = await activity_recognition
          .FlutterActivityRecognition.instance.checkPermission();
      if (permission == activity_recognition.ActivityPermission.DENIED) {
        permission = await activity_recognition
            .FlutterActivityRecognition.instance.requestPermission();
      }
      if (permission != activity_recognition.ActivityPermission.GRANTED) {
        _log('activity recognition permission not granted: $permission');
        return;
      }
      await _activitySubscription?.cancel();
      _activitySubscription = activity_recognition
          .FlutterActivityRecognition.instance.activityStream.listen(
        (activity) {
          _latestActivity = activity;
        },
        onError: (error) {
          _log('activity recognition stream error: $error');
        },
      );
    } catch (error) {
      _log('activity recognition unavailable: $error');
    }
  }

  Future<void> _tick() async {
    if (_dutyLogId == null || _token == null) {
      return;
    }

    await _collectPoint();
    _tickCounter++;
    final stillValid = await _validateActiveDutyIfNeeded();
    if (!stillValid) {
      return;
    }

    final shouldSendHeartbeat = _tickCounter >= _heartbeatEveryTicks;
    if (_pendingPoints.isEmpty) {
      if (shouldSendHeartbeat && _lastCollectedPoint != null) {
        _enqueuePoint(
          _statusPoint(
            provider: 'heartbeat',
            batteryLevel: _lastCollectedPoint?.batteryLevel,
            basePoint: _lastCollectedPoint,
            powerSaveMode:
                _lastCollectedPoint?.statusFlags.contains('battery_saver_on') ??
                    false,
          ),
          squashStatusOnly: true,
        );
        await _sendBatch(isHeartbeat: true);
        if (_pendingPoints.isEmpty) {
          _tickCounter = 0;
        }
      }
      return;
    }

    final latest = _pendingPoints.last;
    final shouldSendStatusOnly = _isStatusOnlyPoint(latest);

    if (shouldSendStatusOnly) {
      if (!shouldSendHeartbeat) {
        FlutterForegroundTask.updateService(
          notificationTitle: 'RPF Tracking',
          notificationText:
              'Waiting for 1 min heartbeat, latest status: ${latest.status}',
        );
        return;
      }
      await _sendBatch(isHeartbeat: true);
      if (_pendingPoints.isEmpty) {
        _tickCounter = 0;
      }
      return;
    }

    await _sendBatch(isHeartbeat: false);
    if (_pendingPoints.isEmpty) {
      _tickCounter = 0;
    }
  }

  Future<void> _collectPoint() async {
    int? batteryLevel;
    bool powerSaveMode = false;
    try {
      batteryLevel = await _battery.batteryLevel;
    } catch (_) {}
    try {
      powerSaveMode = await DeviceSettingsService.isPowerSaveModeEnabled();
    } catch (_) {}

    LocationPermission permission;
    try {
      permission = await Geolocator.checkPermission();
    } catch (_) {
      permission = LocationPermission.denied;
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      _enqueuePoint(
        _statusPoint(
          provider: 'permission_denied',
          batteryLevel: batteryLevel,
          basePoint: _lastCollectedPoint,
          powerSaveMode: powerSaveMode,
        ),
        squashStatusOnly: true,
      );
      await _trimAndPersistQueue();
      FlutterForegroundTask.updateService(
        notificationTitle: 'RPF Tracking',
        notificationText:
            'Location permission missing, status heartbeat active',
      );
      return;
    }

    bool serviceEnabled = false;
    try {
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
    } catch (_) {}

    if (!serviceEnabled) {
      if (_lastGpsEnabled != false) {
        _lastGpsEnabled = false;
        FlutterForegroundTask.sendDataToMain({'event': 'gps_disabled'});
      }
      _enqueuePoint(
        _statusPoint(
          provider: 'gps_disabled',
          batteryLevel: batteryLevel,
          basePoint: _lastCollectedPoint,
          powerSaveMode: powerSaveMode,
        ),
        squashStatusOnly: true,
      );
      await _trimAndPersistQueue();
      FlutterForegroundTask.updateService(
        notificationTitle: 'RPF Tracking',
        notificationText: 'GPS disabled, status heartbeat will be sent',
      );
      return;
    }

    try {
      final pos = await _getBestAvailablePosition();

      if (!_shouldUsePosition(pos)) {
        _enqueuePoint(
          _statusPoint(
            provider: 'gps_weak',
            batteryLevel: batteryLevel,
            basePoint: _lastCollectedPoint,
            powerSaveMode: powerSaveMode,
          ),
          squashStatusOnly: true,
        );
        await _trimAndPersistQueue();
        FlutterForegroundTask.updateService(
          notificationTitle: 'RPF Tracking',
          notificationText: 'GPS weak, waiting for reliable fix',
        );
        return;
      }

      if (_lastGpsEnabled != true) {
        _lastGpsEnabled = true;
        FlutterForegroundTask.sendDataToMain({'event': 'gps_restored'});
      }

      _updateStationaryStreak(pos);

      final point = _gpsPoint(
        pos,
        batteryLevel: batteryLevel,
        provider: 'gps',
        powerSaveMode: powerSaveMode,
      );

      _enqueuePoint(point);
      _lastCollectedPoint = point;
      await _trimAndPersistQueue();

      FlutterForegroundTask.updateService(
        notificationTitle: 'RPF Duty Active',
        notificationText: _isStationary
            ? 'Stationary, checking every ~60 sec, queued ${_pendingPoints.length} point(s)'
            : 'Checking every 10 sec, queued ${_pendingPoints.length} point(s)',
      );
    } catch (_) {
      Position? cachedPosition;
      try {
        cachedPosition = await Geolocator.getLastKnownPosition();
      } catch (_) {}
      if (cachedPosition != null &&
          (_shouldUsePosition(cachedPosition) ||
              _shouldUseFallbackPosition(cachedPosition))) {
        final cachedPoint = _gpsPoint(
          cachedPosition,
          batteryLevel: batteryLevel,
          provider: 'gps_last_known',
          powerSaveMode: powerSaveMode,
          extraMeta: {
            'sample_source': 'foreground_task_cache',
            'flags': [
              'stale_possible',
              if (!_shouldUsePosition(cachedPosition)) 'fallback_fix',
            ],
          },
        );
        _enqueuePoint(cachedPoint, squashStatusOnly: true);
        _lastCollectedPoint = cachedPoint;
      } else {
        _enqueuePoint(
          _statusPoint(
            provider: 'gps_timeout',
            batteryLevel: batteryLevel,
            basePoint: _lastCollectedPoint,
            powerSaveMode: powerSaveMode,
          ),
          squashStatusOnly: true,
        );
      }
      await _trimAndPersistQueue();
      FlutterForegroundTask.updateService(
        notificationTitle: 'RPF Tracking',
        notificationText: 'GPS timeout, retrying location sample',
      );
    }
  }

  Future<Position> _getBestAvailablePosition() async {
    final accuracy = _currentAccuracy;
    await _startPositionStream(accuracy: accuracy);

    // Prefer the already-running position stream over an active one-shot
    // fetch: the stream keeps the GPS chip warm anyway once tracking is
    // active, so reusing a fresh fix avoids a second, separate GPS request.
    final streamPosition = _latestStreamPosition;
    final streamPositionAt = _latestStreamPositionAt;
    final streamFresh = streamPosition != null &&
        streamPositionAt != null &&
        DateTime.now().toUtc().difference(streamPositionAt) <= _streamFreshFor;

    if (streamFresh && _shouldUsePosition(streamPosition)) {
      return streamPosition;
    }

    try {
      return await LocationSampler.getBestEffortPosition(
        count: 2,
        perSampleTimeout: const Duration(seconds: 8),
        gap: const Duration(milliseconds: 700),
        accuracy: accuracy,
      );
    } catch (error) {
      _log('current location sample failed: $error');
    }

    final streamStale = streamPositionAt == null ||
        DateTime.now().toUtc().difference(streamPositionAt) >
            _streamRestartAfter;

    if (_positionSubscription == null || streamStale) {
      await _startPositionStream(accuracy: accuracy);
    }

    if (streamPosition != null && _shouldUseFallbackPosition(streamPosition)) {
      return streamPosition;
    }

    final lastKnown = await Geolocator.getLastKnownPosition();
    if (lastKnown != null && _shouldUseFallbackPosition(lastKnown)) {
      return lastKnown;
    }

    throw TimeoutException('Reliable location sample not available');
  }

  void _updateStationaryStreak(Position pos) {
    final previous = _lastCollectedPoint;
    final speed = pos.speed.isFinite ? pos.speed : 0.0;
    var distanceStationary = true;
    if (previous != null) {
      final distance = Geolocator.distanceBetween(
        previous.latitude,
        previous.longitude,
        pos.latitude,
        pos.longitude,
      );
      distanceStationary = distance < _movementThresholdMeters;
    }
    if (distanceStationary && speed < _stationarySpeedMps) {
      _stationaryStreak++;
    } else {
      _stationaryStreak = 0;
    }
  }

  TrackingPoint _gpsPoint(
    Position pos, {
    required int? batteryLevel,
    required String provider,
    required bool powerSaveMode,
    Map<String, dynamic> extraMeta = const {},
  }) {
    final geofence = _activeGeofence;
    final geofenceSnapshot = geofence?.evaluate(pos.latitude, pos.longitude);
    final statusFlags = <String>[
      if ((geofenceSnapshot?.status ?? 'live') != 'live')
        geofenceSnapshot!.status,
      ...?geofenceSnapshot?.flags,
      if (provider == 'gps_last_known') 'last_known_location',
      if (powerSaveMode) 'battery_saver_on',
    ];
    final status = _composeStatusText(
      baseStatus: (geofenceSnapshot?.status ?? 'live'),
      extraFlags: statusFlags,
    );
    return TrackingPoint(
      latitude: pos.latitude,
      longitude: pos.longitude,
      accuracy: pos.accuracy,
      speed: pos.speed,
      heading: pos.heading,
      altitude: pos.altitude,
      batteryLevel: batteryLevel,
      provider: provider,
      trackedAt: DateTime.now().toUtc().toIso8601String(),
      isMoving: (pos.speed > 0.5),
      status: status,
      statusFlags: statusFlags,
      metaJson: {
        'sample_source': 'foreground_task',
        'accuracy_rating': pos.accuracy <= _maxAcceptedAccuracyMeters
            ? 'good'
            : (pos.accuracy <= _maxRenderableAccuracyMeters
                ? 'usable'
                : 'weak'),
        if (pos.accuracy > _maxRenderableAccuracyMeters)
          'flags': ['low_quality'],
        if (geofenceSnapshot?.distanceMeters != null)
          'geofence_distance_meters': geofenceSnapshot!.distanceMeters!.round(),
        if (geofence?.isConfigured == true)
          'geofence': {
            'status': status,
            'location_type': geofence!.locationType,
          },
        'power_save_mode': powerSaveMode,
        'stationary_mode': _isStationary,
        ...extraMeta,
      },
    );
  }

  bool _shouldUsePosition(Position position) {
    if (!position.latitude.isFinite || !position.longitude.isFinite) {
      return false;
    }

    final accuracy =
        position.accuracy.isFinite ? position.accuracy : double.infinity;
    if (accuracy > _hardRejectAccuracyMeters) {
      return false;
    }

    final previous = _lastCollectedPoint;
    if (previous == null) {
      return accuracy <= _maxRenderableAccuracyMeters;
    }

    final previousTime = DateTime.tryParse(previous.trackedAt)?.toUtc();
    final now = DateTime.now().toUtc();
    final elapsedSeconds = previousTime == null
        ? 10.0
        : math.max(
            1.0,
            now.difference(previousTime).inMilliseconds / 1000.0,
          );

    final distance = Geolocator.distanceBetween(
      previous.latitude,
      previous.longitude,
      position.latitude,
      position.longitude,
    );

    final speed =
        position.speed.isFinite && position.speed > 0 ? position.speed : 0.0;
    final allowedDistance = math.max(
      35.0,
      (speed * (elapsedSeconds + 2)) + (accuracy * 1.4),
    );

    if (accuracy > _maxRenderableAccuracyMeters && distance > allowedDistance) {
      return false;
    }

    if (distance > 120 && speed < 2.0) {
      return false;
    }

    return true;
  }

  bool _shouldUseFallbackPosition(Position position) {
    if (!position.latitude.isFinite || !position.longitude.isFinite) {
      return false;
    }

    final accuracy =
        position.accuracy.isFinite ? position.accuracy : double.infinity;
    if (accuracy > _fallbackHardRejectAccuracyMeters) {
      return false;
    }

    final previous = _lastCollectedPoint;
    if (previous == null) {
      return accuracy <= _fallbackRenderableAccuracyMeters;
    }

    final distance = Geolocator.distanceBetween(
      previous.latitude,
      previous.longitude,
      position.latitude,
      position.longitude,
    );

    return distance <= 250 || accuracy <= _maxRenderableAccuracyMeters;
  }

  String _locationMessageFromProvider(String provider) {
    switch (provider) {
      case 'permission_denied':
        return 'Location permission not granted';
      case 'gps_disabled':
        return 'GPS is turned off';
      case 'gps_timeout':
        return 'Location not found';
      case 'gps_weak':
        return 'Location not found due to weak GPS';
      case 'heartbeat':
        return 'Heartbeat sent';
      default:
        return 'Live location available';
    }
  }

  TrackingPoint _statusPoint({
    required String provider,
    int? batteryLevel,
    TrackingPoint? basePoint,
    required bool powerSaveMode,
  }) {
    final sourcePoint = basePoint ?? _lastCollectedPoint;
    final statusFlags = _statusFlagsFromProvider(
      provider,
      sourcePoint: sourcePoint,
      powerSaveMode: powerSaveMode,
    );
    return TrackingPoint(
      latitude: sourcePoint?.latitude ?? 0,
      longitude: sourcePoint?.longitude ?? 0,
      accuracy: sourcePoint?.accuracy,
      speed: sourcePoint?.speed,
      heading: sourcePoint?.heading,
      altitude: sourcePoint?.altitude,
      batteryLevel: batteryLevel,
      provider: provider,
      trackedAt: DateTime.now().toUtc().toIso8601String(),
      isMoving: false,
      status: _composeStatusText(
        baseStatus: _statusFromProvider(provider),
        extraFlags: statusFlags,
      ),
      statusFlags: statusFlags,
      metaJson: {
        'sample_source': 'foreground_task',
        'status_only': true,
        'heartbeat': provider == 'heartbeat',
        'gps_state': provider,
        'power_save_mode': powerSaveMode,
        'location_message': _locationMessageFromProvider(provider),
      },
    );
  }

  String _statusFromProvider(String provider) {
    switch (provider) {
      case 'permission_denied':
        return 'location_permission_off';
      case 'gps_disabled':
        return 'location_off';
      case 'gps_timeout':
        return 'location_not_found';
      case 'gps_weak':
        return 'location_not_found';
      case 'heartbeat':
        return _lastCollectedPoint?.status ?? 'live';
      default:
        return 'live';
    }
  }

  List<String> _statusFlagsFromProvider(
    String provider, {
    TrackingPoint? sourcePoint,
    required bool powerSaveMode,
  }) {
    final flags = <String>[
      if (_activeGeofence?.isConfigured == true) 'geofence_enforced',
      if (powerSaveMode) 'battery_saver_on',
    ];

    if (provider == 'heartbeat') {
      flags.addAll(sourcePoint?.statusFlags ?? const []);
    }

    switch (provider) {
      case 'permission_denied':
        flags.add('location_permission_off');
        break;
      case 'gps_disabled':
        flags.add('location_off');
        break;
      case 'gps_timeout':
        flags.add('location_not_found');
        break;
      case 'gps_weak':
        flags.add('location_not_found');
        flags.add('weak_gps');
        break;
      case 'heartbeat':
        flags.add('heartbeat');
        break;
    }

    return flags.toSet().toList();
  }

  String _composeStatusText({
    required String baseStatus,
    List<String> extraFlags = const [],
  }) {
    final primaryToken = _resolvePrimaryStatusToken(
      baseStatus: baseStatus,
      extraFlags: extraFlags,
    );
    final message = _messageForStatusToken(primaryToken);
    if (message == null || message.isEmpty) {
      return 'live';
    }
    return message;
  }

  String _resolvePrimaryStatusToken({
    required String baseStatus,
    required List<String> extraFlags,
  }) {
    final tokens = <String>[];

    void addToken(String raw) {
      final value = raw.trim();
      if (value.isEmpty ||
          value == 'geofence_enforced' ||
          value == 'heartbeat') {
        return;
      }
      if (value == 'live' && tokens.isNotEmpty) {
        return;
      }
      if (!tokens.contains(value)) {
        tokens.add(value);
      }
    }

    addToken(baseStatus);
    for (final flag in extraFlags) {
      addToken(flag);
    }

    if (tokens.isEmpty) {
      return 'live';
    }

    tokens.sort((a, b) => _statusPriority(a).compareTo(_statusPriority(b)));
    return tokens.first;
  }

  int _statusPriority(String token) {
    switch (token) {
      case 'location_permission_off':
      case 'permission_denied':
        return 0;
      case 'location_off':
      case 'gps_disabled':
        return 1;
      case 'location_not_found':
      case 'gps_timeout':
      case 'gps_weak':
      case 'weak_gps':
        return 2;
      case 'out_of_geofence':
        return 3;
      case 'last_known_location':
        return 4;
      case 'battery_saver_on':
        return 5;
      case 'live':
        return 6;
      default:
        return 7;
    }
  }

  String? _messageForStatusToken(String token) {
    switch (token) {
      case 'live':
        return 'Live location active';
      case 'out_of_geofence':
        return 'Outside assigned area';
      case 'polygon_boundary':
        return null;
      case 'polyline_boundary':
        return null;
      case 'radius_boundary':
        return null;
      case 'location_permission_off':
      case 'permission_denied':
        return 'Location permission is off';
      case 'location_off':
      case 'gps_disabled':
        return 'Location services are off';
      case 'location_not_found':
      case 'gps_timeout':
        return 'Location not found';
      case 'gps_weak':
      case 'weak_gps':
        return 'GPS signal is weak';
      case 'battery_saver_on':
        return 'Battery saver is on';
      case 'last_known_location':
        return 'Using last known location';
      default:
        return _sentenceCaseToken(token);
    }
  }

  String? _sentenceCaseToken(String token) {
    final value = token.trim();
    if (value.isEmpty) {
      return null;
    }
    final words = value
        .split('_')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .map(
          (part) =>
              '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
        )
        .toList();
    if (words.isEmpty) {
      return null;
    }
    return words.join(' ');
  }

  void _enqueuePoint(
    TrackingPoint point, {
    bool squashStatusOnly = false,
  }) {
    if (!squashStatusOnly &&
        _pendingPoints.isNotEmpty &&
        !_isStatusOnlyPoint(point) &&
        !_isStatusOnlyPoint(_pendingPoints.last)) {
      final previous = _pendingPoints.last;
      final distance = Geolocator.distanceBetween(
        previous.latitude,
        previous.longitude,
        point.latitude,
        point.longitude,
      );
      if (distance < _movementThresholdMeters) {
        _pendingPoints[_pendingPoints.length - 1] = point;
        return;
      }
    }

    if (squashStatusOnly &&
        _pendingPoints.isNotEmpty &&
        _isStatusOnlyPoint(_pendingPoints.last)) {
      _pendingPoints[_pendingPoints.length - 1] = point;
      return;
    }
    _pendingPoints.add(point);
  }

  Future<void> _sendBatch({bool isHeartbeat = false}) async {
    if (_pendingPoints.isEmpty || _dutyLogId == null || _token == null) {
      return;
    }

    final sendCount = _pendingPoints.length.clamp(0, _maxBatchSize);
    final toSend = _pendingPoints
        .take(sendCount)
        .map((point) => point.sanitizedForApi())
        .toList();

    try {
      final statusCode = await _trackingApi.sendLocationBatch(
        token: _token!,
        request: TrackingLocationRequest(
          dutyLogId: _dutyLogId!,
          points: toSend,
        ),
      );

      if (statusCode >= 200 && statusCode < 300) {
        _pendingPoints.removeRange(0, sendCount);
        await _saveQueue();
        final latest = toSend.last;
        final modeTag = _isStationary ? '[Stationary ~60s]' : '[Moving ~10s]';
        FlutterForegroundTask.updateService(
          notificationTitle: 'RPF Duty Active',
          notificationText:
              '$modeTag Sent $sendCount point(s): ${latest.status}',
        );
        FlutterForegroundTask.sendDataToMain({
          'event': 'tracking_sent',
          'count': sendCount,
          'latitude': latest.latitude,
          'longitude': latest.longitude,
          'tracked_at': latest.trackedAt,
          'status': latest.status,
          'mode': isHeartbeat ? 'heartbeat' : 'movement',
        });
        return;
      }

      if (statusCode == 401 || statusCode == 409) {
        await _stopForTrackingAuthFailure(
          statusCode == 401 ? 'auth_failed' : 'conflict',
        );
        return;
      }
      FlutterForegroundTask.sendDataToMain({
        'event': 'tracking_failed',
        'reason': 'http_$statusCode',
      });
      FlutterForegroundTask.updateService(
        notificationTitle: 'RPF Tracking Error',
        notificationText: 'API rejected tracking payload (HTTP $statusCode)',
      );
    } catch (error) {
      _log('tracking/location failed: $error');
      if (_isNonRetryableTrackingAuthError(error)) {
        await _stopForTrackingAuthFailure('auth_failed');
        return;
      }
      final reason = error.toString();
      FlutterForegroundTask.sendDataToMain({
        'event': 'tracking_failed',
        'reason': reason,
      });
      FlutterForegroundTask.updateService(
        notificationTitle: 'RPF Tracking Error',
        notificationText:
            'Tracking send failed, will retry: ${_shortReason(reason)}',
      );
      await _trimAndPersistQueue();
    }
  }

  bool _isNonRetryableTrackingAuthError(Object error) {
    if (error is TrackingApiException &&
        (error.statusCode == 401 || error.statusCode == 409)) {
      return true;
    }
    final message = error.toString();
    return message.contains('RequestGuard::logout') ||
        message.contains('Tracking session expired');
  }

  Future<void> _stopForTrackingAuthFailure(String reason) async {
    FlutterForegroundTask.sendDataToMain({
      'event': 'stop',
      'reason': reason,
    });
    await _cleanup();
    _stopping = true;
    FlutterForegroundTask.updateService(
      notificationTitle: 'RPF Tracking Stopped',
      notificationText: 'Session issue. Please login again.',
    );
    await FlutterForegroundTask.stopService();
  }

  String _shortReason(String reason) {
    final cleaned = reason.replaceAll('Exception: ', '').trim();
    if (cleaned.isEmpty) {
      return 'unknown';
    }
    if (cleaned.length <= 48) {
      return cleaned;
    }
    return '${cleaned.substring(0, 48)}...';
  }

  Future<void> _trimAndPersistQueue() async {
    if (_pendingPoints.length > _maxOfflineQueueSize) {
      _pendingPoints.removeRange(
          0, _pendingPoints.length - _maxOfflineQueueSize);
    }
    await _saveQueue();
  }

  Future<void> _saveQueue() async {
    final prefs = await SharedPreferences.getInstance();
    if (_pendingPoints.isEmpty) {
      await prefs.remove('tracking_queue');
      return;
    }

    final sanitizedQueue =
        _pendingPoints.map((point) => point.sanitizedForApi()).toList();
    await prefs.setString(
      'tracking_queue',
      TrackingPoint.listToJsonString(sanitizedQueue),
    );
  }

  Future<void> _cleanup() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    _latestStreamPosition = null;
    _latestStreamPositionAt = null;
    await _activitySubscription?.cancel();
    _activitySubscription = null;
    _latestActivity = null;
    _stationaryStreak = 0;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('active_duty_log_id');
    await prefs.remove('active_deployment_id');
    await prefs.remove('tracking_queue');
    await prefs.remove('active_duty_geofence');
    _dutyLogId = null;
    _deploymentId = null;
    _token = null;
    _lastCollectedPoint = null;
    _activeGeofence = null;
  }

  bool _isStatusOnlyPoint(TrackingPoint point) {
    return point.metaJson['status_only'] == true;
  }

  Future<bool> _validateActiveDutyIfNeeded() async {
    return _validateActiveDuty(force: false);
  }

  Future<bool> _validateActiveDuty({required bool force}) async {
    if (!force && _tickCounter % _dutyValidationEveryTicks != 0) {
      return true;
    }
    if (_deploymentId == null || _dutyLogId == null || _token == null) {
      return true;
    }

    try {
      final detail = await ApiService.getDutyDetail(_token!, _deploymentId!);
      final currentLog = detail['current_log'] as Map<String, dynamic>?;
      final currentLogId = (currentLog?['id'] as num?)?.toInt();

      if (DutyResumeService.isMountedDutyActiveDetail(detail) &&
          currentLogId == _dutyLogId) {
        return true;
      }

      await _stopServiceSilently(
        'inactive_duty',
        clearPersistedState: true,
      );
      return false;
    } catch (error) {
      _log('duty validation skipped: $error');
      return true;
    }
  }

  Future<void> _stopServiceSilently(
    String reason, {
    bool clearPersistedState = false,
  }) async {
    FlutterForegroundTask.sendDataToMain({
      'event': 'stop',
      'reason': reason,
    });

    if (clearPersistedState) {
      await _cleanup();
    }

    _stopping = true;
    try {
      await FlutterForegroundTask.stopService();
    } catch (error) {
      _log('silent stop failed: $error');
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    await _positionSubscription?.cancel();
    await _activitySubscription?.cancel();
    await _saveQueue();
  }

  @override
  void onReceiveData(Object data) {
    if (data is! Map) {
      return;
    }

    if (data['action'] == 'stop') {
      final reason = (data['reason'] as String?) ?? 'manual_stop';
      _stopping = true;
      unawaited(_handleExternalStop(reason));
    }
  }

  Future<void> _handleExternalStop(String reason) async {
    if (_pendingPoints.isNotEmpty) {
      await _sendBatch();
    }

    if (_dutyLogId != null && _token != null) {
      try {
        await _trackingApi.stopTracking(
          token: _token!,
          request: TrackingStopRequest(
            dutyLogId: _dutyLogId!,
            reason: reason,
          ),
        );
      } catch (error) {
        _log('tracking/stop failed: $error');
      }
    }

    await _cleanup();
    FlutterForegroundTask.sendDataToMain({'event': 'stopped'});
  }

  void _log(String message) {
    if (kDebugMode && AppConfig.debugTrackingLogs) {
      debugPrint('[TrackingTaskHandler] $message');
    }
  }
}
