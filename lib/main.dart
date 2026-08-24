import 'package:flutter/material.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'screens/chat_screen.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  tz_data.initializeTimeZones();
  tz.setLocalLocation(_deviceLocalLocation());
  runApp(const JarvisApp());
}

/// Picks a timezone [tz.Location] matching the device's current UTC
/// offset, without depending on a native plugin (the flutter_timezone
/// package's Android/Kotlin code doesn't build against current Flutter,
/// so we avoid it entirely). Common half-hour-offset zones are mapped by
/// name since the IANA `Etc/GMT` fixed zones only cover whole hours;
/// everything else falls back to the nearest whole-hour `Etc/GMT` zone.
tz.Location _deviceLocalLocation() {
  final offsetMinutes = DateTime.now().timeZoneOffset.inMinutes;
  const halfHourZones = <int, String>{
    330: 'Asia/Kolkata', // UTC+5:30
    345: 'Asia/Kathmandu', // UTC+5:45
    270: 'Asia/Kabul', // UTC+4:30
    210: 'Asia/Tehran', // UTC+3:30
    570: 'Australia/Darwin', // UTC+9:30
    630: 'Australia/Adelaide', // UTC+10:30
    525: 'Australia/Eucla', // UTC+8:45
    -210: 'America/St_Johns', // UTC-3:30
  };
  final specialName = halfHourZones[offsetMinutes];
  if (specialName != null) {
    try {
      return tz.getLocation(specialName);
    } catch (_) {
      // Fall through to the whole-hour approximation below.
    }
  }
  final wholeHours = (offsetMinutes / 60).round();
  final etcName = wholeHours == 0
      ? 'UTC'
      : (wholeHours > 0 ? 'Etc/GMT-${wholeHours}' : 'Etc/GMT+${-wholeHours}');
  try {
    return tz.getLocation(etcName);
  } catch (_) {
    return tz.UTC;
  }
}

class JarvisApp extends StatelessWidget {
  const JarvisApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Jarvis',
      debugShowCheckedModeBanner: false,
      theme: buildJarvisTheme(),
      home: const ChatScreen(),
    );
  }
}
