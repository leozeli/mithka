import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
          'getConnectionState' => {'@type': 'connectionStateReady'},
          'getChats' => {
            '@type': 'chats',
            'chat_ids': [for (var id = 1; id <= 24; id++) 1000 + id],
          },
          'getChat' => _chat(request['chat_id'] as int),
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

  testWidgets('scroll-to-top button labels itself and handles a tap', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [AppLocalizations.delegate],
        theme: ThemeData(extensions: [AppColors.light]),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomRight,
            child: ChatListScrollToTopButton(onTap: () => taps++),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(ChatListScrollToTopButton.buttonKey), findsOneWidget);
    expect(find.byTooltip('Scroll to top'), findsOneWidget);
    expect(find.bySemanticsLabel('Scroll to top'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(ChatListScrollToTopButton.buttonKey)),
      const Size(40, 40),
    );

    await tester.tap(find.byKey(ChatListScrollToTopButton.buttonKey));
    expect(taps, 1);
  });

  testWidgets(
    'chat list shows the control after scrolling and returns to the top',
    (tester) async {
      SharedPreferences.setMockInitialValues({'communitiesEnabled': false});
      final theme = ThemeController(await SharedPreferences.getInstance());
      addTearDown(theme.dispose);
      await tester.binding.setSurfaceSize(const Size(900, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: theme,
          child: MaterialApp(
            locale: const Locale('en'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [AppLocalizations.delegate],
            theme: ThemeData(extensions: [AppColors.light]),
            home: const Scaffold(
              body: SizedBox(
                width: 360,
                height: 280,
                child: ChatListView(desktopSidebar: true),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));

      expect(find.text('Chat 1024'), findsOneWidget);
      expect(find.byKey(ChatListScrollToTopButton.buttonKey), findsNothing);
      expect(find.bySemanticsLabel('Scroll to top'), findsNothing);

      await tester.drag(find.byType(ListView), const Offset(0, -420));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final pixelsBeforeReturn = _listPosition(tester).pixels;
      expect(pixelsBeforeReturn, greaterThan(chatListScrollToTopThreshold));
      expect(find.byKey(ChatListScrollToTopButton.buttonKey), findsOneWidget);
      expect(find.bySemanticsLabel('Scroll to top'), findsOneWidget);

      await tester.tap(find.byKey(ChatListScrollToTopButton.buttonKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(_listPosition(tester).pixels, lessThan(pixelsBeforeReturn));

      await tester.pumpAndSettle();
      expect(_listPosition(tester).pixels, closeTo(0, 0.5));
      expect(find.byKey(ChatListScrollToTopButton.buttonKey), findsNothing);
      expect(find.bySemanticsLabel('Scroll to top'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 6));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );
}

ScrollPosition _listPosition(WidgetTester tester) {
  final states = tester.stateList<ScrollableState>(find.byType(Scrollable));
  return states
      .map((state) => state.position)
      .firstWhere((position) => position.maxScrollExtent > 100);
}

Map<String, dynamic> _chat(int id) => {
  '@type': 'chat',
  'id': id,
  'title': 'Chat $id',
  'type': {'@type': 'chatTypePrivate', 'user_id': id},
  'last_message': {
    '@type': 'message',
    'id': id,
    'chat_id': id,
    'date': id,
    'is_outgoing': false,
    'content': {
      '@type': 'messageText',
      'text': {
        '@type': 'formattedText',
        'text': 'Hello $id',
        'entities': <Object>[],
      },
    },
  },
  'positions': [
    {
      '@type': 'chatPosition',
      'list': {'@type': 'chatListMain'},
      'order': id,
      'is_pinned': false,
    },
  ],
};
