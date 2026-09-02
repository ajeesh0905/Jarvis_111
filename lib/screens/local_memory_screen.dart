import 'package:flutter/material.dart';
import '../services/memory_service.dart';
import '../theme.dart';

/// On-device list of facts Jarvis remembers about you (see MemoryService).
/// Works with no private server needed - add facts here, or just say
/// "remember ..." in chat and Jarvis saves them automatically.
class LocalMemoryScreen extends StatefulWidget {
  const LocalMemoryScreen({super.key});

  @override
  State<LocalMemoryScreen> createState() => _LocalMemoryScreenState();
}

class _LocalMemoryScreenState extends State<LocalMemoryScreen> {
  final _memory = MemoryService.instance;
  final _textController = TextEditingController();
  List<String> _facts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final facts = await _memory.listFacts();
    if (!mounted) return;
    setState(() {
      _facts = facts;
      _loading = false;
    });
  }

  Future<void> _add() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    await _memory.addFact(text);
    _textController.clear();
    await _load();
  }

  Future<void> _delete(int index) async {
    await _memory.deleteFactAt(index);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Memory'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Facts Jarvis remembers about you, saved on this phone - '
                  'used in every conversation, not just recent messages. '
                  'Add one here, or just say "remember ..." in chat.',
                  style: TextStyle(fontSize: 12, color: JarvisColors.textSecondary),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        decoration: const InputDecoration(hintText: 'e.g. "I prefer metric units"'),
                        onSubmitted: (_) => _add(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.add_circle, color: JarvisColors.accent),
                      onPressed: _add,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: JarvisColors.surfaceAlt),
          Expanded(child: _buildList()),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_facts.isEmpty) {
      return const Center(
        child: Text('Nothing saved yet.', style: TextStyle(color: JarvisColors.textSecondary)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _facts.length,
      itemBuilder: (context, i) {
        return ListTile(
          leading: const CircleAvatar(radius: 5, backgroundColor: JarvisColors.accent),
          title: Text(_facts[i]),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline, color: JarvisColors.textSecondary),
            onPressed: () => _delete(i),
          ),
        );
      },
    );
  }
}
