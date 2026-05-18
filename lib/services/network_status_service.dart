import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

class NetworkStatusService extends ChangeNotifier with WidgetsBindingObserver {
  bool _isOnline = true;
  Timer? _pollTimer;

  bool get isOnline => _isOnline;

  void start() {
    WidgetsBinding.instance.addObserver(this);
    unawaited(refresh());
    _pollTimer ??= Timer.periodic(
      const Duration(seconds: 12),
      (_) => unawaited(refresh()),
    );
  }

  Future<void> refresh() async {
    final next = await _checkInternet();
    if (next == _isOnline) {
      return;
    }
    _isOnline = next;
    notifyListeners();
  }

  Future<bool> _checkInternet() async {
    try {
      final result = await InternetAddress.lookup('example.com')
          .timeout(const Duration(seconds: 3));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(refresh());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    super.dispose();
  }
}
