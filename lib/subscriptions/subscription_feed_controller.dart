//
//  subscription_feed_controller.dart
//
//  Owns the on-device subscription list for the signed-in Telegram user and
//  refreshes Telegram channels plus RSS/Atom URLs into one timeline.
//
//  Story folding / tracker matching (td-py-kit) can group items here later.
//  This pass keeps every fetched post as its own row.
//

import 'package:flutter/foundation.dart';

import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import 'feed_models.dart';
import 'rss_fetcher.dart';
import 'rss_parser.dart';
import 'subscription_store.dart';
import 'telegram_feed_source.dart';

class SubscriptionFeedController extends ChangeNotifier {
  SubscriptionFeedController({
    SubscriptionStore? store,
    RssFetcher? rssFetcher,
    TdQuery? query,
    bool Function()? hasClient,
  }) : _store = store ?? SubscriptionStore(),
       _rss = rssFetcher ?? RssFetcher(),
       _ownsFetcher = rssFetcher == null,
       _query = query ?? TdClient.shared.query,
       _hasClient = hasClient ?? (() => TdClient.shared.hasActiveClient);

  final SubscriptionStore _store;
  final RssFetcher _rss;
  final bool _ownsFetcher;
  final TdQuery _query;
  final bool Function() _hasClient;

  String? _selectedId;
  bool _loading = false;
  bool _ready = false;
  int _boundSlot = 0;
  int? _boundUserId;
  int _bindSerial = 0;
  int _refreshGeneration = 0;
  bool _disposed = false;

  SubscriptionStore get store => _store;
  String? get selectedId => _selectedId;
  bool get loading => _loading;
  bool get isReady => _ready;

  List<FeedSubscription> get subscriptions => _store.subscriptions;

  List<SubscriptionGroup> get groups => _store.groups;

  List<SubscriptionOutlineRow> get outline => _store.outline();

  String? groupOf(String sourceId) => _store.groupOf(sourceId);

  FeedSubscription? get selected {
    final id = _selectedId;
    if (id == null) return null;
    for (final subscription in _store.subscriptions) {
      if (subscription.id == id) return subscription;
    }
    return null;
  }

  List<FeedItem> get visibleItems {
    final id = selected?.id;
    final items = id == null ? _store.allItems() : _store.itemsFor(id);
    return items;
  }

  bool isRead(FeedItem item) => _store.isRead(item);

  int unreadCount(String? subscriptionId) => _store.unreadCount(subscriptionId);

  void select(String? id) {
    if (_selectedId == id) return;
    _selectedId = id;
    _notify();
  }

  Future<void> ensureBound({required int slot, int? userId}) async {
    final token = ++_bindSerial;
    var resolved = userId;
    if ((resolved == null || resolved <= 0) && _store.userId != null) {
      resolved = _store.userId;
    }
    if ((resolved == null || resolved <= 0) && _hasClient()) {
      try {
        final me = await _query({'@type': 'getMe'});
        resolved = me.int64('id');
      } catch (_) {}
    }
    if (token != _bindSerial || _disposed) return;
    if (_ready && _boundSlot == slot && _boundUserId == resolved) return;
    await _store.bind(slot: slot, userId: resolved);
    if (token != _bindSerial || _disposed) return;
    _boundSlot = slot;
    _boundUserId = resolved;
    _ready = true;
    if (_selectedId != null &&
        !_store.subscriptions.any((item) => item.id == _selectedId)) {
      _selectedId = null;
    }
    _notify();
    await refresh();
  }

  Future<SubscriptionFailure?> refresh({bool manual = false}) async {
    final generation = ++_refreshGeneration;
    _loading = true;
    _notify();
    SubscriptionFailure? failure;
    final subscriptions = List<FeedSubscription>.of(_store.subscriptions);
    for (final subscription in subscriptions) {
      if (generation != _refreshGeneration || _disposed) return failure;
      final error = await _refreshOne(subscription);
      if (manual) failure ??= error;
    }
    if (generation != _refreshGeneration || _disposed) return failure;
    _loading = false;
    _notify();
    return failure;
  }

  Future<SubscriptionFailure?> addRss(String raw) async {
    final canonical = canonicalFeedUrl(raw);
    if (canonical == null) return SubscriptionFailure.invalidUrl;
    final id = rssSubscriptionId(canonical);
    if (_store.subscriptions.any((item) => item.id == id)) {
      return SubscriptionFailure.alreadyAdded;
    }
    if (_store.subscriptions.length >= SubscriptionStore.softCap) {
      return SubscriptionFailure.full;
    }
    final ParsedFeed feed;
    try {
      feed = await _rss.fetch(Uri.parse(canonical));
    } on RssFetchException catch (error) {
      return error.failure;
    }
    if (_disposed) return null;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final title = feed.title.trim().isEmpty
        ? Uri.parse(canonical).host
        : feed.title.trim();
    final added = await _store.addSubscription(
      FeedSubscription(
        id: id,
        kind: FeedSourceKind.rss,
        title: title,
        feedUrl: canonical,
        addedAt: now,
        fetchedAt: now,
      ),
    );
    if (!added) {
      return _store.subscriptions.any((item) => item.id == id)
          ? SubscriptionFailure.alreadyAdded
          : SubscriptionFailure.full;
    }
    await _store.saveItems(
      id,
      items: [
        for (final entry in feed.entries)
          _rssFeedItem(subscriptionId: id, sourceName: title, entry: entry),
      ],
      clearError: true,
      fetchedAt: now,
    );
    _selectedId = id;
    _notify();
    return null;
  }

  Future<SubscriptionFailure?> addTelegram(ChatSummary chat) async {
    if (!isSubscribableChannel(chat)) return SubscriptionFailure.telegram;
    final id = telegramSubscriptionId(chat.id);
    if (_store.subscriptions.any((item) => item.id == id)) {
      return SubscriptionFailure.alreadyAdded;
    }
    if (_store.subscriptions.length >= SubscriptionStore.softCap) {
      return SubscriptionFailure.full;
    }
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final added = await _store.addSubscription(
      FeedSubscription(
        id: id,
        kind: FeedSourceKind.telegram,
        title: chat.title,
        chatId: chat.id,
        addedAt: now,
      ),
    );
    if (!added) {
      return _store.subscriptions.any((item) => item.id == id)
          ? SubscriptionFailure.alreadyAdded
          : SubscriptionFailure.full;
    }
    _selectedId = id;
    _notify();
    final failure = await _refreshOne(
      _store.subscriptions.firstWhere((item) => item.id == id),
    );
    _notify();
    return failure;
  }

  Future<void> unsubscribe(String id) async {
    await _store.remove(id);
    if (_selectedId == id) _selectedId = null;
    _notify();
  }

  Future<bool> createGroup(String title) async {
    final id = await _store.createGroup(title);
    _notify();
    return id != null;
  }

  Future<void> renameGroup(String id, String title) async {
    await _store.renameGroup(id, title);
    _notify();
  }

  Future<void> deleteGroup(String id) async {
    await _store.deleteGroup(id);
    _notify();
  }

  Future<void> setGroupExpanded(String id, bool expanded) async {
    await _store.setGroupExpanded(id, expanded);
    _notify();
  }

  Future<void> moveSourceToGroup(String sourceId, String? groupId) async {
    await _store.moveSourceToGroup(sourceId, groupId);
    _notify();
  }

  Future<void> markRead(FeedItem item) async {
    if (_store.isRead(item)) return;
    await _store.markRead(item);
    _notify();
  }

  Future<void> markVisibleRead() async {
    await _store.markAllRead(visibleItems);
    _notify();
  }

  Future<SubscriptionFailure?> _refreshOne(
    FeedSubscription subscription,
  ) async {
    try {
      switch (subscription.kind) {
        case FeedSourceKind.rss:
          final url = subscription.feedUrl;
          if (url == null || url.isEmpty) {
            return SubscriptionFailure.invalidUrl;
          }
          final feed = await _rss.fetch(Uri.parse(url));
          final title = feed.title.trim().isEmpty
              ? subscription.title
              : feed.title.trim();
          final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
          await _store.saveItems(
            subscription.id,
            title: title,
            fetchedAt: now,
            clearError: true,
            items: [
              for (final entry in feed.entries)
                _rssFeedItem(
                  subscriptionId: subscription.id,
                  sourceName: title,
                  entry: entry,
                ),
            ],
          );
        case FeedSourceKind.telegram:
          if (!_hasClient()) return SubscriptionFailure.telegram;
          final items = await loadTelegramFeedItems(
            query: _query,
            subscription: subscription,
          );
          final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
          await _store.saveItems(
            subscription.id,
            items: items,
            fetchedAt: now,
            clearError: true,
          );
      }
      _notify();
      return null;
    } on RssFetchException catch (error) {
      await _store.saveItems(subscription.id, error: error.failure.name);
      _notify();
      return error.failure;
    } catch (_) {
      final failure = subscription.kind == FeedSourceKind.rss
          ? SubscriptionFailure.network
          : SubscriptionFailure.telegram;
      await _store.saveItems(subscription.id, error: failure.name);
      _notify();
      return failure;
    }
  }

  FeedItem _rssFeedItem({
    required String subscriptionId,
    required String sourceName,
    required ParsedFeedEntry entry,
  }) {
    return FeedItem(
      id: '$subscriptionId#${entry.id}',
      subscriptionId: subscriptionId,
      title: entry.title,
      sourceName: sourceName,
      summary: entry.summary,
      body: entry.body,
      publishedAt: entry.publishedAt,
      link: entry.link,
    );
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    if (_ownsFetcher) _rss.close();
    super.dispose();
  }
}
