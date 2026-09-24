//
//  subscription_channel_picker.dart
//
//  Lists joined channels, and channels found by search, so the user can add
//  one source at a time. Nothing is subscribed automatically.
//

import 'dart:async';

import 'package:flutter/material.dart';

import '../components/app_interactive_surface.dart';
import '../components/photo_avatar.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import 'feed_models.dart';
import 'subscription_feed_controller.dart';
import 'telegram_feed_source.dart';

class AddTelegramSubscriptionPage extends StatefulWidget {
  const AddTelegramSubscriptionPage({super.key, required this.controller});

  final SubscriptionFeedController controller;

  @override
  State<AddTelegramSubscriptionPage> createState() =>
      _AddTelegramSubscriptionPageState();
}

class _AddTelegramSubscriptionPageState
    extends State<AddTelegramSubscriptionPage> {
  final _search = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  List<ChatSummary> _channels = const [];
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _search.addListener(_schedule);
    unawaited(_load(''));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      final text = _search.text.trim();
      if (text == _query) return;
      unawaited(_load(text));
    });
  }

  Future<void> _load(String query) async {
    setState(() {
      _loading = true;
      _query = query;
    });
    final channels = await loadSubscribableChannels(
      query: TdClient.shared.query,
      search: query,
    );
    if (!mounted || query != _query) return;
    setState(() {
      _channels = channels;
      _loading = false;
    });
  }

  Future<void> _add(ChatSummary chat) async {
    final failure = await widget.controller.addTelegram(chat);
    if (!mounted) return;
    if (failure != null) {
      showToast(context, subscriptionFailureMessage(failure));
    }
    if (failure == null ||
        failure == SubscriptionFailure.alreadyAdded ||
        failure == SubscriptionFailure.telegram) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Pushed on the root navigator from the desktop sidebar, so this route is
    // not under the tab shell's Material. Scaffold supplies that ancestor for
    // the search field and a bounded body for the channel list.
    return Scaffold(
      backgroundColor: c.background,
      body: Column(
        children: [
          NavHeader(
            title: AppStringKeys.subscriptionsAddTelegram,
            onBack: () => Navigator.of(context).pop(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SettingsSearchField(
              hintText: AppStringKeys.subscriptionsSearchChannels,
              controller: _search,
              focusNode: _focus,
            ),
          ),
          Expanded(child: _body(c)),
        ],
      ),
    );
  }

  Widget _body(AppColors c) {
    if (_loading && _channels.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_channels.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            AppStringKeys.subscriptionsNoChannels.l10n(context),
            textAlign: TextAlign.center,
            style: AppTextStyle.body(c.textSecondary),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
      itemCount: _channels.length,
      separatorBuilder: (_, _) => const InsetDivider(leadingInset: 68),
      itemBuilder: (context, index) {
        final chat = _channels[index];
        return AppInteractiveSurface(
          semanticLabel: chat.title,
          onTap: () => unawaited(_add(chat)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                PhotoAvatar(
                  title: chat.title,
                  photo: chat.photo,
                  size: 40,
                  square: true,
                  allowAnimation: false,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    chat.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.bodyLarge(
                      c.textPrimary,
                      weight: AppTextWeight.medium,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

String subscriptionFailureMessage(SubscriptionFailure failure) {
  return switch (failure) {
    SubscriptionFailure.invalidUrl => AppStringKeys.subscriptionsRssInvalidUrl,
    SubscriptionFailure.notFeed => AppStringKeys.subscriptionsRssNotFeed,
    SubscriptionFailure.network => AppStringKeys.subscriptionsRssNetworkError,
    SubscriptionFailure.telegram => AppStringKeys.subscriptionsTelegramFailed,
    SubscriptionFailure.alreadyAdded => AppStringKeys.subscriptionsAlreadyAdded,
    SubscriptionFailure.full => AppStringKeys.subscriptionsTooMany,
  };
}
