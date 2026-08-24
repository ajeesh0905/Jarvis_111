import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

/// A single reminder Jarvis has scheduled as a real on-device
/// notification (via Android's AlarmManager, so it fires even if the
/// app is closed).
class Reminder {
  final int id;
  final String label;
  final DateTime scheduledFor;
  final bool recurringDaily;

  const Reminder({
    required this.id,
    required this.label,
    required this.scheduledFor,
    required this.recurringDaily,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'scheduledFor': scheduledFor.toIso8601String(),
    'recurringDaily': recurringDaily,
  };

  factory Reminder.fromJson(Map<String, dynamic> json) => Reminder(
    id: json['id'] as int,
    label: json['label'] as String,
    scheduledFor: DateTime.parse(json['scheduledFor'] as String),
    recurringDaily: json['recurringDaily'] as bool,
    );
}

/// Parses "remind me..." commands and schedules real Android
/// notifications for them (not just a chat reply) - one-off ("in 20
/// minutes", "at 7pm") or daily-recurring ("every day at 9pm"). Also
/// handles listing and cancelling. Reminders persist across app
/// restarts (Android holds the alarm) and, with the boot receiver
/// declared in AndroidManifest.xml, across a device reboot too.
class ReminderService {
  ReminderService._();
  static final ReminderService instance = ReminderService._();

  static const _channelId = 'reminders';
  static const _channelName = 'Reminders';
  static const _prefsKey = 'jarvis_reminders';
  static const _nextIdKey = 'jarvis_reminder_next_id';

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

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
        description: 'Reminders you asked Jarvis to set',
        importance: Importance.max,
        playSound: true,
        ),
      );
    await androidPlugin?.requestNotificationsPermission();
    await androidPlugin?.requestExactAlarmsPermission();
    _initialized = true;
  }

  Future<int> _nextId() async {
    final prefs = await SharedPreferences.getInstance();
    final next = (prefs.getInt(_nextIdKey) ?? 0) + 1;
    await prefs.setInt(_nextIdKey, next);
    return next;
  }

  Future<List<Reminder>> _loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKey) ?? [];
    return raw
      .map((s) => Reminder.fromJson(jsonDecode(s) as Map<String, dynamic>))
      .toList();
  }

  Future<void> _saveAll(List<Reminder> reminders) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _prefsKey,
      reminders.map((r) => jsonEncode(r.toJson())).toList(),
      );
  }

  Future<List<Reminder>> listReminders() => _loadAll();

  Future<Reminder> _schedule({
    required String label,
    required DateTime when,
    required bool recurringDaily,
  }) async {
    await _ensureInitialized();
    final id = await _nextId();
    final tzWhen = tz.TZDateTime.from(when, tz.local);
    await _notifications.zonedSchedule(
      id,
      'Jarvis reminder',
      label,
      tzWhen,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.max,
          priority: Priority.high,
          category: AndroidNotificationCategory.reminder,
          ),
        ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: recurringDaily ? DateTimeComponents.time : null,
      );
    final reminder = Reminder(
      id: id,
      label: label,
      scheduledFor: when,
      recurringDaily: recurringDaily,
      );
    final all = await _loadAll();
    all.add(reminder);
    await _saveAll(all);
    return reminder;
  }

  Future<bool> cancel(int id) async {
    await _ensureInitialized();
    await _notifications.cancel(id);
    final all = await _loadAll();
    final existed = all.any((r) => r.id == id);
    all.removeWhere((r) => r.id == id);
    await _saveAll(all);
    return existed;
  }

  Future<int> cancelAll() async {
    await _ensureInitialized();
    final all = await _loadAll();
    for (final r in all) {
      await _notifications.cancel(r.id);
    }
    await _saveAll([]);
    return all.length;
  }

  // --- Natural-language command parsing ---

  static final _inPattern = RegExp(
    r'^remind me in\s+(\d+)\s*(minute|minutes|min|mins|hour|hours|hr|hrs)\s+to\s+(.+)$',
    caseSensitive: false,
    );
  static final _dailyAtPattern = RegExp(
    r'^remind me (?:every day|daily) at\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\s+to\s+(.+)$',
    caseSensitive: false,
    );
  static final _atPattern = RegExp(
    r'^remind me at\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\s+to\s+(.+)$',
    caseSensitive: false,
    );
  static final _listPattern = RegExp(
    r'^(?:list|show)\s+(?:my\s+)?reminders$|^what are my reminders\??$',
    caseSensitive: false,
    );
  static final _cancelAllPattern = RegExp(r'^cancel all reminders$', caseSensitive: false);
  static final _cancelOnePattern = RegExp(r'^cancel reminder\s*#?(\d+)$', caseSensitive: false);

  DateTime? _parseClockTime(String hourStr, String? minuteStr, String? ampm) {
    var hour = int.tryParse(hourStr);
    if (hour == null || hour < 0 || hour > 23) return null;
    final minute = minuteStr != null ? int.tryParse(minuteStr) ?? 0 : 0;
    if (minute < 0 || minute > 59) return null;
    if (ampm != null) {
      final isPm = ampm.toLowerCase() == 'pm';
      if (hour == 12) {
        hour = isPm ? 12 : 0;
      } else if (isPm) {
        hour += 12;
      }
    }
    if (hour > 23) return null;
    final now = DateTime.now();
    var when = DateTime(now.year, now.month, now.day, hour, minute);
    if (when.isBefore(now)) when = when.add(const Duration(days: 1));
    return when;
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $ampm';
  }

  /// Tries to handle [text] as a reminder command. Returns a confirmation
  /// string if it was one, or null if it wasn't (so the caller can fall
  /// through to Gemini).
  Future<String?> tryHandle(String text) async {
    final trimmed = text.trim();

    final inMatch = _inPattern.firstMatch(trimmed);
    if (inMatch != null) {
      final amount = int.parse(inMatch.group(1)!);
      final unit = inMatch.group(2)!.toLowerCase();
      final label = inMatch.group(3)!.trim();
      final duration = unit.startsWith('h') ? Duration(hours: amount) : Duration(minutes: amount);
      final when = DateTime.now().add(duration);
      await _schedule(label: label, when: when, recurringDaily: false);
      return "Noted. I'll remind you at ${_formatTime(when)} to $label.";
    }

    final dailyMatch = _dailyAtPattern.firstMatch(trimmed);
    if (dailyMatch != null) {
      final when = _parseClockTime(dailyMatch.group(1)!, dailyMatch.group(2), dailyMatch.group(3));
      if (when == null) {
        return "I didn't catch that time - try \"remind me every day at 9pm to ...\".";
      }
      final label = dailyMatch.group(4)!.trim();
      await _schedule(label: label, when: when, recurringDaily: true);
      return "Noted. I'll remind you every day at ${_formatTime(when)} to $label.";
    }

    final atMatch = _atPattern.firstMatch(trimmed);
    if (atMatch != null) {
      final when = _parseClockTime(atMatch.group(1)!, atMatch.group(2), atMatch.group(3));
      if (when == null) {
        return "I didn't catch that time - try \"remind me at 7pm to ...\".";
      }
      final label = atMatch.group(4)!.trim();
      await _schedule(label: label, when: when, recurringDaily: false);
      return "Noted. I'll remind you at ${_formatTime(when)} to $label.";
    }

    if (_listPattern.hasMatch(trimmed)) {
      final all = await listReminders();
      if (all.isEmpty) return "You don't have any reminders set.";
      final lines = all.map(
        (r) => '#${r.id}: ${r.label} at ${_formatTime(r.scheduledFor)}${r.recurringDaily ? ' (every day)' : ''}',
        );
      return 'Your reminders:\n${lines.join('\n')}';
    }

    if (_cancelAllPattern.hasMatch(trimmed)) {
      final count = await cancelAll();
      return count == 0
        ? "You don't have any reminders to cancel."
        : 'Cancelled $count reminder${count == 1 ? '' : 's'}.';
    }

    final cancelMatch = _cancelOnePattern.firstMatch(trimmed);
    if (cancelMatch != null) {
      final id = int.parse(cancelMatch.group(1)!);
      final existed = await cancel(id);
      return existed
        ? 'Cancelled reminder #$id.'
        : "I couldn't find reminder #$id - try \"list reminders\" first.";
    }

    return null;
  }
}
