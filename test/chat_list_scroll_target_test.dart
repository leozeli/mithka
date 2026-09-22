import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chats/chat_list_view.dart';

void main() {
  test('unread chat scroll target does not accumulate phantom separators', () {
    expect(
      chatListItemScrollOffset(
        itemIndex: 32,
        rowHeight: 72,
        maxScrollExtent: 10000,
      ),
      2304,
    );
  });

  test('unread chat scroll target stays within the list extent', () {
    expect(
      chatListItemScrollOffset(
        itemIndex: 32,
        rowHeight: 72,
        maxScrollExtent: 1800,
      ),
      1800,
    );
  });

  test(
    'unread chat scroll target includes a scrollable leading search item',
    () {
      expect(
        chatListItemScrollOffset(
          itemIndex: 4,
          rowHeight: 72,
          leadingExtent: 56,
          maxScrollExtent: 10000,
        ),
        344,
      );
    },
  );

  test('pull-down archive slot always follows the search row', () {
    expect(chatListPullDownArchiveItemIndex(showSearch: true), 1);
    expect(chatListPullDownArchiveItemIndex(showSearch: false), 0);
  });

  test('scroll-to-top control stays hidden near the top', () {
    expect(chatListShouldShowScrollToTop(scrollPixels: 0), isFalse);
    expect(
      chatListShouldShowScrollToTop(scrollPixels: chatListScrollToTopThreshold),
      isFalse,
    );
    expect(chatListShouldShowScrollToTop(scrollPixels: -36), isFalse);
    expect(
      chatListShouldShowScrollToTop(scrollPixels: -40, minScrollExtent: -40),
      isFalse,
    );
  });

  test('scroll-to-top control appears once the list passes the threshold', () {
    expect(
      chatListShouldShowScrollToTop(
        scrollPixels: chatListScrollToTopThreshold + 0.5,
      ),
      isTrue,
    );
    expect(chatListShouldShowScrollToTop(scrollPixels: 240), isTrue);
  });
}
