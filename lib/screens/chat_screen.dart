import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../models/message.dart';
import '../services/gemini_service.dart';
import '../services/device_control_service.dart';
import '../services/health_service.dart';
import '../services/jarvis_server_service.dart';
import '../services/memory_service.dart';
import '../services/overspeed_service.dart';
import '../services/reminder_service.dart';
import '../services/smart_home_service.dart';
import '../services/storage_service.dart';
import '../services/voice_service.dart';
import '../theme.dart';
import '../widgets/chat_bubble.dart';
import 'documents_screen.dart';
import 'health_screen.dart';
import 'local_memory_screen.dart';
import 'reminders_screen.dart';
import 'settings_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messages = <ChatMessage>[];
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();

  final _gemini = GeminiService();
  final _server = JarvisServerService();
  final _voice = VoiceService();
  final _deviceControl = DeviceControlService();
  final _overspeed = OverspeedService();
  final SmartHomeService _smartHome = NoOpSmartHomeService();
    final _health = HealthService.instance;
  final _reminders = ReminderService.instance;
  final _memory = MemoryService.instance;
  final _imagePicker = ImagePicker();

  bool _sending = false;
  bool _speakReplies = true;
  bool _usingServer = false;
  String? _serverConversationId;
  VoiceState _voiceState = VoiceState.idle;
  double? _currentSpeedKmh;
  OverspeedStatus _overspeedStatus = OverspeedStatus.stopped;

  @override
  void initState() {
    super.initState();
    // Chat history (or the welcome greeting on first launch) is loaded
    // asynchronously in _loadSettings() below.
    _voice.stateStream.listen((s) {
      if (mounted) setState(() => _voiceState = s);
    });
    _overspeed.speedStream.listen((kmh) {
      if (mounted) setState(() => _currentSpeedKmh = kmh);
    });
    _overspeed.statusStream.listen((status) {
      if (mounted) setState(() => _overspeedStatus = status);
    });
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final storage = StorageService.instance;
    final history = await storage.getChatHistory();
    if (history.isNotEmpty) {
      _messages.addAll(history);
    } else {
      _messages.add(ChatMessage(
        sender: Sender.jarvis,
        text: "I'm online. Ask me anything, or try \"open spotify\", "
            "\"set an alarm for 7am\", \"remind me every day at 9am to "
            "take my medicine\", or tap the mic. Tap the bell above for "
            "quick-add daily reminders (water, medicine, and more).",
      ));
    }
    _speakReplies = await storage.getSpeakReplies();
    _usingServer = await storage.isServerConfigured();
    _serverConversationId = await storage.getServerConversationId();
    final wakeEnabled = await storage.getWakeWordEnabled();
    if (wakeEnabled) {
      await _voice.startWakeLoop(onWake: _onWakeWordHeard);
    }
    final overspeedEnabled = await storage.getOverspeedEnabled();
    if (overspeedEnabled) {
      final started = await _overspeed.start();
      if (!started) {
        _addSystem(
          "Couldn't start the overspeed alarm — check that location "
          'permission (including "Allow all the time") and GPS are on.',
        );
      }
    }
    await _maybeShowDailyHealthSummary();
    if (mounted) setState(() {});
  }

  /// Shows (and optionally speaks) a one-off daily steps/heart-rate/sleep
  /// digest, at most once per day, once the configured time of day has
  /// passed. Not a true background alarm - it only fires when the app is
  /// opened, next time after that time each day.
  Future<void> _maybeShowDailyHealthSummary() async {
    final storage = StorageService.instance;
    final enabled = await storage.getDailySummaryEnabled();
    if (!enabled) return;

    final now = DateTime.now();
    final hour = await storage.getDailySummaryHour();
    final minute = await storage.getDailySummaryMinute();
    final afterTime = now.hour > hour || (now.hour == hour && now.minute >= minute);
    if (!afterTime) return;

    final today = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final lastShown = await storage.getDailySummaryLastShown();
    if (lastShown == today) return;

    final message = await _health.buildDailySummaryMessage();
    if (message == null || !mounted) return;

    await storage.setDailySummaryLastShown(today);
    await _respond(message);
  }

  void _onWakeWordHeard() {
    _addSystem('Wake word heard — listening…');
    _startVoiceTurn();
  }

  Future<void> _startVoiceTurn() async {
    final heard = await _voice.listenOnce();
    if (heard == null || heard.trim().isEmpty) return;
    await _handleUserText(heard.trim());
  }

  void _addSystem(String text) {
    setState(() => _messages.add(ChatMessage(sender: Sender.system, text: text)));
    _persistMessages();
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Fire-and-forget: saves the current chat history to local phone
  /// storage (SharedPreferences) so it survives app restarts. Trimmed to
  /// the most recent messages inside StorageService to avoid unbounded
  /// growth.
  void _persistMessages() {
    StorageService.instance.saveChatHistory(List<ChatMessage>.from(_messages));
  }

  Future<void> _handleUserText(String text) async {
    if (text.trim().isEmpty) return;
    setState(() {
      _messages.add(ChatMessage(sender: Sender.user, text: text));
      _sending = true;
    });
    _persistMessages();
    _scrollToEnd();

    // 1. Try it as a memory command ("remember ...", "what do you
    // remember about me", "forget ..."). Checked first since these are
    // explicit, unambiguous commands with no overlap with the other
    // on-device handlers below.
    final memoryReply = await _memory.tryHandle(text);
    if (memoryReply != null) {
      await _respond(memoryReply);
      return;
    }

    // 2. Try it as a reminder command ("remind me...", "set a daily
    // reminder...", "list reminders", "cancel reminder #N" / "cancel all
    // reminders"). This is checked *before* the on-device alarm command
    // below on purpose: a labelled, persisted reminder (e.g. "set an
    // alarm to remind me to take medicine every day at 9am") should win
    // over the device control service's blunt "contains 'set' and
    // 'alarm'" native-alarm-clock match, since the reminder is what the
    // user actually asked for — a recurring, on-screen notification with
    // their custom text, not just the phone's bare stock alarm.
    final reminderReply = await _reminders.tryHandle(text);
    if (reminderReply != null) {
      await _respond(reminderReply);
      return;
    }

    // 3. Try it as an on-device command (open app, set alarm, call, ...).
    final deviceResult = await _deviceControl.tryHandle(text);
    if (deviceResult.handled) {
      await _respond(deviceResult.message);
      return;
    }

    // 4. Try it as a smart-home command.
    final smartHomeReply = await _smartHome.tryHandle(text);
    if (smartHomeReply != null) {
      await _respond(smartHomeReply);
      return;
    }

    // 5. Try it as a health/fitness check-in (steps, heart rate, sleep)
    // answered straight from Health Connect - no LLM round trip needed.
    final healthReply = await _health.tryHandle(text);
    if (healthReply != null) {
      await _respond(healthReply);
      return;
    }

    // 6. Fall back to Gemini (with memory) via your private server, or
    // straight to Gemini if no server is configured.
    if (_usingServer) {
      try {
        final result = await _server.chat(text, conversationId: _serverConversationId);
        if (_serverConversationId != result.conversationId) {
          _serverConversationId = result.conversationId;
          await StorageService.instance.setServerConversationId(result.conversationId);
        }
        await _respond(result.reply);
      } on ServerException catch (e) {
        await _respond(e.toString(), isError: true);
      } catch (e) {
        await _respond('Something went wrong talking to your server: $e', isError: true);
      }
      return;
    }

    try {
      // All prior user/jarvis turns, excluding the message we just added
      // above (it's passed separately as `userMessage`).
      final relevant = _messages.where((m) => m.sender != Sender.system).toList();
      final priorTurns = relevant.length > 1 ? relevant.sublist(0, relevant.length - 1) : <ChatMessage>[];
      final history = priorTurns
          .map((m) => GeminiTurn(m.sender == Sender.user ? 'user' : 'model', m.text))
          .toList();
      // Keep only the last ~10 turns so requests stay small. Long-term
      // facts don't depend on this window — they're pulled from
      // MemoryService and sent on every request instead (see below).
      final trimmedHistory = history.length > 10 ? history.sublist(history.length - 10) : history;
      final facts = await _memory.listFacts();
      final reply = await _gemini.send(
        userMessage: text,
        history: trimmedHistory,
        memoryFacts: facts,
      );
      await _respond(reply);
    } on GeminiException catch (e) {
      await _respond(e.toString(), isError: true);
    } catch (e) {
      await _respond('Something went wrong: $e', isError: true);
    }
  }

  /// Lets the user attach a photo (camera or gallery), shows it as a chat
  /// bubble, and sends it straight to Gemini (with vision support) for a
  /// description/answer — bypassing the on-device command layers above,
  /// since none of them make sense for an image. Works independently of
  /// the private-server chat path; it always talks to Gemini directly.
  Future<void> _pickAndSendImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: JarvisColors.surface,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined, color: JarvisColors.accent),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: JarvisColors.accent),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    XFile? picked;
    try {
      picked = await _imagePicker.pickImage(source: source, maxWidth: 1600, imageQuality: 85);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Couldn't open the camera/gallery: $e")),
        );
      }
      return;
    }
    if (picked == null) return;

    // Copy into app storage so the path stays valid across restarts — the
    // picker's own path can live in a cache dir that gets cleared.
    final dir = await getApplicationDocumentsDirectory();
    final imagesDir = Directory('${dir.path}/jarvis_images');
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }
    final savedPath = '${imagesDir.path}/${DateTime.now().microsecondsSinceEpoch}.jpg';
    await File(picked.path).copy(savedPath);

    final caption = _inputController.text.trim();
    _inputController.clear();

    setState(() {
      _messages.add(ChatMessage(
        sender: Sender.user,
        text: caption,
        imagePath: savedPath,
      ));
      _sending = true;
    });
    _persistMessages();
    _scrollToEnd();

    try {
      final bytes = await File(savedPath).readAsBytes();
      final imageBase64 = base64Encode(bytes);
      final relevant = _messages.where((m) => m.sender != Sender.system).toList();
      final priorTurns = relevant.length > 1 ? relevant.sublist(0, relevant.length - 1) : <ChatMessage>[];
      final history = priorTurns
          .map((m) => GeminiTurn(m.sender == Sender.user ? 'user' : 'model', m.text))
          .toList();
      final trimmedHistory = history.length > 10 ? history.sublist(history.length - 10) : history;
      final facts = await _memory.listFacts();
      final reply = await _gemini.send(
        userMessage: caption.isEmpty ? 'Describe this photo.' : caption,
        history: trimmedHistory,
        memoryFacts: facts,
        imageBase64: imageBase64,
        imageMimeType: 'image/jpeg',
      );
      await _respond(reply);
    } on GeminiException catch (e) {
      await _respond(e.toString(), isError: true);
    } catch (e) {
      await _respond('Something went wrong reading that photo: $e', isError: true);
    }
  }

  Future<void> _respond(String text, {bool isError = false}) async {
    setState(() {
      _messages.add(ChatMessage(sender: Sender.jarvis, text: text));
      _sending = false;
    });
    _persistMessages();
    _scrollToEnd();
    if (_speakReplies && !isError) {
      await _voice.speak(text);
    }
  }

  Future<void> _onMicPressed() async {
    if (_voiceState == VoiceState.listening) return;
    final heard = await _voice.listenOnce();
    if (heard != null && heard.trim().isNotEmpty) {
      await _handleUserText(heard.trim());
    }
  }

  Future<void> _openSettings() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
    if (changed == true) {
      final storage = StorageService.instance;
      _speakReplies = await storage.getSpeakReplies();
      _usingServer = await storage.isServerConfigured();
      final wakeEnabled = await storage.getWakeWordEnabled();
      if (wakeEnabled) {
        await _voice.startWakeLoop(onWake: _onWakeWordHeard);
      } else {
        _voice.stopWakeLoop();
      }
      final overspeedEnabled = await storage.getOverspeedEnabled();
      if (overspeedEnabled) {
        await _overspeed.start();
      } else {
        await _overspeed.stop();
        setState(() => _currentSpeedKmh = null);
      }
      if (mounted) setState(() {});
    }
  }

  void _openServerScreen(Widget screen) {
    if (!_usingServer) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Connect a private server in Settings first (Memory/Documents need it).'),
        ),
      );
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  String get _micStatusLabel {
    switch (_voiceState) {
      case VoiceState.listening:
        return 'Listening…';
      case VoiceState.wakeListening:
        return 'Waiting for "Jarvis"…';
      case VoiceState.speaking:
        return 'Speaking…';
      case VoiceState.error:
        return 'Mic error';
      case VoiceState.idle:
        return '';
    }
  }

  @override
  void dispose() {
    _voice.dispose();
    _overspeed.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.blur_circular, color: JarvisColors.accent),
            const SizedBox(width: 8),
            const Text('Jarvis'),
            if (_micStatusLabel.isNotEmpty) ...[
              const SizedBox(width: 10),
              Text(
                _micStatusLabel,
                style: const TextStyle(fontSize: 12, color: JarvisColors.textSecondary),
              ),
            ],
          ],
        ),
        actions: [
          if (_overspeedStatus != OverspeedStatus.stopped && _currentSpeedKmh != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _overspeedStatus == OverspeedStatus.overLimit
                      ? JarvisColors.danger.withValues(alpha: 0.18)
                      : JarvisColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _overspeedStatus == OverspeedStatus.overLimit
                        ? JarvisColors.danger
                        : JarvisColors.accentDim,
                  ),
                ),
                child: Text(
                  '${_currentSpeedKmh!.round()} km/h',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: _overspeedStatus == OverspeedStatus.overLimit
                        ? JarvisColors.danger
                        : JarvisColors.textSecondary,
                  ),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.notifications_active_outlined),
            tooltip: 'Daily Reminders',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const RemindersScreen()),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.monitor_heart_outlined),
            tooltip: 'Health',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const HealthScreen()),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.psychology_outlined),
            tooltip: 'Memory',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LocalMemoryScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.description_outlined),
            tooltip: 'Documents',
            onPressed: () => _openServerScreen(const DocumentsScreen()),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: _messages.length,
              itemBuilder: (context, i) => ChatBubble(message: _messages[i]),
            ),
          ),
          if (_sending)
            const Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: SizedBox(
                height: 2,
                child: LinearProgressIndicator(
                  backgroundColor: JarvisColors.surfaceAlt,
                  color: JarvisColors.accent,
                ),
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      decoration: const InputDecoration(hintText: 'Ask Jarvis…'),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (v) {
                        _inputController.clear();
                        _handleUserText(v);
                      },
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.attach_file, color: JarvisColors.textSecondary),
                    tooltip: 'Attach photo',
                    onPressed: _pickAndSendImage,
                  ),
                  const SizedBox(width: 4),
                  _MicButton(
                    active: _voiceState == VoiceState.listening || _voiceState == VoiceState.wakeListening,
                    onPressed: _onMicPressed,
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.send, color: JarvisColors.accent),
                    onPressed: () {
                      final v = _inputController.text;
                      _inputController.clear();
                      _handleUserText(v);
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MicButton extends StatelessWidget {
  final bool active;
  final VoidCallback onPressed;
  const _MicButton({required this.active, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? JarvisColors.accent : JarvisColors.surfaceAlt,
      ),
      child: IconButton(
        icon: Icon(Icons.mic, color: active ? Colors.black : JarvisColors.accent),
        onPressed: onPressed,
      ),
    );
  }
}
