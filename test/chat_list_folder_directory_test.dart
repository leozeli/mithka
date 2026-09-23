import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chats/chat_list_folder_directory.dart';
import 'package:mithka/chats/chat_list_view.dart';
import 'package:mithka/chats/chat_list_view_model.dart';
import 'package:mithka/chats/local_folder_group.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/components/chat_folder_icons.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('selecting All shows only the main chats under the folder rows', () {
    final slots = buildChatListFolderDirectory(
      folderIds: const [7, 8],
      selectedFolderId: null,
      selectedEntryCount: 3,
      selectedLoading: false,
      selectedPlaceholderCount: 0,
      hasPullDownArchiveSlot: false,
      hasFiltered: false,
      showInlineArchive: false,
      inlineArchiveIndex: -1,
    );

    expect(
      slots.map((slot) => (slot.kind, slot.folderId, slot.entryIndex)).toList(),
      [
        (ChatListDirectorySlotKind.folderHeader, 7, null),
        (ChatListDirectorySlotKind.folderHeader, 8, null),
        (ChatListDirectorySlotKind.folderHeader, null, null),
        (ChatListDirectorySlotKind.entry, null, 0),
        (ChatListDirectorySlotKind.entry, null, 1),
        (ChatListDirectorySlotKind.entry, null, 2),
      ],
    );
    expect(slots.last.selected, isFalse);
    expect(slots[2].selected, isTrue);
    expect(slots.where((slot) => slot.lastInSection), isEmpty);
  });

  test('selecting a folder replaces the main chats with that folder', () {
    final slots = buildChatListFolderDirectory(
      folderIds: const [7, 8],
      selectedFolderId: 7,
      selectedEntryCount: 2,
      selectedLoading: false,
      selectedPlaceholderCount: 0,
      hasPullDownArchiveSlot: false,
      hasFiltered: false,
      showInlineArchive: false,
      inlineArchiveIndex: -1,
    );
    expect(
      slots.map((slot) => (slot.kind, slot.folderId, slot.entryIndex)).toList(),
      [
        (ChatListDirectorySlotKind.folderHeader, 7, null),
        (ChatListDirectorySlotKind.folderHeader, 8, null),
        (ChatListDirectorySlotKind.folderHeader, null, null),
        (ChatListDirectorySlotKind.entry, 7, 0),
        (ChatListDirectorySlotKind.entry, 7, 1),
      ],
    );
    expect(slots.first.selected, isTrue);
    expect(slots[2].selected, isFalse);
    expect(slots.last.lastInSection, isTrue);
    expect(slots.last.indent, 0);
  });

  test('an empty selected folder explains itself and skips the main list', () {
    final slots = buildChatListFolderDirectory(
      folderIds: const [4],
      selectedFolderId: 4,
      selectedEntryCount: 0,
      selectedLoading: false,
      selectedPlaceholderCount: 6,
      hasPullDownArchiveSlot: false,
      hasFiltered: false,
      showInlineArchive: false,
      inlineArchiveIndex: -1,
    );
    expect(
      slots.where((slot) => slot.kind == ChatListDirectorySlotKind.entry),
      isEmpty,
    );
    expect(
      slots.where((slot) => slot.kind == ChatListDirectorySlotKind.empty),
      hasLength(1),
    );
    expect(slots.last.folderId, 4);
  });

  test('All keeps archive and filtered rows when it is selected', () {
    final slots = buildChatListFolderDirectory(
      folderIds: const [4],
      selectedFolderId: null,
      selectedEntryCount: 1,
      selectedLoading: false,
      selectedPlaceholderCount: 0,
      hasPullDownArchiveSlot: true,
      hasFiltered: true,
      showInlineArchive: true,
      inlineArchiveIndex: 0,
    );
    expect(slots.first.kind, ChatListDirectorySlotKind.pullDownArchive);
    expect(
      slots.where((slot) => slot.kind == ChatListDirectorySlotKind.filtered),
      hasLength(1),
    );
    expect(
      slots.where((slot) => slot.kind == ChatListDirectorySlotKind.archive),
      hasLength(1),
    );
  });

  test('local groups nest folder rows and hide them when collapsed', () {
    const group = LocalFolderGroup(
      id: 'g1',
      title: 'Focus',
      childFolderIds: [7],
    );
    final open = buildChatListFolderDirectory(
      folderIds: const [7, 8],
      selectedFolderId: 7,
      selectedEntryCount: 1,
      selectedLoading: false,
      selectedPlaceholderCount: 0,
      hasPullDownArchiveSlot: false,
      hasFiltered: false,
      showInlineArchive: false,
      inlineArchiveIndex: -1,
      groups: const [group],
    );
    expect(
      open.map((slot) => (slot.kind, slot.groupId, slot.folderId, slot.indent)),
      [
        (ChatListDirectorySlotKind.groupHeader, 'g1', null, 0.0),
        (ChatListDirectorySlotKind.folderHeader, null, 7, 16.0),
        (ChatListDirectorySlotKind.folderHeader, null, 8, 0.0),
        (ChatListDirectorySlotKind.folderHeader, null, null, 0.0),
        (ChatListDirectorySlotKind.entry, null, 7, 0.0),
      ],
    );
    expect(open[1].selected, isTrue);

    final closed = buildChatListFolderDirectory(
      folderIds: const [7, 8],
      selectedFolderId: 7,
      selectedEntryCount: 1,
      selectedLoading: false,
      selectedPlaceholderCount: 0,
      hasPullDownArchiveSlot: false,
      hasFiltered: false,
      showInlineArchive: false,
      inlineArchiveIndex: -1,
      groups: const [
        LocalFolderGroup(
          id: 'g1',
          title: 'Focus',
          childFolderIds: [7],
          expanded: false,
        ),
      ],
    );
    expect(
      closed.where(
        (slot) =>
            slot.kind == ChatListDirectorySlotKind.folderHeader &&
            slot.folderId == 7,
      ),
      isEmpty,
    );
    expect(
      closed.where(
        (slot) =>
            slot.kind == ChatListDirectorySlotKind.entry && slot.folderId == 7,
      ),
      hasLength(1),
    );
    expect(
      closed.where(
        (slot) =>
            slot.kind == ChatListDirectorySlotKind.folderHeader &&
            slot.folderId == 8,
      ),
      hasLength(1),
    );
  });

  test('scroll offset accounts for folder headers above the main list', () {
    final slots = buildChatListFolderDirectory(
      folderIds: const [1],
      selectedFolderId: null,
      selectedEntryCount: 2,
      selectedLoading: false,
      selectedPlaceholderCount: 0,
      hasPullDownArchiveSlot: false,
      hasFiltered: false,
      showInlineArchive: false,
      inlineArchiveIndex: -1,
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
    'folders in the chat list select like the side rail',
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
          {
            'id': 4,
            'title': 'Personal',
            'icon': {'name': 'Home'},
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

      final workHeader = find.byKey(const ValueKey('chat-list-folder-3'));
      final workTitle = tester.widget<Text>(
        find.descendant(of: workHeader, matching: find.text('Work')),
      );
      expect(workTitle.style?.fontSize, AppTextSize.chatListTitle());
      expect(workTitle.style?.fontWeight, FontWeight.w500);
      expect(
        find.descendant(of: workHeader, matching: find.byType(ChatFolderIcon)),
        findsNothing,
      );
      expect(
        find.descendant(of: workHeader, matching: find.byType(AppIcon)),
        findsNothing,
      );
      expect(tester.widget<ChatListFolderHeader>(workHeader).selected, isFalse);
      expect(
        tester.widget<ChatListFolderHeader>(workHeader).showsChevron,
        isFalse,
      );
      final allHeader = find.byKey(const ValueKey('chat-list-folder-all'));
      expect(tester.widget<ChatListFolderHeader>(allHeader).selected, isTrue);
      expect(
        tester.getSize(workHeader).height,
        tester
            .getSize(find.byKey(const ValueKey('chat-list-folder-chat-all-11')))
            .height,
      );

      await tester.tap(workHeader);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));

      expect(find.text('Work chat'), findsOneWidget);
      expect(find.text('Main chat'), findsNothing);
      expect(tester.widget<ChatListFolderHeader>(workHeader).selected, isTrue);
      expect(tester.widget<ChatListFolderHeader>(allHeader).selected, isFalse);
      expect(
        tester.getTopLeft(find.text('Work chat')).dy,
        greaterThan(tester.getTopLeft(allHeader).dy),
      );
      expect(find.byKey(ChatListSelectionHighlight.railKey), findsOneWidget);

      await tester.tap(workHeader);
      await tester.pump();
      expect(find.text('Work chat'), findsOneWidget);
      expect(tester.widget<ChatListFolderHeader>(workHeader).selected, isTrue);

      await tester.tap(allHeader);
      await tester.pump();
      expect(find.text('Main chat'), findsOneWidget);
      expect(find.text('Work chat'), findsNothing);
      expect(tester.widget<ChatListFolderHeader>(allHeader).selected, isTrue);

      await _secondaryClick(
        tester,
        find.byKey(const ValueKey('chat-list-folder-all')),
      );
      await tester.tap(find.text('New local group'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(find.byType(TextField), 'Focus');
      await tester.tap(find.text('Save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Focus'), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('chat-list-folder-3'))).dx,
        tester.getTopLeft(find.byKey(const ValueKey('chat-list-folder-4'))).dx,
      );

      await _secondaryClick(
        tester,
        find.byKey(const ValueKey('chat-list-folder-3')),
      );
      await tester.tap(find.textContaining('Add to'));
      await tester.pump();
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('chat-list-folder-3'))).dx,
        greaterThan(
          tester
              .getTopLeft(find.byKey(const ValueKey('chat-list-folder-4')))
              .dx,
        ),
      );

      await tester.tap(find.text('Focus'));
      await tester.pump();
      expect(find.byKey(const ValueKey('chat-list-folder-3')), findsNothing);
      expect(find.byKey(const ValueKey('chat-list-folder-4')), findsOneWidget);

      final focusHeader = find.ancestor(
        of: find.text('Focus'),
        matching: find.byType(ChatListFolderHeader),
      );
      expect(
        tester.widget<ChatListFolderHeader>(focusHeader).showsChevron,
        isTrue,
      );
      expect(
        tester
            .widget<AppIcon>(
              find.descendant(of: focusHeader, matching: find.byType(AppIcon)),
            )
            .size,
        AppIconSize.xs,
      );

      await tester.tap(find.text('Focus'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('chat-list-folder-3')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.text('Work chat'), findsOneWidget);
      expect(find.text('Main chat'), findsNothing);
      expect(
        tester.getTopLeft(find.text('Focus')).dy,
        lessThan(
          tester
              .getTopLeft(find.byKey(const ValueKey('chat-list-folder-3')))
              .dy,
        ),
      );
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('chat-list-folder-3'))).dy,
        lessThan(
          tester
              .getTopLeft(find.byKey(const ValueKey('chat-list-folder-all')))
              .dy,
        ),
      );
      expect(
        tester
            .getTopLeft(find.byKey(const ValueKey('chat-list-folder-all')))
            .dy,
        lessThan(tester.getTopLeft(find.text('Work chat')).dy),
      );

      await tester.tap(find.byKey(const ValueKey('chat-list-folder-all')));
      await tester.pump();

      await _secondaryClick(
        tester,
        find.byKey(const ValueKey('chat-list-folder-3')),
      );
      await tester.tap(find.text('Remove from local group'));
      await tester.pump();
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('chat-list-folder-3'))).dx,
        tester.getTopLeft(find.byKey(const ValueKey('chat-list-folder-4'))).dx,
      );

      await _secondaryClick(tester, find.text('Focus'));
      await tester.tap(find.text('Delete local group'));
      await tester.pump();
      await tester.tap(find.text('Delete local group'));
      await tester.pump();
      expect(find.text('Focus'), findsNothing);
      expect(find.byKey(const ValueKey('chat-list-folder-3')), findsOneWidget);
      expect(find.byType(ChatFolderRail), findsNothing);

      await _secondaryClick(
        tester,
        find.byKey(const ValueKey('chat-list-folder-4')),
      );
      await tester.tap(find.text('Move up'));
      await tester.pump();
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('chat-list-folder-4'))).dy,
        lessThan(
          tester
              .getTopLeft(find.byKey(const ValueKey('chat-list-folder-3')))
              .dy,
        ),
      );

      final personal = find.byKey(const ValueKey('chat-list-folder-4'));
      final work = find.byKey(const ValueKey('chat-list-folder-3'));
      final drag = await tester.startGesture(
        tester.getCenter(personal),
        kind: PointerDeviceKind.mouse,
      );
      await drag.moveTo(tester.getCenter(work));
      await tester.pump();
      await drag.up();
      await tester.pump();
      expect(
        tester.getTopLeft(work).dy,
        lessThan(tester.getTopLeft(personal).dy),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 6));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );
}

Future<void> _secondaryClick(WidgetTester tester, Finder target) async {
  final gesture = await tester.createGesture(
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  await gesture.down(tester.getCenter(target));
  await gesture.up();
  await tester.pump();
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
