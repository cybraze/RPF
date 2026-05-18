import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../services/device_settings_service.dart';
import 'storage.dart';

const _locationPromptKey = 'location_access';
const _backgroundLocationPromptKey = 'background_location_access';
const _batteryPromptKey = 'battery_optimization';
const _notificationPromptKey = 'notification_permission';

class TrackingSetupStatus {
  final bool notificationAllowed;
  final bool locationAlwaysAllowed;
  final bool locationServiceEnabled;
  final bool batteryUnrestricted;

  const TrackingSetupStatus({
    required this.notificationAllowed,
    required this.locationAlwaysAllowed,
    required this.locationServiceEnabled,
    required this.batteryUnrestricted,
  });

  bool get isComplete =>
      notificationAllowed &&
      locationAlwaysAllowed &&
      locationServiceEnabled &&
      batteryUnrestricted;
}

Future<TrackingSetupStatus> readTrackingSetupStatus() async {
  final notificationPermission =
      await FlutterForegroundTask.checkNotificationPermission();
  final locationPermission = await Geolocator.checkPermission();
  final locationServiceEnabled = await Geolocator.isLocationServiceEnabled();
  final batteryUnrestricted =
      await DeviceSettingsService.isIgnoringBatteryOptimizations();

  return TrackingSetupStatus(
    notificationAllowed:
        notificationPermission == NotificationPermission.granted,
    locationAlwaysAllowed:
        !Platform.isAndroid || locationPermission == LocationPermission.always,
    locationServiceEnabled: locationServiceEnabled,
    batteryUnrestricted: batteryUnrestricted,
  );
}

Future<bool> ensureMandatoryTrackingSetupReady(
  BuildContext context, {
  bool requireLocationService = true,
}) async {
  while (context.mounted) {
    final notificationReady = await ensureNotificationPermissionReady(
      context,
      forceDialog: true,
      mandatory: true,
    );
    if (!notificationReady) {
      continue;
    }

    final locationReady = await ensureTrackingPermissionReady(
      context,
      forceBackgroundAccess: true,
      mandatory: true,
    );
    if (!locationReady) {
      continue;
    }

    if (requireLocationService) {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        await _showTrackingDialog(
          context,
          title: 'Enable Device Location',
          message:
              'Device Location/GPS must remain enabled for accurate mounted duty tracking.',
          primaryLabel: 'Open location settings',
          secondaryLabel: 'Required',
          mandatory: true,
        );
        await Geolocator.openLocationSettings();
        await Future.delayed(const Duration(milliseconds: 800));
        continue;
      }
    }

    final batteryReady = await ensureBatteryOptimizationReady(
      context,
      force: true,
      mandatory: true,
    );
    if (batteryReady) {
      return true;
    }
  }

  return false;
}

Future<bool> ensureTrackingPermissionReady(
  BuildContext context, {
  bool forceBackgroundAccess = false,
  bool mandatory = false,
}) async {
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }

  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    if (!context.mounted ||
        (!mandatory &&
            await Storage.wasPermissionPromptShownRecently(
              _locationPromptKey,
            ))) {
      return false;
    }

    await Storage.markPermissionPromptShown(_locationPromptKey);
    final openSettings = await _showTrackingDialog(
      context,
      title: 'Location Permission Required',
      message:
          'Mounted duty tracking requires location access to record live duty movement. Please allow location permission for this app.',
      primaryLabel: 'Open app permissions',
      secondaryLabel: mandatory ? 'Required' : 'Not now',
      mandatory: mandatory,
    );
    if (openSettings == true) {
      final opened = await DeviceSettingsService.openAppDetailsSettings();
      if (!opened) {
        await Geolocator.openAppSettings();
      }
      await Future.delayed(const Duration(milliseconds: 800));
      permission = await Geolocator.checkPermission();
    }
  }

  if (!Platform.isAndroid || permission == LocationPermission.always) {
    return permission != LocationPermission.denied &&
        permission != LocationPermission.deniedForever;
  }

  if (!forceBackgroundAccess) {
    return true;
  }

  if (!context.mounted ||
      (!mandatory &&
          await Storage.wasPermissionPromptShownRecently(
            _backgroundLocationPromptKey,
          ))) {
    return false;
  }

  await Storage.markPermissionPromptShown(_backgroundLocationPromptKey);
  final openSettings = await _showTrackingDialog(
    context,
    title: 'Enable Background Location',
    message:
        'Mounted duty tracking must continue when the app is in the background. Please select "Allow all the time" in Location permissions.',
    primaryLabel: 'Open location permission',
    secondaryLabel: mandatory ? 'Required' : 'Not now',
    mandatory: mandatory,
  );
  if (openSettings == true) {
    final opened = await DeviceSettingsService.openAppDetailsSettings();
    if (!opened) {
      await Geolocator.openAppSettings();
    }
    await Future.delayed(const Duration(milliseconds: 800));
    permission = await Geolocator.checkPermission();
  }

  return permission == LocationPermission.always;
}

Future<bool> ensureBatteryOptimizationReady(
  BuildContext context, {
  bool force = false,
  bool mandatory = false,
}) async {
  if (!Platform.isAndroid) {
    return true;
  }

  final ignored = await DeviceSettingsService.isIgnoringBatteryOptimizations();
  if (ignored) {
    return true;
  }

  if (!force) {
    return false;
  }

  if (!context.mounted ||
      (!mandatory &&
          await Storage.wasPermissionPromptShownRecently(_batteryPromptKey))) {
    return false;
  }

  await Storage.markPermissionPromptShown(_batteryPromptKey);
  final openSettings = await _showTrackingDialog(
    context,
    title: 'Allow Unrestricted Battery Usage',
    message:
        'To keep live duty tracking active, allow this app to run without battery optimization when prompted by the system.',
    primaryLabel: 'Allow',
    secondaryLabel: mandatory ? 'Required' : 'Not now',
    mandatory: mandatory,
  );

  if (openSettings != true) {
    return false;
  }

  final requested =
      await DeviceSettingsService.requestIgnoreBatteryOptimizations();
  if (!requested) {
    return false;
  }

  await Future.delayed(const Duration(milliseconds: 800));
  final updated = await DeviceSettingsService.isIgnoringBatteryOptimizations();
  if (updated) {
    await Storage.clearPermissionPrompt(_batteryPromptKey);
    return true;
  }
  return false;
}

Future<bool> ensureNotificationPermissionReady(
  BuildContext context, {
  bool forceDialog = false,
  bool mandatory = false,
}) async {
  final permission = await FlutterForegroundTask.checkNotificationPermission();
  if (permission == NotificationPermission.granted) {
    return true;
  }

  final requested = await FlutterForegroundTask.requestNotificationPermission();
  if (requested == NotificationPermission.granted) {
    await Storage.clearPermissionPrompt(_notificationPromptKey);
    return true;
  }

  if (!context.mounted) {
    return false;
  }

  if (!forceDialog &&
      !mandatory &&
      await Storage.wasPermissionPromptShownRecently(_notificationPromptKey)) {
    return false;
  }

  await Storage.markPermissionPromptShown(_notificationPromptKey);
  final openSettings = await _showTrackingDialog(
    context,
    title: 'Enable Notifications',
    message:
        'Mounted duty tracking requires notifications so the active tracking service remains visible while duty is running.',
    primaryLabel: 'Open notification settings',
    secondaryLabel: mandatory ? 'Required' : 'Later',
    mandatory: mandatory,
  );

  if (openSettings != true) {
    return false;
  }

  final opened = await DeviceSettingsService.openNotificationSettings();
  if (!opened) {
    await DeviceSettingsService.openAppDetailsSettings();
  }
  await Future.delayed(const Duration(milliseconds: 800));
  return await FlutterForegroundTask.checkNotificationPermission() ==
      NotificationPermission.granted;
}

Future<bool?> _showTrackingDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String primaryLabel,
  required String secondaryLabel,
  bool mandatory = false,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        title,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      ),
      content: Text(message, style: const TextStyle(fontSize: 14)),
      actions: [
        if (!mandatory)
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(secondaryLabel),
          )
        else
          TextButton(
            onPressed: null,
            child: Text(secondaryLabel),
          ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1E3A8A),
            foregroundColor: Colors.white,
          ),
          child: Text(primaryLabel),
        ),
      ],
    ),
  );
}
