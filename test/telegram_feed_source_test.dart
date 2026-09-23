import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/subscriptions/feed_models.dart';
import 'package:mithka/subscriptions/telegram_feed_source.dart';
import 'package:mithka/tdlib/td_models.dart';

void main() {
  test('maps a channel post and skips service messages', () {
    final post = feedItemFromTelegramMessage(
      subscriptionId: 'tg:-100123',
      sourceName: 'News',
      chatId: -100123,
      message: ChatMessage(
        id: 99,
        chatId: -100123,
        isOutgoing: false,
        text: 'Title line\nBody line',
        date: 1700000000,
        linkPreview: const MessageLinkPreview(
          url: 'https://example.com/story',
          displayUrl: 'example.com',
          siteName: 'Example',
          title: 'Preview',
          description: '',
        ),
      ),
    );

    expect(post, isNotNull);
    expect(post!.id, 'tg:-100123:99');
    expect(post.title, 'Preview');
    expect(post.excerpt, 'Title line\nBody line');
    expect(post.link, 'https://example.com/story');
    expect(post.chatId, -100123);
    expect(post.messageId, 99);
    expect(post.opensInChat, isTrue);

    expect(
      feedItemFromTelegramMessage(
        subscriptionId: 'tg:-100123',
        sourceName: 'News',
        chatId: -100123,
        message: ChatMessage(
          id: 1,
          isOutgoing: false,
          text: 'joined',
          date: 1,
          isService: true,
        ),
      ),
      isNull,
    );
  });

  test('lists joined channels and ignores ordinary groups', () async {
    final chats = await loadSubscribableChannels(
      query: (request) async {
        switch (request['@type']) {
          case 'getChats':
            return {
              'chat_ids': [-100, 5],
            };
          case 'getChat':
            final id = request['chat_id'];
            if (id == -100) {
              return {
                '@type': 'chat',
                'id': -100,
                'title': 'News',
                'type': {
                  '@type': 'chatTypeSupergroup',
                  'supergroup_id': 1,
                  'is_channel': true,
                },
              };
            }
            return {
              '@type': 'chat',
              'id': 5,
              'title': 'Friends',
              'type': {'@type': 'chatTypeBasicGroup', 'basic_group_id': 2},
            };
          default:
            return {'@type': 'ok'};
        }
      },
    );

    expect(chats.map((chat) => chat.id), [-100]);
    expect(chats.single.kind, ChatKind.channel);
    expect(chats.single.title, 'News');
  });

  test('loads recent non-service messages for one chat', () async {
    final items = await loadTelegramFeedItems(
      subscription: const FeedSubscription(
        id: 'tg:-100',
        kind: FeedSourceKind.telegram,
        title: 'News',
        chatId: -100,
        addedAt: 1,
      ),
      query: (request) async {
        expect(request['@type'], 'getChatHistory');
        expect(request['chat_id'], -100);
        return {
          'messages': [
            {
              '@type': 'message',
              'id': 7,
              'chat_id': -100,
              'date': 20,
              'is_outgoing': false,
              'content': {
                '@type': 'messageText',
                'text': {'@type': 'formattedText', 'text': 'Hello channel'},
              },
            },
            {
              '@type': 'message',
              'id': 6,
              'chat_id': -100,
              'date': 10,
              'is_outgoing': false,
              'content': {'@type': 'messageChatJoinByLink'},
            },
          ],
        };
      },
    );

    expect(items, hasLength(1));
    expect(items.single.title, 'Hello channel');
    expect(items.single.messageId, 7);
  });
}
