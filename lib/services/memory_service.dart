import 'package:shared_preferences/shared_preferences.dart';

/// A small on-device, permanent memory of facts about the user (name,
/// preferences, recurring details like a bus schedule) that Jarvis can
/// recall in every conversation - not just the last ~10 chat turns that
/// get sent to Gemini. Works entirely locally, no private server needed
/// (the server-backed "Memory" feature in MemoryScreen is separate and
/// still requires a configured private server).
class MemoryService {
  MemoryService._();
  static final MemoryService instance = MemoryService._();

  static const _prefsKey = 'jarvis_memory_facts';

  static final _rememberPattern = RegExp(
    r'^remember (?:that\s+)?(.+)$',
    caseSensitive: false,
  );
  static final _listPattern = RegExp(
    r'^(?:what do you (?:remember|know) about me\??|list memories|show '
    r'(?:my )?memory)$',
    caseSensitive: false,
  );
  static final _forgetAllPattern = RegExp(
    r'^(?:forget everything|clear (?:your |my )?memory)$',
    caseSensitive: false,
  );
  static final _forgetOnePattern = RegExp(
    r'^forget (?:that\s+)?(.+)$',
    caseSensitive: false,
  );

  Future<List<String>> listFacts() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_prefsKey) ?? [];
  }

  Future<void> addFact(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final facts = prefs.getStringList(_prefsKey) ?? [];
    facts.add(trimmed);
    await prefs.setStringList(_prefsKey, facts);
  }

  Future<void> deleteFactAt(int index) async {
    final prefs = await SharedPreferences.getInstance();
    final facts = prefs.getStringList(_prefsKey) ?? [];
    if (index < 0 || index >= facts.length) return;
    facts.removeAt(index);
    await prefs.setStringList(_prefsKey, facts);
  }

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }

  /// Tries to handle [text] as a memory command ("remember ...", "what do
  /// you remember about me", "forget ..."). Returns a confirmation string
  /// if it was one, or null if it wasn't (so the caller can fall through
  /// to Gemini).
  Future<String?> tryHandle(String text) async {
    final trimmed = text.trim();

    final rememberMatch = _rememberPattern.firstMatch(trimmed);
    if (rememberMatch != null) {
      final fact = rememberMatch.group(1)!.trim();
      if (fact.isEmpty) {
        return "Remember what? Try \"remember I'm allergic to peanuts\".";
      }
      await addFact(fact);
      return 'Got it, I\'ll remember: $fact';
    }

    if (_listPattern.hasMatch(trimmed)) {
      final facts = await listFacts();
      if (facts.isEmpty) {
        return 'I don\'t have anything saved yet - tell me "remember ..." '
            'and I\'ll keep it.';
      }
      final lines = [
        for (var i = 0; i < facts.length; i++) '#${i + 1}: ${facts[i]}',
      ];
      return 'Here\'s what I remember about you:\n${lines.join('\n')}';
    }

    if (_forgetAllPattern.hasMatch(trimmed)) {
      final facts = await listFacts();
      if (facts.isEmpty) return "There's nothing in memory to forget.";
      await clearAll();
      return "Done - I've cleared everything I remembered about you.";
    }

    final forgetMatch = _forgetOnePattern.firstMatch(trimmed);
    if (forgetMatch != null) {
      final query = forgetMatch.group(1)!.trim().toLowerCase();
      final facts = await listFacts();
      final index = facts.indexWhere((f) => f.toLowerCase().contains(query));
      if (index == -1) {
        return "I couldn't find anything matching \"$query\" in memory - "
            'try "what do you remember about me" to see the list.';
      }
      final removed = facts[index];
      await deleteFactAt(index);
      return 'Forgotten: $removed';
    }

    return null;
  }
}
