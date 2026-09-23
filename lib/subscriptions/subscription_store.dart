//
//  subscription_store.dart
//
//  Per-Telegram-user subscription list, cached items, and read cursors.
//  The same shape as local chat pins: this device only, keyed by user id.
//

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'feed_models.dart';

class SubscriptionStore {
  SubscriptionStore({this.preferences, this.persist = true});

  /// Enough room for a personal reading list without an unbounded document.
  static const softCap = 100;
  static const maxItemsPerSubscription = 40;
  static const maxReadIds = 4000;
  static const maxGroups = 40;
  static const maxGroupTitle = 80;

  final SharedPreferences? preferences;
  final bool persist;

  final List<FeedSubscription> _subscriptions = [];
  final List<SubscriptionGroup> _groups = [];
  final Map<String, List<FeedItem>> _items = {};
  final Map<String, int> _cursors = {};
  final List<String> _readIds = [];
  int _groupSerial = 0;

  int _slot = 0;
  int? _userId;
  bool _dirty = false;
  bool _loaded = false;
  Future<void> _queue = Future<void>.value();

  int? get userId => _userId;
  int get slot => _slot;
  bool get isLoaded => _loaded;

  List<FeedSubscription> get subscriptions =>
      List<FeedSubscription>.unmodifiable(_subscriptions);

  List<SubscriptionGroup> get groups =>
      List<SubscriptionGroup>.unmodifiable(_groups);

  List<SubscriptionOutlineRow> outline() =>
      subscriptionOutline(subscriptions: _subscriptions, groups: _groups);

  String? groupOf(String sourceId) {
    for (final group in _groups) {
      if (group.sourceIds.contains(sourceId)) return group.id;
    }
    return null;
  }

  static String storageKeyForUser(int userId) =>
      'mithka.subscriptions.user.$userId';

  List<FeedItem> itemsFor(String subscriptionId) {
    final items = List<FeedItem>.of(
      _items[subscriptionId] ?? const <FeedItem>[],
    );
    items.sort(compareFeedItems);
    return items;
  }

  List<FeedItem> allItems() {
    final items = _items.values.expand((list) => list).toList();
    items.sort(compareFeedItems);
    return items;
  }

  bool isRead(FeedItem item) {
    if (_readIds.contains(item.id)) return true;
    final cursor = _cursors[item.subscriptionId];
    if (cursor == null) return false;
    return item.publishedAt > 0 && item.publishedAt <= cursor;
  }

  int unreadCount(String? subscriptionId) {
    final items = subscriptionId == null
        ? allItems()
        : itemsFor(subscriptionId);
    var count = 0;
    for (final item in items) {
      if (!isRead(item)) count++;
    }
    return count;
  }

  Future<void> bind({required int slot, int? userId}) {
    return _serialized(() async {
      if (userId == null || userId <= 0) {
        if (_loaded && _userId != null) return;
        if (slot != _slot && _userId == null) _clear();
        _slot = slot;
        _loaded = true;
        return;
      }
      if (_loaded && _userId == userId && _slot == slot && !_dirty) return;
      final keepMemory = _dirty && _userId == null;
      _slot = slot;
      _userId = userId;
      _loaded = true;
      if (!persist) {
        _dirty = false;
        return;
      }
      try {
        final prefs = await _prefs();
        if (keepMemory) {
          _dirty = false;
          await _write(prefs, userId);
        } else {
          final pruned = _read(prefs, userId);
          _dirty = false;
          if (pruned) await _write(prefs, userId);
        }
      } catch (_) {
        _dirty = keepMemory;
      }
    });
  }

  Future<bool> addSubscription(FeedSubscription subscription) {
    return _serialized(() async {
      if (_subscriptions.any((item) => item.id == subscription.id)) {
        return false;
      }
      if (_subscriptions.length >= softCap) return false;
      _subscriptions.insert(0, subscription);
      await _persist();
      return true;
    });
  }

  Future<void> updateSubscription(FeedSubscription subscription) {
    return _serialized(() async {
      final index = _subscriptions.indexWhere(
        (item) => item.id == subscription.id,
      );
      if (index < 0) return;
      _subscriptions[index] = subscription;
      await _persist();
    });
  }

  Future<void> remove(String id) {
    return _serialized(() async {
      final removed = _items.remove(id);
      _subscriptions.removeWhere((item) => item.id == id);
      _cursors.remove(id);
      _stripSourceFromGroups(id);
      if (removed != null) {
        final ids = removed.map((item) => item.id).toSet();
        _readIds.removeWhere(ids.contains);
      }
      await _persist();
    });
  }

  /// Replaces the cached items when [items] is non-null. A failed refresh can
  /// record [error] without dropping the last successful fetch.
  Future<void> saveItems(
    String id, {
    List<FeedItem>? items,
    String? title,
    int? fetchedAt,
    String? error,
    bool clearError = false,
  }) {
    return _serialized(() async {
      final index = _subscriptions.indexWhere((item) => item.id == id);
      if (index < 0) return;
      if (items != null) {
        final capped = items.take(maxItemsPerSubscription).toList();
        _items[id] = capped;
      }
      _subscriptions[index] = _subscriptions[index].copyWith(
        title: title,
        fetchedAt: fetchedAt,
        lastError: error,
        clearError: clearError,
      );
      await _persist();
    });
  }

  Future<void> markRead(FeedItem item) {
    return _serialized(() async {
      if (_readIds.contains(item.id)) return;
      _readIds.add(item.id);
      if (_readIds.length > maxReadIds) {
        _readIds.removeRange(0, _readIds.length - maxReadIds);
      }
      await _persist();
    });
  }

  Future<void> markAllRead(Iterable<FeedItem> items) {
    return _serialized(() async {
      final cursors = <String, int>{};
      for (final item in items) {
        if (item.publishedAt > 0) {
          final current = cursors[item.subscriptionId] ?? 0;
          if (item.publishedAt > current) {
            cursors[item.subscriptionId] = item.publishedAt;
          }
          _readIds.remove(item.id);
        } else if (!_readIds.contains(item.id)) {
          _readIds.add(item.id);
        }
      }
      for (final entry in cursors.entries) {
        final existing = _cursors[entry.key] ?? 0;
        if (entry.value > existing) _cursors[entry.key] = entry.value;
      }
      if (_readIds.length > maxReadIds) {
        _readIds.removeRange(0, _readIds.length - maxReadIds);
      }
      await _persist();
    });
  }

  Future<String?> createGroup(String rawTitle) {
    return _serialized(() async {
      final title = _groupTitle(rawTitle);
      if (title == null || _groups.length >= maxGroups) return null;
      final id =
          'grp:${++_groupSerial}:${DateTime.now().microsecondsSinceEpoch}';
      _groups.add(SubscriptionGroup(id: id, title: title, sourceIds: const []));
      await _persist();
      return id;
    });
  }

  Future<bool> renameGroup(String id, String rawTitle) {
    return _serialized(() async {
      final title = _groupTitle(rawTitle);
      final index = _groups.indexWhere((group) => group.id == id);
      if (title == null || index < 0) return false;
      _groups[index] = _groups[index].copyWith(title: title);
      await _persist();
      return true;
    });
  }

  Future<void> deleteGroup(String id) {
    return _serialized(() async {
      final before = _groups.length;
      _groups.removeWhere((group) => group.id == id);
      if (_groups.length == before) return;
      await _persist();
    });
  }

  Future<void> setGroupExpanded(String id, bool expanded) {
    return _serialized(() async {
      final index = _groups.indexWhere((group) => group.id == id);
      if (index < 0 || _groups[index].expanded == expanded) return;
      _groups[index] = _groups[index].copyWith(expanded: expanded);
      await _persist();
    });
  }

  /// [groupId] null leaves the source ungrouped. A source belongs to one group.
  Future<void> moveSourceToGroup(String sourceId, String? groupId) {
    return _serialized(() async {
      if (!_subscriptions.any((item) => item.id == sourceId)) return;
      var changed = false;
      for (var index = 0; index < _groups.length; index++) {
        final group = _groups[index];
        final ids = [
          for (final id in group.sourceIds)
            if (id != sourceId) id,
          if (group.id == groupId) sourceId,
        ];
        if (_sameIds(ids, group.sourceIds)) continue;
        _groups[index] = group.copyWith(sourceIds: ids);
        changed = true;
      }
      if (changed) await _persist();
    });
  }

  Future<T> _serialized<T>(Future<T> Function() action) {
    final run = _queue.then((_) => action());
    _queue = run.then((_) {}, onError: (_) {});
    return run;
  }

  Future<void> _persist() async {
    if (!persist) return;
    final userId = _userId;
    if (userId == null) {
      _dirty = true;
      return;
    }
    _dirty = false;
    try {
      final prefs = await _prefs();
      await _write(prefs, userId);
    } catch (_) {
      _dirty = true;
    }
  }

  Future<SharedPreferences> _prefs() async =>
      preferences ?? await SharedPreferences.getInstance();

  bool _read(SharedPreferences prefs, int userId) {
    _clearLists();
    final raw = prefs.getString(storageKeyForUser(userId));
    if (raw == null || raw.isEmpty) return false;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return false;
      final map = Map<String, dynamic>.from(decoded);
      final subscriptions = map['subscriptions'];
      if (subscriptions is List) {
        for (final entry in subscriptions) {
          if (entry is! Map) continue;
          final subscription = FeedSubscription.fromJson(
            Map<String, dynamic>.from(entry),
          );
          if (subscription == null ||
              _subscriptions.any((item) => item.id == subscription.id)) {
            continue;
          }
          _subscriptions.add(subscription);
          if (_subscriptions.length >= softCap) break;
        }
      }
      final items = map['items'];
      if (items is Map) {
        for (final entry in items.entries) {
          final id = entry.key;
          if (id is! String || entry.value is! List) continue;
          final parsed = <FeedItem>[];
          for (final rawItem in entry.value as List) {
            if (rawItem is! Map) continue;
            final item = FeedItem.fromJson(Map<String, dynamic>.from(rawItem));
            if (item == null || item.subscriptionId != id) continue;
            parsed.add(item);
            if (parsed.length >= maxItemsPerSubscription) break;
          }
          if (parsed.isNotEmpty) _items[id] = parsed;
        }
      }
      final cursors = map['cursors'];
      if (cursors is Map) {
        for (final entry in cursors.entries) {
          final id = entry.key;
          final value = entry.value;
          if (id is! String) continue;
          final cursor = value is int ? value : int.tryParse('$value');
          if (cursor != null && cursor > 0) _cursors[id] = cursor;
        }
      }
      final readIds = map['readIds'];
      if (readIds is List) {
        for (final id in readIds) {
          if (id is! String || id.isEmpty || _readIds.contains(id)) continue;
          _readIds.add(id);
          if (_readIds.length >= maxReadIds) break;
        }
      }
      return _readGroups(map['groups']);
    } catch (_) {
      _clearLists();
      return false;
    }
  }

  bool _readGroups(Object? raw) {
    if (raw == null) return false;
    if (raw is! List) return true;
    final known = _subscriptions.map((item) => item.id).toSet();
    final claimed = <String>{};
    var pruned = false;
    for (final entry in raw) {
      if (entry is! Map) {
        pruned = true;
        continue;
      }
      final group = SubscriptionGroup.fromJson(
        Map<String, dynamic>.from(entry),
      );
      if (group == null || _groups.any((item) => item.id == group.id)) {
        pruned = true;
        continue;
      }
      final kept = <String>[];
      for (final id in group.sourceIds) {
        if (!known.contains(id) || !claimed.add(id)) {
          pruned = true;
          continue;
        }
        kept.add(id);
      }
      _groups.add(group.copyWith(sourceIds: kept));
      if (_groups.length >= maxGroups) {
        if (raw.length > _groups.length) pruned = true;
        break;
      }
    }
    return pruned;
  }

  Future<void> _write(SharedPreferences prefs, int userId) {
    final payload = <String, dynamic>{
      'v': 1,
      'subscriptions': [
        for (final subscription in _subscriptions) subscription.toJson(),
      ],
      'items': {
        for (final entry in _items.entries)
          entry.key: [for (final item in entry.value) item.toJson()],
      },
      'cursors': _cursors,
      'readIds': _readIds,
      'groups': [for (final group in _groups) group.toJson()],
    };
    return prefs.setString(storageKeyForUser(userId), jsonEncode(payload));
  }

  void _clear() {
    _userId = null;
    _dirty = false;
    _clearLists();
  }

  void _clearLists() {
    _subscriptions.clear();
    _groups.clear();
    _items.clear();
    _cursors.clear();
    _readIds.clear();
  }

  void _stripSourceFromGroups(String sourceId) {
    for (var index = 0; index < _groups.length; index++) {
      final group = _groups[index];
      if (!group.sourceIds.contains(sourceId)) continue;
      _groups[index] = group.copyWith(
        sourceIds: [
          for (final id in group.sourceIds)
            if (id != sourceId) id,
        ],
      );
    }
  }

  String? _groupTitle(String raw) {
    final title = raw.trim();
    if (title.isEmpty) return null;
    if (title.length <= maxGroupTitle) return title;
    return title.substring(0, maxGroupTitle).trimRight();
  }

  bool _sameIds(List<String> next, List<String> current) {
    if (next.length != current.length) return false;
    for (var index = 0; index < next.length; index++) {
      if (next[index] != current[index]) return false;
    }
    return true;
  }
}
