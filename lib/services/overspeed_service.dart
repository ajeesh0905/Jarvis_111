import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:vibration/vibration.dart';
import 'storage_service.dart';

enum OverspeedStatus { stopped, ok, overLimit, error }

/// Tracks GPS speed and raises an alarm (spoken warning + vibration +
/// a high-priority notification) whenever the driver goes over the
/// speed limit configured in Settings.
///
/// Uses a foreground-service-backed location stream on Android so this
/// keeps working with the screen off/app backgrounded while driving —
/// that's the whole point of an overspeed alarm. The persistent
/// notification while active ("Jarvis is monitoring your speed") is
/// Android's required trade-off for that: a normal app cannot silently
/// track GPS in the background.
class OverspeedService {
  static const _channelId = 'overspeed_alerts';
  static const _channelName = 'Overspeed alerts';
  static const _foregroundNotifChannelId = 'overspeed_tracking';

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  final FlutterTts _tts = FlutterTts();

  StreamSubscription<Position>? _sub;
  bool _initialized = false;
  DateTime? _lastAlertAt;
  bool _wasOverLimit = false;

  final _statusController = StreamController<OverspeedStatus>.broadcast();
  Stream<OverspeedStatus> get statusStream => _statusController.stream;

  final _speedController = StreamController<double>.broadcast();
  /// Current speed in km/h.
  Stream<double> get speedStream => _speedController.stream;

  bool get isRunning => _sub != null;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _notifications.initialize(
      const InitializationSettings(android: androidInit),
    );
    final androidPlugin = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: 'Alerts when you go over your set speed limit',
        importance: Importance.max,
        playSound: true,
      ),
    );
    await _tts.setSpeechRate(0.55);
    _initialized = true;
  }

  Future<bool> _ensurePermissions() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever ||
        permission == LocationPermission.denied) {
      return false;
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
      return false;
    }
    return true;
  }

  /// Starts monitoring. Safe to call repeatedly; no-ops if already running.
  Future<bool> start() async {
    if (isRunning) return true;
    await _ensureInitialized();
    if (!await _ensurePermissions()) {
      _statusController.add(OverspeedStatus.error);
      return false;
    }

    final androidSettings = AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 0,
      intervalDuration: Duration(seconds: 3),
      foregroundNotificationConfig: ForegroundNotificationConfig(
        notificationTitle: 'Jarvis — overspeed alarm active',
        notificationText: 'Monitoring your driving speed in the background.',
        notificationChannelName: _foregroundNotifChannelId,
        enableWakeLock: true,
      ),
    );

    _sub = Geolocator.getPositionStream(locationSettings: androidSettings).listen(
      _onPosition,
      onError: (_) => _statusController.add(OverspeedStatus.error),
    );
    return true;
  }

  Future<void> _onPosition(Position position) async {
    // Position.speed is meters/second; ignore wildly inaccurate fixes.
    if (position.speedAccuracy > 10 || position.speed.isNaN) return;
    final speedKmh = (position.speed < 0 ? 0 : position.speed) * 3.6;
    _speedController.add(speedKmh);

    final limit = await StorageService.instance.getSpeedLimitKmh();
    final over = speedKmh > limit;
    _statusController.add(over ? OverspeedStatus.overLimit : OverspeedStatus.ok);

    if (over) {
      final now = DateTime.now();
      final coolingDown = _lastAlertAt != null && now.difference(_lastAlertAt!) < const Duration(seconds: 20);
      if (!_wasOverLimit || !coolingDown) {
        _lastAlertAt = now;
        await _raiseAlarm(speedKmh, limit);
      }
    }
    _wasOverLimit = over;
  }

  Future<void> _raiseAlarm(double speedKmh, double limit) async {
    final speedLabel = speedKmh.round();
    final limitLabel = limit.round();

    unawaited(_notifications.show(
      1001,
      'Overspeed!',
      '$speedLabel km/h in a $limitLabel km/h zone.',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.max,
          priority: Priority.high,
          category: AndroidNotificationCategory.alarm,
        ),
      ),
    ));

    if (await Vibration.hasVibrator()) {
      unawaited(Vibration.vibrate(pattern: [0, 400, 200, 400, 200, 400]));
    }

    unawaited(_tts.speak('Warning. You are going $speedLabel kilometers per hour. The limit is $limitLabel.'));
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _wasOverLimit = false;
    _statusController.add(OverspeedStatus.stopped);
  }

  void dispose() {
    _sub?.cancel();
    _statusController.close();
    _speedController.close();
    _tts.stop();
  }
}
