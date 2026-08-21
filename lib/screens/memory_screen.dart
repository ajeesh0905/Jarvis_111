import 'package:flutter/material.dart';
import '../services/jarvis_server_service.dart';
import '../theme.dart';

class MemoryScreen extends StatefulWidget {
  const MemoryScreen({super.key});

  @override
  State<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends State<MemoryScreen> {
  final _server = JarvisServerService();
  final _textController = TextEditingController();
  String _category = 'preference';
  List<MemoryFact> _facts = [];
  bool _loading = true;
  String? _error;

  static const _categories = ['preference', 'goal', 'fact'];

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
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final facts = await _server.listMemoryFacts();
      setState(() {
        _facts = facts;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _add() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    try {
      await _server.addMemoryFact(category: _category, text: text);
      _textController.clear();
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
      }
    }
  }

  Future<void> _delete(MemoryFact fact) async {
    try {
      await _server.deleteMemoryFact(fact.id);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
      }
    }
  }

  Color _categoryColor(String c) {
    switch (c) {
      case 'goal':
        return JarvisColors.success;
      case 'fact':
        return JarvisColors.accent;
      default:
        return JarvisColors.accentDim;
    }
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
                  'Preferences, goals, and facts Jarvis will remember and '
                  'use in every conversation on your private server.',
                  style: TextStyle(fontSize: 12, color: JarvisColors.textSecondary),
                ),
                const SizedBox(height: 12),
                Row(
                  children: _categories.map((c) {
                    final selected = c == _category;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(c),
                        selected: selected,
                        onSelected: (_) => setState(() => _category = c),
                        selectedColor: _categoryColor(c).withValues(alpha: 0.3),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
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
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, style: const TextStyle(color: JarvisColors.danger), textAlign: TextAlign.center),
        ),
      );
    }
    if (_facts.isEmpty) {
      return const Center(
        child: Text('Nothing saved yet.', style: TextStyle(color: JarvisColors.textSecondary)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _facts.length,
      itemBuilder: (context, i) {
        final fact = _facts[i];
        return ListTile(
          leading: CircleAvatar(
            radius: 5,
            backgroundColor: _categoryColor(fact.category),
          ),
          title: Text(fact.text),
          subtitle: Text(fact.category, style: const TextStyle(fontSize: 11, color: JarvisColors.textSecondary)),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline, color: JarvisColors.textSecondary),
            onPressed: () => _delete(fact),
          ),
        );
      },
    );
  }
}
