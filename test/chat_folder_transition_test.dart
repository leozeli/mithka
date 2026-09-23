import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chats/chat_list_folder_directory.dart';
import 'package:mithka/chats/chat_list_view.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final updates = StreamController<Map<String, dynamic>>.broadcast();
  setUpAll(() {
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
  });
  tearDownAll(() async {
    await TdClient.shared.closeProxy();
    await updates.close();
  });

  testWidgets(
    'folders expand in the list and the outer rail stays empty',
    (tester) async {
      await _pumpFolders(tester, updates);
      final controller = tester
          .widget<ChatListView>(find.byType(ChatListView))
          .controller!;
      expect(find.byType(ChatFolderRail), findsNothing);
      expect(controller.sideFolders.value, isNull);
      expect(_header(tester, null).expanded, isTrue);
      expect(_header(tester, 1).expanded, isFalse);

      await tester.tap(find.byKey(const ValueKey('chat-list-folder-1')));
      await tester.pump();
      expect(_header(tester, 1).expanded, isTrue);
      expect(_header(tester, null).expanded, isTrue);
      expect(
        tester
            .widget<ChatListFolderPanes>(find.byType(ChatListFolderPanes))
            .peek,
        isNull,
      );

      await tester.tap(find.byKey(const ValueKey('chat-list-folder-1')));
      await tester.pump();
      expect(_header(tester, 1).expanded, isFalse);
      await _disposeFolders(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets(
    'reduced motion still expands a folder section in place',
    (tester) async {
      await _pumpFolders(tester, updates, reducedMotion: true);
      await tester.tap(find.byKey(const ValueKey('chat-list-folder-1')));
      await tester.pump();
      expect(_header(tester, 1).expanded, isTrue);
      expect(
        tester
            .widget<ChatListFolderPanes>(find.byType(ChatListFolderPanes))
            .peek,
        isNull,
      );
      await _disposeFolders(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets(
    'a horizontal drag does not page away from the folder list',
    (tester) async {
      await _pumpFolders(tester, updates);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(ChatListFolderPanes)),
      );
      await gesture.moveBy(const Offset(-30, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(-100, 0));
      await tester.pump();
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(_header(tester, null).expanded, isTrue);
      expect(_header(tester, 1).expanded, isFalse);
      expect(find.byType(ChatFolderRail), findsNothing);
      await _disposeFolders(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}

ChatListFolderHeader _header(WidgetTester tester, int? folderId) {
  return tester.widget<ChatListFolderHeader>(
    find.byKey(ValueKey('chat-list-folder-${folderId ?? 'all'}')),
  );
}

Future<void> _pumpFolders(
  WidgetTester tester,
  StreamController<Map<String, dynamic>> updates, {
  bool reducedMotion = false,
}) async {
  SharedPreferences.setMockInitialValues({'communitiesEnabled': false});
  final theme = ThemeController(await SharedPreferences.getInstance());
  theme.chatListSwipeMode = ChatListSwipeMode.switchFolders;
  final controller = ChatListController();
  addTearDown(theme.dispose);
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: theme,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(extensions: [AppColors.light]),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: reducedMotion),
          child: child!,
        ),
        home: Scaffold(
          body: Row(
            children: [
              SizedBox(
                width: 90,
                height: 210,
                child: ValueListenableBuilder<Widget?>(
                  valueListenable: controller.sideFolders,
                  builder: (_, child, _) => child ?? const SizedBox.shrink(),
                ),
              ),
              Expanded(
                child: ChatListView(
                  controller: controller,
                  desktopSidebar: true,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  updates.add({
    '@type': 'updateChatFolders',
    'chat_folders': [
      for (var id = 1; id <= 8; id++) {'id': id, 'title': 'Folder $id'},
    ],
  });
  await tester.pump();
  await tester.pumpAndSettle();
}

Future<void> _disposeFolders(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 6));
}
