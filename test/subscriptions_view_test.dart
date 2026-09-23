import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mithka/auth/account_store.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/subscriptions/feed_models.dart';
import 'package:mithka/subscriptions/rss_fetcher.dart';
import 'package:mithka/subscriptions/subscription_feed_controller.dart';
import 'package:mithka/subscriptions/subscription_store.dart';
import 'package:mithka/subscriptions/subscriptions_view.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('timeline opens an item and keeps the source list local', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = SubscriptionStore(preferences: prefs);
    await store.bind(slot: 0, userId: 4);
    await store.addSubscription(
      const FeedSubscription(
        id: 'rss:https://example.com/feed',
        kind: FeedSourceKind.rss,
        title: 'Example',
        feedUrl: 'https://example.com/feed',
        addedAt: 1,
      ),
    );
    await store.saveItems(
      'rss:https://example.com/feed',
      items: const [
        FeedItem(
          id: 'rss:https://example.com/feed#1',
          subscriptionId: 'rss:https://example.com/feed',
          title: 'Hello from feed',
          sourceName: 'Example',
          excerpt: 'A short excerpt',
          publishedAt: 1_700_000_000,
          link: 'https://example.com/hello',
        ),
      ],
    );
    final controller = SubscriptionFeedController(
      store: store,
      rssFetcher: RssFetcher(client: _OfflineClient()),
      hasClient: () => false,
      query: (_) async => {'@type': 'ok'},
    );
    addTearDown(controller.dispose);
    final theme = ThemeController(prefs);
    final accounts = AccountStore(prefs);
    addTearDown(theme.dispose);
    addTearDown(accounts.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeController>.value(value: theme),
          ChangeNotifierProvider<AccountStore>.value(value: accounts),
        ],
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
          home: SubscriptionsReader(controller: controller),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Hello from feed'), findsOneWidget);
    expect(find.text('A short excerpt'), findsOneWidget);
    await tester.tap(find.text('Hello from feed'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.byKey(const ValueKey('subscriptions-open-original')),
      findsOneWidget,
    );
    expect(find.text('A short excerpt'), findsWidgets);
    expect(controller.store.isRead(controller.store.allItems().single), isTrue);
  });
}

class _OfflineClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    throw http.ClientException('offline', request.url);
  }
}
