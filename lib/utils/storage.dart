import 'package:shared_preferences/shared_preferences.dart';

import '../models/active_duty_geofence.dart';
import '../models/user_profile.dart';

class Storage {
  static const _tokenKey = 'token';
  static const _activeDutyLogIdKey = 'active_duty_log_id';
  static const _activeDeploymentIdKey = 'active_deployment_id';
  static const _trackingQueueKey = 'tracking_queue';
  static const _activeDutyGeofenceKey = 'active_duty_geofence';
  static const _userIdKey = 'user_id';
  static const _userProfileKey = 'user_profile';
  static const _permissionPromptPrefix = 'permission_prompt_';

  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userIdKey);
    await prefs.remove(_userProfileKey);
    await prefs.remove(_activeDutyLogIdKey);
    await prefs.remove(_activeDeploymentIdKey);
    await prefs.remove(_trackingQueueKey);
    await prefs.remove(_activeDutyGeofenceKey);
  }

  // ── Active Duty Log ID (for tracking resume on app restart) ───────────────

  static Future<void> saveActiveDutyLogId(
    int dutyLogId, {
    int? deploymentId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_activeDutyLogIdKey, dutyLogId);
    if (deploymentId != null) {
      await prefs.setInt(_activeDeploymentIdKey, deploymentId);
    }
  }

  static Future<int?> getActiveDutyLogId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_activeDutyLogIdKey);
  }

  static Future<int?> getActiveDeploymentId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_activeDeploymentIdKey);
  }

  static Future<void> clearActiveDutyLogId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_activeDutyLogIdKey);
    await prefs.remove(_activeDeploymentIdKey);
  }

  static Future<void> saveActiveDutyGeofence(
      ActiveDutyGeofence geofence) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeDutyGeofenceKey, geofence.toJsonString());
  }

  static Future<ActiveDutyGeofence?> getActiveDutyGeofence() async {
    final prefs = await SharedPreferences.getInstance();
    return ActiveDutyGeofence.fromJsonString(
      prefs.getString(_activeDutyGeofenceKey),
    );
  }

  static Future<void> clearActiveDutyGeofence() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_activeDutyGeofenceKey);
  }

  static Future<void> saveTrackingQueue(String queueJson) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_trackingQueueKey, queueJson);
  }

  static Future<String?> getTrackingQueue() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_trackingQueueKey);
  }

  static Future<void> clearTrackingQueue() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_trackingQueueKey);
  }

  static Future<void> saveUserId(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_userIdKey, userId);
  }

  static Future<int?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_userIdKey);
  }

  static Future<void> saveUserProfile(UserProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userProfileKey, UserProfile.toJsonString(profile));
  }

  static Future<UserProfile?> getUserProfile() async {
    final prefs = await SharedPreferences.getInstance();
    return UserProfile.fromJsonString(prefs.getString(_userProfileKey));
  }

  static Future<void> clearUserProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userProfileKey);
  }

  static Future<void> markPermissionPromptShown(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      '$_permissionPromptPrefix$key',
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  static Future<bool> wasPermissionPromptShownRecently(
    String key, {
    Duration within = const Duration(minutes: 2),
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getInt('$_permissionPromptPrefix$key');
    if (raw == null) {
      return false;
    }
    final lastShown = DateTime.fromMillisecondsSinceEpoch(raw);
    return DateTime.now().difference(lastShown) < within;
  }

  static Future<void> clearPermissionPrompt(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_permissionPromptPrefix$key');
  }
}
