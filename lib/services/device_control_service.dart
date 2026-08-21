import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

/// Result of trying to interpret + run a device-control command.
class DeviceActionResult {
  final bool handled;
  final String message;
  DeviceActionResult(this.handled, this.message);
}

/// Very small on-device "skills" layer: looks for simple command patterns
/// like "open spotify" / "set an alarm for 7am" / "call mom" and performs
/// them via Android intents. This runs entirely on-device — it does not
/// go through Claude, so it works even without an API key, and Claude is
/// never told your alarms/contacts.
///
/// Extend [_appPackages] with any app package name you want JARVIS to be
/// able to open by voice.
class DeviceControlService {
  static const Map<String, String> _appPackages = {
    'whatsapp': 'com.whatsapp',
    'gmail': 'com.google.android.gm',
    'maps': 'com.google.android.apps.maps',
    'google maps': 'com.google.android.apps.maps',
    'youtube': 'com.google.android.youtube',
    'spotify': 'com.spotify.music',
    'chrome': 'com.android.chrome',
    'camera': 'com.android.camera',
    'settings': 'com.android.settings',
    'phone': 'com.android.dialer',
    'messages': 'com.google.android.apps.messaging',
    'calendar': 'com.google.android.calendar',
  };

  /// Tries to interpret [text] as a device command. Returns
  /// handled: false if it doesn't look like one of the supported
  /// commands, so the caller can fall back to sending it to Claude.
  Future<DeviceActionResult> tryHandle(String text) async {
    final t = text.toLowerCase().trim();

    if (t.startsWith('open ') || t.startsWith('launch ')) {
      final appName = t.replaceFirst(RegExp(r'^(open|launch) '), '').trim();
      return _openApp(appName);
    }

    if (t.contains('set') && t.contains('alarm')) {
      return _setAlarm(t);
    }

    if (t.contains('set') && (t.contains('timer'))) {
      return _setTimer(t);
    }

    if (t.startsWith('call ')) {
      final who = t.replaceFirst('call ', '').trim();
      return _dial(who);
    }

    if (t.startsWith('search for ') || t.startsWith('google ')) {
      final query = t
          .replaceFirst(RegExp(r'^(search for|google) '), '')
          .trim();
      return _webSearch(query);
    }

    return DeviceActionResult(false, '');
  }

  Future<DeviceActionResult> _openApp(String appName) async {
    final pkg = _appPackages[appName];
    if (pkg == null) {
      return DeviceActionResult(
        false,
        "I don't have \"$appName\" mapped to a package yet — add it to "
        "DeviceControlService._appPackages.",
      );
    }
    try {
      final intent = AndroidIntent(
        action: 'action_main',
        package: pkg,
        flags: [Flag.FLAG_ACTIVITY_NEW_TASK],
      );
      await intent.launch();
      return DeviceActionResult(true, 'Opening $appName.');
    } catch (e) {
      return DeviceActionResult(true, "I couldn't open $appName: $e");
    }
  }

  Future<DeviceActionResult> _setAlarm(String t) async {
    final hourMatch = RegExp(r'(\d{1,2})(?::(\d{2}))?\s*(am|pm)?').firstMatch(t);
    int hour = 7;
    int minute = 0;
    if (hourMatch != null) {
      hour = int.tryParse(hourMatch.group(1) ?? '7') ?? 7;
      minute = int.tryParse(hourMatch.group(2) ?? '0') ?? 0;
      final ampm = hourMatch.group(3);
      if (ampm == 'pm' && hour < 12) hour += 12;
      if (ampm == 'am' && hour == 12) hour = 0;
    }
    try {
      final intent = AndroidIntent(
        action: 'android.intent.action.SET_ALARM',
        arguments: {
          'android.intent.extra.alarm.HOUR': hour,
          'android.intent.extra.alarm.MINUTES': minute,
          'android.intent.extra.alarm.SKIP_UI': false,
        },
      );
      await intent.launch();
      final label = '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
      return DeviceActionResult(true, 'Setting an alarm for $label.');
    } catch (e) {
      return DeviceActionResult(true, "I couldn't set that alarm: $e");
    }
  }

  Future<DeviceActionResult> _setTimer(String t) async {
    final minMatch = RegExp(r'(\d+)\s*min').firstMatch(t);
    final secMatch = RegExp(r'(\d+)\s*sec').firstMatch(t);
    final minutes = int.tryParse(minMatch?.group(1) ?? '') ?? 0;
    final seconds = int.tryParse(secMatch?.group(1) ?? '') ?? 0;
    final totalSeconds = minutes * 60 + seconds;
    try {
      final intent = AndroidIntent(
        action: 'android.intent.action.SET_TIMER',
        arguments: {
          'android.intent.extra.alarm.LENGTH': totalSeconds > 0 ? totalSeconds : 300,
          'android.intent.extra.alarm.SKIP_UI': false,
        },
      );
      await intent.launch();
      return DeviceActionResult(true, 'Starting a timer.');
    } catch (e) {
      return DeviceActionResult(true, "I couldn't start that timer: $e");
    }
  }

  Future<DeviceActionResult> _dial(String who) async {
    final granted = await Permission.phone.request();
    final uri = Uri(scheme: 'tel', path: who);
    if (!granted.isGranted) {
      // Fall back to the dialer (no permission needed) pre-filled with
      // the number/name so the user just taps call themselves.
      await launchUrl(uri);
      return DeviceActionResult(true, 'Opened the dialer for $who.');
    }
    try {
      final intent = AndroidIntent(
        action: 'android.intent.action.CALL',
        data: 'tel:$who',
      );
      await intent.launch();
      return DeviceActionResult(true, 'Calling $who.');
    } catch (e) {
      await launchUrl(uri);
      return DeviceActionResult(true, 'Opened the dialer for $who.');
    }
  }

  Future<DeviceActionResult> _webSearch(String query) async {
    final uri = Uri.https('www.google.com', '/search', {'q': query});
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    return DeviceActionResult(
      ok,
      ok ? 'Searching for "$query".' : "I couldn't open a browser for that search.",
    );
  }
}
