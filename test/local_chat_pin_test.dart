import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chats/chat_list_view_model.dart';
import 'package:mithka/chats/chat_row_view.dart';
import 'package:mithka/chats/local_chat_pin_store.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ChatSummary chat({
    required int id,
    required int order,
    bool isPinned = false,
    int date = 0,
  }) {
    return ChatSummary(
      id: id,
      title: 'Chat $id',
      lastMessage: '',
      lastMessageId: 0,
      date: date,
      unreadCount: 0,
      order: order,
      isMuted: false,
      isPinned: isPinned,
    );
  }

  test('pins persist for one user and stay off other accounts', () async {
    SharedPreferences.setMockInitialValues({});
    final store = LocalChatPinStore();
    await store.bind(slot: 2, userId: 7);
    expect(await store.pin(11), isTrue);
    expect(await store.pin(22), isTrue);
    expect(await store.pin(-5), isTrue);

    final reloaded = LocalChatPinStore();
    expect(await reloaded.bind(slot: 9, userId: 7), isTrue);
    expect(reloaded.orderedIds, [-5, 22, 11]);

    final otherAccount = LocalChatPinStore();
    expect(await otherAccount.bind(slot: 2, userId: 8), isFalse);
    expect(otherAccount.orderedIds, isEmpty);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(LocalChatPinStore.storageKeyForUser(7)), [
      '-5',
      '22',
      '11',
    ]);
    expect(prefs.getStringList(LocalChatPinStore.storageKeyForUser(8)), isNull);
  });

  test(
    'pins made before the user id is known are saved onto that account',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = LocalChatPinStore();
      await store.bind(slot: 1);
      await store.pin(5);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isEmpty);

      // The pin is already in memory, so binding only writes it.
      expect(await store.bind(slot: 1, userId: 42), isFalse);
      expect(store.orderedIds, [5]);
      expect(prefs.getStringList(LocalChatPinStore.storageKeyForUser(42)), [
        '5',
      ]);

      final restarted = LocalChatPinStore();
      await restarted.bind(slot: 3, userId: 42);
      expect(restarted.orderedIds, [5]);
    },
  );

  test('changing slot before the user id drops unsaved pins', () async {
    SharedPreferences.setMockInitialValues({});
    final store = LocalChatPinStore();
    await store.bind(slot: 1);
    await store.pin(5);
    expect(await store.bind(slot: 2), isTrue);
    expect(store.orderedIds, isEmpty);
  });

  test('stored ids ignore blanks and duplicates', () async {
    SharedPreferences.setMockInitialValues({
      LocalChatPinStore.storageKeyForUser(3): ['4', 'nope', '4', '8'],
    });
    final store = LocalChatPinStore();
    await store.bind(slot: 0, userId: 3);
    expect(store.orderedIds, [4, 8]);
  });

  test('soft cap refuses a new pin and keeps the existing order', () async {
    final ids = [for (var i = 0; i < LocalChatPinStore.softCap; i++) i + 1];
    final store = LocalChatPinStore(persist: false, initialIds: ids);

    expect(await store.pin(99999), isFalse);
    expect(store.orderedIds, ids);
    expect(await store.pin(ids.last), isTrue);
    expect(store.orderedIds, ids);

    await store.unpin(1);
    expect(await store.pin(99999), isTrue);
    expect(store.orderedIds.first, 99999);
    expect(store.orderedIds, hasLength(LocalChatPinStore.softCap));
    expect(store.isPinned(1), isFalse);
  });

  test('main list order is local pins, then server pins, then TDLib order', () {
    final local = chat(id: 1, order: 10, date: 1);
    final both = chat(id: 2, order: 5, isPinned: true, date: 1);
    final server = chat(id: 3, order: 100, isPinned: true, date: 1);
    final older = chat(id: 4, order: 40, date: 2);
    final newer = chat(id: 5, order: 40, date: 9);
    final ranks = {2: 0, 1: 1};

    final sorted = [newer, server, older, local, both]
      ..sort(
        (a, b) =>
            compareMainChatList(a, b, localPinRank: (id) => ranks[id] ?? -1),
      );

    expect(sorted.map((item) => item.id).toList(), [2, 1, 3, 5, 4]);
  });

  test('local pins lead the main list once and do not call TDLib', () async {
    final requests = <String>[];
    final store = LocalChatPinStore(persist: false, initialIds: [30, 10]);
    final model = ChatListViewModel(
      queryForTesting: (request) async {
        requests.add(request['@type'] as String);
        return {'@type': 'ok'};
      },
      localPins: store,
    );
    addTearDown(model.dispose);
    model.seedChatForTesting(chat(id: 10, order: 10));
    model.seedChatForTesting(chat(id: 20, order: 100, isPinned: true));
    model.seedChatForTesting(chat(id: 30, order: 5, isPinned: true));
    model.seedChatForTesting(chat(id: 40, order: 80));
    model.resortForTesting();

    expect(model.chats.map((item) => item.id).toList(), [30, 10, 20, 40]);
    expect(requests, isEmpty);

    final extra = chat(id: 50, order: 1);
    model.seedChatForTesting(extra);
    await model.toggleLocalPin(extra);
    expect(requests, isEmpty);
    expect(extra.isPinned, isFalse);
    expect(model.chats.map((item) => item.id).toList(), [50, 30, 10, 20, 40]);

    await model.toggleLocalPin(extra);
    expect(model.isLocallyPinned(50), isFalse);
    expect(model.chats.first.id, 30);
    expect(requests, isEmpty);
  });

  test('official pin still calls toggleChatIsPinned', () async {
    final requests = <Map<String, dynamic>>[];
    final model = ChatListViewModel(
      queryForTesting: (request) async {
        requests.add(request);
        return {'@type': 'ok'};
      },
      localPins: LocalChatPinStore(persist: false),
    );
    addTearDown(model.dispose);
    final pinned = chat(id: 9, order: 2);
    model.seedChatForTesting(pinned);
    model.togglePin(pinned);
    await Future<void>.delayed(Duration.zero);

    expect(requests, hasLength(1));
    expect(requests.single['@type'], 'toggleChatIsPinned');
    expect(requests.single['chat_id'], 9);
    expect(requests.single['is_pinned'], isTrue);
    expect(requests.single['chat_list'], {'@type': 'chatListMain'});
    expect(pinned.isPinned, isTrue);
    expect(model.isLocallyPinned(9), isFalse);
  });

  testWidgets('a server pin limit falls back to a local pin', (tester) async {
    final requests = <Map<String, dynamic>>[];
    final store = LocalChatPinStore(persist: false);
    final model = ChatListViewModel(
      queryForTesting: (request) {
        requests.add(Map<String, dynamic>.from(request));
        if (request['@type'] == 'toggleChatIsPinned') {
          return Future<Map<String, dynamic>>.error(
            TdError({
              '@type': 'error',
              'code': 400,
              'message': 'PINNED_CHATS_TOO_MUCH',
            }),
          );
        }
        return Future<Map<String, dynamic>>.error(StateError('no refresh'));
      },
      localPins: store,
    );
    addTearDown(model.dispose);
    final pinned = chat(id: 10, order: 20);
    model.seedChatForTesting(pinned);
    model.togglePin(pinned);
    await tester.pump();
    await tester.pump();

    expect(pinned.isPinned, isFalse);
    expect(store.isPinned(10), isTrue);
    expect(model.notice, AppStringKeys.chatListLocalPinnedNotice);
    expect(model.chats.single.id, 10);
    expect(
      requests.where((request) => request['@type'] == 'toggleChatIsPinned'),
      hasLength(1),
    );
  });

  testWidgets('a non-limit pin failure does not create a local pin', (
    tester,
  ) async {
    final store = LocalChatPinStore(persist: false);
    final model = ChatListViewModel(
      queryForTesting: (request) {
        return Future<Map<String, dynamic>>.error(
          TdError({'@type': 'error', 'code': 400, 'message': 'CHAT_NOT_FOUND'}),
        );
      },
      localPins: store,
    );
    addTearDown(model.dispose);
    final pinned = chat(id: 10, order: 20);
    model.seedChatForTesting(pinned);
    model.togglePin(pinned);
    await tester.pump();
    await tester.pump();

    expect(store.isPinned(10), isFalse);
    expect(pinned.isPinned, isFalse);
    expect(model.notice, isNot(AppStringKeys.chatListLocalPinnedNotice));
    expect(model.notice, isNot(AppStringKeys.chatInfoPinLimitReachedError));
  });

  testWidgets('saved local pins apply when the account user id arrives', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      LocalChatPinStore.storageKeyForUser(42): ['7'],
    });
    final model = ChatListViewModel();
    addTearDown(model.dispose);
    model.seedChatForTesting(chat(id: 7, order: 1));
    model.seedChatForTesting(chat(id: 8, order: 50));
    model.resortForTesting();
    expect(model.chats.map((item) => item.id).toList(), [8, 7]);

    model.meId = 42;
    await tester.pump();
    await tester.pump();

    expect(model.chats.map((item) => item.id).toList(), [7, 8]);
    expect(model.isLocallyPinned(7), isTrue);
  });

  testWidgets('folder order ignores local pins', (tester) async {
    final store = LocalChatPinStore(persist: false, initialIds: [10]);
    final model = ChatListViewModel(
      queryForTesting: (_) async => {'@type': 'ok'},
      localPins: store,
    );
    addTearDown(model.dispose);
    model.seedChatForTesting(chat(id: 10, order: 5));
    model.seedChatForTesting(chat(id: 40, order: 80));
    model.applyUpdateForTesting({
      '@type': 'updateChatFolders',
      'chat_folders': [
        {'id': 3, 'title': 'Work'},
      ],
    });
    for (final entry in [(10, 10), (40, 50)]) {
      model.applyUpdateForTesting({
        '@type': 'updateChatPosition',
        'chat_id': entry.$1,
        'position': {
          'list': {'@type': 'chatListFolder', 'chat_folder_id': 3},
          'order': entry.$2,
          'is_pinned': false,
        },
      });
    }
    await tester.pump(const Duration(milliseconds: 50));

    expect(model.chats.map((item) => item.id).toList(), [10, 40]);
    expect(model.chatsForFolder(3).map((item) => item.id).toList(), [40, 10]);
  });

  testWidgets('a local pin fills the pin mark and tints the row', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final theme = ThemeController(await SharedPreferences.getInstance());
    addTearDown(theme.dispose);
    final row = chat(id: 3, order: 1);

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          theme: ThemeData(
            brightness: Brightness.light,
            extensions: [AppColors.light],
          ),
          home: Scaffold(body: ChatRowView(chat: row, locallyPinned: true)),
        ),
      ),
    );

    final icon = tester.widget<AppPinIcon>(
      find.byKey(const ValueKey('chat-row-local-pinned')),
    );
    expect(icon.filled, isTrue);
    expect(find.byKey(const ValueKey('chat-row-pinned')), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Container && widget.color == AppColors.light.pinnedRow,
      ),
      findsOneWidget,
    );
  });

  test('the local pin limit is the high soft cap, not Telegram\'s quota', () {
    expect(LocalChatPinStore.softCap, 100);
  });
}
