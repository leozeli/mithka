import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../platform/adaptive_platform.dart';

export '../platform/adaptive_platform.dart' show isDesktopTargetPlatform;

const double splitSidebarMinWidth = 300;
const double splitSidebarDefaultMinWidth = 320;
const double splitSidebarDefaultMaxWidth = 420;
const double splitDetailMinWidth = 440;
const double splitResizeHandleWidth = 8;
const double desktopNavigationRailWidth = 58;
const double desktopConversationMinWidth = 440;

/// Local-group rail: 12px side padding, a 16px icon, an 8px gap, and a short
/// name. Longer names ellipsize.
const double chatListGroupColumnWidth = 104;

/// Folder rail, same icon row with a little more room for the label.
const double chatListFolderColumnWidth = 128;

double get chatListFolderChromeWidth =>
    chatListGroupColumnWidth + chatListFolderColumnWidth;

/// Narrowest chat column once the rails are beside it. This is the same floor
/// the chat list had before the rails existed, so a 420px list still falls
/// back to in-list rows instead of squeezing titles.
const double chatListColumnMinWidth = splitSidebarMinWidth;

/// True when [chromeWidth] can sit with the list pane and still leave the
/// conversation its minimum width.
bool chatListFolderChromeFits({
  required double totalWidth,
  required double requestedSidebarWidth,
  required double chromeWidth,
  bool infoPaneRequested = false,
}) {
  if (chromeWidth <= 0) return false;
  final geometry = resolveDesktopShellGeometry(
    totalWidth: totalWidth,
    requestedSidebarWidth: requestedSidebarWidth,
    infoPaneRequested: infoPaneRequested,
    folderChromeWidth: chromeWidth,
  );
  return geometry.folderChromeWidth > 0;
}

/// Mouse-oriented group context pane. The width leaves enough room for member
/// names while avoiding a visually empty trailing gutter beside the chat.
const double desktopInfoPaneWidth = 224;
const double desktopInfoPaneHandleWidth = 1;

@immutable
class DesktopShellGeometry {
  const DesktopShellGeometry({
    required this.showListPane,
    required this.showInfoPane,
    required this.sidebarWidth,
    required this.conversationWidth,
    this.folderChromeWidth = 0,
  });

  final bool showListPane;
  final bool showInfoPane;

  /// Chat-list column. Folder rails are [folderChromeWidth], not part of this.
  final double sidebarWidth;
  final double conversationWidth;

  /// Rail width actually placed in front of the chat column. Zero when the
  /// rails would push the conversation below its minimum.
  final double folderChromeWidth;

  double get listPaneWidth => sidebarWidth + folderChromeWidth;
}

bool usesDesktopShellLayout(
  Size size, {
  TargetPlatform? platform,
  bool isWeb = kIsWeb,
}) {
  final target = platform ?? defaultTargetPlatform;
  return !isWeb && isDesktopTargetPlatform(target);
}

bool usesSplitSelectionLayout(
  Size size, {
  TargetPlatform? platform,
  bool isWeb = kIsWeb,
}) =>
    usesDesktopShellLayout(size, platform: platform, isWeb: isWeb) ||
    usesAdaptiveSplitLayout(size, platform: platform, isWeb: isWeb);

bool desktopDetailNeedsBackButton(DesktopShellGeometry geometry) =>
    !geometry.showListPane;

bool canShowDesktopListPane(double totalWidth) =>
    totalWidth >=
    desktopNavigationRailWidth +
        splitSidebarMinWidth +
        desktopConversationMinWidth;

bool canShowDesktopInfoPane({
  required double totalWidth,
  required double sidebarWidth,
  double infoPaneWidth = desktopInfoPaneWidth,
}) =>
    totalWidth >=
    desktopNavigationRailWidth +
        sidebarWidth +
        desktopConversationMinWidth +
        desktopInfoPaneHandleWidth +
        infoPaneWidth;

DesktopShellGeometry resolveDesktopShellGeometry({
  required double totalWidth,
  required double requestedSidebarWidth,
  bool infoPaneRequested = false,
  double infoPaneWidth = desktopInfoPaneWidth,
  double folderChromeWidth = 0,
}) {
  final availableAfterRail = math.max(
    0.0,
    totalWidth - desktopNavigationRailWidth,
  );
  if (!canShowDesktopListPane(totalWidth)) {
    return DesktopShellGeometry(
      showListPane: false,
      showInfoPane: false,
      sidebarWidth: 0,
      conversationWidth: availableAfterRail,
    );
  }

  // Split the window the way it was split when the list pane was only the
  // chat column. Rails borrow that column before they borrow the conversation.
  final baselineSidebar = constrainSplitSidebarWidth(
    requestedWidth: requestedSidebarWidth,
    totalWidth: availableAfterRail,
  );
  var chrome = math.max(0.0, folderChromeWidth);
  var sidebarWidth = baselineSidebar;
  if (chrome > 0) {
    final maxListPane = math.max(
      splitSidebarMinWidth,
      availableAfterRail - desktopConversationMinWidth,
    );
    final minListPane = chatListColumnMinWidth + chrome;
    if (minListPane > maxListPane) {
      chrome = 0;
    } else {
      final listPane = math.min(
        math.max(baselineSidebar, minListPane),
        maxListPane,
      );
      sidebarWidth = listPane - chrome;
    }
  }

  final listPane = sidebarWidth + chrome;
  final showInfoPane =
      infoPaneRequested &&
      canShowDesktopInfoPane(
        totalWidth: totalWidth,
        sidebarWidth: listPane,
        infoPaneWidth: infoPaneWidth,
      );
  final conversationWidth =
      availableAfterRail -
      listPane -
      (showInfoPane ? desktopInfoPaneHandleWidth + infoPaneWidth : 0);
  return DesktopShellGeometry(
    showListPane: true,
    showInfoPane: showInfoPane,
    sidebarWidth: sidebarWidth,
    conversationWidth: conversationWidth,
    folderChromeWidth: chrome,
  );
}

bool usesAdaptiveSplitLayout(
  Size size, {
  TargetPlatform? platform,
  bool isWeb = kIsWeb,
}) {
  final target = platform ?? defaultTargetPlatform;
  final hasSplitWidth =
      size.width >= splitSidebarMinWidth + splitDetailMinWidth;
  if (!isWeb && isDesktopTargetPlatform(target)) return hasSplitWidth;
  return hasSplitWidth &&
      size.width > size.height &&
      math.min(size.width, size.height) >= 600;
}

double defaultSplitSidebarWidth(double totalWidth) {
  return (totalWidth * 0.32)
      .clamp(splitSidebarDefaultMinWidth, splitSidebarDefaultMaxWidth)
      .toDouble();
}

double constrainSplitSidebarWidth({
  required double requestedWidth,
  required double totalWidth,
}) {
  final maxWidth = math.max(
    splitSidebarMinWidth,
    totalWidth - splitDetailMinWidth,
  );
  return requestedWidth.clamp(splitSidebarMinWidth, maxWidth).toDouble();
}
