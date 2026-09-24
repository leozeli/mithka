import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:http/http.dart' as http;
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/subscriptions/article_reader.dart';
import 'package:mithka/subscriptions/feed_models.dart';
import 'package:mithka/subscriptions/subscriptions_view.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _articlePage = '''
<!DOCTYPE html>
<html>
<head><title>Example Article</title></head>
<body>
  <nav>Navigation links here that should stay out of the article.</nav>
  <article>
    <h1>The Main Article Title</h1>
    <p>Clean paragraph from the page with enough sentences to count as an article.
    It contains important information that readers want to see in reader mode.</p>
    <p>This is another paragraph with more content. The Readability algorithm
    will extract this as the main content of the page and leave the chrome behind.</p>
  </article>
  <aside>Sidebar content</aside>
  <footer>Footer content</footer>
</body>
</html>
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('extracts the article and leaves the navigation out', () {
    final html = extractReadableHtml(
      _articlePage,
      baseUri: 'https://example.com/story',
    );
    expect(html, isNotNull);
    expect(html, contains('Clean paragraph from the page'));
    expect(html, contains('<p>'));
    expect(html!.contains('Navigation links here'), isFalse);
  });

  test('keeps heading ids and in-page toc links', () {
    final html = extractReadableHtml('''
<!DOCTYPE html>
<html>
<head><title>Guide</title></head>
<body>
<article>
  <h1>Deployment guide for the service</h1>
  <p>This guide explains how to install, configure, and operate the service
  in production. It is long enough that reader mode keeps the article.</p>
  <ul>
    <li><a href="#prepare">Prepare the host</a></li>
    <li><a href="#launch">Launch the process</a></li>
  </ul>
  <h2 id="prepare">Prepare the host</h2>
  <p>Install the runtime, open the port, and create the account that the
  process will use. These steps are part of the article body.</p>
  <h2 id="launch">Launch the process</h2>
  <p>Start the service, check the logs, and confirm the health endpoint
  returns success before sending traffic.</p>
</article>
</body>
</html>
''', baseUri: 'https://example.com/guide');
    expect(html, isNotNull);
    expect(html, contains('id="prepare"'));
    expect(html, contains('href="#prepare"'));
    expect(html, contains('id="launch"'));
    expect(html, contains('href="#launch"'));
  });

  test('returns null when the page has no article', () {
    expect(
      extractReadableHtml('<html><body><nav>Menu</nav></body></html>'),
      isNull,
    );
  });

  test('caches a successful read and does not refetch', () async {
    var fetches = 0;
    final reader = ArticleReader(
      fetchHtml: (url) async {
        fetches++;
        return _articlePage;
      },
    );
    addTearDown(reader.close);
    final url = Uri.parse('https://example.com/story');
    final first = await reader.read(itemId: 'rss:1#1', url: url);
    final second = await reader.read(itemId: 'rss:1#1', url: url);
    expect(first, contains('Clean paragraph from the page'));
    expect(second, first);
    expect(fetches, 1);
    expect(reader.cached('rss:1#1'), first);
  });

  test('an http error does not fill the cache', () async {
    final client = _StatusClient(500, 'nope', contentType: 'text/html');
    final reader = ArticleReader(client: client);
    addTearDown(reader.close);
    await expectLater(
      reader.read(itemId: 'rss:1#1', url: Uri.parse('https://example.com/a')),
      throwsA(isA<ArticleReadException>()),
    );
    expect(reader.cached('rss:1#1'), isNull);
    expect(client.sends, 1);
  });

  test('a non-html response fails', () async {
    final client = _StatusClient(
      200,
      '{"ok":true}',
      contentType: 'application/json',
    );
    final reader = ArticleReader(client: client);
    addTearDown(reader.close);
    await expectLater(
      reader.read(itemId: 'rss:1#1', url: Uri.parse('https://example.com/a')),
      throwsA(isA<ArticleReadException>()),
    );
    expect(reader.cached('rss:1#1'), isNull);
  });

  testWidgets('rss detail renders feed html and telegram stays plain', (
    tester,
  ) async {
    await _pumpItem(
      tester,
      const FeedItem(
        id: 'rss:1#1',
        subscriptionId: 'rss:1',
        title: 'org/repo',
        sourceName: 'Trending',
        summary: 'A framework',
        body:
            '<h1>Readme</h1><p>First section explains the tool.</p><ul><li>Alpha feature</li></ul>',
        link: 'https://github.com/org/repo',
        publishedAt: 0,
      ),
      reader: ArticleReader(fetchHtml: (_) async => _articlePage),
    );

    expect(find.byType(HtmlWidget), findsOneWidget);
    expect(
      find.textContaining('Alpha feature', findRichText: true),
      findsWidgets,
    );
    expect(find.text('Readme', findRichText: true), findsWidgets);
    expect(find.text('Reader mode'), findsOneWidget);
    expect(find.text('A framework'), findsNothing);

    await _pumpItem(
      tester,
      const FeedItem(
        id: 'tg:1:1',
        subscriptionId: 'tg:1',
        title: 'Preview',
        sourceName: 'News',
        summary: 'Hello',
        body: 'Channel paragraph',
        link: 'https://example.com/story',
        publishedAt: 0,
        chatId: 1,
        messageId: 1,
      ),
      reader: ArticleReader(fetchHtml: (_) async => _articlePage),
    );
    expect(find.text('Channel paragraph'), findsOneWidget);
    expect(find.byType(HtmlWidget), findsNothing);
    expect(
      find.byKey(const ValueKey('subscriptions-reader-mode')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('subscriptions-open-original')),
      findsOneWidget,
    );
  });

  testWidgets('reader mode shows extracted html and reuses the session cache', (
    tester,
  ) async {
    var fetches = 0;
    final reader = ArticleReader(
      fetchHtml: (url) async {
        fetches++;
        return _articlePage;
      },
    );
    addTearDown(reader.close);
    const item = FeedItem(
      id: 'rss:1#1',
      subscriptionId: 'rss:1',
      title: 'org/repo',
      sourceName: 'Trending',
      summary: 'A framework',
      body: '<p>Feed only sentence.</p>',
      link: 'https://github.com/org/repo',
      publishedAt: 0,
    );
    await _pumpItem(tester, item, reader: reader);
    expect(
      find.textContaining('Feed only sentence', findRichText: true),
      findsWidgets,
    );

    await tester.tap(find.byKey(const ValueKey('subscriptions-reader-mode')));
    await tester.pump();
    await tester.pump();

    expect(
      find.textContaining('Clean paragraph from the page', findRichText: true),
      findsWidgets,
    );
    expect(
      find.textContaining('Feed only sentence', findRichText: true),
      findsNothing,
    );
    expect(find.text('Show feed'), findsOneWidget);
    expect(fetches, 1);
    expect(tester.takeException(), isNull);

    await _pumpItem(tester, item, reader: reader);
    expect(
      find.textContaining('Clean paragraph from the page', findRichText: true),
      findsWidgets,
    );
    expect(
      find.textContaining('Feed only sentence', findRichText: true),
      findsNothing,
    );
    expect(fetches, 1);
  });

  testWidgets('reader mode failure keeps the feed body', (tester) async {
    final reader = ArticleReader(
      fetchHtml: (_) async => '<html><body><nav>Menu</nav></body></html>',
    );
    addTearDown(reader.close);
    await _pumpItem(
      tester,
      const FeedItem(
        id: 'rss:1#1',
        subscriptionId: 'rss:1',
        title: 'org/repo',
        sourceName: 'Trending',
        summary: 'A framework',
        body: '<p>Feed only sentence.</p>',
        link: 'https://github.com/org/repo',
        publishedAt: 0,
      ),
      reader: reader,
    );
    await tester.tap(find.byKey(const ValueKey('subscriptions-reader-mode')));
    await tester.pump();
    await tester.pump();

    expect(
      find.textContaining('Feed only sentence', findRichText: true),
      findsWidgets,
    );
    expect(
      find.textContaining('Couldn’t extract a readable article'),
      findsOneWidget,
    );
    expect(reader.cached('rss:1#1'), isNull);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpItem(
  WidgetTester tester,
  FeedItem item, {
  ArticleReader? reader,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final theme = ThemeController(prefs);
  addTearDown(theme.dispose);
  if (reader != null) addTearDown(reader.close);
  await tester.pumpWidget(
    ChangeNotifierProvider<ThemeController>.value(
      value: theme,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(
          brightness: Brightness.light,
          extensions: [AppColors.light],
        ),
        home: SubscriptionItemPage(item: item, reader: reader),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

class _StatusClient extends http.BaseClient {
  _StatusClient(this.status, this.body, {required this.contentType});

  final int status;
  final String body;
  final String contentType;
  int sends = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sends++;
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(body)),
      status,
      headers: {'content-type': contentType},
    );
  }
}
