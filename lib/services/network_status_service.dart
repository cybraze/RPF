import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

class NetworkStatusService extends ChangeNotifier with WidgetsBindingObserver {
  bool _isOnline = true;
  int _failedChecks = 0;
  Timer? _pollTimer;

  bool get isOnline => _isOnline;

  void start() {
    WidgetsBinding.instance.addObserver(this);
    unawaited(refresh());
    _pollTimer ??= Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(refresh()),
    );
  }

  Future<void> refresh() async {
    final reachable = await _checkInternet();
    // A single failed lookup on a weak network is not "offline": require
    // two consecutive failures before flipping the banner.
    _failedChecks = reachable ? 0 : _failedChecks + 1;
    final next = reachable || _failedChecks < 2;
    if (next == _isOnline) {
      return;
    }
    _isOnline = next;
    notifyListeners();
  }

  Future<bool> _checkInternet() async {
    try {
      final result = await InternetAddress.lookup('www.rpfwcr.in')
          .timeout(const Duration(seconds: 8));
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
