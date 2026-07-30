import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../screens/login_screen.dart';
import '../services/api_service.dart';
import 'app_error_message.dart';
import 'storage.dart';

class SessionManager {
  SessionManager._();

  static final navigatorKey = GlobalKey<NavigatorState>();
  static bool _logoutInProgress = false;

  static Future<bool> validateSingleDeviceSession() async {
    final token = await Storage.getToken();
    if (token == null || token.isEmpty) {
      return false;
    }

    try {
      final config = await ApiService.getOtherConfiguration(token);
      final enabled = config['single_device_login_enabled'] == true;
      if (!enabled) {
        return true;
      }

      await ApiService.getHomeProfile(token);
      return true;
    } on SessionExpiredException {
      const configMessage =
          'Your account has been logged in on another device. You have been automatically logged out on this device.';
      await forceLogoutToLogin(message: configMessage);
      return false;
    } catch (_) {
      return true;
    }
  }

  static Future<void> forceLogoutToLogin({String? message}) async {
    if (_logoutInProgress) {
      return;
    }
    _logoutInProgress = true;

    try {
      await FlutterForegroundTask.stopService();
    } catch (_) {}

    await Storage.logout();

    final navigator = navigatorKey.currentState;
    final context = navigatorKey.currentContext;
    if (navigator != null) {
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }

    if (message != null && message.trim().isNotEmpty && context != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(userFriendlyErrorMessage(message))),
        );
    }

    await Future.delayed(const Duration(milliseconds: 300));
    _logoutInProgress = false;
  }
}
