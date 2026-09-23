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
       );

  static const softCap = 40;

  final SharedPreferences? _preferences;

  /// When false, groups stay in memory. Tests use this to skip preferences.
  final bool persist;

  final List<LocalFolderGroup> _groups;
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
      final previous = List<LocalFolderGroup>.of(_groups);
      if (!persist) {
        _slot = slot;
        _userId = userId;
        return false;
      }
      if (userId == null) {
        if (slot != _slot) {
          _groups.clear();
          _dirty = false;
        }
        _slot = slot;
        _userId = null;
        return !_sameGroups(previous, _groups);
      }
      _slot = slot;
      _userId = userId;
      try {
        final prefs = await _prefs();
        final stored = _read(prefs, userId);
        if (_dirty) {
          _replace(_mergeFront(_groups, stored));
          _dirty = false;
          await _write(prefs, userId);
        } else {
          _replace(stored);
        }
      } catch (_) {
        return false;
      }
      final changed = !_sameGroups(previous, _groups);
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
      if (_sameGroups(_groups, pruned)) return false;
      _replace(pruned);
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

  List<LocalFolderGroup> _read(SharedPreferences prefs, int userId) {
    final raw = prefs.getString(storageKeyForUser(userId));
    if (raw == null || raw.isEmpty) return const <LocalFolderGroup>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <LocalFolderGroup>[];
      final groups = <LocalFolderGroup>[];
      for (final entry in decoded) {
        final group = LocalFolderGroup.fromJson(entry);
        if (group == null) continue;
        groups.add(group);
        if (groups.length >= softCap) break;
      }
      return groups;
    } catch (_) {
      return const <LocalFolderGroup>[];
    }
  }

  Future<void> _write(SharedPreferences prefs, int userId) {
    return prefs.setString(
      storageKeyForUser(userId),
      jsonEncode([for (final group in _groups) group.toJson()]),
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
}
