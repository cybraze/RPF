import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

export 'package:http/http.dart'
    show Response, StreamedResponse, MultipartRequest, MultipartFile;

/// Drop-in replacements for the top-level `package:http` helpers with
/// timeouts and retries tuned for weak / slow mobile networks.
///
/// Reads (GET) are retried on connection failures, timeouts and gateway
/// errors. Writes are retried only when the connection could not be
/// established at all, so a request the server may already have processed
/// is never sent twice.
const Duration _readTimeout = Duration(seconds: 30);
const Duration _writeTimeout = Duration(seconds: 40);
const Duration uploadTimeout = Duration(seconds: 120);
const int _maxAttempts = 3;
const Set<int> _retryableStatus = {502, 503, 504};

Future<http.Response> get(Uri url, {Map<String, String>? headers}) {
  return _run(
    () => http.get(url, headers: headers),
    timeout: _readTimeout,
    idempotent: true,
  );
}

Future<http.Response> post(
  Uri url, {
  Map<String, String>? headers,
  Object? body,
  Encoding? encoding,
}) {
  return _run(
    () => http.post(url, headers: headers, body: body, encoding: encoding),
    timeout: _writeTimeout,
    idempotent: false,
  );
}

Future<http.Response> put(
  Uri url, {
  Map<String, String>? headers,
  Object? body,
  Encoding? encoding,
}) {
  return _run(
    () => http.put(url, headers: headers, body: body, encoding: encoding),
    timeout: _writeTimeout,
    idempotent: false,
  );
}

Future<http.Response> patch(
  Uri url, {
  Map<String, String>? headers,
  Object? body,
  Encoding? encoding,
}) {
  return _run(
    () => http.patch(url, headers: headers, body: body, encoding: encoding),
    timeout: _writeTimeout,
    idempotent: false,
  );
}

Future<http.Response> delete(
  Uri url, {
  Map<String, String>? headers,
  Object? body,
  Encoding? encoding,
}) {
  return _run(
    () => http.delete(url, headers: headers, body: body, encoding: encoding),
    timeout: _writeTimeout,
    idempotent: false,
  );
}

Future<http.Response> _run(
  Future<http.Response> Function() send, {
  required Duration timeout,
  required bool idempotent,
}) async {
  Object? lastError;
  for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
    try {
      final response = await send().timeout(timeout);
      if (idempotent &&
          _retryableStatus.contains(response.statusCode) &&
          attempt < _maxAttempts) {
        await Future.delayed(_backoff(attempt));
        continue;
      }
      return response;
    } on SocketException catch (error) {
      lastError = error;
    } on http.ClientException catch (error) {
      if (!idempotent) rethrow;
      lastError = error;
    } on TimeoutException catch (error) {
      if (!idempotent) rethrow;
      lastError = error;
    }
    if (attempt < _maxAttempts) {
      await Future.delayed(_backoff(attempt));
    }
  }
  throw lastError ?? Exception('Request failed');
}

Duration _backoff(int attempt) => Duration(seconds: attempt * 2);
