//
//  rss_fetcher.dart
//
//  Loads an RSS or Atom document from an http(s) URL on the device.
//

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'feed_models.dart';
import 'rss_parser.dart';

class RssFetchException implements Exception {
  const RssFetchException(this.failure);
  final SubscriptionFailure failure;
}

class RssFetcher {
  RssFetcher({http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null;

  static const maxBytes = 2 * 1024 * 1024;

  final http.Client _client;
  final bool _ownsClient;

  void close() {
    if (_ownsClient) _client.close();
  }

  Future<ParsedFeed> fetch(Uri url) async {
    if (url.scheme != 'http' && url.scheme != 'https') {
      throw const RssFetchException(SubscriptionFailure.invalidUrl);
    }
    try {
      final request = http.Request('GET', url);
      request.headers.addAll(const {
        'accept':
            'application/rss+xml, application/atom+xml, application/xml, text/xml, */*',
        'user-agent': 'Mithka RSS',
      });
      final streamed = await _client
          .send(request)
          .timeout(const Duration(seconds: 20));
      if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
        throw const RssFetchException(SubscriptionFailure.network);
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in streamed.stream.timeout(
        const Duration(seconds: 20),
      )) {
        if (bytes.length + chunk.length > maxBytes) {
          throw const RssFetchException(SubscriptionFailure.notFeed);
        }
        bytes.add(chunk);
      }
      final body = utf8.decode(bytes.takeBytes(), allowMalformed: true).trim();
      if (body.isEmpty) {
        throw const RssFetchException(SubscriptionFailure.notFeed);
      }
      return parseRssOrAtom(body);
    } on RssFetchException {
      rethrow;
    } on FeedParseException {
      throw const RssFetchException(SubscriptionFailure.notFeed);
    } on TimeoutException {
      throw const RssFetchException(SubscriptionFailure.network);
    } catch (_) {
      throw const RssFetchException(SubscriptionFailure.network);
    }
  }
}
