import 'dart:async';
import 'dart:io';

class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  final StreamController<bool> _controller =
      StreamController<bool>.broadcast();

  Stream<bool> get onConnectivityChanged => _controller.stream;

  bool _isOnline = true;
  bool get isOnline => _isOnline;

  Timer? _pollTimer;
  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    _check();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _check());
  }

  void stop() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _started = false;
  }

  Future<bool> checkNow() async {
    await _check();
    return _isOnline;
  }

  Future<void> _check() async {
    bool reachable;
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 4));
      reachable = result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } on SocketException {
      reachable = false;
    } on TimeoutException {
      reachable = false;
    } catch (_) {
      reachable = false;
    }

    if (reachable != _isOnline) {
      _isOnline = reachable;
      _controller.add(_isOnline);
    }
  }

  void dispose() {
    stop();
    _controller.close();
  }
}
