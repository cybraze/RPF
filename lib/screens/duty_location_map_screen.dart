import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';


class DutyLocationMapScreen extends StatefulWidget {
  final Map<String, dynamic> deployment;
  final Map<String, dynamic>? currentLog;
  final double? userLatitude;
  final double? userLongitude;

  const DutyLocationMapScreen({
    super.key,
    required this.deployment,
    required this.currentLog,
    required this.userLatitude,
    required this.userLongitude,
  });

  @override
  State<DutyLocationMapScreen> createState() => _DutyLocationMapScreenState();
}

class _DutyLocationMapScreenState extends State<DutyLocationMapScreen>
    with SingleTickerProviderStateMixin {
  static const double _preferredAccuracyMeters = 12.0;
  static const double _usableAccuracyMeters = 25.0;
  static const double _hardRejectAccuracyMeters = 60.0;

  final MapController _mapController = MapController();

  StreamSubscription<Position>? _positionSubscription;
  late final AnimationController _markerAnimationController;

  Animation<LatLng>? _markerAnimation;
  LatLng? _userPoint;
  LatLng? _animatedUserPoint;
  double? _lastAcceptedAccuracy;
  double _heading = 0;
  double _mapRotation = 0;
  bool _liveTrackingEnabled = false;
  bool _locationBlocked = false;
  bool _hasAutoFitted = false;
  bool _mapReady = false;
  // true when _userPoint is the stale value passed in from the previous screen
  bool _userPointIsStale = false;
  String _statusText = 'Initialising live location, please wait...';

  @override
  void initState() {
    super.initState();
    _markerAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..addListener(() {
        final next = _markerAnimation?.value;
        if (next != null && mounted) {
          setState(() {
            _animatedUserPoint = next;
          });
        }
      });

    // Do NOT pre-populate from widget data — that position is stale (taken
    // earlier on the previous screen, often via network/WiFi, which can be
    // hundreds of metres off).  Live GPS from _startLiveLocation will set
    // the correct position within a few seconds.
    final fallbackPoint = _latLngFrom(
      widget.userLatitude,
      widget.userLongitude,
    );
    _userPoint = fallbackPoint;
    _animatedUserPoint = fallbackPoint;
    _lastAcceptedAccuracy = null;
    _userPointIsStale = fallbackPoint != null;
    if (fallbackPoint != null) {
      _statusText = 'Showing approximate location, acquiring live GPS...';
    }
    unawaited(_startLiveLocation());
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _markerAnimationController.dispose();
    super.dispose();
  }

  int get _status => (widget.currentLog?['status'] as num?)?.toInt() ?? 0;

  Map<String, dynamic> get _post =>
      widget.deployment['post'] as Map<String, dynamic>? ?? const {};

  Map<String, dynamic> get _beat =>
      widget.deployment['beat'] as Map<String, dynamic>? ?? const {};

  LatLng? get _postPoint => _latLngFrom(
        _asDouble(_post['latitude'] ?? _post['lat']),
        _asDouble(_post['longitude'] ?? _post['lng']),
      );

  LatLng? get _beatPoint => _latLngFrom(
        _asDouble(_beat['latitude'] ?? _beat['lat'] ?? _beat['centroid_lat']),
        _asDouble(_beat['longitude'] ?? _beat['lng'] ?? _beat['centroid_lng']),
      );

  LatLng? get _targetPoint {
    if (_status == 0 || _status == 3) {
      return _postPoint;
    }
    return _beatPoint ?? (_beatPolyline.isNotEmpty ? _beatPolyline.first : null);
  }

  List<LatLng> get _beatPolygon =>
      _polygonPoints((_beat['polygon_corners'] as List?) ?? const []);

  List<LatLng> get _beatPolyline =>
      _polygonPoints((_beat['polyline_points'] as List?) ?? const []);

  bool get _isBeatPolyline =>
      _beat['location_type']?.toString().toLowerCase() == 'polyline';

  double get _beatRadiusMeters =>
      (_asDouble(_beat['radius_meter'] ?? _beat['radius']) ?? 0).toDouble();

  List<LatLng> get _beatPolylineCorridor =>
      _corridorAroundPolyline(_beatPolyline, _beatRadiusMeters);

  Future<void> _startLiveLocation() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return;
      setState(() {
        _liveTrackingEnabled = false;
        _locationBlocked = true;
        _statusText =
            'Location is turned off. Please enable it to use the live map.';
      });
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (!mounted) return;
      setState(() {
        _liveTrackingEnabled = false;
        _locationBlocked = true;
        _statusText = 'Location permission is required to use the live map.';
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _liveTrackingEnabled = true;
      _locationBlocked = false;
      _statusText = 'Searching for GPS signal...';
    });

    // No getCurrentPosition here — it has a short timeout and falls back to
    // inaccurate network/WiFi location when GPS hasn't warmed up yet.
    // Stream with no timeout lets GPS hardware warm up naturally.
    // distanceFilter:0  → fires on every GPS fix, even when stationary.
    // bestForNavigation → forces real GPS chip ON, prevents network fallback.
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
      ),
    ).listen(
      (position) => _updateUserPoint(position, fromLiveStream: true),
      onError: (_) {
        if (!mounted) return;
        setState(() {
          _liveTrackingEnabled = false;
          _statusText = 'GPS signal lost. Is location enabled?';
        });
      },
    );
  }

  void _updateUserPoint(Position position, {required bool fromLiveStream}) {
    if (!_shouldAcceptPosition(position, fromLiveStream: fromLiveStream)) {
      if (mounted) {
        setState(() {
          _statusText =
              'Weak GPS signal. Showing last reliable location.';
        });
      }
      return;
    }

    final nextPoint = LatLng(position.latitude, position.longitude);
    final previousPoint = _animatedUserPoint ?? _userPoint ?? nextPoint;

    _userPointIsStale = false;
    _userPoint = nextPoint;
    _lastAcceptedAccuracy = position.accuracy.isFinite
        ? position.accuracy
        : _lastAcceptedAccuracy;
    if (position.heading.isFinite && position.heading >= 0) {
      _heading = position.heading;
    }

    _markerAnimation = LatLngTween(
      begin: previousPoint,
      end: nextPoint,
    ).animate(
      CurvedAnimation(
        parent: _markerAnimationController,
        curve: Curves.easeOutCubic,
      ),
    );

    _markerAnimationController
      ..reset()
      ..forward();

    if (!mounted) return;

    final targetPoint = _targetPoint;
    setState(() {
      _statusText = targetPoint == null
          ? 'Live location active.'
          : '${_distanceLabel(nextPoint, targetPoint, _status)} - Live';
    });

    if (_mapReady && !_hasAutoFitted && targetPoint != null) {
      _fitToUserAndTarget();
      _hasAutoFitted = true;
    }
  }

  bool _shouldAcceptPosition(
    Position position, {
    required bool fromLiveStream,
  }) {
    if (!position.latitude.isFinite || !position.longitude.isFinite) {
      return false;
    }

    final accuracy = position.accuracy.isFinite
        ? position.accuracy
        : double.infinity;
    if (accuracy > _hardRejectAccuracyMeters) {
      return false;
    }

    final currentPoint = _userPoint;
    if (currentPoint == null) {
      return accuracy <= _usableAccuracyMeters;
    }

    // Current reference is the stale value passed from the previous screen —
    // skip drift check entirely so the first real GPS fix is always accepted.
    if (_userPointIsStale) {
      return accuracy <= _usableAccuracyMeters;
    }

    if (accuracy <= _preferredAccuracyMeters) {
      return true;
    }

    final nextPoint = LatLng(position.latitude, position.longitude);
    final drift = const Distance().as(LengthUnit.Meter, currentPoint, nextPoint);
    final speed = position.speed.isFinite && position.speed > 0
        ? position.speed
        : 0.0;
    final allowedDrift = math.max(
      25.0,
      (speed * 12) + (accuracy * 1.4),
    );

    if (drift <= allowedDrift) {
      return true;
    }

    if (!fromLiveStream && accuracy <= _usableAccuracyMeters) {
      return true;
    }

    if (drift > 120 && speed < 2.0) {
      return false;
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    final mapCenter =
        _animatedUserPoint ??
        _userPoint ??
        _targetPoint ??
        _postPoint ??
        _beatPoint ??
        const LatLng(23.2599, 77.4126);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Duty Map'),
        backgroundColor: const Color(0xFF1E3A8A),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _startLiveLocation,
            tooltip: 'Refresh live location',
            icon: const Icon(Icons.my_location_rounded),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: mapCenter,
              initialZoom: 16,
              initialRotation: 0,
              onMapReady: () {
                _mapReady = true;
                if (!_hasAutoFitted && _targetPoint != null) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      _fitToUserAndTarget();
                      _hasAutoFitted = true;
                    }
                  });
                }
              },
              onPositionChanged: (camera, _) {
                if (mounted) {
                  setState(() {
                    _mapRotation = camera.rotation;
                  });
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'rpf_flutter',
              ),
              if (_postPoint != null)
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: _postPoint!,
                      radius:
                          (_asDouble(_post['radius_meter'] ?? _post['radius']) ??
                                  0)
                              .clamp(0, 250)
                              .toDouble(),
                      useRadiusInMeter: true,
                      color: const Color(0xFF2563EB).withOpacity(0.12),
                      borderColor: const Color(0xFF2563EB),
                      borderStrokeWidth: 2,
                    ),
                  ],
                ),
              if (_beatPoint != null && _beatPolygon.isEmpty && !_isBeatPolyline)
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: _beatPoint!,
                      radius:
                          (_asDouble(_beat['radius_meter'] ?? _beat['radius']) ??
                                  0)
                              .clamp(0, 500)
                              .toDouble(),
                      useRadiusInMeter: true,
                      color: const Color(0xFF16A34A).withOpacity(0.10),
                      borderColor: const Color(0xFF16A34A),
                      borderStrokeWidth: 2,
                    ),
                  ],
                ),
              if (_isBeatPolyline && _beatPolyline.isNotEmpty) ...[
                if (_beatPolylineCorridor.isNotEmpty)
                  PolygonLayer(
                    polygons: [
                      Polygon(
                        points: _beatPolylineCorridor,
                        color: const Color(0xFF16A34A).withOpacity(0.12),
                        borderColor: const Color(0xFF16A34A),
                        borderStrokeWidth: 1.5,
                      ),
                    ],
                  ),
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _beatPolyline,
                      strokeWidth: 5,
                      color: const Color(0xFF16A34A),
                    ),
                  ],
                ),
              ],
              if (_beatPolygon.isNotEmpty)
                PolygonLayer(
                  polygons: [
                    Polygon(
                      points: _beatPolygon,
                      color: const Color(0xFF16A34A).withOpacity(0.12),
                      borderColor: const Color(0xFF16A34A),
                      borderStrokeWidth: 2,
                    ),
                  ],
                ),
              if ((_animatedUserPoint ?? _userPoint) != null &&
                  _targetPoint != null)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: [(_animatedUserPoint ?? _userPoint)!, _targetPoint!],
                      strokeWidth: 4,
                      color: const Color(0xFFEF4444),
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  if (_postPoint != null)
                    Marker(
                      point: _postPoint!,
                      width: 88,
                      height: 64,
                      child: _marker(
                        color: const Color(0xFF2563EB),
                        icon: Icons.location_city_rounded,
                        label: _post['name']?.toString() ?? 'Post',
                      ),
                    ),
                  if ((_beatPoint ?? (_beatPolyline.isNotEmpty ? _beatPolyline.first : null)) != null)
                    Marker(
                      point: _beatPoint ?? _beatPolyline.first,
                      width: 88,
                      height: 64,
                      child: _marker(
                        color: const Color(0xFF16A34A),
                        icon: Icons.route_rounded,
                        label: _beat['name']?.toString() ?? 'Beat',
                      ),
                    ),
                  if ((_animatedUserPoint ?? _userPoint) != null)
                    Marker(
                      point: (_animatedUserPoint ?? _userPoint)!,
                      width: 84,
                      height: 64,
                      child: _marker(
                        color: const Color(0xFFEF4444),
                        icon: Icons.person_pin_circle_rounded,
                        label: 'You',
                        rotationRadians: _heading * (math.pi / 180),
                      ),
                    ),
                ],
              ),
            ],
          ),
          Positioned(
            right: 12,
            top: 52,
            child: Column(
              children: [
                _roundControl(
                  icon: Icons.center_focus_strong_rounded,
                  tooltip: 'Recenter',
                  onTap: _recenterToUser,
                ),
                const SizedBox(height: 10),
                _roundControl(
                  icon: Icons.fit_screen_rounded,
                  tooltip: 'Auto fit',
                  onTap: _fitToUserAndTarget,
                ),
                const SizedBox(height: 10),
                _roundControl(
                  icon: Icons.explore_rounded,
                  tooltip: 'Compass',
                  badge: '${_heading.round()} deg',
                  onTap: _toggleCompassAlignment,
                ),
              ],
            ),
          ),
          Positioned(
            right: 12,
            top: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                '(c) OpenStreetMap',
                style: TextStyle(
                  color: Color(0xFF475569),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          if (_locationBlocked)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.25),
                alignment: Alignment.center,
                padding: const EdgeInsets.all(24),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.location_off_rounded,
                        color: Color(0xFFDC2626),
                        size: 34,
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Live Map Unavailable',
                        style: TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _statusText,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF475569),
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          OutlinedButton(
                            onPressed: () {
                              Geolocator.openLocationSettings();
                            },
                            child: const Text('Open Settings'),
                          ),
                          const SizedBox(width: 10),
                          FilledButton(
                            onPressed: _startLiveLocation,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: _MapLegendCard(
              postName: _post['name']?.toString(),
              beatName: _beat['name']?.toString(),
              distanceLabel: _statusText,
              targetLabel: _liveTrackingEnabled
                  ? ((_status == 0 || _status == 3)
                      ? 'Target: Post'
                      : 'Target: Beat')
                  : 'Live tracking off',
            ),
          ),
        ],
      ),
    );
  }

  void _fitToUserAndTarget() {
    final user = _animatedUserPoint ?? _userPoint;
    final target = _targetPoint;

    if (!_mapReady) return;

    if (user == null || target == null) {
      final fallback = user ?? target;
      if (fallback != null) {
        _mapController.move(fallback, 16);
      }
      return;
    }

    _mapController.fitCamera(
      CameraFit.coordinates(
        coordinates: [user, target],
        padding: const EdgeInsets.fromLTRB(56, 90, 56, 180),
        maxZoom: 17.5,
      ),
    );
  }

  void _recenterToUser() {
    final user = _animatedUserPoint ?? _userPoint;
    if (user == null || !_mapReady) return;
    _mapController.moveAndRotate(user, 17, _mapRotation);
  }

  void _toggleCompassAlignment() {
    if (!_mapReady) return;
    final center = (_animatedUserPoint ?? _userPoint) ?? _mapController.camera.center;
    final zoom = _mapController.camera.zoom;
    final shouldResetNorth = _mapRotation.abs() > 5;
    final nextRotation = shouldResetNorth ? 0.0 : _heading;
    _mapController.moveAndRotate(center, zoom, nextRotation);
  }

  Widget _roundControl({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    String? badge,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white.withOpacity(0.94),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: 48,
            height: badge == null ? 48 : 58,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 20, color: const Color(0xFF0F172A)),
                if (badge != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    badge,
                    style: const TextStyle(
                      color: Color(0xFF475569),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Widget _marker({
    required Color color,
    required IconData icon,
    required String label,
    double rotationRadians = 0,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Transform.rotate(
          angle: rotationRadians,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  static LatLng? _latLngFrom(double? lat, double? lng) {
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  static List<LatLng> _polygonPoints(List corners) {
    return corners
        .whereType<Map>()
        .map(
          (corner) => _latLngFrom(
            _asDouble(corner['latitude'] ?? corner['lat']),
            _asDouble(corner['longitude'] ?? corner['lng']),
          ),
        )
        .whereType<LatLng>()
      .toList();
  }

  static List<LatLng> _corridorAroundPolyline(
    List<LatLng> points,
    double radiusMeters,
  ) {
    if (points.length < 2 || radiusMeters <= 0) {
      return const [];
    }

    final meanLat = points
            .map((point) => point.latitude)
            .reduce((sum, value) => sum + value) /
        points.length;
    final metersPerDegreeLat = 111320.0;
    final metersPerDegreeLng =
        metersPerDegreeLat * math.cos(meanLat * math.pi / 180);

    _MapPoint toMapPoint(LatLng point) => _MapPoint(
          point.longitude * metersPerDegreeLng,
          point.latitude * metersPerDegreeLat,
        );

    LatLng toLatLng(_MapPoint point) => LatLng(
          point.y / metersPerDegreeLat,
          point.x / metersPerDegreeLng,
        );

    final projected = points.map(toMapPoint).toList();
    final left = <LatLng>[];
    final right = <LatLng>[];

    for (var i = 0; i < projected.length; i++) {
      final normal = _corridorNormal(projected, i);
      left.add(toLatLng(_MapPoint(
        projected[i].x + normal.x * radiusMeters,
        projected[i].y + normal.y * radiusMeters,
      )));
      right.add(toLatLng(_MapPoint(
        projected[i].x - normal.x * radiusMeters,
        projected[i].y - normal.y * radiusMeters,
      )));
    }

    return [...left, ...right.reversed];
  }

  static _MapPoint _corridorNormal(List<_MapPoint> points, int index) {
    _MapPoint segmentNormal(int startIndex, int endIndex) {
      final dx = points[endIndex].x - points[startIndex].x;
      final dy = points[endIndex].y - points[startIndex].y;
      final length = math.sqrt(dx * dx + dy * dy);
      if (length < 1e-9) {
        return const _MapPoint(0, 1);
      }
      return _MapPoint(-dy / length, dx / length);
    }

    if (index == 0) {
      return segmentNormal(0, 1);
    }
    if (index == points.length - 1) {
      return segmentNormal(points.length - 2, points.length - 1);
    }

    final previous = segmentNormal(index - 1, index);
    final next = segmentNormal(index, index + 1);
    final x = previous.x + next.x;
    final y = previous.y + next.y;
    final length = math.sqrt(x * x + y * y);
    if (length < 1e-9) {
      return next;
    }
    return _MapPoint(x / length, y / length);
  }

  static String _distanceLabel(LatLng? user, LatLng? target, int status) {
    if (user == null || target == null) {
      return status <= 0
          ? 'Post distance unavailable'
          : 'Beat distance unavailable';
    }

    final distance = const Distance().as(LengthUnit.Meter, user, target);
    final rounded = distance.round();
    return status <= 0 ? 'Post: $rounded m away' : 'Beat: $rounded m away';
  }

  static double? _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }
}

class _MapPoint {
  final double x;
  final double y;

  const _MapPoint(this.x, this.y);
}

class LatLngTween extends Tween<LatLng> {
  LatLngTween({required super.begin, required super.end});

  @override
  LatLng lerp(double t) {
    final from = begin!;
    final to = end!;
    return LatLng(
      from.latitude + (to.latitude - from.latitude) * t,
      from.longitude + (to.longitude - from.longitude) * t,
    );
  }
}

class _MapLegendCard extends StatelessWidget {
  final String? postName;
  final String? beatName;
  final String distanceLabel;
  final String targetLabel;

  const _MapLegendCard({
    required this.postName,
    required this.beatName,
    required this.distanceLabel,
    required this.targetLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            targetLabel,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            distanceLabel,
            style: const TextStyle(
              color: Color(0xFF475569),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if ((postName ?? '').trim().isNotEmpty)
                _chip(const Color(0xFF2563EB), 'Post: $postName'),
              if ((beatName ?? '').trim().isNotEmpty)
                _chip(const Color(0xFF16A34A), 'Beat: $beatName'),
              _chip(const Color(0xFFEF4444), 'You'),
            ],
          ),
        ],
      ),
    );
  }

  static Widget _chip(Color color, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
