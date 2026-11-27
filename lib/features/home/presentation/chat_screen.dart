import '../../../core/widgets/loading_skeleton.dart';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/chat_connection.dart';
import '../../../core/widgets/profile_image.dart';
import '../../onboarding/application/consent_documents.dart';
import 'profile_device.dart';
import 'widgets/chat_details.dart';
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
  ChatConnection? _connection;
  StreamSubscription<Map<String, dynamic>>? _events;
  StreamSubscription<bool>? _recordInterruptions;
  Timer? _typingStop, _peerTypingExpiry, _peerActiveExpiry, _recordTimer;
  bool _connecting = false,
      _peerTyping = false,
      _recording = false,
      _mediaBusy = false;
  bool? _peerOnline;
  bool _roomVisible = true;
  DateTime? _lastTyping, _lastHeartbeat;
  final _activitySession = const Uuid().v4();
  ChatMessage? _reply;
  XFile? _draft;
  Uint8List? _draftBytes;
  String? _draftKind, _playingId, _audioLoadingId;
  Map<String, dynamic>? _uploadTicket;
  bool _uploaded = false, _completed = false;
  int _seconds = 0, _epoch = 0, _audioEpoch = 0;
  late final ProfileDevice _device;
  late final ProfilePlayer _player;
  late final ApiClient _boundApi;
  String? _owner;
  final _deliveredIds = <String>{};

  ApiClient get _api => ref.read(apiClientProvider);
  bool get _visible =>
      _active && _roomVisible && (ModalRoute.of(context)?.isCurrent ?? true);
  bool get _current =>
      mounted && _owner == ref.read(authControllerProvider).session?.userId;
  bool get _atBottom => !_scroll.hasClients || _scroll.offset < 60;

  @override
  void initState() {
    super.initState();
    _owner = ref.read(authControllerProvider).session?.userId;
    _boundApi = _api;
    _device = ref.read(profileDeviceProvider)();
    _player = ref.read(profilePlayerProvider)();
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(_markVisibleRead);
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_visible && !_closed) {
        unawaited(_refresh().then((_) => _connectRoom()));
        if (_lastHeartbeat == null ||
            DateTime.now().difference(_lastHeartbeat!) >=
                const Duration(seconds: 20)) {
          unawaited(_activity(true));
        }
      }
    });
    unawaited(_refresh());
  }

  @override
  void dispose() {
    _epoch++;
    _audioEpoch++;
    _typingStop?.cancel();
    _peerTypingExpiry?.cancel();
    _peerActiveExpiry?.cancel();
    _recordTimer?.cancel();
    _connection?.send({'type': 'activity', 'active': false, 'typing': false});
    unawaited(_events?.cancel());
    unawaited(_recordInterruptions?.cancel());
    unawaited(_connection?.dispose());
    unawaited(_device.dispose());
    unawaited(_player.dispose());
    unawaited(
      _boundApi
          .chatActivity(widget.matchId, _activitySession, active: false)
          .catchError((Object _) => const ChatActivity()),
    );
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    if (_active && _roomVisible) {
      unawaited(_refresh().then((_) => _connectRoom()));
    } else {
      _leaveRoom();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.valuesOf(context).enabled;
    if (visible == _roomVisible) return;
    _roomVisible = visible;
    if (!visible) {
      _leaveRoom();
    } else if (_active) {
      unawaited(_refresh().then((_) => _connectRoom()));
    }
  }

  Future<void> _refresh() =>
      _fetch ??= _load().whenComplete(() => _fetch = null);

  Future<void> _load() async {
    if (!_current) return;
    final epoch = _epoch;
    try {
      final result = await Future.wait<Object>([
        _api.matchDetail(widget.matchId),
        _api.messagesPage(widget.matchId),
      ]);
      if (!_current || epoch != _epoch) return;
      final match = result[0] as MatchSummary;
      final page = result[1] as MessagePage;
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
        final nextIds = page.items.map((message) => message.messageId).toSet();
        _messages.removeWhere(
          (message) =>
              _latestIds.contains(message.messageId) &&
              !nextIds.contains(message.messageId),
        );
        _merge(page.items);
        _latestIds = page.items.map((item) => item.messageId).toSet();
      });
      if (page.activity != null) _applyActivity(page.activity!);
      unawaited(_deliver(page.items));
      unawaited(_connectRoom());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _markVisibleRead();
      });
    } on ApiException catch (error) {
      if (!_current || epoch != _epoch) return;
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
          _leaveRoom();
        }
      });
    } catch (_) {
      if (_current && epoch == _epoch) {
        setState(
          () => _error = 'Could not update this conversation. Try again.',
        );
      }
    }
  }

  void _merge(List<ChatMessage> items) {
    final unique = {
      for (final message in _messages) message.messageId: message,
    };
    for (final message in items) {
      final previous = unique[message.messageId];
      if (previous?.updatedAt != null &&
          message.updatedAt != null &&
          previous!.updatedAt!.isAfter(message.updatedAt!)) {
        continue;
      }
      unique[message.messageId] = message;
    }
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
    if (!_current || _closed || _older || _cursor == null) return;
    final epoch = _epoch;
    setState(() => _older = true);
    try {
      final page = await _api.messagesPage(widget.matchId, cursor: _cursor);
      if (!_current || epoch != _epoch) return;
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
    if (!_current ||
        _closed ||
        !_visible ||
        !_atBottom ||
        _reading ||
        _match == null) {
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
    final epoch = _epoch;
    try {
      await _api.markMessagesRead(widget.matchId, throughMessageId: anchor);
      if (!_current || epoch != _epoch) return;
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
    ref.listen(
      authControllerProvider.select((state) => state.session?.userId),
      (_, user) {
        if (user != _owner) {
          _epoch++;
          _leaveRoom();
          setState(() {
            _messages.clear();
            _match = null;
            _closed = true;
          });
        }
      },
    );
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
            if (_match != null && MediaQuery.viewInsetsOf(context).bottom < 100)
              _revealBar(_match!),
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
            if (_peerTyping && !_closed)
              DatingTypingIndicator(alias: _match?.alias ?? 'Your match'),
            if (!_closed && _match != null) ...[
              if (_reply != null) _replyComposer(),
              if (_draft != null) _draftComposer(),
              if (_recording) _recordComposer() else _input(),
            ],
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
              Row(
                children: [
                  if (_peerOnline != null) ...[
                    Icon(
                      Icons.circle,
                      size: 7,
                      color: _peerOnline! ? AppColors.teal : AppColors.muted,
                    ),
                    const SizedBox(width: 5),
                  ],
                  Flexible(
                    child: Text(
                      _peerOnline == true
                          ? 'Active in this chat'
                          : _peerOnline == false
                          ? 'Offline'
                          : _match?.state == 'unmasked'
                          ? 'Mutual reveal'
                          : 'Anonymous chat',
                      style: const TextStyle(
                        color: AppColors.secondaryText,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
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

  Future<void> _connectRoom() async {
    if (!_current ||
        !_visible ||
        _closed ||
        _match == null ||
        _connecting ||
        _connection?.connected == true) {
      return;
    }
    _connecting = true;
    final epoch = _epoch;
    try {
      await _events?.cancel();
      await _connection?.dispose();
      final socket = ref.read(chatConnectionProvider)(_api, widget.matchId);
      _connection = socket;
      _events = socket.events.listen((event) {
        if (!_current || epoch != _epoch || !_visible) return;
        if (event['type'] == 'activity' || event['type'] == 'pong') {
          _applyActivity(ChatActivity.fromJson(event));
        }
        if (event['type'] == 'message.new' || event['type'] == 'message.ack') {
          final message = ChatMessage.fromJson(event);
          setState(() {
            _merge([message]);
            _peerTyping = false;
          });
          unawaited(_deliver([message]));
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_current) _markVisibleRead();
          });
        } else if (event['type'] == 'receipts.changed') {
          unawaited(_refresh());
        } else if (event['type'] == 'connection.closed') {
          unawaited(_activity(true));
        }
      });
      await socket.connect();
      if (!_current || epoch != _epoch || !_visible) {
        await socket.dispose();
        return;
      }
      await _activity(true);
    } catch (_) {
      /* Authenticated HTTP polling remains available. */
    } finally {
      _connecting = false;
    }
  }

  Future<void> _activity(bool active, {bool typing = false}) async {
    if (!_current || _closed || (active && !_visible)) return;
    _lastHeartbeat = DateTime.now();
    if (_connection?.send({
          'type': 'activity',
          'active': active,
          'typing': typing,
        }) ==
        true) {
      return;
    }
    final epoch = _epoch;
    try {
      final data = await _boundApi.chatActivity(
        widget.matchId,
        _activitySession,
        active: active,
        typing: typing,
      );
      if (_current && epoch == _epoch && active && _visible) {
        _applyActivity(data);
      }
    } catch (_) {
      /* Unavailable presence is never presented as online. */
    }
  }

  void _applyActivity(ChatActivity data) {
    if (!_current || !_visible) return;
    _peerTypingExpiry?.cancel();
    _peerActiveExpiry?.cancel();
    if (_peerOnline != data.active || _peerTyping != data.typing) {
      setState(() {
        _peerOnline = data.active;
        _peerTyping = data.typing;
      });
    }
    if (data.active == true) {
      _peerActiveExpiry = Timer(
        Duration(seconds: data.activeTtl.clamp(1, 45)),
        () {
          if (_current) setState(() => _peerOnline = false);
        },
      );
    }
    if (data.typing) {
      _peerTypingExpiry = Timer(
        Duration(seconds: data.typingTtl.clamp(1, 6)),
        () {
          if (_current) setState(() => _peerTyping = false);
        },
      );
    }
  }

  void _typingChanged(String value) {
    _typingStop?.cancel();
    if (value.trim().isEmpty) {
      unawaited(_activity(true));
      return;
    }
    if (_lastTyping == null ||
        DateTime.now().difference(_lastTyping!) >= const Duration(seconds: 2)) {
      _lastTyping = DateTime.now();
      unawaited(_activity(true, typing: true));
    }
    _typingStop = Timer(const Duration(seconds: 3), () {
      if (_current) unawaited(_activity(true));
    });
  }

  void _leaveRoom() {
    _typingStop?.cancel();
    _peerTypingExpiry?.cancel();
    _peerActiveExpiry?.cancel();
    _connection?.send({'type': 'activity', 'active': false, 'typing': false});
    unawaited(_events?.cancel());
    unawaited(_connection?.dispose());
    _connection = null;
    if (_current) {
      unawaited(
        _boundApi
            .chatActivity(widget.matchId, _activitySession, active: false)
            .catchError((Object _) => const ChatActivity()),
      );
    }
    unawaited(_stopPlayback());
    if (_recording) unawaited(_finishRecording(save: false));
  }

  Future<void> _deliver(List<ChatMessage> items) async {
    if (!_current || !_visible) return;
    final ids = items
        .where(
          (message) =>
              !_mine(message) &&
              message.moderationStatus == 'clear' &&
              !_deliveredIds.contains(message.messageId),
        )
        .map((message) => message.messageId)
        .take(100)
        .toList();
    if (ids.isEmpty) return;
    final epoch = _epoch;
    try {
      await _boundApi.markMessagesDelivered(widget.matchId, ids);
      if (_current && epoch == _epoch) _deliveredIds.addAll(ids);
    } catch (_) {
      /* Retry on the next fetch. */
    }
  }

  String _quoteText(String body, String kind) => body.isNotEmpty
      ? body
      : kind == 'audio'
      ? 'Voice note'
      : kind == 'image'
      ? 'Photo'
      : 'Message';
  void _selectReply(ChatMessage message) {
    if (!_closed && message.moderationStatus == 'clear') {
      setState(() => _reply = message);
    }
  }

  Widget _replyComposer() => Container(
    margin: const EdgeInsets.symmetric(horizontal: 14),
    padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
    decoration: BoxDecoration(
      color: AppColors.surfaceRaised,
      borderRadius: BorderRadius.circular(12),
      border: const Border(
        left: BorderSide(color: AppColors.accentSoft, width: 3),
      ),
    ),
    child: Row(
      children: [
        const Icon(Icons.reply_rounded, size: 18, color: AppColors.accentSoft),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _mine(_reply!)
                    ? 'Replying to yourself'
                    : 'Replying to ${_match?.alias ?? 'your match'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.accentSoft,
                  fontSize: 11,
                ),
              ),
              Text(
                _quoteText(_reply!.body, _reply!.attachment?.kind ?? 'text'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Cancel reply',
          onPressed: _sending ? null : () => setState(() => _reply = null),
          icon: const Icon(Icons.close, size: 18),
        ),
      ],
    ),
  );

  Widget _draftComposer() => Container(
    margin: const EdgeInsets.fromLTRB(14, 6, 14, 0),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: AppColors.surfaceRaised,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        if (_draftKind == 'image' && _draftBytes != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(
              _draftBytes!,
              width: 44,
              height: 44,
              fit: BoxFit.cover,
              cacheWidth: 132,
            ),
          )
        else
          const Icon(Icons.mic_rounded, color: AppColors.accentSoft),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            _sending
                ? 'Uploading and sending…'
                : _draftKind == 'image'
                ? 'Photo ready to send'
                : 'Voice note ready to send',
            maxLines: 2,
          ),
        ),
        IconButton(
          tooltip: 'Remove attachment',
          onPressed: _sending
              ? null
              : () => setState(() {
                  _draft = null;
                  _draftBytes = null;
                  _uploadTicket = null;
                  _uploaded = false;
                  _completed = false;
                }),
          icon: const Icon(Icons.close),
        ),
      ],
    ),
  );

  Future<void> _choosePhoto() async {
    if (_match?.state != 'unmasked') {
      _notice('Photo sharing unlocks after you both agree to reveal.');
      return;
    }
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose photo'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null || !_current) return;
    setState(() => _mediaBusy = true);
    final epoch = _epoch;
    try {
      final file = await _device.pickPhoto(source);
      if (file == null || !_current || epoch != _epoch) return;
      if (await file.length() > 10485760) {
        _notice('Choose a photo under 10 MB.');
        return;
      }
      final bytes = await file.readAsBytes();
      if (!_current || epoch != _epoch) return;
      setState(() {
        _draft = file;
        _draftBytes = bytes;
        _draftKind = 'image';
        _uploadTicket = null;
        _uploaded = false;
        _completed = false;
      });
    } catch (_) {
      _notice('Could not open that photo. Please try again.');
    } finally {
      if (_current) setState(() => _mediaBusy = false);
    }
  }

  Future<void> _startRecording() async {
    if (_mediaBusy || _recording || _sending) return;
    setState(() => _mediaBusy = true);
    final epoch = _epoch;
    try {
      final consents = await _api.consents();
      if (!mounted || !_current || epoch != _epoch) return;
      if (!consents.any((item) => item.type == 'voice' && item.granted)) {
        final allow = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Allow voice sharing?'),
            content: const Text(
              'Voice notes are stored privately and shared with your match. Your voice is disguised until you both reveal. You can change voice consent in Privacy settings.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Not now'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Allow voice sharing'),
              ),
            ],
          ),
        );
        if (allow != true || !_current || epoch != _epoch) return;
        await _api.recordConsent(
          type: 'voice',
          version: ref.read(consentDocumentsProvider).version,
          granted: true,
        );
      }
      if (!_current || !_visible || epoch != _epoch) return;
      await _device.startRecording();
      if (!_current || !_visible || epoch != _epoch) {
        await _device.stopRecording();
        return;
      }
      setState(() {
        _recording = true;
        _seconds = 0;
      });
      _recordInterruptions = _device.recordingInterruptions.listen((
        interrupted,
      ) {
        if (interrupted && _current && _recording) {
          unawaited(_finishRecording(save: false));
          _notice('Recording interrupted. Please record your note again.');
        }
      });
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!_current) return;
        setState(() => _seconds++);
        if (_seconds >= 60) unawaited(_finishRecording());
      });
    } on ApiException catch (error) {
      _notice(
        error.code == 'microphone_permission_denied'
            ? 'Allow microphone access in your phone settings.'
            : chatError(error.code),
      );
    } catch (_) {
      _notice('Could not start recording. Check microphone permission.');
    } finally {
      if (_current) setState(() => _mediaBusy = false);
    }
  }

  Future<void> _finishRecording({bool save = true}) async {
    if (!_recording) return;
    _recordTimer?.cancel();
    unawaited(_recordInterruptions?.cancel());
    _recordInterruptions = null;
    setState(() {
      _recording = false;
      _mediaBusy = true;
    });
    try {
      final file = await _device.stopRecording();
      if (!save || file == null || !_current) return;
      if (await file.length() > 5242880) {
        _notice('Record a shorter voice note.');
        return;
      }
      if (!_current) return;
      setState(() {
        _draft = file;
        _draftBytes = null;
        _draftKind = 'audio';
        _uploadTicket = null;
        _uploaded = false;
        _completed = false;
      });
    } catch (_) {
      if (_current) _notice('Could not save this recording. Please try again.');
    } finally {
      if (_current) setState(() => _mediaBusy = false);
    }
  }

  Widget _recordComposer() => Padding(
    padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
    child: Row(
      children: [
        IconButton(
          tooltip: 'Discard recording',
          onPressed: () => _finishRecording(save: false),
          icon: const Icon(Icons.delete_outline, color: AppColors.coral),
        ),
        const Icon(Icons.circle, size: 9, color: AppColors.coral),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            'Recording ${_seconds ~/ 60}:${(_seconds % 60).toString().padLeft(2, '0')} / 1:00',
          ),
        ),
        IconButton.filled(
          tooltip: 'Finish recording',
          onPressed: _finishRecording,
          icon: const Icon(Icons.stop_rounded),
        ),
      ],
    ),
  );

  Future<void> _stopPlayback() async {
    _audioEpoch++;
    try {
      await _player.pause();
    } catch (_) {
      // A lifecycle change can race the platform player being disposed.
    }
    if (_current && (_playingId != null || _audioLoadingId != null)) {
      setState(() {
        _playingId = null;
        _audioLoadingId = null;
      });
    }
  }

  Future<void> _openAttachment(ChatAttachment attachment) async {
    if (_playingId == attachment.id) {
      await _stopPlayback();
      return;
    }
    if (_audioLoadingId != null) return;
    final epoch = ++_audioEpoch;
    if (attachment.kind == 'audio') {
      setState(() => _audioLoadingId = attachment.id);
    }
    try {
      final fresh = await _api.chatAttachment(widget.matchId, attachment.id);
      if (!mounted ||
          !_current ||
          !_visible ||
          epoch != _audioEpoch ||
          fresh.url == null) {
        return;
      }
      if (fresh.kind == 'image') {
        await showDialog<void>(
          context: context,
          builder: (context) => Dialog(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: AspectRatio(
                aspectRatio: 1,
                child: ProfileImage(
                  fresh.url!,
                  decodeSize: 1024,
                  fallback: const Center(
                    child: Icon(Icons.broken_image_outlined),
                  ),
                ),
              ),
            ),
          ),
        );
      } else {
        setState(() {
          _playingId = fresh.id;
          _audioLoadingId = null;
        });
        await _player.play(fresh.url!);
      }
    } catch (_) {
      if (_current) {
        _notice('This attachment is not available. Refresh the conversation.');
      }
    } finally {
      if (_current && epoch == _audioEpoch) {
        setState(() {
          _playingId = null;
          _audioLoadingId = null;
        });
      }
    }
  }

  Widget _mediaBubble(ChatAttachment attachment) {
    if (attachment.status != 'ready' || attachment.url == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              attachment.kind == 'audio'
                  ? Icons.mic_none
                  : Icons.image_outlined,
              size: 18,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                attachment.status == 'processing'
                    ? 'Processing attachment…'
                    : 'Attachment unavailable',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      );
    }
    if (attachment.kind == 'image') {
      return GestureDetector(
        onTap: () => _openAttachment(attachment),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: 1,
            child: ProfileImage(
              attachment.url!,
              fallback: const Center(
                child: Icon(Icons.image_not_supported_outlined),
              ),
            ),
          ),
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: _playingId == attachment.id
              ? 'Pause voice note'
              : 'Play voice note',
          onPressed: () => _openAttachment(attachment),
          icon: _audioLoadingId == attachment.id
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  _playingId == attachment.id
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                ),
        ),
        const Icon(Icons.graphic_eq_rounded, color: AppColors.accentSoft),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${attachment.durationMs ~/ 60000}:${((attachment.durationMs ~/ 1000) % 60).toString().padLeft(2, '0')}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              if (attachment.voiceDisguised)
                const Text(
                  'Voice disguised',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.secondaryText,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _bubble(ChatMessage message, bool mine) => SwipeReply(
    key: ValueKey('chat-message-${message.messageId}'),
    onReply: message.moderationStatus == 'clear'
        ? () => _selectReply(message)
        : null,
    child: Align(
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
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.replyTo != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(8),
                  border: const Border(
                    left: BorderSide(color: AppColors.coral, width: 2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      message.replyTo!.senderId == _match?.viewerProfileId
                          ? 'You'
                          : _match?.alias ?? 'Your match',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      _quoteText(message.replyTo!.body, message.replyTo!.kind),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            if (message.attachment != null) _mediaBubble(message.attachment!),
            if (message.body.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  message.body,
                  style: const TextStyle(color: AppColors.text),
                ),
              ),
            if (mine)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: MessageTicks(message),
              ),
          ],
        ),
      ),
    ),
  );

  Widget _input() => Padding(
    padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        IconButton(
          tooltip: 'Share photo',
          onPressed: _sending || _mediaBusy ? null : _choosePhoto,
          icon: Icon(
            _match?.state == 'unmasked'
                ? Icons.add_photo_alternate_outlined
                : Icons.lock_outline_rounded,
          ),
        ),
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
            onChanged: _typingChanged,
            decoration: const InputDecoration(
              hintText: 'Say something kind…',
              counterText: '',
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Record voice note',
          onPressed: _sending || _mediaBusy || _draft != null
              ? null
              : _startRecording,
          icon: const Icon(Icons.mic_none_rounded),
        ),
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
    if ((body.isEmpty && _draft == null) || _sending || _closed) return;
    final epoch = _epoch;
    final fingerprint =
        '$body|${_reply?.messageId ?? ''}|${_draft?.path ?? ''}';
    if (_retryBody != fingerprint) {
      _retryId = const Uuid().v4();
      _retryBody = fingerprint;
    }
    setState(() => _sending = true);
    try {
      String? attachment;
      if (_draft != null) {
        final file = _draft!;
        final bytes = _draftBytes ?? await file.readAsBytes();
        if (!_current || epoch != _epoch) return;
        final kind = _draftKind!;
        final name = file.name.toLowerCase();
        final contentType = kind == 'audio'
            ? 'audio/mp4'
            : name.endsWith('.png')
            ? 'image/png'
            : name.endsWith('.webp')
            ? 'image/webp'
            : 'image/jpeg';
        _uploadTicket ??= await _api.requestChatUpload(
          widget.matchId,
          kind: kind,
          contentType: contentType,
          sizeBytes: bytes.length,
        );
        if (!_current || epoch != _epoch) return;
        if (!_uploaded) {
          await _api.putMedia(_uploadTicket!, bytes);
          _uploaded = true;
        }
        if (!_current || epoch != _epoch) return;
        attachment = _uploadTicket!['upload_id'] as String;
        if (!_completed) {
          await _api.completeChatUpload(widget.matchId, attachment);
          _completed = true;
        }
      }
      if (!_current || epoch != _epoch) return;
      final message = await _api.sendMessage(
        matchId: widget.matchId,
        body: body,
        clientMessageId: _retryId,
        replyToId: _reply?.messageId,
        attachmentId: attachment,
      );
      if (!_current || epoch != _epoch) return;
      _composer.clear();
      _retryId = null;
      _retryBody = null;
      setState(() {
        _merge([message]);
        _reply = null;
        _draft = null;
        _draftBytes = null;
        _uploadTicket = null;
        _uploaded = false;
        _completed = false;
      });
      unawaited(_activity(true));
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
  'reply_message_unavailable' =>
    'That message is no longer available to reply to.',
  'photos_require_mutual_reveal' =>
    'Photo sharing unlocks after you both agree to reveal.',
  'voice_consent_required' =>
    'Allow voice sharing in Privacy settings before sending a note.',
  'media_too_large' || 'media_size_or_type_invalid' =>
    'Choose a smaller photo or record a shorter voice note.',
  'media_storage_unavailable' =>
    'Upload is temporarily unavailable. Your draft is kept here to retry.',
  'attachment_unavailable' =>
    'This attachment is no longer available. Remove it and choose it again.',
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
