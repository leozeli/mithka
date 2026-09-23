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
