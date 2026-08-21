import 'package:flutter/material.dart';
import '../services/jarvis_server_service.dart';
import '../theme.dart';

class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key});

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  final _server = JarvisServerService();
  List<ServerDocument> _docs = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final docs = await _server.listDocuments();
      setState(() {
        _docs = docs;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _delete(ServerDocument doc) async {
    try {
      await _server.deleteDocument(doc.id);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
      }
    }
  }

  Future<void> _openAddDialog() async {
    final titleController = TextEditingController();
    final contentController = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: JarvisColors.surface,
        title: const Text('Add note / document'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(hintText: 'Title'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: contentController,
                maxLines: 8,
                decoration: const InputDecoration(hintText: 'Content'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (saved == true && titleController.text.trim().isNotEmpty && contentController.text.trim().isNotEmpty) {
      try {
        await _server.addDocument(title: titleController.text.trim(), content: contentController.text.trim());
        await _load();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Documents & notes'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAddDialog,
        backgroundColor: JarvisColors.accent,
        child: const Icon(Icons.add, color: Colors.black),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, style: const TextStyle(color: JarvisColors.danger), textAlign: TextAlign.center),
        ),
      );
    }
    if (_docs.isEmpty) {
      return const Center(
        child: Text(
          'No documents yet. Jarvis will search these for context when '
          'you ask it something relevant.',
          style: TextStyle(color: JarvisColors.textSecondary),
          textAlign: TextAlign.center,
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _docs.length,
      itemBuilder: (context, i) {
        final doc = _docs[i];
        return ListTile(
          leading: const Icon(Icons.description_outlined, color: JarvisColors.accentDim),
          title: Text(doc.title),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline, color: JarvisColors.textSecondary),
            onPressed: () => _delete(doc),
          ),
        );
      },
    );
  }
}
