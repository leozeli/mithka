//
//  chat_list_folder_directory.dart
//
//  Telegram folders as expandable sections inside the message list, optionally
//  nested under client-only local groups. Membership stays a flat TDLib
//  chat-list filter. The outer rail and tab strip are not required.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../components/app_icons.dart';
import '../components/app_interactive_surface.dart';
import '../components/chat_folder_icons.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import 'local_folder_group.dart';

/// Nominal height of a folder section header before text scaling.
const chatListFolderHeaderBaseExtent = 40.0;

/// Extra inset for chats nested under a Telegram folder section.
const chatListFolderChildIndent = 16.0;

double chatListFolderHeaderExtent(BuildContext context) =>
    AppMetric.rowExtentFor(
      context,
      base: chatListFolderHeaderBaseExtent,
      lines: const [AppTextSize.callout],
    );

enum ChatListDirectorySlotKind {
  pullDownArchive,
  groupHeader,
  folderHeader,
  filtered,
  archive,
  entry,
  empty,
  placeholder,
}

class ChatListDirectorySlot {
  const ChatListDirectorySlot({
    required this.kind,
    this.folderId,
    this.groupId,
    this.expanded = false,
    this.entryIndex,
    this.lastInSection = false,
    this.indent = 0,
  });

  final ChatListDirectorySlotKind kind;

  /// Null is the main list ("All"). A non-null id is a Telegram folder.
  final int? folderId;

  /// Set on a local-group header. Telegram never assigns this id.
  final String? groupId;
  final bool expanded;
  final int? entryIndex;

  /// The last chat row of an expanded Telegram folder, used to page that list.
  final bool lastInSection;

  /// Leading inset. A grouped folder is one step in; its chats are two.
  final double indent;
}

double chatListDirectorySlotExtent(
  ChatListDirectorySlotKind kind, {
  required double rowHeight,
  required double headerHeight,
  required bool pullDownVisible,
}) {
  return switch (kind) {
    ChatListDirectorySlotKind.pullDownArchive =>
      pullDownVisible ? rowHeight : 0,
    ChatListDirectorySlotKind.groupHeader ||
    ChatListDirectorySlotKind.folderHeader ||
    ChatListDirectorySlotKind.empty => headerHeight,
    ChatListDirectorySlotKind.filtered ||
    ChatListDirectorySlotKind.archive ||
    ChatListDirectorySlotKind.entry ||
    ChatListDirectorySlotKind.placeholder => rowHeight,
  };
}

/// Local groups, then ungrouped Telegram folders, then "All". Groups and
/// folders sit above the main list so they stay reachable without scrolling
/// through every chat. "All" starts expanded. A folder belongs to at most one
/// group; collapsing a group hides that group's folders and their chats.
List<ChatListDirectorySlot> buildChatListFolderDirectory({
  required List<int> folderIds,
  required Set<int> expandedFolderIds,
  required bool allExpanded,
  required Map<int, int> folderEntryCounts,
  required Set<int> loadingFolderIds,
  required int allEntryCount,
  required bool allLoading,
  required bool hasPullDownArchiveSlot,
  required bool hasFiltered,
  required bool showInlineArchive,
  required int inlineArchiveIndex,
  required int allPlaceholderCount,
  List<LocalFolderGroup> groups = const [],
}) {
  final slots = <ChatListDirectorySlot>[];
  if (hasPullDownArchiveSlot) {
    slots.add(
      const ChatListDirectorySlot(
        kind: ChatListDirectorySlotKind.pullDownArchive,
      ),
    );
  }
  final folderIdSet = folderIds.toSet();
  final placed = <int>{};
  for (final group in groups) {
    slots.add(
      ChatListDirectorySlot(
        kind: ChatListDirectorySlotKind.groupHeader,
        groupId: group.id,
        expanded: group.expanded,
      ),
    );
    for (final id in group.childFolderIds) {
      if (!folderIdSet.contains(id) || !placed.add(id)) continue;
      if (!group.expanded) continue;
      _appendFolderSection(
        slots,
        folderId: id,
        expanded: expandedFolderIds.contains(id),
        headerIndent: chatListFolderChildIndent,
        entryCount: folderEntryCounts[id] ?? 0,
        loading: loadingFolderIds.contains(id),
      );
    }
  }
  for (final id in folderIds) {
    if (placed.contains(id)) continue;
    _appendFolderSection(
      slots,
      folderId: id,
      expanded: expandedFolderIds.contains(id),
      headerIndent: 0,
      entryCount: folderEntryCounts[id] ?? 0,
      loading: loadingFolderIds.contains(id),
    );
  }
  slots.add(
    ChatListDirectorySlot(
      kind: ChatListDirectorySlotKind.folderHeader,
      expanded: allExpanded,
    ),
  );
  if (allExpanded) {
    _appendSectionBody(
      slots,
      folderId: null,
      entryCount: allEntryCount,
      loading: allLoading,
      placeholderCount: allPlaceholderCount,
      hasFiltered: hasFiltered,
      showInlineArchive: showInlineArchive,
      inlineArchiveIndex: inlineArchiveIndex,
      pageWhenLastEntryVisible: false,
    );
  }
  return slots;
}

void _appendFolderSection(
  List<ChatListDirectorySlot> slots, {
  required int folderId,
  required bool expanded,
  required double headerIndent,
  required int entryCount,
  required bool loading,
}) {
  slots.add(
    ChatListDirectorySlot(
      kind: ChatListDirectorySlotKind.folderHeader,
      folderId: folderId,
      expanded: expanded,
      indent: headerIndent,
    ),
  );
  if (!expanded) return;
  _appendSectionBody(
    slots,
    folderId: folderId,
    entryCount: entryCount,
    loading: loading,
    placeholderCount: 3,
    hasFiltered: false,
    showInlineArchive: false,
    inlineArchiveIndex: -1,
    pageWhenLastEntryVisible: true,
    indent: headerIndent + chatListFolderChildIndent,
  );
}

void _appendSectionBody(
  List<ChatListDirectorySlot> slots, {
  required int? folderId,
  required int entryCount,
  required bool loading,
  required int placeholderCount,
  required bool hasFiltered,
  required bool showInlineArchive,
  required int inlineArchiveIndex,
  required bool pageWhenLastEntryVisible,
  double indent = 0,
}) {
  if (hasFiltered) {
    slots.add(
      ChatListDirectorySlot(
        kind: ChatListDirectorySlotKind.filtered,
        folderId: folderId,
        indent: indent,
      ),
    );
  }
  if (entryCount == 0 && !showInlineArchive) {
    if (loading && placeholderCount > 0) {
      for (var i = 0; i < placeholderCount; i++) {
        slots.add(
          ChatListDirectorySlot(
            kind: ChatListDirectorySlotKind.placeholder,
            folderId: folderId,
            indent: indent,
          ),
        );
      }
    } else {
      slots.add(
        ChatListDirectorySlot(
          kind: ChatListDirectorySlotKind.empty,
          folderId: folderId,
          indent: indent,
        ),
      );
    }
    return;
  }

  for (var i = 0; i < entryCount; i++) {
    if (showInlineArchive && inlineArchiveIndex == i) {
      slots.add(
        ChatListDirectorySlot(
          kind: ChatListDirectorySlotKind.archive,
          folderId: folderId,
          indent: indent,
        ),
      );
    }
    final archiveFollows =
        showInlineArchive && inlineArchiveIndex == entryCount;
    slots.add(
      ChatListDirectorySlot(
        kind: ChatListDirectorySlotKind.entry,
        folderId: folderId,
        entryIndex: i,
        indent: indent,
        lastInSection:
            pageWhenLastEntryVisible && i == entryCount - 1 && !archiveFollows,
      ),
    );
  }
  if (showInlineArchive && inlineArchiveIndex == entryCount) {
    slots.add(
      ChatListDirectorySlot(
        kind: ChatListDirectorySlotKind.archive,
        folderId: folderId,
        indent: indent,
      ),
    );
  }
}

/// Distance from the top of the scrollable to [targetIndex], counting the
/// search pill as [leadingExtent] the same way the flat chat list does.
double chatListDirectoryScrollOffset({
  required List<ChatListDirectorySlot> slots,
  required int targetIndex,
  required double rowHeight,
  required double headerHeight,
  required double maxScrollExtent,
  required bool pullDownVisible,
  double leadingExtent = 0,
}) {
  var offset = leadingExtent;
  final end = targetIndex.clamp(0, slots.length);
  for (var i = 0; i < end; i++) {
    offset += chatListDirectorySlotExtent(
      slots[i].kind,
      rowHeight: rowHeight,
      headerHeight: headerHeight,
      pullDownVisible: pullDownVisible,
    );
  }
  if (maxScrollExtent.isFinite) {
    offset = math.min(offset, maxScrollExtent);
  }
  return offset;
}

/// One expandable Telegram folder, or the main "All" section, inside the list.
class ChatListFolderHeader extends StatelessWidget {
  const ChatListFolderHeader({
    super.key,
    required this.title,
    required this.iconName,
    required this.expanded,
    required this.onTap,
    this.onSecondaryTap,
  });

  final String title;
  final String iconName;
  final bool expanded;
  final VoidCallback onTap;
  final VoidCallback? onSecondaryTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final height = chatListFolderHeaderExtent(context);
    final collapsedTurns = Directionality.of(context) == TextDirection.rtl
        ? 0.25
        : -0.25;
    return AppInteractiveSurface(
      semanticLabel: title,
      expanded: expanded,
      onTap: onTap,
      onSecondaryTap: onSecondaryTap,
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        decoration: BoxDecoration(
          color: colors.groupedBackground,
          border: Border(bottom: BorderSide(color: colors.divider, width: 0.5)),
        ),
        child: Row(
          children: [
            AnimatedRotation(
              turns: expanded ? 0 : collapsedTurns,
              duration: AppMotion.duration(context, AppMotion.quick),
              curve: AppMotion.standard,
              child: AppIcon(
                HeroAppIcons.chevronDown,
                size: 16,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            ChatFolderIcon(iconName, size: 18, color: colors.textSecondary),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppTextSize.callout,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
