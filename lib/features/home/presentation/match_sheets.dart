import 'dart:async';
import '../../../core/widgets/profile_image.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import 'inbox_controller.dart';
import 'matches_screen.dart' show MatchAvatar;

class IncomingLikesSheet extends ConsumerStatefulWidget {
  const IncomingLikesSheet({super.key});
  @override
  ConsumerState<IncomingLikesSheet> createState() => _IncomingLikesSheetState();
}

class _IncomingLikesSheetState extends ConsumerState<IncomingLikesSheet> {
  LikesPage? _page;
  final _items = <DiscoveryCard>[];
  final _ids = <String, String>{};
  String? _error, _busy;
  bool _loading = false;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load({bool more = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref
          .read(apiClientProvider)
          .incomingLikes(cursor: more ? _page?.nextCursor : null);
      if (!mounted) return;
      setState(() {
        _page = page;
        if (!more) _items.clear();
        _items.addAll(
          page.items.where(
            (item) => !_items.any((old) => old.profileId == item.profileId),
          ),
        );
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not load your likes. Try again.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _like(DiscoveryCard card) async {
    if (_busy != null) return;
    setState(() => _busy = card.profileId);
    try {
      final outcome = await ref
          .read(apiClientProvider)
          .swipe(
            profileId: card.profileId,
            action: 'like',
            clientSwipeId: _ids.putIfAbsent(
              card.profileId,
              () => const Uuid().v4(),
            ),
          );
      if (!mounted) return;
      unawaited(ref.read(inboxProvider.notifier).refresh());
      if (outcome.isMatch && outcome.matchId != null) {
        final router = GoRouter.of(context);
        Navigator.pop(context);
        router.push('/app/matches/${outcome.matchId}');
      } else {
        _items.removeWhere((item) => item.profileId == card.profileId);
        await _load();
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not like this profile. It may no longer be available. Retry or refresh.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .78,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _page == null ? 'Your likes' : '${_page!.count} likes',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh likes',
                  onPressed: _loading ? null : () => _load(),
                  icon: const Icon(Icons.refresh),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: AppColors.coral)),
            if (_loading) const LinearProgressIndicator(),
            if (_page?.unavailableReason != null) ...[
              const SizedBox(height: 24),
              const Text(
                'Open Discover to update your location and matching preferences before viewing nearby likes.',
              ),
              TextButton(
                onPressed: () {
                  final router = GoRouter.of(context);
                  Navigator.pop(context);
                  router.go('/app/discover');
                },
                child: const Text('Open Discover'),
              ),
            ] else if (_page != null && !_page!.canView) ...[
              const SizedBox(height: 32),
              const Icon(Icons.lock_outline, color: AppColors.gold, size: 42),
              const SizedBox(height: 16),
              const Text(
                'See who likes you with Weekly Premium.',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text(
                'Profiles remain anonymous. A like back creates a match; revealing still needs both people’s agreement.',
                style: TextStyle(color: AppColors.secondaryText),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () async {
                  await context.push('/app/store', extra: 0);
                  if (mounted) await _load();
                },
                child: const Text('View Weekly Premium'),
              ),
            ] else if (_page != null)
              Expanded(
                child: ListView(
                  children: [
                    if (_items.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Text('No new nearby likes yet.'),
                      ),
                    ..._items.map(
                      (card) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: MatchAvatar(
                          id: card.profileId,
                          url: card.blurredAvatarUrl,
                        ),
                        title: Text(
                          card.alias,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${card.ageYears} · ${card.distanceBucket}',
                        ),
                        trailing: IconButton(
                          tooltip: 'Like back ${card.alias}',
                          onPressed: _busy == null ? () => _like(card) : null,
                          icon: _busy == card.profileId
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  Icons.favorite,
                                  color: AppColors.coral,
                                ),
                        ),
                      ),
                    ),
                    if (_page?.nextCursor != null)
                      TextButton(
                        onPressed: _loading ? null : () => _load(more: true),
                        child: const Text('Load more likes'),
                      ),
                  ],
                ),
              ),
            if (_page == null && !_loading)
              TextButton(
                onPressed: () => _load(),
                child: const Text('Try again'),
              ),
          ],
        ),
      ),
    ),
  );
}

class RevealedProfileSheet extends ConsumerStatefulWidget {
  const RevealedProfileSheet({
    required this.matchId,
    required this.alias,
    super.key,
  });
  final String matchId, alias;
  @override
  ConsumerState<RevealedProfileSheet> createState() =>
      _RevealedProfileSheetState();
}

class _RevealedProfileSheetState extends ConsumerState<RevealedProfileSheet>
    with WidgetsBindingObserver {
  Map<String, dynamic>? _identity;
  String? _error;
  Timer? _timer;
  bool _active = true, _loading = false;
  DateTime _urlLoaded = DateTime.fromMillisecondsSinceEpoch(0);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_active) unawaited(_load());
    });
    unawaited(_load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() {
      _active = state == AppLifecycleState.resumed;
      _identity = null;
    });
    if (_active) unawaited(_load());
  }

  Future<void> _load() async {
    if (_loading) return;
    _loading = true;
    try {
      final identity = await ref
          .read(apiClientProvider)
          .revealedIdentity(widget.matchId);
      if (!mounted || !_active) return;
      setState(() {
        // Signed original URLs expire after five minutes; do not churn the image on every poll.
        if (_identity?['real_avatar_url'] != null &&
            DateTime.now().difference(_urlLoaded).inMinutes < 4) {
          identity['real_avatar_url'] = _identity!['real_avatar_url'];
        } else {
          _urlLoaded = DateTime.now();
        }
        _identity = identity;
        _error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _identity = null;
          _error =
              'This revealed profile is unavailable. Both people must still consent and be verified.';
        });
      }
    } finally {
      _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final identity = _active ? _identity : null;
    final avatar = identity?['real_avatar_url'] as String?;
    final handles = identity?['social_handles'] as List? ?? const [];
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .78,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ListView(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.alias,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              if (_error != null) ...[
                Text(_error!),
                TextButton(onPressed: _load, child: const Text('Try again')),
              ] else if (identity == null)
                const Center(child: CircularProgressIndicator())
              else ...[
                if (avatar != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: ProfileImage(
                        avatar,
                        fit: BoxFit.cover,
                        fallback: const Center(
                          child: Icon(Icons.person, size: 70),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 18),
                if (identity['real_first_name'] != null)
                  Text(
                    '${identity['real_first_name']}',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                if (identity['username'] != null)
                  SelectableText('@${identity['username']}'),
                for (final handle in handles)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: SelectableText(
                      handle is Map
                          ? '${handle['platform'] ?? ''}: ${handle['handle'] ?? handle['username'] ?? ''}'
                          : '$handle',
                    ),
                  ),
                const SizedBox(height: 18),
                const Text(
                  'Shared with mutual consent. Respect their privacy.',
                  style: TextStyle(color: AppColors.secondaryText),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
