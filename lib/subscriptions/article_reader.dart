//
//  article_reader.dart
//
//  Fetches an RSS item's original page and extracts the article with
//  reader_mode (Mozilla Readability). No WebView: Linux desktop can run this.
//

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:reader_mode/reader_mode.dart' as readability;

class ArticleReadException implements Exception {
  const ArticleReadException();
}

/// Session cache of reader-mode HTML, keyed by feed item id.
class ArticleReader {
  ArticleReader({
    http.Client? client,
    Map<String, String>? cache,
    Future<String> Function(Uri url)? fetchHtml,
  }) : _cache = cache ?? <String, String>{},
       _fetchHtml = fetchHtml,
       _client = client ?? (fetchHtml == null ? http.Client() : null),
       _ownsClient = client == null && fetchHtml == null;

  static const maxBytes = 2 * 1024 * 1024;

  final Map<String, String> _cache;
  final Future<String> Function(Uri url)? _fetchHtml;
  final http.Client? _client;
  final bool _ownsClient;

  String? cached(String itemId) {
    final value = _cache[itemId];
    if (value == null || value.trim().isEmpty) return null;
    return value;
  }

  /// Returns cleaned article HTML. A cached hit skips the network.
  Future<String> read({required String itemId, required Uri url}) async {
    final existing = cached(itemId);
    if (existing != null) return existing;
    if (url.scheme != 'http' && url.scheme != 'https') {
      throw const ArticleReadException();
    }
    final String page;
    try {
      page = _fetchHtml != null ? await _fetchHtml(url) : await _download(url);
    } on ArticleReadException {
      rethrow;
    } catch (_) {
      throw const ArticleReadException();
    }
    final article = extractReadableHtml(page, baseUri: url.toString());
    if (article == null) throw const ArticleReadException();
    _cache[itemId] = article;
    return article;
  }

  void close() {
    if (_ownsClient) _client?.close();
  }

  Future<String> _download(Uri url) async {
    final client = _client;
    if (client == null) throw const ArticleReadException();
    final request = http.Request('GET', url);
    request.headers.addAll(const {
      'accept': 'text/html, application/xhtml+xml, */*',
      'user-agent': 'Mithka RSS',
    });
    final streamed = await client
        .send(request)
        .timeout(const Duration(seconds: 20));
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      throw const ArticleReadException();
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in streamed.stream.timeout(
      const Duration(seconds: 20),
    )) {
      if (bytes.length + chunk.length > maxBytes) {
        throw const ArticleReadException();
      }
      bytes.add(chunk);
    }
    final body = utf8.decode(bytes.takeBytes(), allowMalformed: true).trim();
    if (body.isEmpty || !_looksLikeHtml(streamed, body)) {
      throw const ArticleReadException();
    }
    return body;
  }
}

bool _looksLikeHtml(http.StreamedResponse response, String body) {
  final type = response.headers['content-type']?.toLowerCase() ?? '';
  if (type.contains('text/html') ||
      type.contains('application/xhtml') ||
      type.contains('text/xml') ||
      type.contains('application/xml')) {
    return true;
  }
  if (type.contains('json') ||
      type.contains('image/') ||
      type.contains('pdf') ||
      type.contains('octet-stream')) {
    return false;
  }
  final head = body.trimLeft().toLowerCase();
  return head.startsWith('<!doctype html') ||
      head.startsWith('<html') ||
      head.contains('<body') ||
      head.contains('<article') ||
      head.contains('<p');
}

/// Readability extract. Null when the page has no article.
String? extractReadableHtml(String html, {String? baseUri}) {
  final trimmed = html.trim();
  if (trimmed.isEmpty) return null;
  final article = readability.parse(trimmed, baseUri: baseUri);
  final content = article?.content.trim() ?? '';
  final text = article?.textContent.trim() ?? '';
  // Readability sometimes wraps leftover chrome. Require a real paragraph.
  if (content.isEmpty || text.length < 120) return null;
  return content;
}
