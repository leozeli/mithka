import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chats/chat_list_view.dart';
import 'package:mithka/chats/chat_list_view_model.dart';
import 'package:mithka/chats/local_folder_group.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/components/chat_folder_icons.dart';
import 'package:mithka/l10n/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await AppStrings.ensureLoaded(const Locale('en'));
  });

  testWidgets('right click edits only custom folders without selecting them', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    int? edited;
    var selections = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 72,
            height: 300,
            child: ChatFolderRail(
              filters: const [
                ChatFilterOption(title: 'All'),
                ChatFilterOption(title: 'Work', folderId: 7),
              ],
              selectedFolderId: null,
              onSelect: (_) => selections++,
              onEdit: (folder) => edited = folder.folderId,
            ),
          ),
        ),
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey('side-folder-all')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pump();
    expect(find.text('Edit folder'), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('side-folder-7')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit folder'));
    await tester.pumpAndSettle();
    expect(edited, 7);
    expect(selections, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('group rows toggle expand and nest child folders', (
    tester,
  ) async {
    late StateSetter update;
    var group = const LocalFolderGroup(
      id: 'g1',
      title: 'Focus',
      childFolderIds: [7],
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 72,
            height: 300,
            child: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return ChatFolderRail(
                  filters: const [
                    ChatFilterOption(title: 'All'),
                    ChatFilterOption(title: 'Work', folderId: 7),
                    ChatFilterOption(title: 'Bots', folderId: 9),
                  ],
                  groups: [group],
                  selectedFolderId: null,
                  onSelect: (_) {},
                  onToggleGroup: (value) => update(
                    () => group = value.copyWith(expanded: !value.expanded),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('side-group-g1')), findsOneWidget);
    expect(find.byKey(const ValueKey('side-folder-7')), findsOneWidget);
    expect(find.byKey(const ValueKey('side-folder-9')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('side-group-g1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('side-folder-7')), findsNothing);
    expect(find.byKey(const ValueKey('side-folder-9')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('side-group-g1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('side-folder-7')), findsOneWidget);
  });

  test('folder icons map configured names and safely fall back', () {
    expect(chatFolderIcon('Work'), HeroAppIcons.briefcase);
    expect(chatFolderIcon('Private'), HeroAppIcons.circleUser);
    expect(chatFolderIcon('Game'), HeroAppIcons.puzzle);
    expect(chatFolderIcon('Unread'), HeroAppIcons.message);
    expect(chatFolderIcon('All'), HeroAppIcons.inbox);
    expect(chatFolderIcon('Custom'), HeroAppIcons.folder);
    expect(chatFolderIcon('future-icon'), HeroAppIcons.folder);
  });

  testWidgets(
    'folder rail scrolls and changes selection without moving lower navigation',
    (tester) async {
      int? selected;
      late StateSetter update;
      const navigationKey = ValueKey('fixed-navigation');
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: const MediaQueryData(),
            child: DefaultTextStyle(
              style: const TextStyle(fontSize: 11),
              child: Center(
                child: SizedBox(
                  width: 72,
                  height: 300,
                  child: StatefulBuilder(
                    builder: (context, setState) {
                      update = setState;
                      return Column(
                        children: [
                          Expanded(
                            child: ChatFolderRail(
                              filters: [
                                const ChatFilterOption(title: 'All'),
                                for (var i = 0; i < 12; i++)
                                  ChatFilterOption(
                                    title: 'Folder $i',
                                    folderId: i,
                                    iconName: 'Work',
                                  ),
                              ],
                              selectedFolderId: selected,
                              onSelect: (folder) =>
                                  update(() => selected = folder.folderId),
                            ),
                          ),
                          const SizedBox(key: navigationKey, height: 64),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final navigationRect = tester.getRect(find.byKey(navigationKey));
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('side-folder-10')),
        120,
        scrollable: find.byType(Scrollable),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('side-folder-10')));
      await tester.pumpAndSettle();
      expect(selected, 10);
      final folderIcon = tester.widget<AppIcon>(
        find.descendant(
          of: find.byKey(const ValueKey('side-folder-10')),
          matching: find.byType(AppIcon),
        ),
      );
      expect(folderIcon.icon, HeroAppIcons.briefcase);
      expect(tester.getRect(find.byKey(navigationKey)), navigationRect);
      expect(tester.takeException(), isNull);
    },
  );
}
