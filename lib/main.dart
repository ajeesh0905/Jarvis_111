import 'package:flutter/material.dart';
import 'screens/chat_screen.dart';
import 'theme.dart';

void main() {
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
