import '../../../core/widgets/loading_skeleton.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/verified_badge.dart';
import 'inbox_controller.dart';
import 'match_sheets.dart';
import 'matches_screen.dart' show MatchAvatar;

class BackendChatScreen extends ConsumerStatefulWidget {
  const BackendChatScreen({required this.matchId, super.key});
  final String matchId;
  @override
  ConsumerState<BackendChatScreen> createState() => _BackendChatScreenState();
}

class _BackendChatScreenState extends ConsumerState<BackendChatScreen>
    with WidgetsBindingObserver {
  final _composer = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <ChatMessage>[];
  Set<String> _latestIds = {};
  MatchSummary? _match;
  Timer? _timer;
  Future<void>? _fetch;
  String? _cursor, _error, _retryBody, _retryId, _readAnchor;
  bool _active = true,
      _sending = false,
      _acting = false,
      _older = false,
      _closed = false,
      _reading = false,
      _historyLoaded = false;

  ApiClient get _api => ref.read(apiClientProvider);
  bool get _visible => _active && (ModalRoute.of(context)?.isCurrent ?? true);
  bool get _atBottom => !_scroll.hasClients || _scroll.offset < 60;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(_markVisibleRead);
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_visible && !_closed) unawaited(_refresh());
    });
    unawaited(_refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    if (_active) unawaited(_refresh());
  }

  Future<void> _refresh() =>
      _fetch ??= _load().whenComplete(() => _fetch = null);

  Future<void> _load() async {
    if (!mounted) return;
    try {
      final match = await _api.matchDetail(widget.matchId);
      final page = await _api.messagesPage(widget.matchId);
      if (!mounted) return;
      setState(() {
        _match = match;
        _error = null;
        _closed = false;
        if (_latestIds.isNotEmpty &&
            page.items.isNotEmpty &&
            !page.items.any((item) => _latestIds.contains(item.messageId))) {
          _messages.clear();
          _historyLoaded = false;
        }
        if (!_historyLoaded) _cursor = page.nextCursor;
        _messages.removeWhere(
          (message) => _latestIds.contains(message.messageId),
        );
        _merge(page.items);
        _latestIds = page.items.map((item) => item.messageId).toSet();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _markVisibleRead();
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.statusCode == 401
            ? 'Your session has expired. Sign in again.'
            : chatError(error.code);
        if (error.statusCode == 404 ||
            error.statusCode == 401 ||
            error.code == 'match_not_found' ||
            error.code == 'account_not_active') {
          _closed = true;
          _match = null;
          _messages.clear();
        }
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not update this conversation. Try again.',
        );
      }
    }
  }

  void _merge(List<ChatMessage> items) {
    final unique = {
      for (final message in _messages) message.messageId: message,
      for (final message in items) message.messageId: message,
    };
    _messages
      ..clear()
      ..addAll(unique.values);
    _messages.sort((a, b) {
      final time = (a.createdAt ?? DateTime(1970)).compareTo(
        b.createdAt ?? DateTime(1970),
      );
      return time == 0 ? a.messageId.compareTo(b.messageId) : time;
    });
  }

  Future<void> _loadOlder() async {
    if (_older || _cursor == null) return;
    setState(() => _older = true);
    try {
      final page = await _api.messagesPage(widget.matchId, cursor: _cursor);
      if (!mounted) return;
      setState(() {
        _merge(page.items);
        _cursor = page.nextCursor;
        _historyLoaded = true;
      });
    } on ApiException catch (error) {
      _notice(chatError(error.code));
    } finally {
      if (mounted) setState(() => _older = false);
    }
  }

  Future<void> _markVisibleRead() async {
    if (!mounted || !_visible || !_atBottom || _reading || _match == null) {
      return;
    }
    final incoming = _messages
        .where(
          (message) =>
              !_mine(message) &&
              message.moderationStatus == 'clear' &&
              message.readAt == null,
        )
        .toList();
    if (incoming.isEmpty || _readAnchor == incoming.last.messageId) return;
    final anchor = incoming.last.messageId;
    _reading = true;
    try {
      await _api.markMessagesRead(widget.matchId, throughMessageId: anchor);
      if (!mounted) return;
      _readAnchor = anchor;
      unawaited(ref.read(inboxProvider.notifier).refresh());
    } catch (_) {
      /* Next foreground poll retries this acknowledgement. */
    } finally {
      _reading = false;
    }
  }

  bool _mine(ChatMessage message) => _match?.viewerProfileId != null
      ? message.senderProfileId == _match!.viewerProfileId
      : message.senderProfileId != _match?.profileId;

  @override
  Widget build(BuildContext context) {
    ref.listen(inboxProvider, (_, next) {
      if (_visible && _match != null && !_closed) unawaited(_refresh());
    });
    return Scaffold(
      backgroundColor: AppColors.ink,
      body: SafeArea(
        child: Column(
          children: [
            _header(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(color: AppColors.coral),
                      ),
                    ),
                    TextButton(
                      onPressed:
                          _error == 'Your session has expired. Sign in again.'
                          ? () => context.go('/auth')
                          : _refresh,
                      child: Text(
                        _error == 'Your session has expired. Sign in again.'
                            ? 'Sign in'
                            : 'Retry',
                      ),
                    ),
                  ],
                ),
              ),
            if (_match != null) _revealBar(_match!),
            Expanded(
              child: _match == null
                  ? Center(
                      child: _error == null
                          ? const Padding(
                              padding: EdgeInsets.all(24),
                              child: ContentSkeleton(
                                content: SkeletonContent.chat,
                              ),
                            )
                          : Text(
                              _closed
                                  ? 'This conversation is no longer available.'
                                  : 'Unable to load conversation.',
                            ),
                    )
                  : RefreshIndicator(
                      onRefresh: _refresh,
                      child: ListView.builder(
                        controller: _scroll,
                        reverse: true,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                        itemCount: _messages.length + 1,
                        itemBuilder: (context, index) {
                          if (index == _messages.length) {
                            return _cursor == null
                                ? const Padding(
                                    padding: EdgeInsets.all(16),
                                    child: Text(
                                      'Say hello. Keep it kind and respect each other’s privacy.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: AppColors.muted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  )
                                : TextButton(
                                    onPressed: _older ? null : _loadOlder,
                                    child: Text(
                                      _older
                                          ? 'Loading…'
                                          : 'Load earlier messages',
                                    ),
                                  );
                          }
                          final message =
                              _messages[_messages.length - index - 1];
                          return _bubble(message, _mine(message));
                        },
                      ),
                    ),
            ),
            if (!_closed && _match != null) _input(),
          ],
        ),
      ),
    );
  }

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
    child: Row(
      children: [
        IconButton(
          tooltip: 'Back',
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/app/matches'),
          icon: const Icon(Icons.chevron_left),
        ),
        if (_match != null) ...[
          MatchAvatar(
            id: _match!.profileId,
            url: _match!.blurredAvatarUrl,
            size: 40,
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      _match?.alias ?? 'Conversation',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  if (_match?.isVerified == true)
                    const Padding(
                      padding: EdgeInsets.only(left: 5),
                      child: VerifiedBadge(size: 18),
                    ),
                ],
              ),
              Text(
                _match?.state == 'unmasked'
                    ? 'Mutual reveal'
                    : 'Anonymous chat',
                style: const TextStyle(
                  color: AppColors.secondaryText,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        if (_match != null)
          PopupMenuButton<String>(
            tooltip: 'Conversation options',
            onSelected: _menuAction,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'report', child: Text('Report')),
              PopupMenuItem(value: 'block', child: Text('Block')),
              PopupMenuItem(value: 'unmatch', child: Text('Unmatch')),
            ],
          ),
      ],
    ),
  );

  Widget _revealBar(MatchSummary match) {
    final cooldown = match.revealCooldownUntil?.isAfter(DateTime.now()) == true;
    final text = switch (match.revealStatus) {
      'incoming' =>
        '${match.alias} would like to reveal. Both of you must agree.',
      'outgoing' => 'Reveal requested. You can withdraw before they agree.',
      'revealed' => 'You both agreed to reveal.',
      _ =>
        cooldown
            ? 'Give them time. You can ask again after 24 hours.'
            : 'Your photos stay private until you both agree to reveal.',
    };
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            style: const TextStyle(
              color: AppColors.secondaryText,
              fontSize: 12,
            ),
          ),
          Wrap(
            spacing: 10,
            children: [
              if (match.revealStatus == 'incoming') ...[
                TextButton(
                  onPressed: _acting
                      ? null
                      : () => _action(
                          () => _api.respondReveal(
                            matchId: widget.matchId,
                            accept: true,
                          ),
                        ),
                  child: const Text('Accept reveal'),
                ),
                TextButton(
                  onPressed: _acting
                      ? null
                      : () => _action(
                          () => _api.respondReveal(
                            matchId: widget.matchId,
                            accept: false,
                          ),
                        ),
                  child: const Text('Not now'),
                ),
              ] else if (match.revealStatus == 'outgoing')
                TextButton(
                  onPressed: _acting
                      ? null
                      : () =>
                            _action(() => _api.withdrawReveal(widget.matchId)),
                  child: const Text('Withdraw request'),
                )
              else if (match.revealStatus == 'revealed')
                TextButton(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => RevealedProfileSheet(
                      matchId: widget.matchId,
                      alias: match.alias,
                    ),
                  ),
                  child: const Text('View revealed profile'),
                )
              else
                TextButton(
                  onPressed: _acting || cooldown
                      ? null
                      : () => _action(() => _api.requestReveal(widget.matchId)),
                  child: const Text('Request reveal'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bubble(ChatMessage message, bool mine) => Align(
    alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * .78,
      ),
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: mine ? AppColors.accent : AppColors.surfaceRaised,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(mine ? 18 : 4),
          bottomRight: Radius.circular(mine ? 4 : 18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(message.body, style: const TextStyle(color: AppColors.text)),
          if (mine)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(switch (message.moderationStatus) {
                'queued' => 'Checking…',
                'flagged' => 'Under review · not delivered',
                'blocked' => 'Not delivered',
                _ => message.readAt == null ? 'Sent' : 'Read',
              }, style: const TextStyle(color: Colors.white70, fontSize: 10)),
            ),
        ],
      ),
    ),
  );

  Widget _input() => Padding(
    padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            key: const Key('chat-composer'),
            controller: _composer,
            minLines: 1,
            maxLines: 4,
            maxLength: 2000,
            enabled: !_sending,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _send(),
            decoration: const InputDecoration(
              hintText: 'Say something kind…',
              counterText: '',
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filled(
          tooltip: 'Send message',
          onPressed: _sending ? null : _send,
          icon: _sending
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send_rounded),
        ),
      ],
    ),
  );

  Future<void> _send() async {
    final body = _composer.text.trim();
    if (body.isEmpty || _sending || _closed) return;
    if (_retryBody != body) {
      _retryId = const Uuid().v4();
      _retryBody = body;
    }
    setState(() => _sending = true);
    try {
      final message = await _api.sendMessage(
        matchId: widget.matchId,
        body: body,
        clientMessageId: _retryId,
      );
      if (!mounted) return;
      _composer.clear();
      _retryId = null;
      _retryBody = null;
      setState(() => _merge([message]));
      if (_scroll.hasClients) {
        unawaited(
          _scroll.animateTo(
            0,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
          ),
        );
      }
      unawaited(ref.read(inboxProvider.notifier).refresh());
    } on ApiException catch (error) {
      _notice(chatError(error.code));
      if (error.code == 'match_not_found') unawaited(_refresh());
    } catch (_) {
      _notice('Message not sent. Your draft is saved here; tap send to retry.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _action(Future<void> Function() action) async {
    if (_acting) return;
    setState(() => _acting = true);
    try {
      await action();
      if (!mounted) return;
      await _fetch;
      if (!mounted) return;
      await _refresh();
      if (mounted) unawaited(ref.read(inboxProvider.notifier).refresh());
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error.code == 'verification_required_before_unmask') {
        final start = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Verification needed'),
            content: const Text(
              'Both people need to be verified before revealing. Start in the Safety center.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Later'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Safety center'),
              ),
            ],
          ),
        );
        if (start == true && mounted) {
          await context.push('/app/safety');
          if (mounted) await _refresh();
        }
      } else {
        _notice(chatError(error.code));
      }
    } catch (_) {
      _notice('Could not complete this action. Try again.');
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _menuAction(String action) async {
    final match = _match;
    if (match == null || _acting) return;
    if (action == 'report') {
      final reason = await showModalBottomSheet<String>(
        context: context,
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(
                title: Text(
                  'Report this profile',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              for (final entry in const {
                'scam': 'Scam or asking for money',
                'solicitation': 'Commercial solicitation',
                'harassment': 'Harassment',
                'fake': 'Fake profile',
                'underage': 'Under 18',
                'other': 'Other',
              }.entries)
                ListTile(
                  title: Text(entry.value),
                  onTap: () => Navigator.pop(context, entry.key),
                ),
            ],
          ),
        ),
      );
      if (reason != null && mounted) {
        await _action(() async {
          await _api.reportProfile(
            profileId: match.profileId,
            reason: reason,
            messageIds: _messages
                .where((message) => !_mine(message))
                .map((message) => message.messageId)
                .take(10)
                .toList(),
          );
          _notice('Report submitted. You can track it in the Safety center.');
        });
      }
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          action == 'block' ? 'Block this person?' : 'Unmatch this person?',
        ),
        content: Text(
          action == 'block'
              ? 'They will no longer be able to discover or contact you. This conversation will close.'
              : 'This conversation and access to revealed details will close.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action == 'block' ? 'Block' : 'Unmatch'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _action(() async {
      if (action == 'block') {
        await _api.blockProfile(match.profileId);
      } else {
        await _api.unmatch(widget.matchId);
      }
      if (!mounted) return;
      unawaited(ref.read(inboxProvider.notifier).refresh());
      context.go('/app/matches');
    });
  }

  void _notice(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(text),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 90),
        ),
      );
    }
  }
}

String chatError(String code) => switch (code) {
  'contact_exchange_not_allowed' =>
    'Keep contact details private until you both agree to reveal.',
  'unmask_cooldown' => 'Please wait 24 hours after a declined reveal request.',
  'unmask_request_not_found' =>
    'This reveal request has changed. Refresh the conversation.',
  'match_not_found' ||
  'match_closed' ||
  'messaging_blocked' => 'This conversation is no longer available.',
  'throttled' => 'Please wait a moment before trying again.',
  'message_too_long' => 'Messages can contain up to 2,000 characters.',
  _ => 'Could not complete this request. Please try again.',
};
