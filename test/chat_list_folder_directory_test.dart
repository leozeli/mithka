import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chats/chat_list_folder_directory.dart';
import 'package:mithka/chats/chat_list_view.dart';
import 'package:mithka/chats/chat_list_view_model.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'directory keeps collapsed folders as headers and nests their chats',
    () {
      final slots = buildChatListFolderDirectory(
        folderIds: const [7, 8],
        expandedFolderIds: const {7},
        allExpanded: true,
        folderEntryCounts: const {7: 2, 8: 4},
        loadingFolderIds: const {},
        allEntryCount: 3,
        allLoading: false,
        hasPullDownArchiveSlot: false,
        hasFiltered: false,
        showInlineArchive: false,
        inlineArchiveIndex: -1,
        allPlaceholderCount: 0,
      );

      expect(
        slots
            .map((slot) => (slot.kind, slot.folderId, slot.entryIndex))
            .toList(),
        [
          (ChatListDirectorySlotKind.folderHeader, 7, null),
          (ChatListDirectorySlotKind.entry, 7, 0),
          (ChatListDirectorySlotKind.entry, 7, 1),
          (ChatListDirectorySlotKind.folderHeader, 8, null),
          (ChatListDirectorySlotKind.folderHeader, null, null),
          (ChatListDirectorySlotKind.entry, null, 0),
          (ChatListDirectorySlotKind.entry, null, 1),
          (ChatListDirectorySlotKind.entry, null, 2),
        ],
      );
      expect(slots[2].lastInSection, isTrue);
      expect(
        slots.where((slot) => slot.folderId == null && slot.lastInSection),
        isEmpty,
      );
    },
  );

  test(
    'collapsed All omits main chats and an empty folder explains itself',
    () {
      final slots = buildChatListFolderDirectory(
        folderIds: const [4],
        expandedFolderIds: const {4},
        allExpanded: false,
        folderEntryCounts: const {4: 0},
        loadingFolderIds: const {},
        allEntryCount: 9,
        allLoading: false,
        hasPullDownArchiveSlot: true,
        hasFiltered: true,
        showInlineArchive: true,
        inlineArchiveIndex: 0,
        allPlaceholderCount: 6,
      );
      expect(slots.first.kind, ChatListDirectorySlotKind.pullDownArchive);
      expect(
        slots.where(
          (slot) =>
              slot.folderId == null &&
              slot.kind == ChatListDirectorySlotKind.entry,
        ),
        isEmpty,
      );
      expect(
        slots.where(
          (slot) =>
              slot.folderId == 4 &&
              slot.kind == ChatListDirectorySlotKind.empty,
        ),
        hasLength(1),
      );
    },
  );

  test('scroll offset accounts for folder headers above the main list', () {
    final slots = buildChatListFolderDirectory(
      folderIds: const [1],
      expandedFolderIds: const {},
      allExpanded: true,
      folderEntryCounts: const {},
      loadingFolderIds: const {},
      allEntryCount: 2,
      allLoading: false,
      hasPullDownArchiveSlot: false,
      hasFiltered: false,
      showInlineArchive: false,
      inlineArchiveIndex: -1,
      allPlaceholderCount: 0,
    );
    final unread = slots.indexWhere(
      (slot) =>
          slot.kind == ChatListDirectorySlotKind.entry && slot.entryIndex == 1,
    );
    expect(
      chatListDirectoryScrollOffset(
        slots: slots,
        targetIndex: unread,
        rowHeight: 58,
        headerHeight: 40,
        maxScrollExtent: 1000,
        pullDownVisible: false,
      ),
      40 + 40 + 58,
    );
  });

  test('folder projection uses Telegram folder membership', () {
    final model = ChatListViewModel(
      queryForTesting: (_) async => {'@type': 'ok'},
    );
    addTearDown(model.dispose);
    model.applyUpdateForTesting({
      '@type': 'updateChatFolders',
      'chat_folders': [
        {'id': 7, 'title': 'Work'},
      ],
    });
    model.seedChatForTesting(_chat(id: 1, order: 10, title: 'Inbox'));
    model.seedChatForTesting(_chat(id: 2, order: 0, title: 'Folder only'));
    model.applyUpdateForTesting({
      '@type': 'updateChatPosition',
      'chat_id': 1,
      'position': _folderPosition(7, 20),
    });
    model.applyUpdateForTesting({
      '@type': 'updateChatPosition',
      'chat_id': 2,
      'position': _folderPosition(7, 30),
    });
    model.resortForTesting();

    expect(model.chats.map((chat) => chat.id), [1]);
    expect(model.chatsForFolder(7).map((chat) => chat.id), [2, 1]);
    expect(model.chatListEntriesForFolder(7).length, 2);
  });

  test('pinning from a folder section targets that folder list', () {
    final queries = <Map<String, dynamic>>[];
    final model = ChatListViewModel(
      queryForTesting: (request) async {
        queries.add(Map<String, dynamic>.from(request));
        return {'@type': 'ok'};
      },
    );
    addTearDown(model.dispose);
    final chat = _chat(id: 9, order: 5, title: 'Work chat');
    model.seedChatForTesting(chat);
    model.togglePin(
      chat,
      chatList: {'@type': 'chatListFolder', 'chat_folder_id': 7},
    );
    expect(queries.single['chat_list'], {
      '@type': 'chatListFolder',
      'chat_folder_id': 7,
    });
    expect(queries.single['chat_id'], 9);
    expect(queries.single['is_pinned'], isTrue);
  });

  testWidgets(
    'expanding a folder reveals only that folder\'s chats',
    (tester) async {
      final updates = StreamController<Map<String, dynamic>>.broadcast();
      TdClient.shared.configureProxy(
        TdClientProxyTransport(
          accountSlot: 0,
          query: (request) async => switch (request['@type']) {
            'getMe' => {'@type': 'user', 'id': 1, 'first_name': 'Test'},
            _ => {'@type': 'ok'},
          },
          send: (_) async {},
          updates: updates.stream,
        ),
      );
      addTearDown(() async {
        await TdClient.shared.closeProxy();
        await updates.close();
      });
      SharedPreferences.setMockInitialValues({'communitiesEnabled': false});
      final theme = ThemeController(await SharedPreferences.getInstance());
      addTearDown(theme.dispose);
      final controller = ChatListController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: theme,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: const [AppLocalizations.delegate],
            supportedLocales: AppLocalizations.supportedLocales,
            theme: ThemeData(extensions: [AppColors.light]),
            home: Scaffold(
              body: ChatListView(controller: controller, desktopSidebar: true),
            ),
          ),
        ),
      );
      updates.add({
        '@type': 'updateChatFolders',
        'chat_folders': [
          {
            'id': 3,
            'title': 'Work',
            'icon': {'name': 'Work'},
          },
        ],
      });
      updates.add({
        '@type': 'updateNewChat',
        'chat': _rawChat(
          id: 11,
          title: 'Main chat',
          positions: [
            {
              '@type': 'chatPosition',
              'list': {'@type': 'chatListMain'},
              'order': '100',
              'is_pinned': false,
            },
          ],
        ),
      });
      updates.add({
        '@type': 'updateNewChat',
        'chat': _rawChat(
          id: 12,
          title: 'Work chat',
          positions: [
            {
              '@type': 'chatPosition',
              'list': {'@type': 'chatListFolder', 'chat_folder_id': 3},
              'order': '80',
              'is_pinned': false,
            },
          ],
        ),
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));

      expect(find.byType(ChatFolderRail), findsNothing);
      expect(controller.sideFolders.value, isNull);
      expect(find.text('Main chat'), findsOneWidget);
      expect(find.text('Work chat'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('chat-list-folder-3')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));

      expect(find.text('Work chat'), findsOneWidget);
      expect(find.text('Main chat'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Work chat')).dy,
        lessThan(tester.getTopLeft(find.text('Main chat')).dy),
      );

      await tester.tap(find.byKey(const ValueKey('chat-list-folder-3')));
      await tester.pump();
      expect(find.text('Work chat'), findsNothing);
      expect(find.text('Main chat'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 6));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );
}

ChatSummary _chat({
  required int id,
  required int order,
  required String title,
}) {
  return ChatSummary(
    id: id,
    title: title,
    lastMessage: '',
    lastMessageId: 0,
    date: id,
    unreadCount: 0,
    order: order,
    isMuted: false,
  );
}

Map<String, dynamic> _folderPosition(int folderId, int order) => {
  '@type': 'chatPosition',
  'list': {'@type': 'chatListFolder', 'chat_folder_id': folderId},
  'order': order,
  'is_pinned': false,
};

Map<String, dynamic> _rawChat({
  required int id,
  required String title,
  required List<Map<String, dynamic>> positions,
}) => {
  '@type': 'chat',
  'id': id,
  'title': title,
  'unread_count': 0,
  'type': {'@type': 'chatTypePrivate', 'user_id': 4},
  'positions': positions,
};
