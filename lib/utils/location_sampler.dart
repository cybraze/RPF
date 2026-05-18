import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class LocationSampler {
  LocationSampler._();

  static const int sampleCount = 3;
  static const double preferredAccuracyMeters = 15.0;
  static const Duration trackingInterval = Duration(seconds: 10);

  static LocationSettings trackingSettings({
    Duration? timeLimit,
  }) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        intervalDuration: trackingInterval,
        timeLimit: timeLimit,
      );
    }

    return LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0,
      timeLimit: timeLimit,
    );
  }

  static Future<Position> getBestEffortPosition({
    int count = sampleCount,
    Duration perSampleTimeout = const Duration(seconds: 6),
    Duration gap = const Duration(milliseconds: 900),
  }) async {
    Position? best;
    Object? lastError;

    for (var i = 0; i < count; i++) {
      try {
        final sample = await GeolocatorPlatform.instance.getCurrentPosition(
          locationSettings: trackingSettings(
            timeLimit: perSampleTimeout,
          ),
        );

        if (best == null || sample.accuracy < best.accuracy) {
          best = sample;
        }

        if (best.accuracy <= preferredAccuracyMeters) {
          return best;
        }
      } catch (error) {
        lastError = error;
      }

      if (i < count - 1) {
        await Future.delayed(gap);
      }
    }

    if (best != null) {
      return best;
    }

    throw lastError ?? Exception('Location sample nahi mil paaya.');
  }
}
