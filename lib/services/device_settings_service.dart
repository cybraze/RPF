import 'dart:io';

import 'package:flutter/services.dart';

class DeviceSettingsService {
  DeviceSettingsService._();

  static const MethodChannel _channel = MethodChannel(
    'rpf_flutter/device_control',
  );

  static Future<bool> isIgnoringBatteryOptimizations() async {
    if (!Platform.isAndroid) {
      return true;
    }

    try {
      final result =
          await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> openBatteryOptimizationSettings() async {
    if (!Platform.isAndroid) {
      return false;
    }

    try {
      final result =
          await _channel.invokeMethod<bool>('openBatteryOptimizationSettings');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> requestIgnoreBatteryOptimizations() async {
    if (!Platform.isAndroid) {
      return false;
    }

    try {
      final result = await _channel
          .invokeMethod<bool>('requestIgnoreBatteryOptimizations');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> openAppDetailsSettings() async {
    if (!Platform.isAndroid) {
      return false;
    }

    try {
      final result =
          await _channel.invokeMethod<bool>('openAppDetailsSettings');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> openNotificationSettings() async {
    if (!Platform.isAndroid) {
      return false;
    }

    try {
      final result =
          await _channel.invokeMethod<bool>('openNotificationSettings');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isPowerSaveModeEnabled() async {
    if (!Platform.isAndroid) {
      return false;
    }

    try {
      final result =
          await _channel.invokeMethod<bool>('isPowerSaveModeEnabled');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<String> getAndroidId() async {
    if (!Platform.isAndroid) {
      return '';
    }

    try {
      final result = await _channel.invokeMethod<String>('getAndroidId');
      return result?.trim() ?? '';
    } catch (_) {
      return '';
    }
  }

  static Future<String> getDeviceName() async {
    if (!Platform.isAndroid) {
      return 'unknown';
    }

    try {
      final result = await _channel.invokeMethod<String>('getDeviceName');
      final trimmed = result?.trim() ?? '';
      return trimmed.isEmpty ? 'android' : trimmed;
    } catch (_) {
      return 'android';
    }
  }
}
