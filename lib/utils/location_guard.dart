import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'storage.dart';

Future<bool> ensureLocationEnabledForMountedDuty(
  BuildContext context, {
  bool force = true,
}) async {
  final enabled = await Geolocator.isLocationServiceEnabled();
  if (enabled) {
    return true;
  }

  if (!context.mounted ||
      await Storage.wasPermissionPromptShownRecently('location_service_on')) {
    return false;
  }

  await Storage.markPermissionPromptShown('location_service_on');
  final openSettings = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.location_off_rounded, color: Color(0xFFF04438), size: 22),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Location is Disabled',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      content: Text(
        force
            ? 'Location must remain enabled while duty is mounted. Please turn on Location to continue.'
            : 'Please enable Location to continue tracking.',
        style: const TextStyle(fontSize: 14),
      ),
      actions: [
        if (!force)
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Later'),
          ),
        ElevatedButton.icon(
          onPressed: () => Navigator.pop(ctx, true),
          icon: const Icon(Icons.settings_rounded, size: 16),
          label: const Text('Open Location Settings'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF3B5BDB),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ],
    ),
  );

  if (openSettings != true) {
    return false;
  }

  await Geolocator.openLocationSettings();
  await Future.delayed(const Duration(milliseconds: 600));
  return Geolocator.isLocationServiceEnabled();
}
