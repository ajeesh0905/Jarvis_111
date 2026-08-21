enum Sender { user, jarvis, system }

class ChatMessage {
  final String text;
  final Sender sender;
  final DateTime time;

  ChatMessage({
    required this.text,
    required this.sender,
    DateTime? time,
  }) : time = time ?? DateTime.now();

  /// Two-digit-padded HH:MM for the chat bubble timestamp.
  /// (Written by hand instead of pulling in `intl`, to keep the
  /// dependency graph — and the odds of a plugin/AGP version clash — small.)
  String get timeLabel {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
