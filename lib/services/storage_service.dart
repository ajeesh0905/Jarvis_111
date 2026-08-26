import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/message.dart';

/// Wraps secure storage (for the Gemini API key) and SharedPreferences
/// (for plain settings) behind one small API.
class StorageService {
  StorageService._();
  static final StorageService instance = StorageService._();

  final _secure = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _keyApiKey = 'gemini_api_key';
  static const _keyModel = 'gemini_model';
  static const _keyWakeWord = 'wake_word_enabled';
  static const _keySpeakReplies = 'speak_replies_enabled';
  static const _keySystemPrompt = 'jarvis_system_prompt';
  static const _keyOverspeedEnabled = 'overspeed_enabled';
  static const _keySpeedLimitKmh = 'overspeed_limit_kmh';
  static const _keyServerUrl = 'jarvis_server_url';
  static const _keyServerToken = 'jarvis_server_token';
  static const _keyServerConversationId = 'jarvis_server_conversation_id';
  static const _keyDailySummaryEnabled = 'daily_summary_enabled';
  static const _keyDailySummaryHour = 'daily_summary_hour';
  static const _keyDailySummaryMinute = 'daily_summary_minute';
  static const _keyDailySummaryLastShown = 'daily_summary_last_shown';
  static const _keyChatHistory = 'jarvis_chat_history';

  static const defaultModel = 'gemini-3.6-flash';
  static const availableModels = [
        'gemini-3.7-flash',
        'gemini-3.6-flash',
        'gemini-3.5-flash',
        'gemini-3.5-flash-lite',
        'gemini-2.5-pro',
      ];

  static const defaultSystemPrompt =
      'You are JARVIS, a witty, concise, and unflappable personal AI '
      'assistant running on the user\'s phone. Keep spoken replies short '
      '(1-3 sentences) unless the user asks for detail. Opening apps, '
      'setting alarms/timers, placing calls, and reminders are handled by '
      'the app itself BEFORE your reply is ever generated — if a message '
      'reaches you asking about one of those, the app did NOT recognize it '
      'as that kind of command, so nothing was actually done. Never claim '
      'you set an alarm, timer, or reminder, or that you performed any '
      'device action — you have no way to know whether it worked. Instead, '
      'tell the user the request wasn\'t understood and ask them to '
      'rephrase it plainly, e.g. "set an alarm for 7am".';

  Future<String?> getApiKey() => _secure.read(key: _keyApiKey);

  Future<void> setApiKey(String value) =>
      _secure.write(key: _keyApiKey, value: value.trim());

  Future<void> clearApiKey() => _secure.delete(key: _keyApiKey);

  Future<String> getModel() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyModel) ?? defaultModel;
  }

  Future<void> setModel(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyModel, value);
  }

  Future<bool> getWakeWordEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyWakeWord) ?? false;
  }

  Future<void> setWakeWordEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyWakeWord, value);
  }

  Future<bool> getSpeakReplies() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keySpeakReplies) ?? true;
  }

  Future<void> setSpeakReplies(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keySpeakReplies, value);
  }

  Future<String> getSystemPrompt() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keySystemPrompt) ?? defaultSystemPrompt;
  }

  Future<void> setSystemPrompt(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySystemPrompt, value);
  }

  Future<bool> getOverspeedEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyOverspeedEnabled) ?? false;
  }

  Future<void> setOverspeedEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyOverspeedEnabled, value);
  }

  /// Speed limit in km/h that triggers the overspeed alarm.
  Future<double> getSpeedLimitKmh() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_keySpeedLimitKmh) ?? 80.0;
  }

  Future<void> setSpeedLimitKmh(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keySpeedLimitKmh, value);
  }

  // --- Private (self-hosted) server, for persistent memory ---
  // When both of these are set, chat is routed through your own server
  // (which stores conversation/preference/document memory) instead of
  // calling Gemini directly from the phone. See jarvis_server/README.md.

  Future<String?> getServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyServerUrl);
    if (raw == null || raw.trim().isEmpty) return null;
    // Strip a trailing slash so callers can safely do '$base/chat'.
    return raw.trim().replaceFirst(RegExp(r'/+$'), '');
  }

  Future<void> setServerUrl(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyServerUrl, value.trim());
  }

  Future<String?> getServerToken() => _secure.read(key: _keyServerToken);

  Future<void> setServerToken(String value) =>
      _secure.write(key: _keyServerToken, value: value.trim());

  Future<bool> isServerConfigured() async {
    final url = await getServerUrl();
    final token = await getServerToken();
    return url != null && url.isNotEmpty && token != null && token.isNotEmpty;
  }

  /// The active conversation id on the private server, so history
  /// continues across app restarts instead of starting a fresh
  /// conversation every launch. Null means "start a new one."
  Future<String?> getServerConversationId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyServerConversationId);
  }

  Future<void> setServerConversationId(String? value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value == null) {
      await prefs.remove(_keyServerConversationId);
    } else {
      await prefs.setString(_keyServerConversationId, value);
    }
  }

  // --- Daily health summary ---
  // Each day, after the chosen time, Jarvis shows (and optionally speaks)
  // a one-time digest of steps/heart rate/sleep from Health Connect the
  // next time the app is opened. Not a true background alarm - it fires
  // on app launch, gated by a last-shown date so it only shows once a day.

  Future<bool> getDailySummaryEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyDailySummaryEnabled) ?? false;
  }

  Future<void> setDailySummaryEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDailySummaryEnabled, value);
  }

  Future<int> getDailySummaryHour() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyDailySummaryHour) ?? 8;
  }

  Future<int> getDailySummaryMinute() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyDailySummaryMinute) ?? 0;
  }

  Future<void> setDailySummaryTime(int hour, int minute) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyDailySummaryHour, hour);
    await prefs.setInt(_keyDailySummaryMinute, minute);
  }

  Future<String?> getDailySummaryLastShown() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyDailySummaryLastShown);
  }

  Future<void> setDailySummaryLastShown(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDailySummaryLastShown, value);
  }

  // --- Chat history ---
  // Persists the chat transcript in local phone storage so it survives
  // app restarts, instead of resetting to a blank chat every launch.
  // Capped at a fixed number of messages so storage doesn't grow forever.

  static const _maxChatHistoryMessages = 200;

  Future<List<ChatMessage>> getChatHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_keyChatHistory) ?? [];
    return raw
        .map((s) => ChatMessage.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveChatHistory(List<ChatMessage> messages) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = messages.length > _maxChatHistoryMessages
        ? messages.sublist(messages.length - _maxChatHistoryMessages)
        : messages;
    await prefs.setStringList(
      _keyChatHistory,
      trimmed.map((m) => jsonEncode(m.toJson())).toList(),
    );
  }

  Future<void> clearChatHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyChatHistory);
  }
}
