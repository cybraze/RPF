import 'dart:async';
import 'dart:io';

import '../services/api_service.dart';

String userFriendlyErrorMessage(
  Object error, {
  String? action,
}) {
  final normalized = _normalizeError(error);
  final lower = normalized.toLowerCase();

  if (error is SessionExpiredException ||
      lower.contains('session expired') ||
      lower.contains('login session is missing') ||
      lower.contains('auth_failed') ||
      lower.contains('401')) {
    return 'Session expired. Please log in again.';
  }

  if (error is TimeoutException ||
      lower.contains('timed out') ||
      lower.contains('timeout')) {
    return 'Server timeout. Please try again.';
  }

  if (error is SocketException ||
      lower.contains('failed host lookup') ||
      lower.contains('host lookup') ||
      lower.contains('no address associated with hostname') ||
      lower.contains('network is unreachable') ||
      lower.contains('connection refused')) {
    return 'No connection. Check internet and retry.';
  }

  if (lower.contains('clientconnection closed before full header was received') ||
      lower.contains('connection closed before full header was received') ||
      lower.contains('connection reset') ||
      lower.contains('connection closed')) {
    return 'Connection lost. Please try again.';
  }

  if (lower.contains('server error') ||
      lower.contains('http 500') ||
      lower.contains('status: 500') ||
      lower.contains('http_500') ||
      lower.contains('502') ||
      lower.contains('503') ||
      lower.contains('504')) {
    return 'Server error. Please try again later.';
  }

  if (lower.contains('photo picker could not open')) {
    return 'Could not open gallery. Try again.';
  }

  if (lower.contains('photo processing failed')) {
    return 'Photo processing failed. Try another image.';
  }

  if (lower.contains('photo update failed')) {
    return 'Photo update failed. Check your connection.';
  }

  if (lower.contains('camera error')) {
    return 'Camera error. Please try again.';
  }

  if (lower.contains('gps band hai') ||
      lower.contains('gps is turned off') ||
      lower.contains('location services enable') ||
      lower.contains('location services are off')) {
    return 'Location is turned off. Please enable GPS and try again.';
  }

  if (lower.contains('location permission') ||
      lower.contains('permission was not granted') ||
      lower.contains('permission nahi mili')) {
    return 'Location permission denied. Please allow it in Settings.';
  }

  if (lower.contains('location not found') || lower.contains('weak gps')) {
    return 'Weak GPS signal. Move to open area and retry.';
  }

  if (action == 'activity_upload') {
    return 'Activity not saved. Check your connection.';
  }

  final cleaned = normalized.trim();
  if (cleaned.isEmpty || cleaned == 'Exception') {
    return 'Something went wrong. Please try again.';
  }

  return cleaned;
}

String _normalizeError(Object error) {
  final raw = error.toString().trim();
  return raw
      .replaceFirst('Exception: ', '')
      .replaceFirst('ClientException: ', '')
      .replaceFirst('SocketException: ', '')
      .trim();
}
