import 'dart:convert';
import 'package:http/http.dart' as http;
import 'storage_service.dart';

class GeminiException implements Exception {
  final String message;
  GeminiException(this.message);
  @override
  String toString() => message;
}

/// A single past turn, kept short so the request stays small.
class GeminiTurn {
  final String role; // 'user' or 'model'
  final String text;
  GeminiTurn(this.role, this.text);
}

/// Talks to Google's Gemini API using the key the user enters in
/// Settings. The key lives only in secure on-device storage and is sent
/// straight to generativelanguage.googleapis.com — it never passes
/// through any server of ours, because there isn't one.
class GeminiService {
  static const _baseUrl = 'https://generativelanguage.googleapis.com/v1beta/models';

  Future<String> send({
    required String userMessage,
    required List<GeminiTurn> history,
  }) async {
    final apiKey = await StorageService.instance.getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw GeminiException(
        'No Gemini API key set yet. Add one in Settings to let JARVIS think.',
      );
    }
    final model = await StorageService.instance.getModel();
    final systemPrompt = await StorageService.instance.getSystemPrompt();

    final contents = [
      ...history.map(
        (t) => {
          'role': t.role,
          'parts': [
            {'text': t.text},
          ],
        },
      ),
      {
        'role': 'user',
        'parts': [
          {'text': userMessage},
        ],
      },
    ];

    final uri = Uri.parse(
      '$_baseUrl/$model:generateContent',
    ).replace(queryParameters: {'key': apiKey});

    http.Response response;
    try {
      response = await http
          .post(
            uri,
            headers: {'content-type': 'application/json'},
            body: jsonEncode({
              'system_instruction': {
                'parts': [
                  {'text': systemPrompt},
                ],
              },
              'contents': contents,
            }),
          )
          .timeout(const Duration(seconds: 45));
    } catch (e) {
      throw GeminiException('Could not reach Gemini: $e');
    }

    if (response.statusCode == 400 ||
        response.statusCode == 401 ||
        response.statusCode == 403) {
      String detail = response.body;
      try {
        final decoded = jsonDecode(response.body);
        detail = decoded['error']?['message'] ?? detail;
      } catch (_) {}
      throw GeminiException(
        'Gemini rejected the request (${response.statusCode}): $detail. '
        'Double-check the API key in Settings.',
      );
    }
    if (response.statusCode == 429) {
      throw GeminiException('Rate limited — try again in a moment.');
    }
    if (response.statusCode >= 400) {
      String detail = response.body;
      try {
        final decoded = jsonDecode(response.body);
        detail = decoded['error']?['message'] ?? detail;
      } catch (_) {}
      throw GeminiException('Gemini API error (${response.statusCode}): $detail');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = decoded['candidates'] as List<dynamic>?;
    if (candidates == null || candidates.isEmpty) {
      final blockReason = decoded['promptFeedback']?['blockReason'];
      if (blockReason != null) {
        throw GeminiException('Gemini blocked the response ($blockReason).');
      }
      throw GeminiException('Gemini returned an empty response.');
    }
    final content = candidates.first['content'] as Map<String, dynamic>?;
    final parts = content?['parts'] as List<dynamic>?;
    if (parts == null || parts.isEmpty) {
      throw GeminiException('Gemini returned an empty response.');
    }
    final buffer = StringBuffer();
    for (final part in parts) {
      if (part is Map && part['text'] != null) {
        buffer.write(part['text']);
      }
    }
    final text = buffer.toString().trim();
    if (text.isEmpty) {
      throw GeminiException('Gemini returned an empty response.');
    }
    return text;
  }
}
