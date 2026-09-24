//
//  subscription_article_body.dart
//
//  Draws an RSS article as widgets when the source is HTML, and as selectable
//  text when it is a Telegram post or a plain feed blurb.
//

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import '../theme/app_theme.dart';

class SubscriptionArticleBody extends StatefulWidget {
  const SubscriptionArticleBody({
    super.key,
    required this.text,
    required this.html,
    required this.onOpenLink,
    this.pageUrl,
  });

  final String text;
  final bool html;
  final Future<void> Function(String url) onOpenLink;

  /// Article URL. Same-page links that only add a `#fragment` scroll here.
  final String? pageUrl;

  @override
  State<SubscriptionArticleBody> createState() =>
      _SubscriptionArticleBodyState();
}

class _SubscriptionArticleBodyState extends State<SubscriptionArticleBody> {
  final _htmlKey = GlobalKey<HtmlWidgetState>();

  @override
  Widget build(BuildContext context) {
    final style = AppTextStyle.body(
      context.colors.textPrimary,
    ).copyWith(height: 1.45);
    if (!widget.html) {
      return SelectableText(widget.text, style: style);
    }
    final link = _cssHex(context.colors.linkBlue);
    final page = _httpPage(widget.pageUrl);
    return HtmlWidget(
      widget.text,
      key: _htmlKey,
      textStyle: style,
      onTapUrl: (url) => _onTapUrl(url, page),
      customStylesBuilder: (element) {
        if (element.localName != 'a') return null;
        return {'color': link};
      },
      customWidgetBuilder: (element) {
        switch (element.localName) {
          case 'img':
          case 'picture':
          case 'video':
          case 'audio':
          case 'iframe':
          case 'svg':
          case 'source':
            return const SizedBox.shrink();
          default:
            return null;
        }
      },
    );
  }

  /// Fragment-only links scroll. Returning true would skip that and swallow
  /// the tap. A same-page `https://…#id` (reader mode sometimes rewrites `#id`
  /// this way) scrolls through the same anchor table. Other http(s) links open
  /// outside the article.
  bool _onTapUrl(String url, Uri? page) {
    if (url.startsWith('#')) return false;
    final fragment = _samePageFragment(url, page);
    if (fragment != null) {
      final state = _htmlKey.currentState;
      if (state != null) {
        unawaited(state.scrollToAnchor(fragment));
      }
      return true;
    }
    final uri = Uri.tryParse(url);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      unawaited(widget.onOpenLink(url));
    }
    return true;
  }
}

String _cssHex(Color color) {
  final rgb = color.toARGB32() & 0xFFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0')}';
}

Uri? _httpPage(String? pageUrl) {
  final raw = pageUrl?.trim();
  if (raw == null || raw.isEmpty) return null;
  final uri = Uri.tryParse(raw);
  if (uri == null || uri.host.isEmpty) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  return uri;
}

/// Fragment of [url] when it points at [page] and only adds a hash.
String? _samePageFragment(String url, Uri? page) {
  if (page == null) return null;
  final uri = Uri.tryParse(url);
  if (uri == null || uri.fragment.isEmpty) return null;
  if (!_sameDocument(uri, page)) return null;
  return uri.fragment;
}

bool _sameDocument(Uri link, Uri page) {
  if (link.scheme != page.scheme) return false;
  if (link.host != page.host) return false;
  if (_port(link) != _port(page)) return false;
  if (_path(link) != _path(page)) return false;
  return link.query == page.query;
}

int _port(Uri uri) {
  if (uri.hasPort) return uri.port;
  return uri.scheme == 'https' ? 443 : 80;
}

String _path(Uri uri) => uri.path.isEmpty ? '/' : uri.path;
