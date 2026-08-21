import 'dart:convert';
import 'package:http/http.dart' as http;
import 'storage_service.dart';

class ServerException implements Exception {
  final String message;
  ServerException(this.message);
  @override
  String toString() => message;
}

class ServerConversation {
  final String id;
  final String title;
  final double updatedAt;
  ServerConversation({required this.id, required this.title, required this.updatedAt});
  factory ServerConversation.fromJson(Map<String, dynamic> j) => ServerConversation(
        id: j['id'],
        title: j['title'],
        updatedAt: (j['updated_at'] as num).toDouble(),
      );
}

class ServerMessage {
  final String role; // 'user' or 'assistant'
  final String content;
  ServerMessage({required this.role, required this.content});
  factory ServerMessage.fromJson(Map<String, dynamic> j) =>
      ServerMessage(role: j['role'], content: j['content']);
}

class MemoryFact {
  final String id;
  final String category;
  final String text;
  MemoryFact({required this.id, required this.category, required this.text});
  factory MemoryFact.fromJson(Map<String, dynamic> j) =>
      MemoryFact(id: j['id'], category: j['category'], text: j['text']);
}

class ServerDocument {
  final String id;
  final String title;
  ServerDocument({required this.id, required this.title});
  factory ServerDocument.fromJson(Map<String, dynamic> j) =>
      ServerDocument(id: j['id'], title: j['title']);
}

class DocumentSearchHit {
  final String id;
  final String title;
  final String snippet;
  DocumentSearchHit({required this.id, required this.title, required this.snippet});
  factory DocumentSearchHit.fromJson(Map<String, dynamic> j) =>
      DocumentSearchHit(id: j['id'], title: j['title'], snippet: j['snippet']);
}

/// Talks to your self-hosted Jarvis Personal Server (see
/// jarvis_server/README.md) instead of calling Claude directly. Only
/// used once Settings has both a server URL and token configured.
class JarvisServerService {
  Future<Map<String, String>> _headers() async {
    final token = await StorageService.instance.getServerToken();
    return {
      'content-type': 'application/json',
      if (token != null) 'authorization': 'Bearer $token',
    };
  }

  Future<String> _base() async {
    final url = await StorageService.instance.getServerUrl();
    if (url == null) {
      throw ServerException('No private server configured. Set one in Settings.');
    }
    return url;
  }

  Never _throwForStatus(http.Response r) {
    String detail = r.body;
    try {
      final decoded = jsonDecode(r.body);
      detail = decoded['detail']?.toString() ?? detail;
    } catch (_) {}
    if (r.statusCode == 401) {
      throw ServerException('Server rejected the token — check it in Settings.');
    }
    throw ServerException('Server error (${r.statusCode}): $detail');
  }

  Future<({String reply, String conversationId})> chat(String message, {String? conversationId}) async {
    final base = await _base();
    http.Response r;
    try {
      r = await http
          .post(
            Uri.parse('$base/chat'),
            headers: await _headers(),
            body: jsonEncode({
              'message': message,
              if (conversationId != null) 'conversation_id': conversationId,
            }),
          )
          .timeout(const Duration(seconds: 60));
    } catch (e) {
      throw ServerException('Could not reach your server: $e');
    }
    if (r.statusCode >= 400) _throwForStatus(r);
    final decoded = jsonDecode(r.body) as Map<String, dynamic>;
    return (reply: decoded['reply'] as String, conversationId: decoded['conversation_id'] as String);
  }

  Future<List<ServerConversation>> listConversations() async {
    final base = await _base();
    final r = await http.get(Uri.parse('$base/conversations'), headers: await _headers());
    if (r.statusCode >= 400) _throwForStatus(r);
    return (jsonDecode(r.body) as List).map((e) => ServerConversation.fromJson(e)).toList();
  }

  Future<List<ServerMessage>> getMessages(String conversationId) async {
    final base = await _base();
    final r = await http.get(Uri.parse('$base/conversations/$conversationId/messages'), headers: await _headers());
    if (r.statusCode >= 400) _throwForStatus(r);
    return (jsonDecode(r.body) as List).map((e) => ServerMessage.fromJson(e)).toList();
  }

  Future<void> deleteConversation(String id) async {
    final base = await _base();
    final r = await http.delete(Uri.parse('$base/conversations/$id'), headers: await _headers());
    if (r.statusCode >= 400) _throwForStatus(r);
  }

  Future<List<MemoryFact>> listMemoryFacts() async {
    final base = await _base();
    final r = await http.get(Uri.parse('$base/memory'), headers: await _headers());
    if (r.statusCode >= 400) _throwForStatus(r);
    return (jsonDecode(r.body) as List).map((e) => MemoryFact.fromJson(e)).toList();
  }

  Future<void> addMemoryFact({required String category, required String text}) async {
    final base = await _base();
    final r = await http.post(
      Uri.parse('$base/memory'),
      headers: await _headers(),
      body: jsonEncode({'category': category, 'text': text}),
    );
    if (r.statusCode >= 400) _throwForStatus(r);
  }

  Future<void> deleteMemoryFact(String id) async {
    final base = await _base();
    final r = await http.delete(Uri.parse('$base/memory/$id'), headers: await _headers());
    if (r.statusCode >= 400) _throwForStatus(r);
  }

  Future<List<ServerDocument>> listDocuments() async {
    final base = await _base();
    final r = await http.get(Uri.parse('$base/documents'), headers: await _headers());
    if (r.statusCode >= 400) _throwForStatus(r);
    return (jsonDecode(r.body) as List).map((e) => ServerDocument.fromJson(e)).toList();
  }

  Future<void> addDocument({required String title, required String content}) async {
    final base = await _base();
    final r = await http.post(
      Uri.parse('$base/documents'),
      headers: await _headers(),
      body: jsonEncode({'title': title, 'content': content}),
    );
    if (r.statusCode >= 400) _throwForStatus(r);
  }

  Future<void> deleteDocument(String id) async {
    final base = await _base();
    final r = await http.delete(Uri.parse('$base/documents/$id'), headers: await _headers());
    if (r.statusCode >= 400) _throwForStatus(r);
  }

  Future<List<DocumentSearchHit>> searchDocuments(String query) async {
    final base = await _base();
    final r = await http.get(
      Uri.parse('$base/documents/search').replace(queryParameters: {'q': query}),
      headers: await _headers(),
    );
    if (r.statusCode >= 400) _throwForStatus(r);
    return (jsonDecode(r.body) as List).map((e) => DocumentSearchHit.fromJson(e)).toList();
  }

  /// Quick reachability check used by the Settings screen's "Test
  /// connection" button.
  Future<bool> ping() async {
    try {
      final base = await _base();
      final r = await http.get(Uri.parse('$base/health')).timeout(const Duration(seconds: 8));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
