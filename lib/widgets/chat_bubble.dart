import 'dart:io';

import 'package:flutter/material.dart';
import '../models/message.dart';
import '../theme.dart';

class ChatBubble extends StatelessWidget {
  final ChatMessage message;
  const ChatBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.sender == Sender.user;
    final isSystem = message.sender == Sender.system;

    if (isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Center(
          child: Text(
            message.text,
            style: const TextStyle(
              color: JarvisColors.textSecondary,
              fontSize: 12,
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final bubbleColor = isUser ? JarvisColors.accentDim.withValues(alpha: 0.25) : JarvisColors.surface;
    final align = isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final mainAlign = isUser ? MainAxisAlignment.end : MainAxisAlignment.start;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: mainAlign,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
            child: Column(
              crossAxisAlignment: align,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: bubbleColor,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isUser ? 16 : 4),
                      bottomRight: Radius.circular(isUser ? 4 : 16),
                    ),
                    border: isUser
                        ? null
                        : Border.all(color: JarvisColors.accentDim.withValues(alpha: 0.35)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (message.imagePath != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(
                            File(message.imagePath!),
                            width: 220,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => Container(
                              width: 220,
                              height: 140,
                              alignment: Alignment.center,
                              color: JarvisColors.surfaceAlt,
                              child: const Icon(
                                Icons.broken_image_outlined,
                                color: JarvisColors.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      if (message.imagePath != null && message.text.isNotEmpty)
                        const SizedBox(height: 8),
                      if (message.text.isNotEmpty)
                        Text(
                          message.text,
                          style: const TextStyle(fontSize: 15, height: 1.35),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 3, left: 4, right: 4),
                  child: Text(
                    message.timeLabel,
                    style: const TextStyle(fontSize: 10, color: JarvisColors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
