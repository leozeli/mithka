//
//  feed_models.dart
//
//  Local subscription records and the timeline items they produce.
//  Nothing here is synced to a server.
//

enum FeedSourceKind { telegram, rss }

enum SubscriptionFailure {
  invalidUrl,
  notFeed,
  network,
  telegram,
  alreadyAdded,
  full,
}

/// One source the user explicitly added on this device.
class FeedSubscription {
  const FeedSubscription({
    required this.id,
    required this.kind,
    required this.title,
    required this.addedAt,
    this.chatId,
    this.feedUrl,
    this.fetchedAt,
    this.lastError,
  });

  final String id;
  final FeedSourceKind kind;
  final String title;
  final int addedAt;
  final int? chatId;
  final String? feedUrl;
  final int? fetchedAt;

  /// `network`, `notFeed`, or `telegram` after the last failed fetch.
  final String? lastError;

  FeedSubscription copyWith({
    String? title,
    int? fetchedAt,
    String? lastError,
    bool clearError = false,
  }) {
    return FeedSubscription(
      id: id,
      kind: kind,
      title: title ?? this.title,
      addedAt: addedAt,
      chatId: chatId,
      feedUrl: feedUrl,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'title': title,
    'addedAt': addedAt,
    if (chatId != null) 'chatId': '$chatId',
    if (feedUrl != null) 'feedUrl': feedUrl,
    if (fetchedAt != null) 'fetchedAt': fetchedAt,
    if (lastError != null && lastError!.isNotEmpty) 'lastError': lastError,
  };

  static FeedSubscription? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final kindName = json['kind'];
    final title = json['title'];
    if (id is! String || id.isEmpty || title is! String) return null;
    final kind = FeedSourceKind.values
        .where((value) => value.name == kindName)
        .firstOrNull;
    if (kind == null) return null;
    final addedAt = _asInt(json['addedAt']) ?? 0;
    return FeedSubscription(
      id: id,
      kind: kind,
      title: title,
      addedAt: addedAt,
      chatId: _asInt(json['chatId']),
      feedUrl: json['feedUrl'] is String ? json['feedUrl'] as String : null,
      fetchedAt: _asInt(json['fetchedAt']),
      lastError: json['lastError'] is String
          ? json['lastError'] as String
          : null,
    );
  }
}

/// One row in the unified timeline.
class FeedItem {
  const FeedItem({
    required this.id,
    required this.subscriptionId,
    required this.title,
    required this.sourceName,
    required this.excerpt,
    required this.publishedAt,
    this.link,
    this.chatId,
    this.messageId,
  });

  final String id;
  final String subscriptionId;
  final String title;
  final String sourceName;
  final String excerpt;
  final int publishedAt;
  final String? link;
  final int? chatId;
  final int? messageId;

  bool get opensInChat => chatId != null && messageId != null;

  bool get hasLink => link != null && link!.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {
    'id': id,
    'subscriptionId': subscriptionId,
    'title': title,
    'sourceName': sourceName,
    'excerpt': excerpt,
    'publishedAt': publishedAt,
    if (link != null) 'link': link,
    if (chatId != null) 'chatId': '$chatId',
    if (messageId != null) 'messageId': '$messageId',
  };

  static FeedItem? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final subscriptionId = json['subscriptionId'];
    if (id is! String ||
        id.isEmpty ||
        subscriptionId is! String ||
        subscriptionId.isEmpty) {
      return null;
    }
    return FeedItem(
      id: id,
      subscriptionId: subscriptionId,
      title: json['title'] is String ? json['title'] as String : '',
      sourceName: json['sourceName'] is String
          ? json['sourceName'] as String
          : '',
      excerpt: json['excerpt'] is String ? json['excerpt'] as String : '',
      publishedAt: _asInt(json['publishedAt']) ?? 0,
      link: json['link'] is String ? json['link'] as String : null,
      chatId: _asInt(json['chatId']),
      messageId: _asInt(json['messageId']),
    );
  }
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is String) return int.tryParse(value);
  return null;
}

String telegramSubscriptionId(int chatId) => 'tg:$chatId';

String rssSubscriptionId(String canonicalUrl) => 'rss:$canonicalUrl';

String telegramFeedItemId(int chatId, int messageId) => 'tg:$chatId:$messageId';

int compareFeedItems(FeedItem a, FeedItem b) {
  final byDate = b.publishedAt.compareTo(a.publishedAt);
  if (byDate != 0) return byDate;
  return b.id.compareTo(a.id);
}

/// One local folder of subscriptions. Groups do not nest.
class SubscriptionGroup {
  SubscriptionGroup({
    required this.id,
    required this.title,
    required List<String> sourceIds,
    this.expanded = true,
  }) : sourceIds = List<String>.unmodifiable(sourceIds);

  final String id;
  final String title;
  final List<String> sourceIds;
  final bool expanded;

  SubscriptionGroup copyWith({
    String? title,
    List<String>? sourceIds,
    bool? expanded,
  }) {
    return SubscriptionGroup(
      id: id,
      title: title ?? this.title,
      sourceIds: sourceIds ?? this.sourceIds,
      expanded: expanded ?? this.expanded,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'sourceIds': sourceIds,
    'expanded': expanded,
  };

  static SubscriptionGroup? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final title = json['title'];
    if (id is! String || id.isEmpty || title is! String) return null;
    final trimmed = title.trim();
    if (trimmed.isEmpty) return null;
    final rawIds = json['sourceIds'];
    final ids = <String>[];
    if (rawIds is List) {
      for (final sourceId in rawIds) {
        if (sourceId is! String || sourceId.isEmpty || ids.contains(sourceId)) {
          continue;
        }
        ids.add(sourceId);
      }
    }
    final expanded = json['expanded'];
    return SubscriptionGroup(
      id: id,
      title: trimmed,
      sourceIds: ids,
      expanded: expanded is bool ? expanded : true,
    );
  }
}

enum SubscriptionOutlineKind { group, source }

/// One row in the source list. Ungrouped sources come first, then each group
/// and, when it is expanded, the sources that belong to it.
class SubscriptionOutlineRow {
  const SubscriptionOutlineRow.group(this.group)
    : source = null,
      nested = false,
      kind = SubscriptionOutlineKind.group;

  const SubscriptionOutlineRow.source(this.source, {this.nested = false})
    : group = null,
      kind = SubscriptionOutlineKind.source;

  final SubscriptionOutlineKind kind;
  final SubscriptionGroup? group;
  final FeedSubscription? source;
  final bool nested;
}

List<SubscriptionOutlineRow> subscriptionOutline({
  required List<FeedSubscription> subscriptions,
  required List<SubscriptionGroup> groups,
}) {
  final byId = {
    for (final subscription in subscriptions) subscription.id: subscription,
  };
  final owner = <String, String>{};
  for (final group in groups) {
    for (final id in group.sourceIds) {
      if (!byId.containsKey(id)) continue;
      owner.putIfAbsent(id, () => group.id);
    }
  }
  final rows = <SubscriptionOutlineRow>[];
  for (final subscription in subscriptions) {
    if (owner.containsKey(subscription.id)) continue;
    rows.add(SubscriptionOutlineRow.source(subscription));
  }
  for (final group in groups) {
    rows.add(SubscriptionOutlineRow.group(group));
    if (!group.expanded) continue;
    for (final id in group.sourceIds) {
      if (owner[id] != group.id) continue;
      final source = byId[id];
      if (source == null) continue;
      rows.add(SubscriptionOutlineRow.source(source, nested: true));
    }
  }
  return rows;
}
