import 'package:flutter/material.dart';
import '../services/health_service.dart';
import '../theme.dart';

/// Shows today's steps, latest heart rate, and last night's sleep - all
/// read from Android Health Connect. Point the Zepp app at Health Connect
/// (Zepp app -> Profile -> Privacy -> Sync to Health Connect, or similar,
/// depending on your Zepp version) so your Amazfit watch's data lands
/// here for Jarvis to read.
class HealthScreen extends StatefulWidget {
  const HealthScreen({super.key});

  @override
  State<HealthScreen> createState() => _HealthScreenState();
}

enum _LoadState { loading, needsInstall, needsPermission, ready, unsupported }

class _HealthScreenState extends State<HealthScreen> {
  final _health = HealthService.instance;
  _LoadState _state = _LoadState.loading;
  HealthSummary? _summary;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _state = _LoadState.loading;
      _error = null;
    });

    final availability = await _health.checkAvailability();
    if (availability == HealthConnectAvailability.notInstalled) {
      setState(() => _state = _LoadState.needsInstall);
      return;
    }
    if (availability == HealthConnectAvailability.unsupported) {
      setState(() => _state = _LoadState.unsupported);
      return;
    }

    final hasPerms = await _health.hasPermissions();
    if (!hasPerms) {
      setState(() => _state = _LoadState.needsPermission);
      return;
    }

    await _fetchSummary();
  }
  Future<void> _fetchSummary() async {
    try {
      final summary = await _health.getSummary();
      setState(() {
        _summary = summary;
        _state = _LoadState.ready;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _state = _LoadState.ready;
      });
    }
  }

  Future<void> _connect() async {
    final granted = await _health.requestPermissions();
    if (granted) {
      await _fetchSummary();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Permission not granted - Jarvis needs Health Connect access to show your data.'),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Health'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _state == _LoadState.loading ? null : _load,
            ),
          ],
        ),
      body: _buildBody(),
      );
  }

  Widget _buildBody() {
    switch (_state) {
      case _LoadState.loading:
        return const Center(child: CircularProgressIndicator());

      case _LoadState.unsupported:
        return _InfoPanel(
          icon: Icons.error_outline,
          title: "Health Connect isn't available",
          body: "This device or Android version doesn't support Health "
          'Connect, so Jarvis can\'t read health data here.',
          );

      case _LoadState.needsInstall:
        return _InfoPanel(
          icon: Icons.download_outlined,
          title: 'Install Health Connect',
          body: 'Health Connect is the Android app that Zepp syncs your '
          "Amazfit watch's steps, heart rate, and sleep into. Install "
          "it, open the Zepp app and turn on syncing to it, then come "
          'back here.',
          actionLabel: 'Open Play Store',
          onAction: () async {
            await _health.openHealthConnectInstall();
          },
          );

      case _LoadState.needsPermission:
        return _InfoPanel(
          icon: Icons.favorite_border,
          title: 'Connect your health data',
          body: 'Health Connect is installed. Grant Jarvis read access to '
          'steps, heart rate, and sleep to see your overview here - '
          'and to ask Jarvis things like "how did I sleep?"',
          actionLabel: 'Grant access',
          onAction: _connect,
          );

      case _LoadState.ready:
        return _buildSummary();
    }
  }
  Widget _buildSummary() {
    final summary = _summary;
    return RefreshIndicator(
      onRefresh: _fetchSummary,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'From Health Connect - synced from your Zepp app / Amazfit watch.',
            style: TextStyle(fontSize: 12, color: JarvisColors.textSecondary),
            ),
          const SizedBox(height: 16),
          if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              "Couldn't load your data: $_error",
              style: const TextStyle(color: JarvisColors.danger),
              ),
            ),
          _MetricCard(
            icon: Icons.directions_walk,
            label: 'Steps today',
            value: summary?.steps != null ? '${summary!.steps}' : '-',
            ),
          const SizedBox(height: 12),
          _MetricCard(
            icon: Icons.favorite,
            label: 'Heart rate',
            value: summary?.heartRateBpm != null
            ? '${summary!.heartRateBpm!.round()} bpm'
            : '-',
            subtitle: summary?.heartRateAt != null ? _relativeTime(summary!.heartRateAt!) : null,
            ),
          const SizedBox(height: 12),
          _MetricCard(
            icon: Icons.bedtime,
            label: 'Sleep last night',
            value: summary?.sleepLastNight != null && summary!.sleepLastNight!.inMinutes > 0
            ? '${summary.sleepLastNight!.inHours}h ${summary.sleepLastNight!.inMinutes % 60}m'
            : '-',
            ),
          const SizedBox(height: 24),
          if (summary != null && summary.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              "No data yet. Make sure the Zepp app is syncing your watch "
              'to Health Connect, then pull down to refresh.',
              style: TextStyle(fontSize: 12, color: JarvisColors.textSecondary),
              ),
            ),
          ],
        ),
      );
  }

  String _relativeTime(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
class _MetricCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? subtitle;

  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: JarvisColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: JarvisColors.surfaceAlt),
        ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: JarvisColors.accentDim.withValues(alpha: 0.2),
              shape: BoxShape.circle,
              ),
            child: Icon(icon, color: JarvisColors.accent),
            ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 12, color: JarvisColors.textSecondary)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          if (subtitle != null)
          Text(subtitle!, style: const TextStyle(fontSize: 11, color: JarvisColors.textSecondary)),
          ],
        ),
      );
  }
}

class _InfoPanel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _InfoPanel({
    required this.icon,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: JarvisColors.accent),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(body, style: const TextStyle(color: JarvisColors.textSecondary), textAlign: TextAlign.center),
            if (actionLabel != null) ...[
              const SizedBox(height: 20),
              ElevatedButton(onPressed: onAction, child: Text(actionLabel!)),
              ],
            ],
          ),
        ),
      );
  }
}
