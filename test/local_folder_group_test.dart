import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chats/local_folder_group.dart';
import 'package:mithka/chats/local_folder_group_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  test('json keeps expansion and ignores duplicate children', () {
    final group = LocalFolderGroup.fromJson({
      'id': 'g1',
      'title': 'Focus',
      'childFolderIds': [7, '7', 3, 'nope'],
      'expanded': false,
    });
    expect(group, isNotNull);
    expect(group!.childFolderIds, [7, 3]);
    expect(group.expanded, isFalse);
    expect(LocalFolderGroup.fromJson(group.toJson()), group);
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
      expect(store.groupFor(b.id)?.expanded, isTrue);
    });

    test('rename and delete keep folders off the deleted group', () async {
      final store = LocalFolderGroupStore(persist: false);
      await store.bind(slot: 0, userId: 1);
      final group = await store.create(title: 'Focus', childFolderIds: [4]);
      expect(await store.rename(group!.id, 'Later'), isTrue);
      expect(store.groups.single.title, 'Later');
      expect(await store.delete(group.id), isTrue);
      expect(store.groups, isEmpty);
      expect(store.groupContaining(4), isNull);
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

    test(
      'reorders groups and folders locally without touching peers',
      () async {
        SharedPreferences.setMockInitialValues({});
        final store = LocalFolderGroupStore();
        await store.bind(slot: 1, userId: 11);
        final first = await store.create(
          title: 'A',
          childFolderIds: const [7, 3],
        );
        final second = await store.create(title: 'B');
        expect(await store.moveGroupBy(second!.id, -1), isTrue);
        expect(store.groups.map((group) => group.title), ['B', 'A']);
        expect(store.canMoveGroup(second.id, -1), isFalse);
        expect(await store.moveFolderBy(3, -1, const [7, 3, 9, 4]), isTrue);
        expect(store.groupFor(first!.id)?.childFolderIds, [3, 7]);
        expect(await store.moveFolderBy(4, -1, const [7, 3, 9, 4]), isTrue);
        expect(store.ungroupedDisplayOrder(const [7, 3, 9, 4]), [4, 9]);
        expect(store.directoryFolderIds(const [7, 3, 9, 4]), [4, 9, 3, 7]);
        expect(await store.moveGroupTo(first.id, 0), isTrue);
        expect(store.groups.map((group) => group.title), ['A', 'B']);
        expect(await store.moveGroupTo(first.id, 0), isFalse);
        expect(await store.moveFolderTo(7, 3, const [7, 3, 9, 4]), isTrue);
        expect(store.groupFor(first.id)?.childFolderIds, [7, 3]);
        expect(await store.moveFolderTo(7, 9, const [7, 3, 9, 4]), isFalse);
        expect(await store.moveFolderTo(9, 4, const [7, 3, 9, 4]), isTrue);
        expect(store.ungroupedDisplayOrder(const [7, 3, 9, 4]), [9, 4]);

        final reloaded = LocalFolderGroupStore();
        expect(await reloaded.bind(slot: 1, userId: 11), isTrue);
        expect(reloaded.groups.map((group) => group.title), ['A', 'B']);
        expect(reloaded.groupFor(first.id)?.childFolderIds, [7, 3]);
        expect(reloaded.ungroupedDisplayOrder(const [7, 3, 9, 4, 5]), [
          9,
          4,
          5,
        ]);
      },
    );

    test('an older group list still loads', () async {
      SharedPreferences.setMockInitialValues({
        LocalFolderGroupStore.storageKeyForUser(
          4,
        ): '[{"id":"g1","title":"Focus","iconName":"Custom","childFolderIds":[7],"expanded":true}]',
      });
      final store = LocalFolderGroupStore();
      expect(await store.bind(slot: 0, userId: 4), isTrue);
      expect(store.groups.single.childFolderIds, [7]);
      expect(store.ungroupedDisplayOrder(const [7, 8]), [8]);
    });

    test('orphaned ids are pruned and the empty group remains', () async {
      final store = LocalFolderGroupStore(
        persist: false,
        initialGroups: const [
          LocalFolderGroup(id: 'g1', title: 'Focus', childFolderIds: [7, 8, 9]),
        ],
      );
      await store.bind(slot: 0, userId: 1);
      expect(await store.pruneMissing({7, 9}), isTrue);
      expect(store.groups.single.childFolderIds, [7, 9]);
      expect(await store.pruneMissing({}), isTrue);
      expect(store.groups.single.childFolderIds, isEmpty);
      expect(store.groups.single.title, 'Focus');
    });
  });
}
