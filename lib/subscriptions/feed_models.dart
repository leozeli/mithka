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
