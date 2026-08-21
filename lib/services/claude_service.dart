import 'dart:convert';
import 'package:http/http.dart' as http;
import 'storage_service.dart';

class ClaudeException implements Exception {
  final String message;
  ClaudeException(this.message);
  @override
  String toString() => message;
}

/// A single past turn, kept short so the request stays small.
class ClaudeTurn {
  final String role; // 'user' or 'assistant'
  final String text;
  ClaudeTurn(this.role, this.text);
}

/// Talks to Anthropic's Messages API using the key the user enters in
/// Settings. The key lives only in secure on-device storage and is sent
/// straight to api.anthropic.com — it never passes through any server of
/// ours, because there isn't one.
class ClaudeService {
  static const _endpoint = 'https://api.anthropic.com/v1/messages';
  static const _apiVersion = '2023-06-01';

  Future<String> send({
    required String userMessage,
    required List<ClaudeTurn> history,
  }) async {
    final apiKey = await StorageService.instance.getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw ClaudeException(
        'No Claude API key set yet. Add one in Settings to let JARVIS '
        'think.',
      );
    }
    final model = await StorageService.instance.getModel();
    final systemPrompt = await StorageService.instance.getSystemPrompt();

    final messages = [
      ...history.map((t) => {'role': t.role, 'content': t.text}),
      {'role': 'user', 'content': userMessage},
    ];

    http.Response response;
    try {
      response = await http
          .post(
            Uri.parse(_endpoint),
            headers: {
              'content-type': 'application/json',
              'x-api-key': apiKey,
              'anthropic-version': _apiVersion,
            },
            body: jsonEncode({
              'model': model,
              'max_tokens': 1024,
              'system': systemPrompt,
              'messages': messages,
            }),
          )
          .timeout(const Duration(seconds: 45));
    } catch (e) {
      throw ClaudeException('Could not reach Claude: $e');
    }

    if (response.statusCode == 401) {
      throw ClaudeException(
        'Claude rejected the API key (401). Double-check it in Settings.',
      );
    }
    if (response.statusCode == 429) {
      throw ClaudeException('Rate limited — try again in a moment.');
    }
    if (response.statusCode >= 400) {
      String detail = response.body;
      try {
        final decoded = jsonDecode(response.body);
        detail = decoded['error']?['message'] ?? detail;
      } catch (_) {}
      throw ClaudeException('Claude API error (${response.statusCode}): $detail');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final content = decoded['content'] as List<dynamic>?;
    if (content == null || content.isEmpty) {
      throw ClaudeException('Claude returned an empty response.');
    }
    final buffer = StringBuffer();
    for (final block in content) {
      if (block is Map && block['type'] == 'text') {
        buffer.write(block['text']);
      }
    }
    final text = buffer.toString().trim();
    if (text.isEmpty) {
      throw ClaudeException('Claude returned an empty response.');
    }
    return text;
  }
}
