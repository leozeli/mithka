//
//  telegram_feed_source.dart
//
//  Turns explicitly chosen channel chats into timeline rows. Joined chats are
//  never added on their own; the user picks one from search or the channel list.
//

import '../tdlib/json_helpers.dart';
import '../tdlib/td_models.dart';
import 'feed_models.dart';

typedef TdQuery =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> request);

/// Channels are supergroups TDLib marks with `is_channel`. That is the set of
/// broadcasts the signed-in user can already open.
bool isSubscribableChannel(ChatSummary chat) => chat.kind == ChatKind.channel;

Future<List<ChatSummary>> loadSubscribableChannels({
  required TdQuery query,
  String search = '',
}) async {
  final ids = <int>[];
  final text = search.trim();
  if (text.isEmpty) {
    ids.addAll(
      await _chatIds(query, {
        '@type': 'getChats',
        'chat_list': {'@type': 'chatListMain'},
        'limit': 80,
      }),
    );
    ids.addAll(
      await _chatIds(query, {
        '@type': 'getChats',
        'chat_list': {'@type': 'chatListArchive'},
        'limit': 40,
      }),
    );
  } else {
    ids.addAll(
      await _chatIds(query, {
        '@type': 'searchChats',
        'query': text,
        'limit': 30,
      }),
    );
    ids.addAll(
      await _chatIds(query, {'@type': 'searchPublicChats', 'query': text}),
    );
    final username = text.startsWith('@') ? text.substring(1) : text;
    if (username.isNotEmpty && !username.contains(' ')) {
      try {
        final chat = await query({
          '@type': 'searchPublicChat',
          'username': username,
        });
        final id = chat.int64('id');
        if (id != null) ids.add(id);
      } catch (_) {}
    }
  }

  final seen = <int>{};
  final chats = <ChatSummary>[];
  for (final id in ids) {
    if (!seen.add(id)) continue;
    try {
      final raw = await query({'@type': 'getChat', 'chat_id': id});
      final chat = TDParse.chat(raw);
      if (chat == null || !isSubscribableChannel(chat)) continue;
      chats.add(chat);
    } catch (_) {}
  }
  chats.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  return chats;
}

Future<List<FeedItem>> loadTelegramFeedItems({
  required TdQuery query,
  required FeedSubscription subscription,
  int limit = 30,
}) async {
  final chatId = subscription.chatId;
  if (chatId == null) return const [];
  final response = await query({
    '@type': 'getChatHistory',
    'chat_id': chatId,
    'from_message_id': 0,
    'offset': 0,
    'limit': limit,
    'only_local': false,
  });
  final messages =
      response.objects('messages') ?? const <Map<String, dynamic>>[];
  final items = <FeedItem>[];
  for (final raw in messages) {
    final message = TDParse.message(raw);
    if (message == null) continue;
    final item = feedItemFromTelegramMessage(
      subscriptionId: subscription.id,
      sourceName: subscription.title,
      chatId: chatId,
      message: message,
    );
    if (item != null) items.add(item);
  }
  return items;
}

/// Maps one channel post onto a timeline row. Service messages are skipped.
/// Photo thumbnails can be attached later; the text and link are enough for now.
FeedItem? feedItemFromTelegramMessage({
  required String subscriptionId,
  required String sourceName,
  required int chatId,
  required ChatMessage message,
}) {
  if (message.isService) return null;
  final text = message.text.trim();
  final previewTitle = message.linkPreview?.title.trim() ?? '';
  final link = message.linkPreview?.url.trim();
  final usableLink = link == null || link.isEmpty ? null : link;
  if (text.isEmpty && previewTitle.isEmpty && usableLink == null) return null;
  final firstLine = text
      .split('\n')
      .map((line) => line.trim())
      .firstWhere((line) => line.isNotEmpty, orElse: () => '');
  final title = _clip(
    previewTitle.isNotEmpty
        ? previewTitle
        : (firstLine.isEmpty ? sourceName : firstLine),
    200,
  );
  var excerpt = text;
  if (title.isNotEmpty && excerpt.startsWith(title)) {
    excerpt = excerpt.substring(title.length).trimLeft();
  }
  final resolvedChatId = message.chatId ?? chatId;
  final body = _clip(excerpt, 4000);
  return FeedItem(
    id: telegramFeedItemId(resolvedChatId, message.id),
    subscriptionId: subscriptionId,
    title: title,
    sourceName: sourceName,
    summary: feedListSummary(body),
    body: body,
    publishedAt: message.date,
    link: usableLink,
    chatId: resolvedChatId,
    messageId: message.id,
  );
}

String _clip(String text, int maxChars) {
  final trimmed = text.trim();
  if (trimmed.length <= maxChars) return trimmed;
  return trimmed.substring(0, maxChars).trimRight();
}

Future<List<int>> _chatIds(TdQuery query, Map<String, dynamic> request) async {
  try {
    final response = await query(request);
    return response.int64Array('chat_ids') ?? const <int>[];
  } catch (_) {
    return const <int>[];
  }
}
