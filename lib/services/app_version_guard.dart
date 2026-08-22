import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/app_version_policy.dart';
import '../screens/force_update_screen.dart';
import '../utils/storage.dart';
import 'api_service.dart';

class AppVersionGuard {
  AppVersionGuard._();

  static bool _checking = false;
  static bool _showingUpdate = false;

  static Future<AppVersionCheckResult> check() async {
    final installedVersionCode = await installedBuildNumber();
    try {
      final policy = await ApiService.getAppVersionPolicy();
      final required = policy.requiresUpdate(installedVersionCode);
      await Storage.saveAppVersionPolicy(
        policy,
        updateRequired: required,
      );
      return AppVersionCheckResult(
        updateRequired: required,
        policy: policy,
        installedVersionCode: installedVersionCode,
      );
    } catch (_) {
      final cachedRequired = await Storage.wasAppUpdateRequired();
      if (cachedRequired) {
        return AppVersionCheckResult(
          updateRequired: true,
          policy: await Storage.getAppVersionPolicy() ??
              const AppVersionPolicy(
                minimumVersionCode: 1,
                latestVersionCode: 1,
                forceUpdate: true,
                playStoreUrl:
                    'https://play.google.com/store/apps/details?id=in.rpfwcr',
              ),
          installedVersionCode: installedVersionCode,
          fromCachedPolicy: true,
        );
      }
      return AppVersionCheckResult(
        updateRequired: false,
        policy: null,
        installedVersionCode: installedVersionCode,
        versionCheckFailed: true,
      );
    }
  }

  static Future<bool> enforceOnNavigator(GlobalKey<NavigatorState> key) async {
    if (_checking || _showingUpdate) return _showingUpdate;
    _checking = true;
    try {
      final result = await check();
      if (!result.updateRequired) return false;
      final navigator = key.currentState;
      final context = key.currentContext;
      final policy = result.policy;
      if (navigator == null ||
          context == null ||
          !context.mounted ||
          policy == null) {
        return false;
      }
      _showingUpdate = true;
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => ForceUpdateScreen(
            policy: policy,
            installedVersionCode: result.installedVersionCode,
            fromCachedPolicy: result.fromCachedPolicy,
          ),
        ),
        (route) => false,
      );
      return true;
    } finally {
      _checking = false;
    }
  }

  static Future<int> installedBuildNumber() async {
    final info = await PackageInfo.fromPlatform();
    return int.tryParse(info.buildNumber) ?? 1;
  }
}

class AppVersionCheckResult {
  final bool updateRequired;
  final AppVersionPolicy? policy;
  final int installedVersionCode;
  final bool fromCachedPolicy;
  final bool versionCheckFailed;

  const AppVersionCheckResult({
    required this.updateRequired,
    required this.policy,
    required this.installedVersionCode,
    this.fromCachedPolicy = false,
    this.versionCheckFailed = false,
  });
}
