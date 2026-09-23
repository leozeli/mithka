import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chats/chat_list_view_model.dart';
import 'package:mithka/chats/local_folder_group.dart';
import 'package:mithka/chats/local_folder_group_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalFolderGroup projection', () {
    const all = ChatFilterOption(title: 'All');
    const work = ChatFilterOption(title: 'Work', folderId: 7);
    const personal = ChatFilterOption(title: 'Personal', folderId: 3);
    const bots = ChatFilterOption(title: 'Bots', folderId: 9);

    test('nests expanded children and keeps ungrouped folders top-level', () {
      const group = LocalFolderGroup(
        id: 'g1',
        title: 'Focus',
        childFolderIds: [7, 99, 3],
      );
      final entries = buildChatFolderRailEntries(
        filters: const [all, work, personal, bots],
        groups: const [group],
      );
      expect(
        entries
            .map((e) => e.isGroup ? e.group!.id : e.filter!.folderId)
            .toList(),
        [null, 'g1', 7, 3, 9],
      );
      expect(entries[2].nested, isTrue);
      expect(entries[3].nested, isTrue);
      expect(entries[4].nested, isFalse);
    });

    test('hides children when a group is collapsed', () {
      const group = LocalFolderGroup(
        id: 'g1',
        title: 'Focus',
        childFolderIds: [7],
        expanded: false,
      );
      final entries = buildChatFolderRailEntries(
        filters: const [all, work, bots],
        groups: const [group],
      );
      expect(
        entries
            .map((e) => e.isGroup ? e.group!.id : e.filter!.folderId)
            .toList(),
        [null, 'g1', 9],
      );
    });

    test('flatten keeps All then group children then ungrouped', () {
      const group = LocalFolderGroup(
        id: 'g1',
        title: 'Focus',
        childFolderIds: [3, 7],
      );
      final flat = flattenChatFiltersForDisplay(
        filters: const [all, work, personal, bots],
        groups: const [group],
      );
      expect([for (final f in flat) f.folderId], [null, 3, 7, 9]);
    });

    test('prune drops deleted folder ids without removing the group', () {
      const group = LocalFolderGroup(
        id: 'g1',
        title: 'Focus',
        childFolderIds: [7, 3, 9],
      );
      final pruned = pruneLocalFolderGroups(const [group], {7});
      expect(pruned.single.childFolderIds, [7]);
      expect(pruned.single.id, 'g1');
    });
  });

  group('LocalFolderGroupStore', () {
    test('persists per user and stays off other accounts', () async {
      SharedPreferences.setMockInitialValues({});
      final store = LocalFolderGroupStore();
      await store.bind(slot: 1, userId: 11);
      final created = await store.create(
        title: 'Focus',
        childFolderIds: const [7, 3],
      );
      expect(created, isNotNull);
      expect(store.groups.single.title, 'Focus');

      final reloaded = LocalFolderGroupStore();
      expect(await reloaded.bind(slot: 2, userId: 11), isTrue);
      expect(reloaded.groups.single.childFolderIds, [7, 3]);

      final other = LocalFolderGroupStore();
      expect(await other.bind(slot: 1, userId: 22), isFalse);
      expect(other.groups, isEmpty);

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(LocalFolderGroupStore.storageKeyForUser(11)),
        isNotNull,
      );
      expect(
        prefs.getString(LocalFolderGroupStore.storageKeyForUser(22)),
        isNull,
      );
    });

    test('moving a folder between groups keeps a single membership', () async {
      final store = LocalFolderGroupStore(persist: false);
      await store.bind(slot: 0, userId: 1);
      final a = await store.create(title: 'A', childFolderIds: const [7]);
      final b = await store.create(title: 'B');
      expect(a, isNotNull);
      expect(b, isNotNull);
      expect(await store.addFolder(b!.id, 7), isTrue);
      expect(store.groupContaining(7)?.id, b.id);
      expect(store.groupFor(a!.id)?.childFolderIds, isEmpty);
    });

    test('edits before user id bind are saved onto that account', () async {
      SharedPreferences.setMockInitialValues({});
      final store = LocalFolderGroupStore();
      await store.bind(slot: 1);
      await store.create(title: 'Draft');
      expect(await store.bind(slot: 1, userId: 55), isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(LocalFolderGroupStore.storageKeyForUser(55)),
        contains('Draft'),
      );
    });

    test('orphaned ids are pruned without breaking the rail order', () async {
      final store = LocalFolderGroupStore(
        persist: false,
        initialGroups: const [
          LocalFolderGroup(id: 'g1', title: 'Focus', childFolderIds: [7, 8, 9]),
        ],
      );
      await store.bind(slot: 0, userId: 1);
      expect(await store.pruneMissing({7, 9}), isTrue);
      expect(store.groups.single.childFolderIds, [7, 9]);
    });
  });
}
