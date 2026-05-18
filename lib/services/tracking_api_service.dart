import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/tracking_api_models.dart';

class TrackingApiException implements Exception {
  final String message;
  final int? statusCode;

  const TrackingApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class TrackingApiService {
  const TrackingApiService({http.Client? client}) : _client = client;

  final http.Client? _client;

  http.Client get _httpClient => _client ?? http.Client();

  Future<void> startTracking({
    required String token,
    required TrackingStartRequest request,
  }) async {
    await _postWithRetry(
      path: '/tracking/start',
      token: token,
      body: request.toJson(),
      acceptedStatusCodes: const {200, 201},
    );
  }

  Future<int> sendLocationBatch({
    required String token,
    required TrackingLocationRequest request,
  }) async {
    final response = await _postWithRetry(
      path: '/tracking/location',
      token: token,
      body: request.toJson(),
      acceptedStatusCodes: const {200, 201, 202, 401, 409},
      retryOnStatusCodes: const {500, 502, 503, 504},
    );
    return response.statusCode;
  }

  Future<void> stopTracking({
    required String token,
    required TrackingStopRequest request,
  }) async {
    await _postWithRetry(
      path: '/tracking/stop',
      token: token,
      body: request.toJson(),
      acceptedStatusCodes: const {200, 201, 202},
    );
  }

  Future<http.Response> authorizeSocket({
    required String token,
    required String socketId,
    required String channelName,
  }) {
    return _httpClient.post(
      Uri.parse(AppConfig.socketAuthEndpoint),
      headers: _headers(token),
      body: jsonEncode({
        'socket_id': socketId,
        'channel_name': channelName,
      }),
    );
  }

  Future<http.Response> _postWithRetry({
    required String path,
    required String token,
    required Map<String, dynamic> body,
    required Set<int> acceptedStatusCodes,
    Set<int> retryOnStatusCodes = const {408, 429, 500, 502, 503, 504},
    int maxAttempts = 3,
  }) async {
    Object? lastError;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final response = await _httpClient
            .post(
              AppConfig.apiUri(path),
              headers: _headers(token),
              body: jsonEncode(body),
            )
            .timeout(const Duration(seconds: 12));

        if (acceptedStatusCodes.contains(response.statusCode)) {
          return response;
        }

        final message = _extractMessage(response);
        if (_isAuthGuardLogoutError(message)) {
          throw TrackingApiException(
            'Tracking session expired. Please login again.',
            statusCode: 401,
          );
        }

        if (retryOnStatusCodes.contains(response.statusCode) &&
            attempt < maxAttempts) {
          await Future.delayed(_retryDelay(attempt));
          continue;
        }

        throw TrackingApiException(
          message,
          statusCode: response.statusCode,
        );
      } catch (error) {
        lastError = error;
        if (error is TrackingApiException &&
            !retryOnStatusCodes.contains(error.statusCode)) {
          break;
        }
        if (attempt == maxAttempts) {
          break;
        }
        await Future.delayed(_retryDelay(attempt));
      }
    }

    if (lastError is TrackingApiException) {
      throw lastError;
    }
    throw TrackingApiException('Tracking request failed after retries');
  }

  Map<String, String> _headers(String token) => {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      };

  Duration _retryDelay(int attempt) => Duration(milliseconds: 500 * attempt);

  bool _isAuthGuardLogoutError(String message) {
    return message.contains('RequestGuard::logout') ||
        message.contains('Method Illuminate\\Auth\\RequestGuard::logout') ||
        message.contains('Method Illuminate\\\\Auth\\\\RequestGuard::logout');
  }

  String _extractMessage(http.Response response) {
    final body = response.body.trim();
    if (body.isEmpty) {
      return 'Server returned empty response (${response.statusCode})';
    }

    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final message = decoded['message'];
        if (message is String && message.isNotEmpty) {
          return message;
        }
      }
    } catch (_) {
      // Ignore parse errors and fall through to a generic message.
    }

    return 'Tracking request failed (${response.statusCode})';
  }
}
