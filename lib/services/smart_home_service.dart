/// Extensibility point for smart-home control ("turn off the lights",
/// "set the thermostat to 70"). No concrete hub/vendor was specified when
/// this app was built, so this ships as a clean interface + a documented
/// example implementation you can wire up to your actual system.
///
/// To activate a real integration:
///  1. Implement [SmartHomeService] for your platform (see
///     [HueBridgeExample] below for the shape of an HTTP-based one —
///     Philips Hue, Home Assistant's REST API, SmartThings, and most
///     hub-based systems all look similar: a base URL + a token).
///  2. Construct it in `main.dart` and pass it into ChatScreen instead of
///     the default [NoOpSmartHomeService].
abstract class SmartHomeService {
  /// Returns null if [command] isn't a smart-home command this service
  /// understands, otherwise performs it and returns a human-readable
  /// confirmation.
  Future<String?> tryHandle(String command);
}

/// Default implementation: recognizes smart-home phrasing so JARVIS can
/// give an honest "not connected yet" answer instead of silently doing
/// nothing or making something up.
class NoOpSmartHomeService implements SmartHomeService {
  static final _pattern = RegExp(
    r'\b(lights?|thermostat|lock the door|unlock the door|smart plug|'
    r'turn (on|off) the)\b',
    caseSensitive: false,
  );

  @override
  Future<String?> tryHandle(String command) async {
    if (_pattern.hasMatch(command)) {
      return "I hear you, but I'm not connected to any smart-home system "
          "yet. Wire one up in lib/services/smart_home_service.dart.";
    }
    return null;
  }
}

/// EXAMPLE ONLY — not wired up by default. Shows the shape of a real
/// integration against something like a local Home Assistant instance or
/// a Hue bridge exposing a simple REST API. Fill in [baseUrl]/[token] and
/// swap this in for [NoOpSmartHomeService] in main.dart to activate it.
class HueBridgeExample implements SmartHomeService {
  final String baseUrl; // e.g. http://192.168.1.50/api/<username>
  final String token;

  HueBridgeExample({required this.baseUrl, required this.token});

  @override
  Future<String?> tryHandle(String command) async {
    final t = command.toLowerCase();
    if (!t.contains('light')) return null;

    // final on = t.contains('on') && !t.contains('off');
    // await http.put(
    //   Uri.parse('$baseUrl/lights/1/state'),
    //   body: jsonEncode({'on': on}),
    // );

    final on = t.contains('on') && !t.contains('off');
    return 'Turning the lights ${on ? 'on' : 'off'}. '
        '(Stub — implement the actual bridge call in HueBridgeExample.)';
  }
}
