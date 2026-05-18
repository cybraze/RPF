import 'dart:async';

import 'package:flutter/material.dart';

import '../screens/tracking_setup_screen.dart';
import 'background_tracking_prep.dart';
import 'session_manager.dart';
import 'storage.dart';

class PermissionRedirectGuard {
  PermissionRedirectGuard._();

  static bool _checking = false;
  static bool _redirecting = false;

  static Future<void> enforceRequiredPermissions() async {
    if (_checking || _redirecting || TrackingSetupScreen.isVisible) {
      return;
    }

    _checking = true;
    try {
      final token = await Storage.getToken();
      if (token == null || token.isEmpty) {
        return;
      }

      final status = await readTrackingSetupStatus();
      if (status.isComplete || TrackingSetupScreen.isVisible) {
        return;
      }

      final navigator = SessionManager.navigatorKey.currentState;
      final context = SessionManager.navigatorKey.currentContext;
      if (navigator == null || context == null || !context.mounted) {
        return;
      }

      _redirecting = true;
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const TrackingSetupScreen()),
        (route) => false,
      );

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'App use karne ke liye sabhi required permissions complete kariye.',
            ),
          ),
        );

      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 700)).then((_) {
          _redirecting = false;
        }),
      );
    } finally {
      _checking = false;
    }
  }
}
