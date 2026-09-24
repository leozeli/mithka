//
//  chat_list_folder_directory.dart
//
//  Telegram folders and local groups live in the message list. A folder row
//  selects that folder and the chats below are that list, the way the old
//  side rail filtered. Groups only expand to show their folder rows.
//  Membership stays a flat TDLib chat-list filter. The outer rail is not
//  required.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../components/app_icons.dart';
import '../components/app_interactive_surface.dart';
import '../components/chat_folder_icons.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import 'local_folder_group.dart';

/// Extra inset for a Telegram folder row nested under a local group.
const chatListFolderChildIndent = 16.0;

/// Group and folder rows are a short icon-and-label rail, in the columns and
/// in the narrow in-list fallback.
const double chatListFolderRailExtent = 40;

double chatListFolderHeaderExtent() => chatListFolderRailExtent;

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
    this.selected = false,
    this.entryIndex,
    this.lastInSection = false,
    this.indent = 0,
  });

  final ChatListDirectorySlotKind kind;

  /// Null is the main list ("All"). A non-null id is a Telegram folder.
  final int? folderId;

  /// Set on a local-group header. Telegram never assigns this id.
  final String? groupId;

  /// A local group is expanded when its folder rows are visible.
  final bool expanded;

  /// The folder or All row that currently filters the chats below the headers.
  final bool selected;
  final int? entryIndex;

  /// The last chat row of the selected folder, used to page that list.
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

/// Local groups, then ungrouped Telegram folders, then "All", then the chats
/// of the selected row. Groups and folders stay above the chats so they can
/// be selected without scrolling the whole list. Collapsing a group hides
/// its folder rows. The selected list is still the chats underneath, including
/// when that folder's row is inside a collapsed group.
List<ChatListDirectorySlot> buildChatListFolderDirectory({
  required List<int> folderIds,
  required int? selectedFolderId,
  required int selectedEntryCount,
  required bool selectedLoading,
  required int selectedPlaceholderCount,
  required bool hasPullDownArchiveSlot,
  required bool hasFiltered,
  required bool showInlineArchive,
  required int inlineArchiveIndex,
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
      _appendFolderHeader(
        slots,
        folderId: id,
        headerIndent: chatListFolderChildIndent,
        selectedFolderId: selectedFolderId,
      );
    }
  }
  for (final id in folderIds) {
    if (placed.contains(id)) continue;
    _appendFolderHeader(
      slots,
      folderId: id,
      headerIndent: 0,
      selectedFolderId: selectedFolderId,
    );
  }
  slots.add(
    ChatListDirectorySlot(
      kind: ChatListDirectorySlotKind.folderHeader,
      selected: selectedFolderId == null,
    ),
  );
  final showingAll = selectedFolderId == null;
  _appendSectionBody(
    slots,
    folderId: selectedFolderId,
    entryCount: selectedEntryCount,
    loading: selectedLoading,
    placeholderCount: selectedPlaceholderCount,
    hasFiltered: showingAll && hasFiltered,
    showInlineArchive: showingAll && showInlineArchive,
    inlineArchiveIndex: inlineArchiveIndex,
    pageWhenLastEntryVisible: !showingAll,
  );
  return slots;
}

void _appendFolderHeader(
  List<ChatListDirectorySlot> slots, {
  required int folderId,
  required double headerIndent,
  required int? selectedFolderId,
}) {
  slots.add(
    ChatListDirectorySlot(
      kind: ChatListDirectorySlotKind.folderHeader,
      folderId: folderId,
      indent: headerIndent,
      selected: folderId == selectedFolderId,
    ),
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

/// One local group, Telegram folder, or the main "All" row.
///
/// The row is a leading folder glyph plus the label. A group that can expand
/// keeps a small trailing chevron. [iconName] is a TDLib chat-folder icon
/// name; unknown names use the folder glyph.
///
/// When [draggable], a pointer drag reorders the row. The grab cursor and a
/// tertiary bars glyph on hover are the only extra chrome.
class ChatListFolderHeader extends StatelessWidget {
  const ChatListFolderHeader({
    super.key,
    required this.title,
    required this.onTap,
    this.iconName = 'Custom',
    this.expanded = false,
    this.showsChevron = false,
    this.selected = false,
    this.onSecondaryTap,
    this.draggable = false,
    this.dragging = false,
    this.highlighted = false,
  });

  final String title;
  final String iconName;
  final VoidCallback onTap;

  /// Chevron rotation for a local group. Folder and All rows leave this false.
  final bool expanded;

  /// Local groups disclose their folder rows. Folder and All rows do not.
  final bool showsChevron;
  final bool selected;

  final VoidCallback? onSecondaryTap;
  final bool draggable;
  final bool dragging;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return AppInteractiveSurface(
      semanticLabel: title,
      expanded: showsChevron ? expanded : null,
      selected: selected,
      onTap: onTap,
      onSecondaryTap: onSecondaryTap,
      mouseCursor: draggable
          ? (dragging ? SystemMouseCursors.grabbing : SystemMouseCursors.grab)
          : SystemMouseCursors.click,
      child: _FolderHeaderChrome(
        title: title,
        iconName: iconName,
        expanded: expanded,
        showsChevron: showsChevron,
        selected: selected,
        draggable: draggable,
        highlighted: highlighted,
      ),
    );
  }
}

class _FolderHeaderChrome extends StatefulWidget {
  const _FolderHeaderChrome({
    required this.title,
    required this.iconName,
    required this.expanded,
    required this.showsChevron,
    required this.selected,
    required this.draggable,
    required this.highlighted,
  });

  final String title;
  final String iconName;
  final bool expanded;
  final bool showsChevron;
  final bool selected;
  final bool draggable;
  final bool highlighted;

  @override
  State<_FolderHeaderChrome> createState() => _FolderHeaderChromeState();
}

class _FolderHeaderChromeState extends State<_FolderHeaderChrome> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final collapsedTurns = Directionality.of(context) == TextDirection.rtl
        ? 0.25
        : -0.25;
    return MouseRegion(
      onEnter: (_) {
        if (!_hover) setState(() => _hover = true);
      },
      onExit: (_) {
        if (_hover) setState(() => _hover = false);
      },
      child: SizedBox(
        height: chatListFolderRailExtent,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Row(
                children: [
                  ChatFolderIcon(
                    widget.iconName,
                    size: AppIconSize.md,
                    color: widget.selected
                        ? colors.linkBlue
                        : colors.textSecondary,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppTextSize.footnote,
                        fontWeight: FontWeight.w500,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  if (widget.showsChevron) ...[
                    const SizedBox(width: AppSpacing.xs),
                    AnimatedRotation(
                      turns: widget.expanded ? 0 : collapsedTurns,
                      duration: AppMotion.duration(context, AppMotion.quick),
                      curve: AppMotion.standard,
                      child: AppIcon(
                        HeroAppIcons.chevronDown,
                        size: AppIconSize.xs,
                        color: colors.textTertiary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (widget.draggable && _hover)
              PositionedDirectional(
                end: AppSpacing.md,
                top: 0,
                bottom: 0,
                child: IgnorePointer(
                  child: Center(
                    child: AppIcon(
                      HeroAppIcons.bars,
                      size: AppIconSize.xs,
                      color: colors.textTertiary,
                    ),
                  ),
                ),
              ),
            if (widget.highlighted)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.linkBlue.withValues(alpha: 0.08),
                      border: BorderDirectional(
                        start: BorderSide(color: colors.linkBlue, width: 2),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

typedef ChatListSectionDragChild =
    Widget Function({required bool dragging, required bool highlighted});

/// Pointer drag for one local-group or Telegram-folder header.
///
/// A mouse or stylus drag wins against the list scroll immediately, so the
/// header can be dragged directly. Touch keeps scrolling and starts a drag
/// only after a long press. The list order changes on drop.
class ChatListSectionDrag extends StatefulWidget {
  const ChatListSectionDrag({
    super.key,
    required this.enabled,
    required this.token,
    required this.title,
    required this.expanded,
    required this.showsChevron,
    this.iconName = 'Custom',
    required this.highlight,
    required this.resolveTarget,
    required this.onDrop,
    required this.onTap,
    required this.builder,
  });

  final bool enabled;
  final String token;
  final String title;
  final bool expanded;
  final bool showsChevron;
  final String iconName;
  final ValueNotifier<String?> highlight;
  final String? Function(Offset global) resolveTarget;
  final ValueChanged<String> onDrop;
  final VoidCallback onTap;
  final ChatListSectionDragChild builder;

  @override
  State<ChatListSectionDrag> createState() => _ChatListSectionDragState();
}

class _ChatListSectionDragState extends State<ChatListSectionDrag> {
  GestureRecognizer? _recognizer;
  OverlayEntry? _overlay;
  Offset? _origin;
  Offset _grab = Offset.zero;
  Size _size = Size.zero;
  Offset _pointer = Offset.zero;
  double _slop = kPrecisePointerPanSlop;
  String? _target;
  bool _eager = false;
  bool _dragging = false;
  bool _settled = true;

  @override
  void dispose() {
    _removeOverlay();
    final recognizer = _recognizer;
    _recognizer = null;
    recognizer?.dispose();
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent event) {
    if (!widget.enabled || event.buttons != kPrimaryButton) return;
    if (_recognizer != null && !_settled) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    _settled = false;
    _dragging = false;
    _target = null;
    _origin = event.position;
    _pointer = event.position;
    _size = box.size;
    _grab = event.position - box.localToGlobal(Offset.zero);
    _slop = computePanSlop(
      event.kind,
      MediaQuery.maybeGestureSettingsOf(context),
    );
    _eager = switch (event.kind) {
      PointerDeviceKind.mouse ||
      PointerDeviceKind.stylus ||
      PointerDeviceKind.invertedStylus => true,
      _ => false,
    };
    if (_eager) {
      final recognizer = _EagerSectionDrag(
        debugOwner: this,
        onMove: _onMove,
        onEnd: () => _finish(canceled: false),
        onCancel: () => _finish(canceled: true),
      );
      _recognizer = recognizer;
      recognizer.addPointer(event);
      return;
    }
    final recognizer = DelayedMultiDragGestureRecognizer(debugOwner: this)
      ..gestureSettings = MediaQuery.maybeGestureSettingsOf(context)
      ..onStart = _startDelayed;
    _recognizer = recognizer;
    recognizer.addPointer(event);
  }

  Drag _startDelayed(Offset position) {
    return _SectionPointerDrag(
      origin: _origin ?? position,
      onMove: _onMove,
      onEnd: () => _finish(canceled: false),
      onCancel: () => _finish(canceled: true),
    );
  }

  void _onMove(Offset global) {
    if (_settled) return;
    final origin = _origin;
    if (origin == null || (global - origin).distance <= _slop) return;
    _pointer = global;
    if (!_dragging) {
      _dragging = true;
      if (mounted) setState(() {});
      _insertOverlay();
    } else {
      _overlay?.markNeedsBuild();
    }
    final target = widget.resolveTarget(global);
    if (target == _target) return;
    _target = target;
    widget.highlight.value = target;
  }

  void _finish({required bool canceled}) {
    if (_settled) return;
    _settled = true;
    final drop = !canceled && _dragging ? _target : null;
    final tap = !canceled && _eager && !_dragging;
    _target = null;
    if (widget.highlight.value != null) widget.highlight.value = null;
    _removeOverlay();
    _releaseRecognizer();
    if (_dragging && mounted) setState(() => _dragging = false);
    if (drop != null) {
      widget.onDrop(drop);
    } else if (tap) {
      widget.onTap();
    }
  }

  void _insertOverlay() {
    if (_overlay != null) return;
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    final overlayBox = overlay.context.findRenderObject() as RenderBox?;
    _overlay = OverlayEntry(
      builder: (context) {
        final topLeft = _pointer - _grab;
        final local = overlayBox != null && overlayBox.attached
            ? overlayBox.globalToLocal(topLeft)
            : topLeft;
        return Positioned(
          left: local.dx,
          top: local.dy,
          width: _size.width,
          height: _size.height,
          child: IgnorePointer(
            child: _SectionDragFeedback(
              title: widget.title,
              iconName: widget.iconName,
              expanded: widget.expanded,
              showsChevron: widget.showsChevron,
            ),
          ),
        );
      },
    );
    overlay.insert(_overlay!);
  }

  void _removeOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  void _releaseRecognizer() {
    final recognizer = _recognizer;
    if (recognizer == null) return;
    _recognizer = null;
    scheduleMicrotask(recognizer.dispose);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return widget.builder(dragging: false, highlighted: false);
    }
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      child: ValueListenableBuilder<String?>(
        valueListenable: widget.highlight,
        builder: (context, token, _) {
          return Opacity(
            opacity: _dragging ? 0.4 : 1,
            child: widget.builder(
              dragging: _dragging,
              highlighted: token == widget.token,
            ),
          );
        },
      ),
    );
  }
}

class _SectionDragFeedback extends StatelessWidget {
  const _SectionDragFeedback({
    required this.title,
    required this.iconName,
    required this.expanded,
    required this.showsChevron,
  });

  final String title;
  final String iconName;
  final bool expanded;
  final bool showsChevron;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: const [
          BoxShadow(
            color: Color(0x24000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: _FolderHeaderChrome(
        title: title,
        iconName: iconName,
        expanded: expanded,
        showsChevron: showsChevron,
        selected: false,
        draggable: false,
        highlighted: false,
      ),
    );
  }
}

class _EagerSectionDrag extends OneSequenceGestureRecognizer {
  _EagerSectionDrag({
    required this.onMove,
    required this.onEnd,
    required this.onCancel,
    super.debugOwner,
  });

  final ValueChanged<Offset> onMove;
  final VoidCallback onEnd;
  final VoidCallback onCancel;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    startTrackingPointer(event.pointer, event.transform);
    resolve(GestureDisposition.accepted);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) {
      onMove(event.position);
    } else if (event is PointerUpEvent) {
      stopTrackingPointer(event.pointer);
      onEnd();
    } else if (event is PointerCancelEvent) {
      stopTrackingPointer(event.pointer);
      onCancel();
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  String get debugDescription => 'section-reorder';
}

class _SectionPointerDrag extends Drag {
  _SectionPointerDrag({
    required Offset origin,
    required this.onMove,
    required this.onEnd,
    required this.onCancel,
  }) : _position = origin;

  final ValueChanged<Offset> onMove;
  final VoidCallback onEnd;
  final VoidCallback onCancel;
  Offset _position;

  @override
  void update(DragUpdateDetails details) {
    _position += details.delta;
    onMove(_position);
  }

  @override
  void end(DragEndDetails details) => onEnd();

  @override
  void cancel() => onCancel();
}
