//
//  local_folder_group_store.dart
//
//  Device-local folder groups for the message list. Telegram folders stay
//  flat; these parents only nest them in the chat list on this device.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_folder_group.dart';

/// Persisted local folder groups for one Telegram account.
///
/// Identity is the account's user id, same as local chat pins.
class LocalFolderGroupStore extends ChangeNotifier {
  LocalFolderGroupStore({
    this._preferences,
    List<LocalFolderGroup>? initialGroups,
    this.persist = true,
  }) : _groups = List<LocalFolderGroup>.of(
         initialGroups ?? const <LocalFolderGroup>[],
       ),
       _ungroupedFolderIds = <int>[];

  static const softCap = 40;

  final SharedPreferences? _preferences;

  /// When false, groups stay in memory. Tests use this to skip preferences.
  final bool persist;

  final List<LocalFolderGroup> _groups;

  /// Local display order for Telegram folders that are not inside a group.
  /// Missing ids keep Telegram's order after these.
  final List<int> _ungroupedFolderIds;
  int _slot = 0;
  int? _userId;
  bool _dirty = false;
  Future<void> _queue = Future<void>.value();

  int? get userId => _userId;
  int get slot => _slot;

  List<LocalFolderGroup> get groups =>
      List<LocalFolderGroup>.unmodifiable(_groups);

  LocalFolderGroup? groupFor(String id) {
    for (final group in _groups) {
      if (group.id == id) return group;
    }
    return null;
  }

  /// The group that currently contains [folderId], if any.
  LocalFolderGroup? groupContaining(int folderId) {
    for (final group in _groups) {
      if (group.childFolderIds.contains(folderId)) return group;
    }
    return null;
  }

  static String storageKeyForUser(int userId) =>
      'mithka.localFolderGroups.user.$userId';

  /// Loads the account's groups. In-memory edits made before [userId] was known
  /// are kept ahead of the stored list.
  Future<bool> bind({required int slot, int? userId}) {
    return _serialized(() async {
      final previousGroups = List<LocalFolderGroup>.of(_groups);
      final previousOrder = List<int>.of(_ungroupedFolderIds);
      if (!persist) {
        _slot = slot;
        _userId = userId;
        return false;
      }
      if (userId == null) {
        if (slot != _slot) {
          _groups.clear();
          _ungroupedFolderIds.clear();
          _dirty = false;
        }
        _slot = slot;
        _userId = null;
        return !_sameSnapshot(previousGroups, previousOrder);
      }
      _slot = slot;
      _userId = userId;
      try {
        final prefs = await _prefs();
        final stored = _read(prefs, userId);
        if (_dirty) {
          _replace(_mergeFront(_groups, stored.groups));
          _setUngroupedOrder(
            _mergeIdFront(_ungroupedFolderIds, stored.ungroupedFolderIds),
          );
          _dirty = false;
          await _write(prefs, userId);
        } else {
          _replace(stored.groups);
          _setUngroupedOrder(stored.ungroupedFolderIds);
        }
      } catch (_) {
        return false;
      }
      final changed = !_sameSnapshot(previousGroups, previousOrder);
      if (changed) notifyListeners();
      return changed;
    });
  }

  Future<LocalFolderGroup?> create({
    required String title,
    String iconName = 'Custom',
    List<int> childFolderIds = const <int>[],
    bool expanded = true,
  }) {
    return _serialized(() async {
      final trimmed = title.trim();
      if (trimmed.isEmpty || _groups.length >= softCap) return null;
      final children = <int>[];
      for (final id in childFolderIds) {
        if (children.contains(id)) continue;
        children.add(id);
      }
      // A folder can only live in one group.
      for (var i = 0; i < _groups.length; i++) {
        final group = _groups[i];
        final remaining = [
          for (final id in group.childFolderIds)
            if (!children.contains(id)) id,
        ];
        if (remaining.length != group.childFolderIds.length) {
          _groups[i] = group.copyWith(childFolderIds: remaining);
        }
      }
      final created = LocalFolderGroup(
        id: 'g-${DateTime.now().microsecondsSinceEpoch}',
        title: trimmed,
        iconName: iconName,
        childFolderIds: children,
        expanded: expanded,
      );
      _groups.add(created);
      await _persist();
      notifyListeners();
      return created;
    });
  }

  Future<bool> rename(String id, String title) {
    return _serialized(() async {
      final trimmed = title.trim();
      if (trimmed.isEmpty) return false;
      final index = _indexOf(id);
      if (index < 0) return false;
      if (_groups[index].title == trimmed) return true;
      _groups[index] = _groups[index].copyWith(title: trimmed);
      await _persist();
      notifyListeners();
      return true;
    });
  }

  Future<bool> delete(String id) {
    return _serialized(() async {
      final index = _indexOf(id);
      if (index < 0) return false;
      _groups.removeAt(index);
      await _persist();
      notifyListeners();
      return true;
    });
  }

  Future<bool> setExpanded(String id, bool expanded) {
    return _serialized(() async {
      final index = _indexOf(id);
      if (index < 0) return false;
      if (_groups[index].expanded == expanded) return true;
      _groups[index] = _groups[index].copyWith(expanded: expanded);
      await _persist();
      notifyListeners();
      return true;
    });
  }

  Future<bool> toggleExpanded(String id) {
    final group = groupFor(id);
    if (group == null) return Future.value(false);
    return setExpanded(id, !group.expanded);
  }

  /// Moves [folderId] into [groupId], removing it from any other group.
  Future<bool> addFolder(String groupId, int folderId) {
    return _serialized(() async {
      final index = _indexOf(groupId);
      if (index < 0) return false;
      for (var i = 0; i < _groups.length; i++) {
        final group = _groups[i];
        if (!group.childFolderIds.contains(folderId)) continue;
        if (i == index) return true;
        _groups[i] = group.copyWith(
          childFolderIds: [
            for (final id in group.childFolderIds)
              if (id != folderId) id,
          ],
        );
      }
      final target = _groups[index];
      _groups[index] = target.copyWith(
        childFolderIds: [...target.childFolderIds, folderId],
        expanded: true,
      );
      await _persist();
      notifyListeners();
      return true;
    });
  }

  Future<bool> removeFolder(int folderId) {
    return _serialized(() async {
      var changed = false;
      for (var i = 0; i < _groups.length; i++) {
        final group = _groups[i];
        if (!group.childFolderIds.contains(folderId)) continue;
        _groups[i] = group.copyWith(
          childFolderIds: [
            for (final id in group.childFolderIds)
              if (id != folderId) id,
          ],
        );
        changed = true;
      }
      if (!changed) return false;
      await _persist();
      notifyListeners();
      return true;
    });
  }

  /// Drops folder ids that no longer exist in Telegram's folder list.
  Future<bool> pruneMissing(Set<int> existingFolderIds) {
    return _serialized(() async {
      final pruned = pruneLocalFolderGroups(_groups, existingFolderIds);
      final order = [
        for (final id in _ungroupedFolderIds)
          if (existingFolderIds.contains(id)) id,
      ];
      if (_sameGroups(_groups, pruned) &&
          listEquals(_ungroupedFolderIds, order)) {
        return false;
      }
      _replace(pruned);
      _setUngroupedOrder(order);
      await _persist();
      notifyListeners();
      return true;
    });
  }

  /// Telegram folder ids in the order the message list should draw them.
  /// Ungrouped folders use the saved display order; grouped ids stay in the
  /// list so membership checks still see them.
  List<int> directoryFolderIds(List<int> telegramFolderIds) {
    final ungrouped = ungroupedDisplayOrder(telegramFolderIds);
    final known = telegramFolderIds.toSet();
    final grouped = <int>[];
    final seen = <int>{};
    for (final group in _groups) {
      for (final id in group.childFolderIds) {
        if (!known.contains(id) || !seen.add(id)) continue;
        grouped.add(id);
      }
    }
    return [...ungrouped, ...grouped];
  }

  /// Ungrouped folders: saved order first, then any new Telegram folders in
  /// their server order.
  List<int> ungroupedDisplayOrder(List<int> telegramFolderIds) {
    final grouped = <int>{for (final group in _groups) ...group.childFolderIds};
    final visible = [
      for (final id in telegramFolderIds)
        if (!grouped.contains(id)) id,
    ];
    return _applySavedOrder(visible, _ungroupedFolderIds);
  }

  bool canMoveGroup(String id, int delta) {
    final index = _indexOf(id);
    if (index < 0 || delta == 0) return false;
    final next = index + delta;
    return next >= 0 && next < _groups.length;
  }

  bool canMoveFolder(int folderId, int delta, List<int> telegramFolderIds) {
    if (delta == 0) return false;
    final group = groupContaining(folderId);
    final order = group == null
        ? ungroupedDisplayOrder(telegramFolderIds)
        : group.childFolderIds;
    final index = order.indexOf(folderId);
    if (index < 0) return false;
    final next = index + delta;
    return next >= 0 && next < order.length;
  }

  /// Moves a local group among its siblings. Negative [delta] moves it up.
  Future<bool> moveGroupBy(String id, int delta) {
    return _serialized(() async {
      final index = _indexOf(id);
      if (index < 0 || delta == 0) return false;
      final next = index + delta;
      if (next < 0 || next >= _groups.length) return false;
      final group = _groups.removeAt(index);
      _groups.insert(next, group);
      await _persist();
      notifyListeners();
      return true;
    });
  }

  /// Moves a Telegram folder among the siblings of its current section.
  ///
  /// Inside a group that is the group's saved child order. Outside a group it
  /// is the local ungrouped order. Telegram's own folder order is left alone.
  Future<bool> moveFolderBy(
    int folderId,
    int delta,
    List<int> telegramFolderIds,
  ) {
    return _serialized(() async {
      if (delta == 0) return false;
      final group = groupContaining(folderId);
      if (group != null) {
        final index = _indexOf(group.id);
        if (index < 0) return false;
        final children = List<int>.of(_groups[index].childFolderIds);
        if (!_shift(children, folderId, delta)) return false;
        _groups[index] = _groups[index].copyWith(childFolderIds: children);
      } else {
        final order = ungroupedDisplayOrder(telegramFolderIds);
        if (!_shift(order, folderId, delta)) return false;
        _setUngroupedOrder(order);
      }
      await _persist();
      notifyListeners();
      return true;
    });
  }

  /// Ensures the group that owns [folderId] is expanded so its section shows.
  Future<void> expandGroupContaining(int folderId) async {
    final group = groupContaining(folderId);
    if (group == null || group.expanded) return;
    await setExpanded(group.id, true);
  }

  Future<T> _serialized<T>(Future<T> Function() action) {
    final run = _queue.then((_) => action());
    _queue = run.then((_) {}, onError: (_) {});
    return run;
  }

  Future<void> _persist() async {
    if (!persist) return;
    final userId = _userId;
    if (userId == null) {
      _dirty = true;
      return;
    }
    _dirty = false;
    try {
      final prefs = await _prefs();
      await _write(prefs, userId);
    } catch (_) {
      _dirty = true;
    }
  }

  Future<SharedPreferences> _prefs() async =>
      _preferences ?? await SharedPreferences.getInstance();

  _FolderGroupSnapshot _read(SharedPreferences prefs, int userId) {
    final raw = prefs.getString(storageKeyForUser(userId));
    if (raw == null || raw.isEmpty) return _FolderGroupSnapshot.empty;
    try {
      return _decodeSnapshot(jsonDecode(raw));
    } catch (_) {
      return _FolderGroupSnapshot.empty;
    }
  }

  Future<void> _write(SharedPreferences prefs, int userId) {
    return prefs.setString(
      storageKeyForUser(userId),
      jsonEncode({
        'groups': [for (final group in _groups) group.toJson()],
        'ungroupedFolderIds': _ungroupedFolderIds,
      }),
    );
  }

  void _replace(List<LocalFolderGroup> groups) {
    _groups
      ..clear()
      ..addAll(groups);
  }

  List<LocalFolderGroup> _mergeFront(
    List<LocalFolderGroup> preferred,
    List<LocalFolderGroup> extra,
  ) {
    final merged = <LocalFolderGroup>[];
    final seen = <String>{};
    for (final group in [...preferred, ...extra]) {
      if (!seen.add(group.id)) continue;
      merged.add(group);
      if (merged.length >= softCap) break;
    }
    return merged;
  }

  int _indexOf(String id) {
    for (var i = 0; i < _groups.length; i++) {
      if (_groups[i].id == id) return i;
    }
    return -1;
  }

  bool _sameGroups(List<LocalFolderGroup> a, List<LocalFolderGroup> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  bool _sameSnapshot(List<LocalFolderGroup> groups, List<int> order) =>
      _sameGroups(groups, _groups) && listEquals(order, _ungroupedFolderIds);

  void _setUngroupedOrder(List<int> ids) {
    _ungroupedFolderIds
      ..clear()
      ..addAll(ids);
  }

  List<int> _mergeIdFront(List<int> preferred, List<int> extra) {
    final merged = <int>[];
    for (final id in [...preferred, ...extra]) {
      if (merged.contains(id)) continue;
      merged.add(id);
    }
    return merged;
  }

  List<int> _applySavedOrder(List<int> visible, List<int> saved) {
    final remaining = visible.toSet();
    final ordered = <int>[];
    for (final id in saved) {
      if (remaining.remove(id)) ordered.add(id);
    }
    for (final id in visible) {
      if (remaining.remove(id)) ordered.add(id);
    }
    return ordered;
  }

  bool _shift(List<int> ids, int id, int delta) {
    final index = ids.indexOf(id);
    if (index < 0) return false;
    final next = index + delta;
    if (next < 0 || next >= ids.length) return false;
    final moved = ids.removeAt(index);
    ids.insert(next, moved);
    return true;
  }
}

class _FolderGroupSnapshot {
  const _FolderGroupSnapshot(this.groups, this.ungroupedFolderIds);

  static const empty = _FolderGroupSnapshot(<LocalFolderGroup>[], <int>[]);

  final List<LocalFolderGroup> groups;
  final List<int> ungroupedFolderIds;
}

_FolderGroupSnapshot _decodeSnapshot(Object? decoded) {
  if (decoded is List) {
    return _FolderGroupSnapshot(_decodeGroups(decoded), const <int>[]);
  }
  if (decoded is! Map) return _FolderGroupSnapshot.empty;
  final map = Map<String, dynamic>.from(decoded);
  final groups = map['groups'];
  return _FolderGroupSnapshot(
    groups is List ? _decodeGroups(groups) : const <LocalFolderGroup>[],
    _decodeIds(map['ungroupedFolderIds']),
  );
}

List<LocalFolderGroup> _decodeGroups(List<dynamic> raw) {
  final groups = <LocalFolderGroup>[];
  for (final entry in raw) {
    final group = LocalFolderGroup.fromJson(entry);
    if (group == null) continue;
    groups.add(group);
    if (groups.length >= LocalFolderGroupStore.softCap) break;
  }
  return groups;
}

List<int> _decodeIds(Object? raw) {
  if (raw is! List) return const <int>[];
  final ids = <int>[];
  for (final entry in raw) {
    final id = switch (entry) {
      final int value => value,
      final String value => int.tryParse(value),
      _ => null,
    };
    if (id == null || ids.contains(id)) continue;
    ids.add(id);
  }
  return ids;
}
