//
//  local_folder_group.dart
//
//  Client-only parent groups for the chat-folder rail. Telegram folders stay
//  flat on the server; these groups only rearrange how the left rail nests
//  them on this device.
//

import 'package:flutter/foundation.dart';

import 'chat_list_view_model.dart';

/// One local parent that can hold Telegram folder ids.
@immutable
class LocalFolderGroup {
  const LocalFolderGroup({
    required this.id,
    required this.title,
    this.iconName = 'Custom',
    this.childFolderIds = const <int>[],
    this.expanded = true,
  });

  final String id;
  final String title;
  final String iconName;
  final List<int> childFolderIds;
  final bool expanded;

  LocalFolderGroup copyWith({
    String? id,
    String? title,
    String? iconName,
    List<int>? childFolderIds,
    bool? expanded,
  }) {
    return LocalFolderGroup(
      id: id ?? this.id,
      title: title ?? this.title,
      iconName: iconName ?? this.iconName,
      childFolderIds: childFolderIds ?? this.childFolderIds,
      expanded: expanded ?? this.expanded,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'iconName': iconName,
    'childFolderIds': childFolderIds,
    'expanded': expanded,
  };

  static LocalFolderGroup? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final id = map['id']?.toString();
    final title = map['title']?.toString();
    if (id == null || id.isEmpty || title == null || title.isEmpty) {
      return null;
    }
    final children = <int>[];
    final rawChildren = map['childFolderIds'];
    if (rawChildren is List) {
      for (final entry in rawChildren) {
        final id = switch (entry) {
          final int value => value,
          final String value => int.tryParse(value),
          _ => null,
        };
        if (id == null || children.contains(id)) continue;
        children.add(id);
      }
    }
    return LocalFolderGroup(
      id: id,
      title: title,
      iconName: map['iconName']?.toString() ?? 'Custom',
      childFolderIds: children,
      expanded: map['expanded'] is bool ? map['expanded'] as bool : true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LocalFolderGroup &&
      other.id == id &&
      other.title == title &&
      other.iconName == iconName &&
      other.expanded == expanded &&
      listEquals(other.childFolderIds, childFolderIds);

  @override
  int get hashCode => Object.hash(
    id,
    title,
    iconName,
    expanded,
    Object.hashAll(childFolderIds),
  );
}

/// One row in the side folder rail: either a local group header or a leaf.
enum ChatFolderRailEntryKind { group, filter }

@immutable
class ChatFolderRailEntry {
  const ChatFolderRailEntry.group(this.group)
    : kind = ChatFolderRailEntryKind.group,
      filter = null,
      nested = false;

  const ChatFolderRailEntry.filter(this.filter, {this.nested = false})
    : kind = ChatFolderRailEntryKind.filter,
      group = null;

  final ChatFolderRailEntryKind kind;
  final LocalFolderGroup? group;
  final ChatFilterOption? filter;
  final bool nested;

  bool get isGroup => kind == ChatFolderRailEntryKind.group;
}

/// Builds the nested side-rail order: All, then groups (with children when
/// expanded), then ungrouped Telegram folders in their existing order.
List<ChatFolderRailEntry> buildChatFolderRailEntries({
  required List<ChatFilterOption> filters,
  required List<LocalFolderGroup> groups,
}) {
  final byId = <int, ChatFilterOption>{
    for (final filter in filters)
      if (filter.folderId != null) filter.folderId!: filter,
  };
  final grouped = <int>{};
  for (final group in groups) {
    for (final id in group.childFolderIds) {
      if (byId.containsKey(id)) grouped.add(id);
    }
  }

  final entries = <ChatFolderRailEntry>[];
  for (final filter in filters) {
    if (!filter.isAll) continue;
    entries.add(ChatFolderRailEntry.filter(filter));
  }

  for (final group in groups) {
    entries.add(ChatFolderRailEntry.group(group));
    if (!group.expanded) continue;
    for (final id in group.childFolderIds) {
      final child = byId[id];
      if (child == null) continue;
      entries.add(ChatFolderRailEntry.filter(child, nested: true));
    }
  }

  for (final filter in filters) {
    if (filter.isAll) continue;
    final id = filter.folderId;
    if (id == null || grouped.contains(id)) continue;
    entries.add(ChatFolderRailEntry.filter(filter));
  }
  return entries;
}

/// Flat leaf order for tabs, menu, and folder swipe: All, then each group's
/// children in group order, then ungrouped folders. Group headers are omitted.
List<ChatFilterOption> flattenChatFiltersForDisplay({
  required List<ChatFilterOption> filters,
  required List<LocalFolderGroup> groups,
}) {
  final byId = <int, ChatFilterOption>{
    for (final filter in filters)
      if (filter.folderId != null) filter.folderId!: filter,
  };
  final grouped = <int>{};
  final flat = <ChatFilterOption>[];

  for (final filter in filters) {
    if (filter.isAll) flat.add(filter);
  }

  for (final group in groups) {
    for (final id in group.childFolderIds) {
      final child = byId[id];
      if (child == null || !grouped.add(id)) continue;
      flat.add(child);
    }
  }

  for (final filter in filters) {
    if (filter.isAll) continue;
    final id = filter.folderId;
    if (id == null || grouped.contains(id)) continue;
    flat.add(filter);
  }
  return flat;
}

/// Drops deleted Telegram folder ids from every group. Empty groups stay so
/// the user can still rename or delete them.
List<LocalFolderGroup> pruneLocalFolderGroups(
  List<LocalFolderGroup> groups,
  Set<int> existingFolderIds,
) {
  return [
    for (final group in groups)
      group.copyWith(
        childFolderIds: [
          for (final id in group.childFolderIds)
            if (existingFolderIds.contains(id)) id,
        ],
      ),
  ];
}
