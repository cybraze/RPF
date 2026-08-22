import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../models/app_version_policy.dart';
import '../models/inspection_task.dart';
import '../models/tracking_point.dart';
import '../models/user_profile.dart';
import '../models/beat_sector_models.dart';
import 'device_settings_service.dart';

class SessionExpiredException implements Exception {
  final String message;

  const SessionExpiredException([
    this.message = 'Session expired. Please login again.',
  ]);

  @override
  String toString() => message;
}

class ApiService {
  static const String baseUrl = AppConfig.apiBaseUrl;

  /// Safe JSON decode — returns a clear error if the response is HTML or invalid
  static Map<String, dynamic> _decodeJson(http.Response response) {
    final body = response.body.trim();
    if (body.isEmpty) {
      throw Exception(
          "Server returned an empty response (status: ${response.statusCode})");
    }
    if (!body.startsWith('{') && !body.startsWith('[')) {
      throw Exception("Server error (status: ${response.statusCode})");
    }
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      throw Exception(
          "Failed to parse server response (status: ${response.statusCode})");
    }
  }

  // â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€
  // AUTH
  // â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€

  static Future<Map<String, dynamic>> login(
      String login, String password) async {
    final androidId = await DeviceSettingsService.getAndroidId();
    if (androidId.isEmpty) {
      throw Exception('Android ID not available. Please try again.');
    }
    final deviceName = await DeviceSettingsService.getDeviceName();
    final response = await http.post(
      Uri.parse("$baseUrl/auth/login"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "login": login,
        "password": password,
        "device_name": deviceName,
        "android_id": androidId,
      }),
    );
    final data = _decodeJson(response);
    if (response.statusCode == 200) return data;
    throw Exception(data['message'] ?? "Login failed");
  }

  static UserProfile? extractUserProfileFromLoginResponse(
      Map<String, dynamic> response) {
    final data = response['data'];
    if (data is! Map) {
      return null;
    }

    final profile = UserProfile.fromDynamic(
      data['user'] ?? data['employee'] ?? data['profile'] ?? data,
    );
    return profile;
  }

  static Future<AppVersionPolicy> getAppVersionPolicy() async {
    final response = await http.get(
      AppConfig.apiUri('app/version'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    );
    final data = _decodeJson(response);
    if (response.statusCode == 200) {
      return AppVersionPolicy.fromJson(data);
    }
    throw Exception(data['message'] ?? 'Failed to check app version');
  }

  static Future<UserProfile?> getCurrentUserProfile(String token) async {
    final candidates = <String>[
      '$baseUrl/auth/me',
      '$baseUrl/me',
      '$baseUrl/profile',
      '$baseUrl/user/profile',
    ];

    for (final url in candidates) {
      try {
        final response = await http.get(
          Uri.parse(url),
          headers: {
            "Authorization": "Bearer $token",
            "Content-Type": "application/json",
            "Accept": "application/json",
          },
        );

        if (response.statusCode == 404) {
          continue;
        }

        final data = _decodeJson(response);
        if (response.statusCode == 200) {
          final body = data['data'] ?? data;
          return UserProfile.fromDynamic(
            body is Map
                ? (body['user'] ?? body['employee'] ?? body['profile'] ?? body)
                : body,
          );
        }
      } catch (_) {
        continue;
      }
    }

    return null;
  }

  static Future<void> sendOtp(String mobile) async {
    final response = await http.post(
      Uri.parse("$baseUrl/auth/forgot-password"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"mobile": mobile}),
    );
    final data = _decodeJson(response);
    if (response.statusCode != 200) {
      throw Exception(data['message'] ?? "OTP send failed");
    }
  }

  static Future<void> resetPassword(
      String mobile, String otp, String password) async {
    final response = await http.post(
      Uri.parse("$baseUrl/auth/reset-password"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "mobile": mobile,
        "otp": otp,
        "password": password,
        "password_confirmation": password,
      }),
    );
    final data = _decodeJson(response);
    if (response.statusCode != 200) {
      throw Exception(data['message'] ?? "Reset failed");
    }
  }

  // â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€
  // DUTY LIST / DETAIL
  // â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€

  static Future<InspectionTaskPage> getInspectionTasks(
    String token, {
    required String status,
    int page = 1,
    int perPage = 20,
  }) async {
    final response = await http.get(
      AppConfig.apiUri("inspection-tasks").replace(
        queryParameters: {
          'status': status,
          'page': page.toString(),
          'per_page': perPage.toString(),
        },
      ),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
        "Accept": "application/json",
      },
    );
    final data = _decodeJson(response);
    if (response.statusCode == 401) {
      throw const SessionExpiredException();
    }
    if (response.statusCode == 200) {
      return InspectionTaskPage.fromJson(data);
    }
    throw Exception(data['message'] ?? "Failed to load inspection tasks");
  }

  static Future<InspectionTask> getInspectionTaskDetail(
    String token,
    int taskId,
  ) async {
    final response = await http.get(
      AppConfig.apiUri("inspection-tasks/$taskId"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
        "Accept": "application/json",
      },
    );
    final data = _decodeJson(response);
    if (response.statusCode == 401) {
      throw const SessionExpiredException();
    }
    if (response.statusCode == 200) {
      final payload = data['data'];
      if (payload is Map && payload['task'] is Map) {
        return InspectionTask.fromJson(
          (payload['task'] as Map).cast<String, dynamic>(),
        );
      }
      if (payload is Map) {
        return InspectionTask.fromJson(payload.cast<String, dynamic>());
      }
    }
    throw Exception(data['message'] ?? "Failed to load task detail");
  }

  static Future<void> completeInspectionTask(
    String token,
    int taskId, {
    required String completionRemark,
  }) async {
    final response = await http.post(
      AppConfig.apiUri("inspection-tasks/$taskId/complete"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
        "Accept": "application/json",
      },
      body: jsonEncode({
        'completion_remark': completionRemark,
      }),
    );
    final data = _decodeJson(response);
    if (response.statusCode == 401) {
      throw const SessionExpiredException();
    }
    if (response.statusCode == 200 || response.statusCode == 201) {
      return;
    }
    throw Exception(data['message'] ?? "Failed to complete task");
  }

  static Future<List<dynamic>> getDutyList(String token) async {
    final response = await http.get(
      Uri.parse("$baseUrl/duty/list"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json"
      },
    );
    final data = _decodeJson(response);
    if (response.statusCode == 200) return data['data']['items'];
    throw Exception(data['message'] ?? "Failed to load duties");
  }

  static Future<Map<String, dynamic>> getDutyDetail(
      String token, int deploymentId) async {
    final response = await http.get(
      Uri.parse("$baseUrl/duty/$deploymentId"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json"
      },
    );
    final data = _decodeJson(response);
    if (response.statusCode == 200) return data['data'] as Map<String, dynamic>;
    throw Exception(data['message'] ?? "Failed to load duty detail");
  }

  static Future<Map<String, dynamic>> getDashboard(String token) async {
    final response = await http.get(
      AppConfig.apiUri("fayyum-api/home"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
        "Accept": "application/json",
      },
    );
    final data = _decodeJson(response);
    if (response.statusCode == 200) {
      return data['data'] as Map<String, dynamic>;
    }
    throw Exception(data['message'] ?? "Failed to load dashboard");
  }

  static Future<List<dynamic>> getDutyLifecycleReport(
    String token, {
    String? dateFrom,
    String? dateTo,
    int? userId,
    int? postId,
    String status = 'all',
    String actionType = 'all',
    int? forceReasonId,
  }) async {
    final query = <String, String>{
      if (dateFrom != null && dateFrom.isNotEmpty) 'date_from': dateFrom,
      if (dateTo != null && dateTo.isNotEmpty) 'date_to': dateTo,
      if (userId != null && userId > 0) 'user_id': userId.toString(),
      if (postId != null && postId > 0) 'post_id': postId.toString(),
      if (status.isNotEmpty) 'status': status,
      if (actionType.isNotEmpty) 'action_type': actionType,
      if (forceReasonId != null && forceReasonId > 0)
        'force_reason_id': forceReasonId.toString(),
    };

    final response = await http.get(
      Uri.parse("$baseUrl/reports/duty-lifecycle").replace(
        queryParameters: query.isEmpty ? null : query,
      ),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
        "Accept": "application/json",
      },
    );
    final data = _decodeJson(response);
    if (response.statusCode == 200) {
      final payload = data['data'] as Map<String, dynamic>? ?? const {};
      return payload['items'] as List<dynamic>? ?? const [];
    }
    throw Exception(data['message'] ?? "Failed to load duty lifecycle report");
  }

  static Future<Map<String, dynamic>> getHomeDutyReport(
    String token, {
    required String date,
  }) async {
    final response = await http.get(
      AppConfig.apiUri("fayyum-api/home/duty-report").replace(
        queryParameters: {
          'date': date,
        },
      ),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
        "Accept": "application/json",
      },
    );
    final data = _decodeJson(response);
    if (response.statusCode == 200) {
      return data['data'] as Map<String, dynamic>;
    }
    throw Exception(data['message'] ?? "Failed to load duty report");
  }

  static Future<Map<String, dynamic>> sendHomeLocation(
    String token, {
    required double latitude,
    required double longitude,
    double? accuracy,
  }) async {
    final response = await http.post(
      AppConfig.apiUri("fayyum-api/home/send-location"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
        "Accept": "application/json",
      },
      body: jsonEncode({
        'latitude': latitude,
        'longitude': longitude,
        if (accuracy != null) 'accuracy': accuracy,
      }),
    );
    final data = _decodeJson(response);
    if (response.statusCode == 200 || response.statusCode == 201) {
      return data['data'] as Map<String, dynamic>;
    }
    throw Exception(data['message'] ?? "Failed to send location");
  }

  static Future<String> updateProfilePhoto(
      String token, String photoPath) async {
    final uri = Uri.parse('$baseUrl/profile/photo');
    final request = http.MultipartRequest('POST', uri);
    request.headers['Authorization'] = 'Bearer $token';
    request.headers['Accept'] = 'application/json';
    request.files.add(await http.MultipartFile.fromPath('photo', photoPath));

    final streamed = await request.send();
    final body = await streamed.stream.bytesToString();
    final bodyTrim = body.trim();
    if (!bodyTrim.startsWith('{')) {
      throw Exception('Server error (${streamed.statusCode})');
    }
    final data = jsonDecode(bodyTrim) as Map<String, dynamic>;
    if (streamed.statusCode == 200 || streamed.statusCode == 201) {
      final payload = data['data'];
      if (payload is Map<String, dynamic>) {
        final directUrl = payload['profile_photo_url'] ??
            payload['photo_url'] ??
            payload['avatar_url'];
        if (directUrl != null) {
          return directUrl.toString();
        }

        final user = payload['user'];
        if (user is Map<String, dynamic>) {
          final nestedUrl = user['profile_photo_url'] ??
              user['photo_url'] ??
              user['avatar_url'];
          if (nestedUrl != null) {
            return nestedUrl.toString();
          }
        }
      }
      return '';
    }
    throw Exception(data['message'] ?? 'Photo update failed');
  }

  static Future<Map<String, dynamic>> getHomeProfile(String token) async {
    final response = await http.get(
      AppConfig.apiUri("fayyum-api/home/profile"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
        "Accept": "application/json",
      },
    );
    final data = _decodeJson(response);
    if (response.statusCode == 401) {
      throw const SessionExpiredException();
    }
    if (response.statusCode == 200) {
      return data['data'] as Map<String, dynamic>;
    }
    throw Exception(data['message'] ?? "Failed to load profile");
  }

  static Future<Map<String, dynamic>> getOtherConfiguration(
      String token) async {
    final response = await http.get(
      AppConfig.apiUri("fayyum-api/other-configuration"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
        "Accept": "application/json",
      },
    );
    final data = _decodeJson(response);
    if (response.statusCode == 401) {
      throw const SessionExpiredException();
    }
    if (response.statusCode == 200) {
      return data['data'] as Map<String, dynamic>;
    }
    throw Exception(data['message'] ?? "Failed to load configuration");
  }

  static Future<void> updateHomePassword(
    String token, {
    required String currentPassword,
    required String password,
    required String passwordConfirmation,
  }) async {
    final response = await http.post(
      AppConfig.apiUri("fayyum-api/home/update-password"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
        "Accept": "application/json",
      },
      body: jsonEncode({
        'current_password': currentPassword,
        'password': password,
        'password_confirmation': passwordConfirmation,
      }),
    );
    final data = _decodeJson(response);
    if (response.statusCode == 200) {
      return;
    }
    throw Exception(data['message'] ?? "Failed to update password");
  }

  static Future<List<dynamic>> getUserPerformanceReport(
    String token, {
    String? dateFrom,
    String? dateTo,
  }) async {
    final query = <String, String>{
      if (dateFrom != null && dateFrom.isNotEmpty) 'date_from': dateFrom,
      if (dateTo != null && dateTo.isNotEmpty) 'date_to': dateTo,
    };

    final response = await http.get(
      Uri.parse("$baseUrl/reports/user-performance").replace(
        queryParameters: query.isEmpty ? null : query,
      ),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
        "Accept": "application/json",
      },
    );
    final data = _decodeJson(response);
    if (response.statusCode == 200) {
      final payload = data['data'] as Map<String, dynamic>? ?? const {};
      return payload['items'] as List<dynamic>? ?? const [];
    }
    throw Exception(
        data['message'] ?? "Failed to load user performance report");
  }

  // â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€
  // DUTY LIFECYCLE
  //
  // Server routes:
  //   POST /duty/login
  //   POST /duty/mount
  //   POST /duty/dismount
  //   POST /duty/logout
  //
  // All endpoints require deployment_id + latitude + longitude in the body
  // (server's validateGpsPayload runs on all of them)
  // â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€

  static Future<void> loginDuty(
      String token, int deploymentId, double lat, double lng) async {
    final response = await http.post(
      Uri.parse("$baseUrl/duty/login"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json"
      },
      body: jsonEncode({
        "deployment_id": deploymentId,
        "latitude": lat,
        "longitude": lng,
      }),
    );
    final data = _decodeJson(response);
    if (response.statusCode != 201 && response.statusCode != 200) {
      throw Exception(data['message'] ?? "Duty login failed");
    }
  }

  static Future<Map<String, dynamic>> mountDuty(
      String token, int deploymentId, double lat, double lng) async {
    final response = await http.post(
      Uri.parse("$baseUrl/duty/mount"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json"
      },
      body: jsonEncode({
        "deployment_id": deploymentId,
        "latitude": lat,
        "longitude": lng,
      }),
    );
    final data = _decodeJson(response);
    if (response.statusCode != 200) {
      throw Exception(data['message'] ?? "Mount failed");
    }
    return data['data'] as Map<String, dynamic>? ?? const {};
  }

  static Future<void> dismountDuty(
      String token, int deploymentId, double lat, double lng) async {
    final response = await http.post(
      Uri.parse("$baseUrl/duty/dismount"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json"
      },
      body: jsonEncode({
        "deployment_id": deploymentId,
        "latitude": lat,
        "longitude": lng,
      }),
    );
    final data = _decodeJson(response);
    if (response.statusCode != 200) {
      throw Exception(data['message'] ?? "Dismount failed");
    }
  }

  static Future<void> logoutDuty(
      String token, int deploymentId, double lat, double lng) async {
    final response = await http.post(
      Uri.parse("$baseUrl/duty/logout"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json"
      },
      body: jsonEncode({
        "deployment_id": deploymentId,
        "latitude": lat,
        "longitude": lng,
      }),
    );
    final data = _decodeJson(response);
    if (response.statusCode != 200) {
      throw Exception(data['message'] ?? "Logout failed");
    }
  }

  // â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€
  // ACTIVITY
  // â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€

  /// GET /activity-categories
  /// Response: { data: { categories: [ { id, name, subs: [{id, name}] } ] } }
  static Future<List<dynamic>> getActivityCategories(String token) async {
    final response = await http.get(
      Uri.parse("$baseUrl/activity-categories"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json"
      },
    );
    final data = _decodeJson(response);
    if (response.statusCode == 200) {
      final d = data['data'];
      if (d is Map && d['categories'] is List) return d['categories'];
      if (d is List) return d;
      return [];
    }
    throw Exception(data['message'] ?? "Failed to load activity categories");
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TRACKING
  // ─────────────────────────────────────────────────────────────────────────

  /// POST /tracking/start — called once after duty is mounted
  static Future<void> startTrackingSession(String token, int dutyLogId) async {
    final response = await http.post(
      Uri.parse("$baseUrl/tracking/start"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
      },
      body: jsonEncode({"duty_log_id": dutyLogId}),
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      final body = response.body.trim();
      String msg = "Tracking start failed";
      try {
        if (body.startsWith('{')) {
          msg = (jsonDecode(body) as Map)['message'] ?? msg;
        }
      } catch (_) {}
      throw Exception(msg);
    }
  }

  /// POST /tracking/location — send batched GPS points.
  /// Returns the HTTP status code so caller can handle 409/401 specially.
  static Future<int> sendTrackingPoints(
      String token, int dutyLogId, List<TrackingPoint> points) async {
    final response = await http.post(
      Uri.parse("$baseUrl/tracking/location"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
      },
      body: jsonEncode({
        "duty_log_id": dutyLogId,
        "points": points.map((p) => p.toJson()).toList(),
      }),
    );
    return response.statusCode;
  }

  /// POST /tracking/stop — called on dismount, logout, or 409 conflict
  static Future<void> stopTrackingSession(
      String token, int dutyLogId, String reason) async {
    await http.post(
      Uri.parse("$baseUrl/tracking/stop"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
      },
      body: jsonEncode({
        "duty_log_id": dutyLogId,
        "reason": reason,
      }),
    );
    // Best effort — ignore response errors
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ACTIVITY
  // ─────────────────────────────────────────────────────────────────────────

  /// POST /activity-logs
  /// multipart request â€" photo optional, remaining fields required
  static Future<void> saveActivityLog({
    required String token,
    required int dutyLogId,
    required int mainCategoryId,
    required int subCategoryId,
    required double latitude,
    required double longitude,
    String? remarks,
    String? photoPath,
  }) async {
    final uri = Uri.parse("$baseUrl/activity-logs");
    final request = http.MultipartRequest('POST', uri);

    request.headers['Authorization'] = 'Bearer $token';
    request.fields['duty_log_id'] = dutyLogId.toString();
    request.fields['main_category_id'] = mainCategoryId.toString();
    request.fields['sub_category_id'] = subCategoryId.toString();
    request.fields['latitude'] = latitude.toString();
    request.fields['longitude'] = longitude.toString();
    request.fields['activity_time'] = DateTime.now().toIso8601String();
    if (remarks != null && remarks.isNotEmpty) {
      request.fields['remarks'] = remarks;
    }
    if (photoPath != null && photoPath.isNotEmpty) {
      request.files.add(await http.MultipartFile.fromPath('photo', photoPath));
    }

    final streamed = await request.send();
    final body = await streamed.stream.bytesToString();
    final bodyTrim = body.trim();

    if (streamed.statusCode != 200 && streamed.statusCode != 201) {
      String msg = "Failed to save activity";
      try {
        if (bodyTrim.startsWith('{')) {
          final json = jsonDecode(bodyTrim) as Map;
          msg = json['message'] ?? msg;
        }
      } catch (_) {}
      throw Exception(msg);
    }
  }

  static Map<String, dynamic> _decodeMultipartBody(
    int statusCode,
    String body,
  ) {
    final bodyTrim = body.trim();
    if (bodyTrim.isEmpty) {
      return <String, dynamic>{};
    }
    if (!bodyTrim.startsWith('{')) {
      throw Exception('Server error ($statusCode)');
    }
    return jsonDecode(bodyTrim) as Map<String, dynamic>;
  }

  static List<Map<String, dynamic>> _extractBeatList(dynamic payload) {
    if (payload is List) {
      return payload
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
    }
    if (payload is Map) {
      final data = payload.cast<String, dynamic>();
      for (final key in const [
        'items',
        'data',
        'inspections',
        'records',
        'results',
        'rows',
        'history',
      ]) {
        final extracted = _extractBeatList(data[key]);
        if (extracted.isNotEmpty) {
          return extracted;
        }
      }
    }
    return const [];
  }

  static Never _throwBeatApiError(
    int statusCode,
    Map<String, dynamic> data,
    String fallback,
  ) {
    if (statusCode == 401) {
      throw const SessionExpiredException();
    }
    final errors = data['errors'];
    if (errors is Map && errors.isNotEmpty) {
      final first = errors.values.first;
      if (first is List && first.isNotEmpty) {
        throw Exception(first.first.toString());
      }
    }
    throw Exception(data['message'] ?? fallback);
  }

  static Future<AppBootstrap> getAppBootstrap(String token) async {
    final response = await http.get(
      AppConfig.apiUri('app/bootstrap'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    );
    final data = _decodeJson(response);
    if (response.statusCode == 200) {
      return AppBootstrap.fromJson(data);
    }
    _throwBeatApiError(response.statusCode, data, 'Failed to load app access');
  }

  static Future<BeatSectorHomeData> getBeatSectorHome(String token) async {
    final response = await http.get(
      AppConfig.apiUri('beat-sector/home'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    );
    final data = _decodeJson(response);
    if (response.statusCode == 200) {
      return BeatSectorHomeData.fromJson(data);
    }
    _throwBeatApiError(response.statusCode, data, 'Failed to load Beat Sector');
  }

  static Future<BeatPage> getSectorBeats(
    String token, {
    int page = 1,
    int perPage = 20,
  }) async {
    final response = await http.get(
      AppConfig.apiUri('beat-sector/beats').replace(queryParameters: {
        'page': page.toString(),
        'per_page': perPage.toString(),
      }),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    );
    final data = _decodeJson(response);
    if (response.statusCode == 200) {
      return BeatPage.fromJson(data);
    }
    _throwBeatApiError(response.statusCode, data, 'Failed to load beats');
  }

  static Future<SectorBeat> getSectorBeatDetail(
      String token, int beatId) async {
    final response = await http.get(
      AppConfig.apiUri('beat-sector/beats/$beatId'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    );
    final data = _decodeJson(response);
    if (response.statusCode == 200) {
      final payload = data['data'];
      final beat = payload is Map && payload['beat'] is Map
          ? (payload['beat'] as Map).cast<String, dynamic>()
          : (payload as Map).cast<String, dynamic>();
      return SectorBeat.fromJson(beat);
    }
    _throwBeatApiError(response.statusCode, data, 'Failed to load beat detail');
  }

  static Future<BeatMapping> getBeatMapping(String token, int beatId) async {
    final response = await http.get(
      AppConfig.apiUri('beat-sector/beats/$beatId/mapping'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    );
    final data = _decodeJson(response);
    if (response.statusCode == 200) {
      return BeatMapping.fromJson(data);
    }
    _throwBeatApiError(response.statusCode, data, 'Failed to load mapping');
  }

  static Future<void> saveBeatMapping({
    required String token,
    required int beatId,
    required int bufferMeter,
    required List<BeatPoint> points,
  }) async {
    final response = await http.put(
      AppConfig.apiUri('beat-sector/beats/$beatId/mapping'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        'buffer_meter': bufferMeter,
        'points': points.map((point) => point.toJson()).toList(),
      }),
    );
    final data = _decodeJson(response);
    if (response.statusCode == 200 || response.statusCode == 201) {
      return;
    }
    _throwBeatApiError(response.statusCode, data, 'Failed to save mapping');
  }

  static Future<BeatLookups> getBeatLookups(String token) async {
    final response = await http.get(
      AppConfig.apiUri('beat-sector/lookups'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    );
    final data = _decodeJson(response);
    if (response.statusCode == 200) {
      return BeatLookups.fromJson(data);
    }
    _throwBeatApiError(response.statusCode, data, 'Failed to load lookups');
  }

  static Future<List<Map<String, dynamic>>> getBeatMasters(
    String token,
    int beatId,
    String type,
  ) async {
    final response = await http.get(
      AppConfig.apiUri('beat-sector/beats/$beatId/masters/$type'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    );
    final data = _decodeJson(response);
    if (response.statusCode == 200) {
      return _extractBeatList(data['data'] ?? data);
    }
    _throwBeatApiError(response.statusCode, data, 'Failed to load master data');
  }

  static Future<void> createBeatMaster(
    String token,
    int beatId,
    String type,
    Map<String, dynamic> body,
  ) async {
    final response = await http.post(
      AppConfig.apiUri('beat-sector/beats/$beatId/masters/$type'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        ...body,
        'beat_id': beatId,
        'sector_beat_id': beatId,
      }),
    );
    final data = _decodeJson(response);
    if (response.statusCode == 200 || response.statusCode == 201) return;
    _throwBeatApiError(response.statusCode, data, 'Failed to save master data');
  }

  static Future<void> updateBeatMaster(
    String token,
    int beatId,
    String type,
    int itemId,
    Map<String, dynamic> body,
  ) async {
    final response = await http.patch(
      AppConfig.apiUri('beat-sector/beats/$beatId/masters/$type/$itemId'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        ...body,
        'beat_id': beatId,
        'sector_beat_id': beatId,
      }),
    );
    final data = _decodeJson(response);
    if (response.statusCode == 200) return;
    _throwBeatApiError(
        response.statusCode, data, 'Failed to update master data');
  }

  static Future<void> deleteBeatMaster(
    String token,
    int beatId,
    String type,
    int itemId,
  ) async {
    final response = await http.delete(
      AppConfig.apiUri('beat-sector/beats/$beatId/masters/$type/$itemId'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    );
    final data = _decodeJson(response);
    if (response.statusCode == 200 || response.statusCode == 204) return;
    _throwBeatApiError(
        response.statusCode, data, 'Failed to delete master data');
  }

  static Map<String, dynamic> buildStartBeatInspectionPayload({
    required int beatId,
    int? deploymentId,
  }) {
    return {
      if (deploymentId != null) 'deployment_id': deploymentId,
      'sector_beat_id': beatId,
    };
  }

  static Future<InspectionDeploymentPage> getInspectionDeployments(
    String token, {
    InspectionDeploymentStatus status = InspectionDeploymentStatus.all,
    DateTime? from,
    DateTime? to,
    int page = 1,
    int perPage = 20,
  }) async {
    String date(DateTime value) {
      final month = value.month.toString().padLeft(2, '0');
      final day = value.day.toString().padLeft(2, '0');
      return '${value.year}-$month-$day';
    }

    final response = await http.get(
      AppConfig.apiUri('beat-sector/inspection-deployments').replace(
        queryParameters: {
          'status': status.apiValue,
          if (from != null) 'from': date(from),
          if (to != null) 'to': date(to),
          'page': page.toString(),
          'per_page': perPage.toString(),
        },
      ),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    );
    final data = _decodeJson(response);
    if (response.statusCode == 200) {
      return InspectionDeploymentPage.fromJson(data);
    }
    _throwBeatApiError(
      response.statusCode,
      data,
      'Failed to load inspection schedule',
    );
  }

  static Future<Map<String, dynamic>> startBeatInspection(
    String token,
    int beatId, {
    int? deploymentId,
  }) async {
    final response = await http.post(
      AppConfig.apiUri('beat-sector/inspections'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode(
        buildStartBeatInspectionPayload(
          beatId: beatId,
          deploymentId: deploymentId,
        ),
      ),
    );
    final data = _decodeJson(response);
    if (response.statusCode == 200 || response.statusCode == 201) {
      return (data['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    }
    _throwBeatApiError(response.statusCode, data, 'Failed to start inspection');
  }

  static Future<Map<String, dynamic>> getBeatInspection(
    String token,
    int inspectionId,
  ) async {
    final response = await http.get(
      AppConfig.apiUri('beat-sector/inspections/$inspectionId'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    );
    final data = _decodeJson(response);
    if (response.statusCode == 200) {
      return (data['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    }
    _throwBeatApiError(response.statusCode, data, 'Failed to load inspection');
  }

  static Future<List<Map<String, dynamic>>> getBeatInspections(
    String token, {
    String status = '',
    int page = 1,
    int perPage = 20,
  }) async {
    final query = <String, String>{
      if (status.trim().isNotEmpty) 'status': status,
      'page': page.toString(),
      'per_page': perPage.toString(),
    };
    final response = await http.get(
      AppConfig.apiUri('beat-sector/inspections')
          .replace(queryParameters: query),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    );
    final data = _decodeJson(response);
    if (response.statusCode == 200) {
      return _extractBeatList(data['data'] ?? data);
    }
    _throwBeatApiError(response.statusCode, data, 'Failed to load inspections');
  }

  static Future<void> addBeatInspectionItem({
    required String token,
    required int inspectionId,
    required int categoryId,
    required String remark,
    required double latitude,
    required double longitude,
    double? locationAccuracy,
    DateTime? capturedAt,
    String? attachmentPath,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      AppConfig.apiUri('beat-sector/inspections/$inspectionId/items'),
    );
    request.headers['Authorization'] = 'Bearer $token';
    request.headers['Accept'] = 'application/json';
    request.fields['category_id'] = categoryId.toString();
    request.fields['remark'] = remark;
    request.fields['latitude'] = latitude.toString();
    request.fields['longitude'] = longitude.toString();
    if (locationAccuracy != null) {
      request.fields['location_accuracy'] = locationAccuracy.toString();
    }
    if (capturedAt != null) {
      request.fields['captured_at'] = capturedAt.toUtc().toIso8601String();
    }
    if (attachmentPath != null && attachmentPath.isNotEmpty) {
      request.files.add(
        await http.MultipartFile.fromPath('attachment', attachmentPath),
      );
    }
    final streamed = await request.send();
    final body = await streamed.stream.bytesToString();
    final data = _decodeMultipartBody(streamed.statusCode, body);
    if (streamed.statusCode == 200 || streamed.statusCode == 201) return;
    _throwBeatApiError(streamed.statusCode, data, 'Failed to add observation');
  }

  static Future<void> finishBeatInspection(
    String token,
    int inspectionId,
  ) async {
    final response = await http.post(
      AppConfig.apiUri('beat-sector/inspections/$inspectionId/finish'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    );
    final data = _decodeJson(response);
    if (response.statusCode == 200 || response.statusCode == 201) return;
    _throwBeatApiError(
        response.statusCode, data, 'Failed to finish inspection');
  }
}
