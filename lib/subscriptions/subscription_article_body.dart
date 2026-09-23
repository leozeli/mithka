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

class SubscriptionArticleBody extends StatelessWidget {
  const SubscriptionArticleBody({
    super.key,
    required this.text,
    required this.html,
    required this.onOpenLink,
  });

  final String text;
  final bool html;
  final Future<void> Function(String url) onOpenLink;

  @override
  Widget build(BuildContext context) {
    final style = AppTextStyle.body(
      context.colors.textPrimary,
    ).copyWith(height: 1.45);
    if (!html) {
      return SelectableText(text, style: style);
    }
    final link = _cssHex(context.colors.linkBlue);
    return HtmlWidget(
      text,
      key: const ValueKey('subscriptions-article-html'),
      textStyle: style,
      onTapUrl: (url) {
        final uri = Uri.tryParse(url);
        if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
          unawaited(onOpenLink(url));
        }
        return true;
      },
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
}

String _cssHex(Color color) {
  final rgb = color.toARGB32() & 0xFFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0')}';
}
