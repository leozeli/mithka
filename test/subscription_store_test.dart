import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/subscriptions/feed_models.dart';
import 'package:mithka/subscriptions/subscription_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  FeedSubscription sample(String id) => FeedSubscription(
    id: id,
    kind: FeedSourceKind.rss,
    title: 'Example',
    feedUrl: 'https://example.com/feed',
    addedAt: 10,
  );

  FeedItem item(String id, int publishedAt) => FeedItem(
    id: id,
    subscriptionId: 'rss:https://example.com/feed',
    title: 'Post $publishedAt',
    sourceName: 'Example',
    excerpt: 'Body',
    publishedAt: publishedAt,
    link: 'https://example.com/$publishedAt',
  );

  test('round-trips subscriptions, items, and negative chat ids', () async {
    final store = SubscriptionStore(preferences: prefs);
    await store.bind(slot: 0, userId: 42);
    expect(
      await store.addSubscription(
        const FeedSubscription(
          id: 'tg:-100123',
          kind: FeedSourceKind.telegram,
          title: 'News',
          chatId: -100123,
          addedAt: 5,
        ),
      ),
      isTrue,
    );
    await store.saveItems(
      'tg:-100123',
      items: [
        const FeedItem(
          id: 'tg:-100123:99',
          subscriptionId: 'tg:-100123',
          title: 'Hello',
          sourceName: 'News',
          excerpt: 'There',
          publishedAt: 50,
          chatId: -100123,
          messageId: 99,
        ),
      ],
      fetchedAt: 60,
    );

    final again = SubscriptionStore(preferences: prefs);
    await again.bind(slot: 0, userId: 42);
    expect(again.subscriptions.single.chatId, -100123);
    expect(again.subscriptions.single.fetchedAt, 60);
    final loaded = again.itemsFor('tg:-100123').single;
    expect(loaded.messageId, 99);
    expect(loaded.chatId, -100123);
    expect(loaded.excerpt, 'There');
  });

  test('keeps each Telegram user on their own list', () async {
    final store = SubscriptionStore(preferences: prefs);
    await store.bind(slot: 0, userId: 1);
    await store.addSubscription(sample('rss:https://example.com/feed'));
    await store.bind(slot: 0, userId: 2);
    expect(store.subscriptions, isEmpty);
    await store.bind(slot: 0, userId: 1);
    expect(store.subscriptions, hasLength(1));
  });

  test('read cursors cover older items and leave newer ones unread', () async {
    final store = SubscriptionStore(preferences: prefs);
    await store.bind(slot: 1, userId: 7);
    await store.addSubscription(sample('rss:https://example.com/feed'));
    await store.saveItems(
      'rss:https://example.com/feed',
      items: [item('a', 100), item('b', 300)],
    );
    await store.markAllRead(store.allItems());
    expect(store.isRead(item('a', 100)), isTrue);
    expect(store.isRead(item('b', 300)), isTrue);

    await store.saveItems(
      'rss:https://example.com/feed',
      items: [item('a', 100), item('b', 300), item('c', 400)],
    );
    expect(store.isRead(item('a', 100)), isTrue);
    expect(store.isRead(item('c', 400)), isFalse);

    await store.markRead(item('c', 400));
    expect(store.isRead(item('c', 400)), isTrue);

    final again = SubscriptionStore(preferences: prefs);
    await again.bind(slot: 1, userId: 7);
    expect(again.isRead(item('c', 400)), isTrue);
    expect(again.unreadCount(null), 0);
  });

  test('unsubscribe drops cached items', () async {
    final store = SubscriptionStore(preferences: prefs);
    await store.bind(slot: 0, userId: 3);
    await store.addSubscription(sample('rss:https://example.com/feed'));
    await store.saveItems(
      'rss:https://example.com/feed',
      items: [item('a', 100)],
    );
    await store.remove('rss:https://example.com/feed');
    expect(store.subscriptions, isEmpty);
    expect(store.allItems(), isEmpty);
  });

  test('corrupt storage opens as an empty list', () async {
    await prefs.setString(SubscriptionStore.storageKeyForUser(9), '{');
    final store = SubscriptionStore(preferences: prefs);
    await store.bind(slot: 0, userId: 9);
    expect(store.subscriptions, isEmpty);
  });

  test('groups sources locally and prunes removed ones', () async {
    final store = SubscriptionStore(preferences: prefs);
    await store.bind(slot: 0, userId: 8);
    await store.addSubscription(sample('rss:https://example.com/feed'));
    await store.addSubscription(sample('rss:https://example.com/other'));
    final groupId = await store.createGroup('  News  ');
    expect(groupId, isNotNull);
    await store.moveSourceToGroup('rss:https://example.com/feed', groupId);
    await store.moveSourceToGroup('rss:https://example.com/other', groupId);
    await store.moveSourceToGroup('rss:https://example.com/feed', groupId);

    final outline = store.outline();
    expect(outline.first.group?.title, 'News');
    expect(outline.first.group?.expanded, isTrue);
    expect(outline.where((row) => row.nested).map((row) => row.source!.id), [
      'rss:https://example.com/other',
      'rss:https://example.com/feed',
    ]);
    expect(store.groupOf('rss:https://example.com/feed'), groupId);

    final second = await store.createGroup('Later');
    await store.moveSourceToGroup('rss:https://example.com/feed', second);
    expect(store.groupOf('rss:https://example.com/feed'), second);
    expect(
      store.groups.first.sourceIds,
      isNot(contains('rss:https://example.com/feed')),
    );

    await store.setGroupExpanded(groupId!, false);
    expect(store.groups.first.expanded, isFalse);
    expect(
      store.outline().where((row) => row.nested).map((row) => row.source!.id),
      ['rss:https://example.com/feed'],
    );

    await store.remove('rss:https://example.com/other');
    expect(store.groups.first.sourceIds, isEmpty);

    final again = SubscriptionStore(preferences: prefs);
    await again.bind(slot: 0, userId: 8);
    expect(again.groups, hasLength(2));
    expect(again.groups.first.title, 'News');
    expect(again.groups.first.expanded, isFalse);
    expect(again.groups.first.sourceIds, isEmpty);
    expect(again.groupOf('rss:https://example.com/feed'), second);

    await again.deleteGroup(groupId);
    expect(again.groups, hasLength(1));
    expect(again.groupOf('rss:https://example.com/feed'), second);
    await again.moveSourceToGroup('rss:https://example.com/feed', null);
    expect(again.groupOf('rss:https://example.com/feed'), isNull);
    expect(
      again.outline().where((row) => row.source != null).single.source?.id,
      'rss:https://example.com/feed',
    );
    expect(again.outline().where((row) => row.nested), isEmpty);
  });

  test('drops orphaned group members when storage is reopened', () async {
    await prefs.setString(
      SubscriptionStore.storageKeyForUser(11),
      '{"v":1,"subscriptions":[{"id":"rss:https://example.com/feed","kind":"rss","title":"Example","addedAt":1,"feedUrl":"https://example.com/feed"}],"groups":[{"id":"grp:1","title":"News","expanded":true,"sourceIds":["rss:https://example.com/feed","rss:missing","rss:https://example.com/feed"]}]}',
    );
    final store = SubscriptionStore(preferences: prefs);
    await store.bind(slot: 0, userId: 11);
    expect(store.groups.single.sourceIds, ['rss:https://example.com/feed']);

    final again = SubscriptionStore(preferences: prefs);
    await again.bind(slot: 0, userId: 11);
    expect(again.groups.single.sourceIds, ['rss:https://example.com/feed']);
  });

  test('refuses a duplicate subscription', () async {
    final store = SubscriptionStore(preferences: prefs, persist: false);
    await store.bind(slot: 0, userId: 1);
    expect(
      await store.addSubscription(sample('rss:https://example.com/feed')),
      isTrue,
    );
    expect(
      await store.addSubscription(sample('rss:https://example.com/feed')),
      isFalse,
    );
    expect(store.subscriptions, hasLength(1));
  });
}
