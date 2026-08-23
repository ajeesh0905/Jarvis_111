import 'package:flutter/material.dart';
import '../services/jarvis_server_service.dart';
import '../services/storage_service.dart';
import '../theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _apiKeyController = TextEditingController();
  final _modelController = TextEditingController();
  final _systemPromptController = TextEditingController();
  final _speedLimitController = TextEditingController();
  final _serverUrlController = TextEditingController();
  final _serverTokenController = TextEditingController();
  bool _obscureKey = true;
  bool _obscureServerToken = true;
  bool _wakeWordEnabled = false;
  bool _speakReplies = true;
  bool _overspeedEnabled = false;
  bool _dailySummaryEnabled = false;
  TimeOfDay _dailySummaryTime = const TimeOfDay(hour: 8, minute: 0);
  bool _hasStoredKey = false;
  bool _loading = true;
  bool _testingConnection = false;

    static const _customModelValue = '__custom__';
    String _selectedModel = StorageService.defaultModel;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _modelController.dispose();
    _systemPromptController.dispose();
    _speedLimitController.dispose();
    _serverUrlController.dispose();
    _serverTokenController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final storage = StorageService.instance;
    final key = await storage.getApiKey();
    final model = await storage.getModel();
    final prompt = await storage.getSystemPrompt();
    final wake = await storage.getWakeWordEnabled();
    final speak = await storage.getSpeakReplies();
    final overspeed = await storage.getOverspeedEnabled();
    final speedLimit = await storage.getSpeedLimitKmh();
    final serverUrl = await storage.getServerUrl();
    final serverToken = await storage.getServerToken();
    final dailySummaryEnabled = await storage.getDailySummaryEnabled();
    final dailySummaryHour = await storage.getDailySummaryHour();
    final dailySummaryMinute = await storage.getDailySummaryMinute();
    setState(() {
      _hasStoredKey = key != null && key.isNotEmpty;
      _apiKeyController.text = key ?? '';
      if (StorageService.availableModels.contains(model)) {
                _selectedModel = model;
                _modelController.text = '';
      } else {
                _selectedModel = _customModelValue;
                _modelController.text = model;
      }
      _systemPromptController.text = prompt;
      _wakeWordEnabled = wake;
      _speakReplies = speak;
      _overspeedEnabled = overspeed;
      _speedLimitController.text = speedLimit.round().toString();
      _serverUrlController.text = serverUrl ?? '';
      _serverTokenController.text = serverToken ?? '';
      _dailySummaryEnabled = dailySummaryEnabled;
      _dailySummaryTime = TimeOfDay(hour: dailySummaryHour, minute: dailySummaryMinute);
      _loading = false;
    });
  }

  Future<void> _testConnection() async {
    setState(() => _testingConnection = true);
    // Save the current field values first so the test actually checks
    // what's in the boxes right now, not the last-saved values.
    await StorageService.instance.setServerUrl(_serverUrlController.text.trim());
    await StorageService.instance.setServerToken(_serverTokenController.text.trim());
    final ok = await JarvisServerService().ping();
    if (mounted) {
      setState(() => _testingConnection = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? 'Connected ✓' : "Couldn't reach that server — check the URL/token and that it's running."),
        ),
      );
    }
  }

  Future<void> _save() async {
    final storage = StorageService.instance;
    if (_apiKeyController.text.trim().isNotEmpty) {
      await storage.setApiKey(_apiKeyController.text.trim());
    }
    final customModel = _modelController.text.trim();
        await storage.setModel(
                _selectedModel == _customModelValue
                    ? (customModel.isEmpty ? StorageService.defaultModel : customModel)
                    : _selectedModel,
              );
    await storage.setSystemPrompt(
      _systemPromptController.text.trim().isEmpty
          ? StorageService.defaultSystemPrompt
          : _systemPromptController.text.trim(),
    );
    await storage.setWakeWordEnabled(_wakeWordEnabled);
    await storage.setSpeakReplies(_speakReplies);
    await storage.setOverspeedEnabled(_overspeedEnabled);
    final parsedLimit = double.tryParse(_speedLimitController.text.trim());
    await storage.setSpeedLimitKmh(parsedLimit != null && parsedLimit > 0 ? parsedLimit : 80.0);
    await storage.setServerUrl(_serverUrlController.text.trim());
    await storage.setServerToken(_serverTokenController.text.trim());
    await storage.setDailySummaryEnabled(_dailySummaryEnabled);
    await storage.setDailySummaryTime(_dailySummaryTime.hour, _dailySummaryTime.minute);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved.')),
      );
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Gemini API key',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 6),
          Text(
            _hasStoredKey
                ? 'A key is currently saved on this device (encrypted storage).'
                : 'Paste your Google Gemini API key below. Get a free one at '
                    'aistudio.google.com/apikey — it is stored only on this '
                    'phone and sent directly to Google, never to any '
                    'server of ours.',
            style: const TextStyle(color: JarvisColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _apiKeyController,
            obscureText: _obscureKey,
            decoration: InputDecoration(
              hintText: 'AIza...',
              suffixIcon: IconButton(
                icon: Icon(_obscureKey ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscureKey = !_obscureKey),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Private server (optional)',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 6),
          const Text(
            'Point Jarvis at your self-hosted server (see jarvis_server/) '
            'to get persistent memory — conversation history, preferences/'
            'goals, and documents — instead of the API key above talking '
            'to Gemini directly. When both fields below are filled in, '
            'this takes over and the API key field is unused.',
            style: TextStyle(color: JarvisColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _serverUrlController,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(hintText: 'http://100.x.x.x:8000'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _serverTokenController,
            obscureText: _obscureServerToken,
            decoration: InputDecoration(
              hintText: 'Server token (from data/.env)',
              suffixIcon: IconButton(
                icon: Icon(_obscureServerToken ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscureServerToken = !_obscureServerToken),
              ),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _testingConnection ? null : _testConnection,
            child: Text(_testingConnection ? 'Testing…' : 'Test connection'),
          ),
          const SizedBox(height: 24),
          const Text(
            'Model',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 6),
          const Text(
                        'Google occasionally retires older models - if replies start '
                        'failing with a 404 mentioning the model name, switch to a '
                        'newer one here.',
                        style: TextStyle(color: JarvisColors.textSecondary, fontSize: 12),
                      ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                                  initialValue: _selectedModel,
                                  items: [
                                                  ...StorageService.availableModels.map(
                                                                    (m) => DropdownMenuItem(value: m, child: Text(m)),
                                                                  ),
                                                  const DropdownMenuItem(
                                                                    value: _customModelValue,
                                                                    child: Text('Custom...'),
                                                                  ),
                                                ],
                                  onChanged: (v) {
                                                  if (v != null) setState(() => _selectedModel = v);
                                  },
                                ),
                    if (_selectedModel == _customModelValue) ...[
                                  const SizedBox(height: 10),
                                  TextField(
                                                  controller: _modelController,
                                                  decoration: const InputDecoration(hintText: StorageService.defaultModel),
                                                ),
                                ],
          const SizedBox(height: 24),
          const Text(
            'Personality / system prompt',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _systemPromptController,
            maxLines: 5,
          ),
          const SizedBox(height: 24),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Wake word ("Jarvis")'),
            subtitle: const Text(
              'Continuously listens while the app is open. True '
              'screen-off background wake word needs a dedicated engine '
              '— see README.',
              style: TextStyle(fontSize: 12, color: JarvisColors.textSecondary),
            ),
            value: _wakeWordEnabled,
            onChanged: (v) => setState(() => _wakeWordEnabled = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Speak replies aloud'),
            value: _speakReplies,
            onChanged: (v) => setState(() => _speakReplies = v),
          ),
          const SizedBox(height: 24),
          const Text(
            'Overspeed alarm',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 6),
          const Text(
            'Watches your GPS speed — including with the screen off — and '
            'warns you (spoken alert + vibration + notification) when '
            "you're over the limit. Android shows a persistent "
            '"monitoring" notification while this is on; that\'s required '
            'for background location tracking to keep working.',
            style: TextStyle(fontSize: 12, color: JarvisColors.textSecondary),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enable overspeed alarm'),
            value: _overspeedEnabled,
            onChanged: (v) => setState(() => _overspeedEnabled = v),
          ),
          if (_overspeedEnabled) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _speedLimitController,
              keyboardType: const TextInputType.numberWithOptions(decimal: false),
              decoration: const InputDecoration(
                hintText: '80',
                suffixText: 'km/h',
              ),
            ),
          ],
          const SizedBox(height: 24),
          const Text(
            'Daily health summary',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          const SizedBox(height: 6),
          const Text(
            'The next time you open Jarvis after this time each day, it will '
            'show (and optionally speak) a summary of your steps, heart rate, '
            'and sleep from Health Connect. Not a background alert - it only '
            'fires when you open the app.',
            style: TextStyle(fontSize: 12, color: JarvisColors.textSecondary),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enable daily health summary'),
            value: _dailySummaryEnabled,
            onChanged: (v) => setState(() => _dailySummaryEnabled = v),
            ),
          if (_dailySummaryEnabled) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: _dailySummaryTime,
                  );
                if (picked != null) setState(() => _dailySummaryTime = picked);
              },
              child: Text('Show after ${_dailySummaryTime.format(context)}'),
              ),
            ],
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _save,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Text('Save'),
            ),
          ),
          if (_hasStoredKey) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: () async {
                await StorageService.instance.clearApiKey();
                setState(() {
                  _hasStoredKey = false;
                  _apiKeyController.clear();
                });
              },
              child: const Text('Remove saved API key', style: TextStyle(color: JarvisColors.danger)),
            ),
          ],
        ],
      ),
    );
  }
}
