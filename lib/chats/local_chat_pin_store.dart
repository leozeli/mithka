//
//  local_chat_pin_store.dart
//
//  Device-local chat pins. These float chats to the top of the main list on
//  this device only. They are never sent to TDLib and do not count against
//  Telegram's pin quota.
//

import 'package:shared_preferences/shared_preferences.dart';

import '../tdlib/td_models.dart';

/// Persisted, ordered local pins for one Telegram account.
///
/// Identity is the account's user id, so pins survive a restart and stay on
/// this device. A slot is only used to drop unsaved pins if the active slot
/// changes before that user id is known. The list is newest-pin first.
class LocalChatPinStore {
  LocalChatPinStore({
    this._preferences,
    List<int>? initialIds,
    this.persist = true,
  }) : _ids = List<int>.of(initialIds ?? const <int>[]);

  /// High ceiling so a person can pin far past Telegram's server limit.
  /// `chatListLocalPinLimit` names this number in every locale.
  static const softCap = 100;

  final SharedPreferences? _preferences;

  /// When false, pins stay in memory. Tests use this to skip preferences.
  final bool persist;

  final List<int> _ids;
  int _slot = 0;
  int? _userId;
  bool _dirty = false;
  Future<void> _queue = Future<void>.value();

  int? get userId => _userId;
  int get slot => _slot;

  /// Newest local pin first. Index 0 is the top of the chat list.
  List<int> get orderedIds => List<int>.unmodifiable(_ids);

  bool isPinned(int chatId) => _ids.contains(chatId);

  /// Zero-based position among local pins, or -1 when [chatId] is not pinned.
  int rankOf(int chatId) => _ids.indexOf(chatId);

  static String storageKeyForUser(int userId) =>
      'mithka.localChatPins.user.$userId';

  /// Loads the account's pins. In-memory pins made before [userId] was known
  /// are kept in front of the stored list.
  Future<bool> bind({required int slot, int? userId}) {
    return _serialized(() async {
      final previous = List<int>.of(_ids);
      if (!persist) {
        _slot = slot;
        _userId = userId;
        return false;
      }
      if (userId == null) {
        if (slot != _slot) {
          _ids.clear();
          _dirty = false;
        }
        _slot = slot;
        _userId = null;
        return !_sameIds(previous, _ids);
      }
      _slot = slot;
      _userId = userId;
      try {
        final prefs = await _prefs();
        final stored = _read(prefs, userId);
        if (_dirty) {
          _replace(_mergeFront(_ids, stored));
          _dirty = false;
          await _write(prefs, userId);
        } else {
          _replace(stored);
        }
      } catch (_) {
        return false;
      }
      return !_sameIds(previous, _ids);
    });
  }

  /// Pins [chatId] at the top. Returns false when the soft cap is already full.
  /// An id that is already pinned stays where it is.
  Future<bool> pin(int chatId) {
    return _serialized(() async {
      if (_ids.contains(chatId)) return true;
      if (_ids.length >= softCap) return false;
      _ids.insert(0, chatId);
      await _persist();
      return true;
    });
  }

  Future<void> unpin(int chatId) {
    return _serialized(() async {
      if (!_ids.remove(chatId)) return;
      await _persist();
    });
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

  List<int> _read(SharedPreferences prefs, int userId) {
    final raw = prefs.getStringList(storageKeyForUser(userId));
    if (raw == null) return const <int>[];
    final ids = <int>[];
    for (final entry in raw) {
      final id = int.tryParse(entry);
      if (id == null || ids.contains(id)) continue;
      ids.add(id);
      if (ids.length >= softCap) break;
    }
    return ids;
  }

  Future<void> _write(SharedPreferences prefs, int userId) {
    return prefs.setStringList(storageKeyForUser(userId), [
      for (final id in _ids) '$id',
    ]);
  }

  void _replace(List<int> ids) {
    _ids
      ..clear()
      ..addAll(ids);
  }

  List<int> _mergeFront(List<int> preferred, List<int> extra) {
    final merged = <int>[];
    for (final id in [...preferred, ...extra]) {
      if (merged.contains(id)) continue;
      if (merged.length >= softCap) break;
      merged.add(id);
    }
    return merged;
  }

  bool _sameIds(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Main-list order: local pins in stored order, then Telegram-pinned chats,
/// then the existing TDLib order. A chat that is both locally and
/// server-pinned is one row and stays in the local-pin group.
int compareMainChatList(
  ChatSummary a,
  ChatSummary b, {
  required int Function(int chatId) localPinRank,
}) {
  final aRank = localPinRank(a.id);
  final bRank = localPinRank(b.id);
  final aLocal = aRank >= 0;
  final bLocal = bRank >= 0;
  if (aLocal != bLocal) return aLocal ? -1 : 1;
  if (aLocal && aRank != bRank) return aRank.compareTo(bRank);
  return compareServerChatList(a, b);
}

/// Telegram's own chat-list order: server pins, then `order`, then date.
int compareServerChatList(ChatSummary a, ChatSummary b) {
  if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
  if (a.order != b.order) return b.order.compareTo(a.order);
  if (a.date != b.date) return b.date.compareTo(a.date);
  return b.id.compareTo(a.id);
}
