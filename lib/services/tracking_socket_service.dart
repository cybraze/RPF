import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:pusher_client_socket/pusher_client_socket.dart';

import '../config/app_config.dart';
import '../models/tracking_socket_event.dart';

enum TrackingSocketStatus {
  disconnected,
  connecting,
  connected,
  reconnecting,
  error,
}

class TrackingSocketService {
  TrackingSocketService();

  final StreamController<TrackingSocketEvent> _locationController =
      StreamController<TrackingSocketEvent>.broadcast();
  final StreamController<TrackingSocketEvent> _stoppedController =
      StreamController<TrackingSocketEvent>.broadcast();
  final StreamController<TrackingSocketEvent> _offlineController =
      StreamController<TrackingSocketEvent>.broadcast();
  final StreamController<TrackingSocketStatus> _statusController =
      StreamController<TrackingSocketStatus>.broadcast();

  PusherClient? _client;
  Channel? _liveChannel;
  Channel? _userChannel;
  bool _connected = false;
  bool _connecting = false;
  String? _authToken;

  Stream<TrackingSocketEvent> get locationUpdates => _locationController.stream;
  Stream<TrackingSocketEvent> get userStoppedEvents => _stoppedController.stream;
  Stream<TrackingSocketEvent> get userOfflineEvents => _offlineController.stream;
  Stream<TrackingSocketStatus> get statusStream => _statusController.stream;

  Future<void> connect({
    required String token,
    int? userId,
  }) async {
    if (AppConfig.socketAppKey.isEmpty) {
      _log('Socket app key missing; skipping realtime connection.');
      return;
    }

    if (_authToken != null && _authToken != token && _client != null) {
      await disconnect();
      _client = null;
    }
    _authToken = token;

    if (_connected) {
      await _subscribeChannels(userId);
      return;
    }

    if (_connecting) {
      return;
    }

    _connecting = true;
    _statusController.add(TrackingSocketStatus.connecting);

    _client ??= _buildClient(token);
    _client!.connect();
    await _subscribeChannels(userId);
  }

  Future<void> ensureConnected({
    required String token,
    int? userId,
  }) async {
    if (_connected) {
      await _subscribeChannels(userId);
      return;
    }
    await connect(token: token, userId: userId);
  }

  Future<void> disconnect() async {
    _liveChannel?.unsubscribe();
    _userChannel?.unsubscribe();
    _liveChannel = null;
    _userChannel = null;
    _client?.disconnect();
    _connected = false;
    _connecting = false;
    _statusController.add(TrackingSocketStatus.disconnected);
  }

  Future<void> dispose() async {
    await disconnect();
    await _locationController.close();
    await _stoppedController.close();
    await _offlineController.close();
    await _statusController.close();
  }

  PusherClient _buildClient(String token) {
    final options = PusherOptions(
      key: AppConfig.socketAppKey,
      host: AppConfig.socketHost,
      wsPort: AppConfig.socketPort,
      wssPort: AppConfig.socketPort,
      encrypted: AppConfig.socketUseTls,
      autoConnect: false,
      enableLogging: kDebugMode && AppConfig.debugTrackingLogs,
      authOptions: PusherAuthOptions(
        AppConfig.socketAuthEndpoint,
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ),
    );

    final client = PusherClient(options: options);
    client.onConnectionEstablished((_) {
      _connected = true;
      _connecting = false;
      _statusController.add(TrackingSocketStatus.connected);
    });
    client.onDisconnected((_) {
      final previous = _connected;
      _connected = false;
      _connecting = false;
      _statusController.add(
        previous
            ? TrackingSocketStatus.reconnecting
            : TrackingSocketStatus.disconnected,
      );
    });
    client.onConnectionError((error) {
      _connected = false;
      _connecting = false;
      _log('Socket connection error: $error');
      _statusController.add(TrackingSocketStatus.error);
    });
    client.onError((error) {
      _log('Socket error: $error');
      _statusController.add(TrackingSocketStatus.error);
    });
    return client;
  }

  Future<void> _subscribeChannels(int? userId) async {
    final client = _client;
    if (client == null) {
      return;
    }

    _liveChannel ??= client.private('tracking.live');
    _bindChannel(_liveChannel!);

    final nextUserChannelName =
        userId == null ? null : 'private-tracking.user.$userId';
    if (nextUserChannelName == null) {
      _userChannel?.unsubscribe();
      _userChannel = null;
      return;
    }

    if (_userChannel?.name != nextUserChannelName) {
      _userChannel?.unsubscribe();
      _userChannel = client.private('tracking.user.$userId');
      _bindChannel(_userChannel!);
    }
  }

  void _bindChannel(Channel channel) {
    channel.bind('tracking.location.updated', (data) {
      _emitParsedEvent(data, _locationController);
    });
    channel.bind('tracking.user.stopped', (data) {
      _emitParsedEvent(data, _stoppedController);
    });
    channel.bind('tracking.user.offline', (data) {
      _emitParsedEvent(data, _offlineController);
    });
  }

  void _emitParsedEvent(
    dynamic data,
    StreamController<TrackingSocketEvent> controller,
  ) {
    try {
      controller.add(TrackingSocketEvent.fromDynamic(data));
    } catch (error) {
      _log('Socket payload parse failed: $error');
      if (kDebugMode && AppConfig.debugTrackingLogs) {
        debugPrint('Raw socket payload: ${_safePayload(data)}');
      }
    }
  }

  String _safePayload(dynamic payload) {
    if (payload is String) {
      return payload;
    }
    try {
      return jsonEncode(payload);
    } catch (_) {
      return payload.toString();
    }
  }

  void _log(String message) {
    if (kDebugMode && AppConfig.debugTrackingLogs) {
      debugPrint('[TrackingSocketService] $message');
    }
  }
}
