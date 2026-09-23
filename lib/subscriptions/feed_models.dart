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
    required this.summary,
    this.body = '',
    required this.publishedAt,
    this.link,
    this.chatId,
    this.messageId,
  });

  final String id;
  final String subscriptionId;
  final String title;
  final String sourceName;

  /// Short line for the timeline. Not the article.
  final String summary;

  /// Detail-page source. RSS items keep feed HTML; Telegram stays plain text.
  final String body;
  final int publishedAt;
  final String? link;
  final int? chatId;
  final int? messageId;

  bool get opensInChat => chatId != null && messageId != null;

  bool get hasLink => link != null && link!.trim().isNotEmpty;

  /// Timeline copy. Falls back to the first paragraph when only [body] is set.
  String get listSummary {
    final text = summary.trim();
    if (text.isNotEmpty) return text;
    final source = feedBodyIsHtml(body) ? _plainFromHtml(body) : body;
    return feedListSummary(source);
  }

  /// Reader copy. A summary-only item still has something to show.
  String get articleBody {
    final text = body.trim();
    if (text.isNotEmpty) return text;
    return summary.trim();
  }

  /// `github.com` for an RSS link. Telegram rows leave this empty.
  String? get siteLabel {
    if (opensInChat) return null;
    final raw = link?.trim();
    if (raw == null || raw.isEmpty) return null;
    final host = Uri.tryParse(raw)?.host.toLowerCase() ?? '';
    if (host.isEmpty) return null;
    final label = host.startsWith('www.') ? host.substring(4) : host;
    if (label.isEmpty) return null;
    if (label == sourceName.trim().toLowerCase()) return null;
    return label;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'subscriptionId': subscriptionId,
    'title': title,
    'sourceName': sourceName,
    'summary': summary,
    'body': body,
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
    final storedBody = json['body'] is String ? json['body'] as String : '';
    final storedSummary = json['summary'] is String
        ? json['summary'] as String
        : '';
    final legacy = json['excerpt'] is String ? json['excerpt'] as String : '';
    final body = storedBody.isNotEmpty ? storedBody : legacy;
    final summary = storedSummary.trim().isNotEmpty
        ? storedSummary
        : feedListSummary(legacy);
    return FeedItem(
      id: id,
      subscriptionId: subscriptionId,
      title: json['title'] is String ? json['title'] as String : '',
      sourceName: json['sourceName'] is String
          ? json['sourceName'] as String
          : '',
      summary: summary,
      body: body,
      publishedAt: _asInt(json['publishedAt']) ?? 0,
      link: json['link'] is String ? json['link'] as String : null,
      chatId: _asInt(json['chatId']),
      messageId: _asInt(json['messageId']),
    );
  }
}

/// Timeline cards stay short even when the article is a README.
const int feedSummaryMaxChars = 180;

/// Plain-text detail cap. HTML articles use [feedHtmlMaxChars].
const int feedBodyMaxChars = 8000;

/// Feed HTML kept for the detail card, short of an entire repository file.
const int feedHtmlMaxChars = 24000;

final _htmlStructure = RegExp(
  r'<\s*/?\s*(p|br|h[1-6]|ul|ol|li|div|a|blockquote|pre|table|tr|td|strong|em|code|article|section)\b',
  caseSensitive: false,
);

/// True when [text] still has the tags a reader should draw.
bool feedBodyIsHtml(String text) => _htmlStructure.hasMatch(text);

String _plainFromHtml(String text) {
  return text
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(
        RegExp(r'</(p|div|h[1-6]|li|tr|blockquote)\s*>', caseSensitive: false),
        '\n\n',
      )
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

/// First useful paragraph, clipped to [maxChars] on a word boundary.
String feedListSummary(String plain, {int maxChars = feedSummaryMaxChars}) {
  final trimmed = plain.trim();
  if (trimmed.isEmpty) return '';
  final paragraphs = trimmed.split(RegExp(r'\n\s*\n'));
  String? fallback;
  for (final paragraph in paragraphs) {
    final line = paragraph.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (line.isEmpty) continue;
    fallback ??= line;
    if (_isUsefulSummaryLine(line)) return clipFeedText(line, maxChars);
  }
  return clipFeedText(
    fallback ?? trimmed.replaceAll(RegExp(r'\s+'), ' ').trim(),
    maxChars,
  );
}

String clipFeedText(String text, int maxChars) {
  final trimmed = text.trim();
  if (trimmed.length <= maxChars) return trimmed;
  var end = trimmed.lastIndexOf(' ', maxChars);
  if (end < (maxChars * 0.6).round()) end = maxChars;
  return trimmed.substring(0, end).trimRight();
}

String clipFeedBody(String text, {int maxChars = feedBodyMaxChars}) {
  final trimmed = text.trim();
  if (trimmed.length <= maxChars) return trimmed;
  var end = trimmed.lastIndexOf('\n\n', maxChars);
  if (end < (maxChars * 0.5).round()) {
    end = trimmed.lastIndexOf(' ', maxChars);
  }
  if (end < (maxChars * 0.5).round()) end = maxChars;
  return trimmed.substring(0, end).trimRight();
}

bool _isUsefulSummaryLine(String line) {
  final bare = line.replaceFirst(RegExp(r'^[•\-]\s*'), '').trim();
  if (bare.isEmpty) return false;
  final uri = Uri.tryParse(bare);
  if (uri != null && uri.hasScheme && !bare.contains(' ')) return false;
  return true;
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
