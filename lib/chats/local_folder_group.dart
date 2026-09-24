//
//  local_folder_group.dart
//
//  Client-only parents for Telegram folders inside the message list. Telegram
//  folders stay flat on the server; a group only decides which folder sections
//  nest together on this device.

import 'package:flutter/foundation.dart';

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
        final childId = switch (entry) {
          final int value => value,
          final String value => int.tryParse(value),
          _ => null,
        };
        if (childId == null || children.contains(childId)) continue;
        children.add(childId);
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
