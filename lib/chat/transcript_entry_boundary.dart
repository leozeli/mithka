import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Tracks only laid-out transcript rows for viewport reads and scroll anchors.
/// Pagination can retain thousands of messages; a scroll frame needs the
/// handful of render boxes attached by the two lazy slivers.
class TranscriptEntryBoundary extends SingleChildRenderObjectWidget {
  const TranscriptEntryBoundary({
    super.key,
    required this.messageId,
    required this.mountedEntries,
    required super.child,
  });

  final int messageId;
  final Map<int, RenderBox> mountedEntries;

  @override
  RenderRepaintBoundary createRenderObject(BuildContext context) =>
      _RenderTranscriptEntryBoundary(messageId, mountedEntries);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderRepaintBoundary renderObject,
  ) => (renderObject as _RenderTranscriptEntryBoundary).updateRegistration(
    messageId,
    mountedEntries,
  );
}

class _RenderTranscriptEntryBoundary extends RenderRepaintBoundary {
  _RenderTranscriptEntryBoundary(this._messageId, this._mountedEntries);

  int _messageId;
  Map<int, RenderBox> _mountedEntries;

  void _unregister() {
    if (identical(_mountedEntries[_messageId], this)) {
      _mountedEntries.remove(_messageId);
    }
  }

  void updateRegistration(int messageId, Map<int, RenderBox> mountedEntries) {
    if (_messageId == messageId && identical(_mountedEntries, mountedEntries)) {
      return;
    }
    if (attached) _unregister();
    _messageId = messageId;
    _mountedEntries = mountedEntries;
    if (attached && hasSize) _mountedEntries[_messageId] = this;
  }

  @override
  void performLayout() {
    super.performLayout();
    // attach() runs before this box has a size. Scroll anchoring and selection
    // both read size; only publish the row once layout has produced one.
    if (attached && hasSize) {
      _mountedEntries[_messageId] = this;
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    if (hasSize) _mountedEntries[_messageId] = this;
  }

  @override
  void detach() {
    _unregister();
    super.detach();
  }
}

/// A box that is in the tree and has been through layout.
///
/// An element stays [BuildContext.mounted] after it is deactivated and until
/// it unmounts. [BuildContext.findRenderObject] asserts in that gap.
RenderBox? laidOutBoxOf(BuildContext? context) {
  if (context is! Element || !context.mounted) return null;
  var active = true;
  assert(() {
    active = context.debugIsActive;
    return true;
  }());
  if (!active) return null;
  final object = context.findRenderObject();
  if (object is! RenderBox || !isLaidOutBox(object)) return null;
  return object;
}

bool isLaidOutBox(RenderObject? object) =>
    object is RenderBox && object.attached && object.hasSize;
