import 'package:flutter/material.dart';
import '../services/reminder_service.dart';
import '../theme.dart';

/// Quick-add screen for common daily-needs reminders (water, medicine,
/// stretch, bedtime) plus a custom one - built on top of the same
/// natural-language ReminderService.tryHandle() the chat uses, so these
/// show up identically to reminders set by typing to Jarvis.
class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _QuickReminder {
  final String label;
  final IconData icon;
  final String command;
  const _QuickReminder({
    required this.label,
    required this.icon,
    required this.command,
  });
}

class _RemindersScreenState extends State<RemindersScreen> {
  final _reminders = ReminderService.instance;
  List<Reminder> _list = [];
  bool _loading = true;

  static const _quickAdds = [
    _QuickReminder(
      label: 'Drink water',
      icon: Icons.local_drink_outlined,
      command: 'remind me every 2 hours between 8am and 10pm to drink water',
    ),
    _QuickReminder(
      label: 'Take medicine',
      icon: Icons.medication_outlined,
      command: 'remind me every day at 9am to take my medicine',
    ),
    _QuickReminder(
      label: 'Stretch',
      icon: Icons.self_improvement_outlined,
      command: 'remind me every 3 hours between 9am and 9pm to stretch',
    ),
    _QuickReminder(
      label: 'Bedtime',
      icon: Icons.bedtime_outlined,
      command: 'remind me every day at 10:30pm to wind down for bed',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await _reminders.listReminders();
    if (!mounted) return;
    setState(() {
      _list = list;
      _loading = false;
    });
  }

  Future<void> _addQuick(_QuickReminder q) async {
    await _reminders.tryHandle(q.command);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Added: ${q.label}')),
    );
    await _load();
  }

  Future<void> _addCustom() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: JarvisColors.surface,
        title: const Text('Custom reminder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'e.g. remind me every day at 6pm to feed the cat',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty) return;
    final reply = await _reminders.tryHandle(result);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          reply ??
              "I didn't understand that - try \"remind me every day at "
                  '6pm to ...".',
        ),
      ),
    );
    await _load();
  }

  Future<void> _cancel(Reminder r) async {
    await _reminders.cancel(r.id);
    await _load();
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $ampm';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Reminders'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    'Quick add',
                    style: TextStyle(fontSize: 12, color: JarvisColors.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final q in _quickAdds)
                        ActionChip(
                          avatar: Icon(q.icon, size: 18, color: JarvisColors.accent),
                          label: Text(q.label),
                          backgroundColor: JarvisColors.surfaceAlt,
                          onPressed: () => _addQuick(q),
                        ),
                      ActionChip(
                        avatar: const Icon(Icons.add, size: 18, color: JarvisColors.accent),
                        label: const Text('Custom'),
                        backgroundColor: JarvisColors.surfaceAlt,
                        onPressed: _addCustom,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Your reminders',
                    style: TextStyle(fontSize: 12, color: JarvisColors.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  if (_list.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        "You don't have any reminders yet - tap a quick add "
                        'above, or use Custom.',
                        style: TextStyle(color: JarvisColors.textSecondary),
                      ),
                    ),
                  for (final r in _list)
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: JarvisColors.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: JarvisColors.surfaceAlt),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            r.recurringDaily ? Icons.repeat : Icons.alarm,
                            color: JarvisColors.accent,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  r.label,
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${_formatTime(r.scheduledFor)}'
                                  '${r.recurringDaily ? ' - every day' : ''}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: JarvisColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: JarvisColors.textSecondary),
                            onPressed: () => _cancel(r),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
