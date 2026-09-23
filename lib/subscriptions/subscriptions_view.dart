//
//  subscriptions_view.dart
//
//  The subscriptions tab: a source list and a newest-first timeline of
//  Telegram channels the user added plus RSS/Atom feeds. Replaces the
//  topic-channel browser as the body of that tab.
//

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/adaptive_split_layout.dart';
import '../app/bottom_bar_layout.dart';
import '../app/primary_chat_launcher.dart';
import '../auth/account_store.dart';
import '../chat/link_handler.dart';
import '../components/app_confirm_dialog.dart';
import '../components/app_dialog.dart';
import '../components/app_icons.dart';
import '../components/app_interactive_surface.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import '../theme/date_text.dart';
import 'feed_models.dart';
import 'subscription_channel_picker.dart';
import 'subscription_feed_controller.dart';

class SubscriptionsReader extends StatelessWidget {
  const SubscriptionsReader({
    super.key,
    required this.controller,
    this.sidebar = false,
    this.desktopSidebar = false,
    this.onRevealTimeline,
  });

  final SubscriptionFeedController controller;
  final bool sidebar;
  final bool desktopSidebar;
  final VoidCallback? onRevealTimeline;

  @override
  Widget build(BuildContext context) {
    if (sidebar) {
      return SubscriptionsSourcePane(
        controller: controller,
        desktopSidebar: desktopSidebar,
        onRevealTimeline: onRevealTimeline,
      );
    }
    return SubscriptionsTimeline(
      controller: controller,
      showSourcesButton: true,
    );
  }
}

class SubscriptionsSourcePane extends StatefulWidget {
  const SubscriptionsSourcePane({
    super.key,
    required this.controller,
    this.desktopSidebar = false,
    this.onRevealTimeline,
    this.onPicked,
  });

  final SubscriptionFeedController controller;
  final bool desktopSidebar;
  final VoidCallback? onRevealTimeline;

  /// Mobile source page pops after a choice. The list has already selected it.
  final VoidCallback? onPicked;

  @override
  State<SubscriptionsSourcePane> createState() =>
      _SubscriptionsSourcePaneState();
}

class _SubscriptionsSourcePaneState extends State<SubscriptionsSourcePane>
    with _FeedBinding<SubscriptionsSourcePane> {
  @override
  SubscriptionFeedController get feedController => widget.controller;

  void _choose(String? id) {
    widget.controller.select(id);
    if (widget.onPicked != null) {
      widget.onPicked!();
      return;
    }
    final size = MediaQuery.sizeOf(context);
    final narrowDesktop =
        usesDesktopShellLayout(size) && !canShowDesktopListPane(size.width);
    if (narrowDesktop) widget.onRevealTimeline?.call();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final subscriptions = widget.controller.subscriptions;
    return ColoredBox(
      key: const ValueKey('subscriptions-source-pane'),
      color: c.background,
      child: Column(
        children: [
          _PaneHeader(
            title: AppStringKeys.subscriptionsSources.l10n(context),
            desktop: widget.desktopSidebar,
            onBack: widget.onPicked == null
                ? null
                : () => Navigator.of(context).pop(),
            actions: [
              _HeaderAction(
                key: const ValueKey('subscriptions-add'),
                icon: HeroAppIcons.plus,
                label: AppStringKeys.subscriptionsAdd,
                onTap: () => unawaited(
                  showAddSubscriptionMenu(context, widget.controller),
                ),
              ),
            ],
          ),
          Expanded(
            child: subscriptions.isEmpty
                ? const _EmptyMessage(
                    icon: HeroAppIcons.towerBroadcast,
                    message: AppStringKeys.subscriptionsEmpty,
                  )
                : ListView(
                    padding: EdgeInsets.only(
                      bottom: BottomBarInset.of(context),
                    ),
                    children: [
                      _SourceRow(
                        icon: HeroAppIcons.inbox,
                        title: AppStringKeys.subscriptionsAll.l10n(context),
                        selected: widget.controller.selectedId == null,
                        unread: widget.controller.unreadCount(null),
                        onTap: () => _choose(null),
                      ),
                      for (final subscription in subscriptions)
                        _SourceRow(
                          icon: subscription.kind == FeedSourceKind.telegram
                              ? HeroAppIcons.towerBroadcast
                              : HeroAppIcons.globe,
                          title: subscription.title,
                          subtitle: _errorText(context, subscription.lastError),
                          selected:
                              widget.controller.selectedId == subscription.id,
                          unread: widget.controller.unreadCount(
                            subscription.id,
                          ),
                          onTap: () => _choose(subscription.id),
                          onRemove: () => unawaited(_unsubscribe(subscription)),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _unsubscribe(FeedSubscription subscription) async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: AppStringKeys.subscriptionsUnsubscribe,
      message: AppStringKeys.subscriptionsUnsubscribeMessage,
      confirmText: AppStringKeys.subscriptionsUnsubscribe,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await widget.controller.unsubscribe(subscription.id);
  }
}

class SubscriptionsTimeline extends StatefulWidget {
  const SubscriptionsTimeline({
    super.key,
    required this.controller,
    this.showBackButton = false,
    this.onBack,
    this.showSourcesButton = false,
  });

  final SubscriptionFeedController controller;
  final bool showBackButton;
  final VoidCallback? onBack;
  final bool showSourcesButton;

  @override
  State<SubscriptionsTimeline> createState() => _SubscriptionsTimelineState();
}

class _SubscriptionsTimelineState extends State<SubscriptionsTimeline>
    with _FeedBinding<SubscriptionsTimeline> {
  String? _openId;

  @override
  SubscriptionFeedController get feedController => widget.controller;

  FeedItem? get _opened {
    final id = _openId;
    if (id == null) return null;
    for (final item in widget.controller.store.allItems()) {
      if (item.id == id) return item;
    }
    return null;
  }

  Future<void> _open(FeedItem item) async {
    await widget.controller.markRead(item);
    if (!mounted) return;
    if (widget.showSourcesButton) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SubscriptionItemPage(item: item),
        ),
      );
      return;
    }
    setState(() => _openId = item.id);
  }

  @override
  Widget build(BuildContext context) {
    final opened = _opened;
    if (_openId != null && opened == null) _openId = null;
    if (opened != null) {
      return SubscriptionItemPage(
        item: opened,
        onBack: () => setState(() => _openId = null),
      );
    }
    final c = context.colors;
    final controller = widget.controller;
    final items = controller.visibleItems;
    final selected = controller.selected;
    final title =
        selected?.title ?? AppStringKeys.subscriptionsAll.l10n(context);
    return ColoredBox(
      key: const ValueKey('subscriptions-timeline'),
      color: c.background,
      child: Column(
        children: [
          _PaneHeader(
            title: title,
            desktop: false,
            onBack: widget.showBackButton ? widget.onBack : null,
            actions: [
              if (widget.showSourcesButton)
                _HeaderAction(
                  key: const ValueKey('subscriptions-sources'),
                  icon: HeroAppIcons.listCheck,
                  label: AppStringKeys.subscriptionsSources,
                  onTap: () => unawaited(_openSources(context)),
                ),
              _HeaderAction(
                icon: HeroAppIcons.arrowsRotate,
                label: AppStringKeys.subscriptionsRefresh,
                busy: controller.loading,
                onTap: () => unawaited(_refresh(context)),
              ),
              _HeaderAction(
                icon: HeroAppIcons.check,
                label: AppStringKeys.subscriptionsMarkAllRead,
                onTap: () => unawaited(controller.markVisibleRead()),
              ),
              if (widget.showSourcesButton)
                _HeaderAction(
                  key: const ValueKey('subscriptions-add'),
                  icon: HeroAppIcons.plus,
                  label: AppStringKeys.subscriptionsAdd,
                  onTap: () =>
                      unawaited(showAddSubscriptionMenu(context, controller)),
                ),
            ],
          ),
          Expanded(
            child: items.isEmpty
                ? _EmptyMessage(
                    icon: HeroAppIcons.inbox,
                    message: controller.subscriptions.isEmpty
                        ? AppStringKeys.subscriptionsEmpty
                        : AppStringKeys.subscriptionsTimelineEmpty,
                  )
                : ListView.separated(
                    padding: EdgeInsets.only(
                      bottom: BottomBarInset.of(context),
                    ),
                    itemCount: items.length,
                    separatorBuilder: (_, _) =>
                        const InsetDivider(leadingInset: 28),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return _TimelineRow(
                        item: item,
                        read: controller.isRead(item),
                        showSource: controller.selectedId == null,
                        onTap: () => unawaited(_open(item)),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _openSources(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SubscriptionsSourcePane(
          controller: widget.controller,
          onPicked: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  Future<void> _refresh(BuildContext context) async {
    final failure = await widget.controller.refresh(manual: true);
    if (!context.mounted || failure == null) return;
    showToast(context, subscriptionFailureMessage(failure));
  }
}

class SubscriptionItemPage extends StatelessWidget {
  const SubscriptionItemPage({super.key, required this.item, this.onBack});

  final FeedItem item;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final title = item.title.trim().isEmpty ? item.sourceName : item.title;
    final canOpen = item.opensInChat || item.hasLink;
    return ColoredBox(
      color: c.background,
      child: Column(
        children: [
          NavHeader(
            title: item.sourceName,
            localizeTitle: false,
            onBack: onBack ?? () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                20 + MediaQuery.paddingOf(context).bottom,
              ),
              children: [
                Text(
                  title,
                  style: AppTextStyle.title(
                    c.textPrimary,
                    weight: AppTextWeight.semibold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  [
                    item.sourceName,
                    if (item.publishedAt > 0)
                      DateText.separatorLabel(item.publishedAt),
                  ].join(' · '),
                  style: AppTextStyle.footnote(c.textTertiary),
                ),
                if (item.excerpt.trim().isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    item.excerpt,
                    style: AppTextStyle.body(
                      c.textPrimary,
                    ).copyWith(height: 1.4),
                  ),
                ],
                if (canOpen) ...[
                  const SizedBox(height: 24),
                  AppInteractiveSurface(
                    key: const ValueKey('subscriptions-open-original'),
                    semanticLabel: AppStringKeys.subscriptionsOpenOriginal.l10n(
                      context,
                    ),
                    isButton: true,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    onTap: () => unawaited(_openOriginal(context)),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppTheme.brand,
                        borderRadius: BorderRadius.circular(AppRadius.card),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          AppStringKeys.subscriptionsOpenOriginal.l10n(context),
                          textAlign: TextAlign.center,
                          style: AppTextStyle.body(
                            const Color(0xFFFFFFFF),
                            weight: AppTextWeight.semibold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openOriginal(BuildContext context) async {
    if (item.opensInChat) {
      await openChatFromCurrentWindow(
        context,
        chatId: item.chatId!,
        title: item.sourceName,
        initialMessageId: item.messageId,
      );
      return;
    }
    final link = item.link;
    if (link == null || link.isEmpty || !context.mounted) return;
    await openLink(context, link);
  }
}

Future<void> showAddSubscriptionMenu(
  BuildContext context,
  SubscriptionFeedController controller,
) async {
  final choice = await showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: AppStringKeys.countryPickerCancel.l10n(context),
    barrierColor: const Color(0x99000000),
    transitionDuration: AppMotion.duration(context, AppMotion.responsive),
    transitionBuilder: AppMotion.dialogTransition,
    pageBuilder: (dialogContext, _, _) => AppDialogSurface(
      title: AppStringKeys.tabSubscriptions.l10n(dialogContext),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MenuChoice(
            icon: HeroAppIcons.towerBroadcast,
            label: AppStringKeys.subscriptionsAddTelegram.l10n(dialogContext),
            onTap: () => Navigator.of(dialogContext).pop('telegram'),
          ),
          const SizedBox(height: 8),
          _MenuChoice(
            icon: HeroAppIcons.link,
            label: AppStringKeys.subscriptionsAddRss.l10n(dialogContext),
            onTap: () => Navigator.of(dialogContext).pop('rss'),
          ),
        ],
      ),
      actions: [
        AppDialogAction(
          label: AppStringKeys.countryPickerCancel.l10n(dialogContext),
          onTap: () => Navigator.of(dialogContext).pop(),
        ),
      ],
    ),
  );
  if (!context.mounted || choice == null) return;
  if (choice == 'telegram') {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AddTelegramSubscriptionPage(controller: controller),
      ),
    );
    return;
  }
  await _promptRssUrl(context, controller);
}

mixin _FeedBinding<T extends StatefulWidget> on State<T> {
  SubscriptionFeedController get feedController;
  AccountStore? _accounts;

  @override
  void initState() {
    super.initState();
    feedController.addListener(_onFeed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _accounts = context.read<AccountStore>()..addListener(_bind);
      _bind();
    });
  }

  void _onFeed() {
    if (mounted) setState(() {});
  }

  void _bind() {
    final accounts = _accounts;
    if (!mounted || accounts == null) return;
    unawaited(
      feedController.ensureBound(
        slot: accounts.activeSlot,
        userId: accounts.activeUserId,
      ),
    );
  }

  @override
  void dispose() {
    feedController.removeListener(_onFeed);
    _accounts?.removeListener(_bind);
    super.dispose();
  }
}

class _PaneHeader extends StatelessWidget {
  const _PaneHeader({
    required this.title,
    required this.desktop,
    required this.actions,
    this.onBack,
  });

  final String title;
  final bool desktop;
  final List<Widget> actions;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    if (!desktop) {
      return NavHeader(
        title: title,
        localizeTitle: false,
        onBack: onBack,
        trailing: Row(mainAxisSize: MainAxisSize.min, children: actions),
      );
    }
    final c = context.colors;
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      decoration: BoxDecoration(
        color: c.navBar,
        border: Border(
          bottom: BorderSide(color: c.divider, width: AppMetric.divider),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.title(c.textPrimary),
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.busy = false,
  });

  final AppIconData icon;
  final String label;
  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppInteractiveSurface(
      semanticLabel: label.l10n(context),
      isButton: true,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      onTap: busy ? null : onTap,
      child: SizedBox(
        width: 36,
        height: 36,
        child: Center(
          child: busy
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: c.textSecondary,
                  ),
                )
              : AppIcon(icon, size: 22, color: c.textPrimary),
        ),
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({
    required this.icon,
    required this.title,
    required this.selected,
    required this.unread,
    required this.onTap,
    this.subtitle,
    this.onRemove,
  });

  final AppIconData icon;
  final String title;
  final String? subtitle;
  final bool selected;
  final int unread;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ColoredBox(
      color: selected
          ? AppTheme.brand.withValues(alpha: isDark ? 0.16 : 0.1)
          : c.background,
      child: Row(
        children: [
          Expanded(
            child: AppInteractiveSurface(
              semanticLabel: title,
              selected: selected,
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                child: Row(
                  children: [
                    AppIcon(icon, size: 20, color: c.textSecondary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyle.body(
                              c.textPrimary,
                              weight: selected
                                  ? AppTextWeight.semibold
                                  : AppTextWeight.regular,
                            ),
                          ),
                          if (subtitle != null && subtitle!.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyle.caption(AppTheme.tagRed),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (unread > 0)
                      Text(
                        unread > 99 ? '99+' : '$unread',
                        style: AppTextStyle.caption(
                          c.textSecondary,
                          weight: AppTextWeight.semibold,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (onRemove != null)
            AppInteractiveSurface(
              semanticLabel: AppStringKeys.subscriptionsUnsubscribe.l10n(
                context,
              ),
              isButton: true,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              onTap: onRemove,
              child: SizedBox(
                width: 36,
                height: 44,
                child: Center(
                  child: AppIcon(
                    HeroAppIcons.xmark,
                    size: 16,
                    color: c.textTertiary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.item,
    required this.read,
    required this.showSource,
    required this.onTap,
  });

  final FeedItem item;
  final bool read;
  final bool showSource;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final title = item.title.trim().isEmpty ? item.sourceName : item.title;
    return AppInteractiveSurface(
      semanticLabel: title,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 6, right: 10),
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: read ? const Color(0x00000000) : AppTheme.brand,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyle.bodyLarge(
                            c.textPrimary,
                            weight: read
                                ? AppTextWeight.regular
                                : AppTextWeight.semibold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        DateText.listLabel(item.publishedAt),
                        style: AppTextStyle.caption(c.textTertiary),
                      ),
                    ],
                  ),
                  if (showSource) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.sourceName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyle.footnote(c.textSecondary),
                    ),
                  ],
                  if (item.excerpt.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.excerpt,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyle.footnote(
                        c.textSecondary,
                      ).copyWith(height: 1.35),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyMessage extends StatelessWidget {
  const _EmptyMessage({required this.icon, required this.message});

  final AppIconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(icon, size: 46, color: AppTheme.brand),
            const SizedBox(height: 12),
            Text(
              message.l10n(context),
              textAlign: TextAlign.center,
              style: AppTextStyle.body(c.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuChoice extends StatelessWidget {
  const _MenuChoice({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final AppIconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppInteractiveSurface(
      semanticLabel: label,
      isButton: true,
      borderRadius: BorderRadius.circular(AppRadius.card),
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.searchFill,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              AppIcon(icon, size: 20, color: c.textPrimary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label, style: AppTextStyle.body(c.textPrimary)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _promptRssUrl(
  BuildContext context,
  SubscriptionFeedController controller,
) async {
  final url = await showAppTextEntryDialog(
    context,
    title: AppStringKeys.subscriptionsRssUrlTitle.l10n(context),
    actionLabel: AppStringKeys.subscriptionsAddRss.l10n(context),
    hint: AppStringKeys.subscriptionsRssUrlHint.l10n(context),
    allowEmpty: false,
    keyboardType: TextInputType.url,
  );
  if (url == null || !context.mounted) return;
  final failure = await controller.addRss(url);
  if (!context.mounted || failure == null) return;
  showToast(context, subscriptionFailureMessage(failure));
}

String? _errorText(BuildContext context, String? code) {
  final key = switch (code) {
    'network' => AppStringKeys.subscriptionsRssNetworkError,
    'notFeed' => AppStringKeys.subscriptionsRssNotFeed,
    'invalidUrl' => AppStringKeys.subscriptionsRssInvalidUrl,
    'telegram' => AppStringKeys.subscriptionsTelegramFailed,
    _ => null,
  };
  if (key == null) return null;
  return key.l10n(context);
}
