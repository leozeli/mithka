//
//  chat_list_folder_directory.dart
//
//  Telegram folders as expandable sections inside the message list. Membership
//  stays a flat TDLib chat-list filter; this only changes where those folders
//  are browsed. The outer rail and tab strip are not required.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../components/app_icons.dart';
import '../components/app_interactive_surface.dart';
import '../components/chat_folder_icons.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';

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
    this.expanded = false,
    this.entryIndex,
    this.lastInSection = false,
  });

  final ChatListDirectorySlotKind kind;

  /// Null is the main list ("All"). A non-null id is a Telegram folder.
  final int? folderId;
  final bool expanded;
  final int? entryIndex;

  /// The last chat row of an expanded Telegram folder, used to page that list.
  final bool lastInSection;
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
    ChatListDirectorySlotKind.folderHeader ||
    ChatListDirectorySlotKind.empty => headerHeight,
    ChatListDirectorySlotKind.filtered ||
    ChatListDirectorySlotKind.archive ||
    ChatListDirectorySlotKind.entry ||
    ChatListDirectorySlotKind.placeholder => rowHeight,
  };
}

/// Folders sit above the main list so they stay reachable without scrolling
/// through every chat. "All" is the last section and starts expanded.
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
}) {
  final slots = <ChatListDirectorySlot>[];
  if (hasPullDownArchiveSlot) {
    slots.add(
      const ChatListDirectorySlot(
        kind: ChatListDirectorySlotKind.pullDownArchive,
      ),
    );
  }
  for (final id in folderIds) {
    final expanded = expandedFolderIds.contains(id);
    slots.add(
      ChatListDirectorySlot(
        kind: ChatListDirectorySlotKind.folderHeader,
        folderId: id,
        expanded: expanded,
      ),
    );
    if (!expanded) continue;
    _appendSectionBody(
      slots,
      folderId: id,
      entryCount: folderEntryCounts[id] ?? 0,
      loading: loadingFolderIds.contains(id),
      placeholderCount: 3,
      hasFiltered: false,
      showInlineArchive: false,
      inlineArchiveIndex: -1,
      pageWhenLastEntryVisible: true,
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
}) {
  if (hasFiltered) {
    slots.add(
      ChatListDirectorySlot(
        kind: ChatListDirectorySlotKind.filtered,
        folderId: folderId,
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
          ),
        );
      }
    } else {
      slots.add(
        ChatListDirectorySlot(
          kind: ChatListDirectorySlotKind.empty,
          folderId: folderId,
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
