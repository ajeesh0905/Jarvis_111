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

  /// Serializes to JSON so chat history can be persisted in local phone
  /// storage (SharedPreferences) and survive app restarts.
  Map<String, dynamic> toJson() => {
    'text': text,
    'sender': sender.name,
    'time': time.toIso8601String(),
  };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    text: json['text'] as String,
    sender: Sender.values.byName(json['sender'] as String),
    time: DateTime.parse(json['time'] as String),
  );
}
