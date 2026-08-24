import 'package:flutter/material.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'screens/chat_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz_data.initializeTimeZones();
  try {
    final localTimezone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(localTimezone));
  } catch (_) {
    // Fall back to the device's default (UTC) if this fails; reminder
    // times may be off by the local UTC offset until it succeeds.
  }
  runApp(const JarvisApp());
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
