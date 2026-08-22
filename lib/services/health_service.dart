import 'package:health/health.dart';
import 'package:permission_handler/permission_handler.dart';

/// A snapshot of today's key health metrics, pulled from Android Health
/// Connect.
class HealthSummary {
  final int? steps;
  final double? heartRateBpm;
  final DateTime? heartRateAt;
  final Duration? sleepLastNight;

  const HealthSummary({
    this.steps,
    this.heartRateBpm,
    this.heartRateAt,
    this.sleepLastNight,
  });

  bool get isEmpty => steps == null && heartRateBpm == null && sleepLastNight == null;
}

enum HealthConnectAvailability { available, notInstalled, unsupported, unknown }

/// Reads step/heart-rate/sleep data from Android Health Connect - the
/// OS-level health data store that the Zepp app can sync your Amazfit
/// watch's data into. Jarvis never talks to Zepp or the watch itself, or
/// asks for any Zepp/Amazfit login - it only reads whatever Health
/// Connect already has, with your explicit permission.
class HealthService {
  HealthService._();
  static final HealthService instance = HealthService._();

  final Health _health = Health();
  bool _configured = false;

  static const _types = [
    HealthDataType.STEPS,
    HealthDataType.HEART_RATE,
    HealthDataType.SLEEP_ASLEEP,
    ];

  static const _permissions = [
    HealthDataAccess.READ,
    HealthDataAccess.READ,
    HealthDataAccess.READ,
    ];

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  /// Whether Health Connect is installed and usable on this device.
  Future<HealthConnectAvailability> checkAvailability() async {
    await _ensureConfigured();
    try {
      final status = await _health.getHealthConnectSdkStatus();
      if (status == HealthConnectSdkStatus.sdkAvailable) {
        return HealthConnectAvailability.available;
      }
      return HealthConnectAvailability.notInstalled;
    } catch (_) {
      return HealthConnectAvailability.unsupported;
    }
  }

  /// Sends the user to the Play Store to install/update Health Connect.
  Future<void> openHealthConnectInstall() async {
    await _ensureConfigured();
    await _health.installHealthConnect();
  }

  Future<bool> hasPermissions() async {
    await _ensureConfigured();
    return await _health.hasPermissions(_types, permissions: _permissions) ?? false;
  }

  /// Requests read access to steps/heart rate/sleep. Returns true once
  /// the user has granted it (or already had).
  Future<bool> requestPermissions() async {
    await _ensureConfigured();
    // Older Android versions gate step-counting behind this runtime
    // permission in addition to the Health Connect grant.
    await Permission.activityRecognition.request();
    if (await hasPermissions()) return true;
    return await _health.requestAuthorization(_types, permissions: _permissions);
  }

  /// Pulls together today's steps, the most recent heart-rate reading
  /// (last 24h), and last night's total sleep.
  Future<HealthSummary> getSummary() async {
    await _ensureConfigured();
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day);

    int? steps;
    try {
      steps = await _health.getTotalStepsInInterval(midnight, now);
    } catch (_) {
      // No data / not permitted yet - leave it null rather than fail
      // the whole summary.
    }

    double? heartRate;
    DateTime? heartRateAt;
    try {
      final hrPoints = await _health.getHealthDataFromTypes(
        now.subtract(const Duration(hours: 24)),
        now,
        [HealthDataType.HEART_RATE],
        );
      if (hrPoints.isNotEmpty) {
        hrPoints.sort((a, b) => a.dateTo.compareTo(b.dateTo));
        final latest = hrPoints.last;
        heartRate = double.tryParse(latest.value.toString());
        heartRateAt = latest.dateTo;
      }
    } catch (_) {}

    Duration? sleep;
    try {
      // Look back far enough to catch a sleep session that started
      // yesterday evening.
      final sleepWindowStart = midnight.subtract(const Duration(hours: 18));
      final sleepPoints = await _health.getHealthDataFromTypes(
        sleepWindowStart,
        now,
        [HealthDataType.SLEEP_ASLEEP],
        );
      if (sleepPoints.isNotEmpty) {
        sleep = sleepPoints.fold<Duration>(
          Duration.zero,
          (total, p) => total + p.dateTo.difference(p.dateFrom),
          );
      }
    } catch (_) {}

    return HealthSummary(
      steps: steps,
      heartRateBpm: heartRate,
      heartRateAt: heartRateAt,
      sleepLastNight: sleep,
      );
  }

  static final _healthQueryPattern = RegExp(
    r'\b(steps?|heart ?rate|bpm|pulse|slept|sleep|health (overview|summary|check)|'
    r'how (did|was) (i|my) sleep)\b',
    caseSensitive: false,
    );
  static final _stepsPattern = RegExp(r'\bsteps?\b', caseSensitive: false);
  static final _heartPattern = RegExp(r'\b(heart ?rate|bpm|pulse)\b', caseSensitive: false);
  static final _sleepPattern = RegExp(r'\b(sleep|slept)\b', caseSensitive: false);

  /// Tries to answer a health/fitness question directly from Health
  /// Connect data so a simple check-in like "how many steps have I done"
  /// or "how did I sleep" is answered instantly, without a round trip to
  /// Gemini. Returns null if [text] isn't a health question.
  Future<String?> tryHandle(String text) async {
    if (!_healthQueryPattern.hasMatch(text)) return null;

    final availability = await checkAvailability();
    if (availability != HealthConnectAvailability.available) {
      return "I can't reach Health Connect on this phone - install it from "
        'the Play Store, make sure the Zepp app is syncing your Amazfit '
        'data into it, then open the Health tab in Jarvis to connect.';
    }
    if (!await hasPermissions()) {
      final granted = await requestPermissions();
      if (!granted) {
        return "I don't have permission to read your health data yet - "
          'grant it from the Health tab in Jarvis.';
      }
    }

    final summary = await getSummary();
    if (summary.isEmpty) {
      return "Health Connect doesn't have any data yet - make sure the "
        'Zepp app is syncing your Amazfit watch to it.';
    }

    final wantsSteps = _stepsPattern.hasMatch(text);
    final wantsHeart = _heartPattern.hasMatch(text);
    final wantsSleep = _sleepPattern.hasMatch(text);
    final wantsAll = !wantsSteps && !wantsHeart && !wantsSleep;

    final parts = <String>[];
    if (wantsSteps || wantsAll) {
      parts.add(summary.steps != null
                ? "you're at ${summary.steps} steps today"
                : "I don't have a step count for today yet");
    }
    if (wantsHeart || wantsAll) {
      parts.add(summary.heartRateBpm != null
                ? 'your last heart rate reading was ${summary.heartRateBpm!.round()} bpm'
                : "I don't have a recent heart rate reading");
    }
    if (wantsSleep || wantsAll) {
      final sleep = summary.sleepLastNight;
      if (sleep != null && sleep.inMinutes > 0) {
        parts.add('you slept about ${sleep.inHours}h ${sleep.inMinutes % 60}m last night');
      } else {
        parts.add("I don't have last night's sleep yet");
      }
    }

    final joined = parts.length == 1
      ? parts.first
      : '${parts.sublist(0, parts.length - 1).join(', ')}, and ${parts.last}';
    return '${joined[0].toUpperCase()}${joined.substring(1)}.';
  }
}
