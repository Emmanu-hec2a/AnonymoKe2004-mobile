import '../../../core/widgets/loading_skeleton.dart';
import '../../../core/widgets/profile_image.dart';
import 'tab_refresh.dart';
import 'match_sheets.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/location_service.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/verified_badge.dart';
import 'widgets/discovery_deck.dart';
import '../../onboarding/application/consent_documents.dart';

class BackendDiscoverScreen extends ConsumerStatefulWidget {
  const BackendDiscoverScreen({super.key});

  @override
  ConsumerState<BackendDiscoverScreen> createState() =>
      _BackendDiscoverScreenState();
}

class _BackendDiscoverScreenState extends ConsumerState<BackendDiscoverScreen>
    with WidgetsBindingObserver {
  late Future<List<DiscoveryCard>> _request;
  final AudioPlayer _audioPlayer = AudioPlayer();
  int _index = 0;
  String? _nextCursor;
  bool _paging = false, _hadCandidates = false;
  bool get _inputLocked => _busy || _loading;
  String? _pageError;
  final _decidedIds = <String>{};
  final _usedCursors = <String>{};
  double _distanceKm = 5;
  RangeValues _ageRange = const RangeValues(24, 34);
  String? _playingProfileId;
  bool _loading = false;
  bool _visible = true, _foreground = true, _feedDirty = false;
  DateTime? _lastLoaded;
  int _loadEpoch = 0;
  String? _bufferingProfileId;
  final _deckKey = GlobalKey<DiscoveryDeckState>();
  bool _busy = false;
  ProfileSummary? _profile;
  List<DiscoveryCard> _cards = const [];
  int _voiceRequest = 0;
  final _pendingIds = <String, String>{};
  SwipeOutcome? _outcome;
  ({DiscoveryCard card, String id, String action})? _lastSwipe;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _request = _loadCards();
  }

  @override
  void dispose() {
    _loadEpoch++;
    WidgetsBinding.instance.removeObserver(this);
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (state != AppLifecycleState.resumed) unawaited(_stopVoice());
    if (_foreground && _visible && !_busy) _refreshVisible();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.valuesOf(context).enabled;
    if (visible == _visible) return;
    _visible = visible;
    if (!visible) {
      unawaited(_stopVoice());
    } else if (_foreground &&
        (_feedDirty ||
            _lastLoaded == null ||
            DateTime.now().difference(_lastLoaded!) >
                const Duration(seconds: 30))) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _visible) _refreshVisible();
      });
    }
  }

  Future<List<DiscoveryCard>> _loadCards() async {
    final epoch = ++_loadEpoch;
    _paging = false;
    final owner = ref.read(authControllerProvider).session?.userId;
    bool current() =>
        mounted &&
        epoch == _loadEpoch &&
        owner == ref.read(authControllerProvider).session?.userId;
    _loading = true;
    try {
      final api = ref.read(apiClientProvider);
      final initial = await Future.wait<Object>([
        api.profile(),
        api.consents(),
      ]);
      if (!current()) return const [];
      final profile = initial[0] as ProfileSummary;
      _profile = profile;
      if (!profile.isDiscoverable) throw const ApiException('profile_paused');
      if (profile.gender.isEmpty) {
        throw const ApiException('profile_incomplete');
      }
      _distanceKm = profile.maxDistanceKm.clamp(1, 50).toDouble();
      _ageRange = RangeValues(
        profile.minAgePref.clamp(18, 100).toDouble(),
        profile.maxAgePref.clamp(18, 100).toDouble(),
      );
      final consents = initial[1] as List<ConsentSummary>;
      if (!mounted) return const [];
      for (final kind in ['location', 'sensitive_data']) {
        if (!consents.any((item) => item.type == kind && item.granted)) {
          throw ApiException('${kind}_consent_required');
        }
      }
      await ref
          .read(discoveryLocationProvider)
          .sync(api, profileId: profile.profileId);
      if (!current()) return const [];
      final page = await api.discoveryPage();
      final loaded = page.items;
      if (!current()) return const [];
      // A fresh server query is authoritative, including likes withdrawn elsewhere.
      _decidedIds.clear();
      final previousId = _index < _cards.length
          ? _cards[_index].profileId
          : null;
      _cards = loaded
          .where((card) => !_decidedIds.contains(card.profileId))
          .toList();
      final previousIndex = _cards.indexWhere(
        (card) => card.profileId == previousId,
      );
      _index = previousIndex < 0 ? 0 : previousIndex;
      _nextCursor = page.nextCursor;
      _usedCursors.clear();
      _pageError = null;
      _hadCandidates = _hadCandidates || loaded.isNotEmpty;
      _lastLoaded = DateTime.now();
      _feedDirty = false;
      _preload(_cards, 0);
      return _cards;
    } finally {
      if (epoch == _loadEpoch) _loading = false;
    }
  }

  void _reload() {
    if (!mounted || _busy || _loading) return;
    unawaited(_stopVoice());
    setState(() {
      _request = _loadCards();
    });
  }

  void _refreshVisible() {
    if (_feedDirty || _cards.isEmpty || _index >= _cards.length) {
      _reload();
      return;
    }
    if (_lastLoaded != null &&
        DateTime.now().difference(_lastLoaded!) < const Duration(seconds: 30)) {
      return;
    }
    unawaited(_refreshCurrentCard());
  }

  Future<void> _refreshCurrentCard() async {
    if (_loading || _busy || _paging || _index >= _cards.length) return;
    final epoch = _loadEpoch;
    final owner = ref.read(authControllerProvider).session?.userId;
    final id = _cards[_index].profileId;
    try {
      final fresh = await ref.read(apiClientProvider).discoveryProfile(id);
      if (!mounted ||
          epoch != _loadEpoch ||
          owner != ref.read(authControllerProvider).session?.userId) {
        return;
      }
      final position = _cards.indexWhere((card) => card.profileId == id);
      if (position >= 0) {
        setState(() {
          _cards[position] = fresh;
        });
      }
    } on ApiException catch (error) {
      if (mounted &&
          epoch == _loadEpoch &&
          owner == ref.read(authControllerProvider).session?.userId) {
        if (error.statusCode == 401 ||
            error.statusCode == 403 ||
            const {
              'profile_not_eligible',
              'profile_not_found',
              'profile_paused',
              'account_not_active',
            }.contains(error.code)) {
          _feedDirty = true;
          _reload();
        }
      }
    } catch (_) {
      /* A temporary refresh failure retains the browsing position. */
    }
  }

  Future<void> _stopVoice() async {
    _voiceRequest++;
    try {
      await _audioPlayer.stop();
    } catch (_) {
      /* Already disposed. */
    }
    if (mounted && (_playingProfileId != null || _bufferingProfileId != null)) {
      setState(() {
        _playingProfileId = null;
        _bufferingProfileId = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      authControllerProvider.select((state) => state.session?.userId),
      (before, after) {
        if (before == after) return;
        _loadEpoch++;
        _loading = false;
        _feedDirty = true;
        _cards = const [];
        _profile = null;
        _busy = false;
        _pendingIds.clear();
        _decidedIds.clear();
        _usedCursors.clear();
        _nextCursor = null;
        _hadCandidates = false;
        _paging = false;
        _pageError = null;
        _outcome = null;
        _lastSwipe = null;
        unawaited(_stopVoice());
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _visible) _reload();
        });
      },
    );
    ref.listen(discoveryRefreshSignal, (_, _) {
      _feedDirty = true;
      _hadCandidates = false;
      _cards = const [];
      if (_visible && _foreground && !_busy) {
        setState(() {
          _index = 0;
          _request = _loadCards();
        });
      }
    });
    return FutureBuilder<List<DiscoveryCard>>(
      future: _request,
      builder: (context, snapshot) {
        final cards = _feedDirty ? const <DiscoveryCard>[] : _cards;
        if (snapshot.connectionState == ConnectionState.waiting &&
            cards.isEmpty) {
          return AppPage(
            child: Column(
              children: [
                _topBar(context),
                const ContentSkeleton(content: SkeletonContent.discover),
              ],
            ),
          );
        }
        if (snapshot.hasError) return _emptyState(context, snapshot.error);
        if (cards.isEmpty || _index >= cards.length) {
          if (_nextCursor != null || _paging || _pageError != null) {
            return _moreProfilesState(context);
          }
          return _emptyState(context, null);
        }
        return _cardView(context, cards);
      },
    );
  }

  Widget _cardView(BuildContext context, List<DiscoveryCard> cards) {
    final card = cards[_index];
    return AppPage(
      child: Column(
        children: [
          _topBar(context),
          const SizedBox(height: 14),
          DiscoveryDeck(
            key: _deckKey,
            itemId: card.profileId,
            enabled: !_inputLocked,
            confirmSwipe: (direction) => _submitSwipe(card, direction),
            canBrowse: _prepareBrowse,
            onBrowse: _finishBrowse,
            canBrowsePrevious: _index > 0,
            previousChild: _index > 0 ? _profileCard(cards[_index - 1]) : null,
            onSwipe: (_) => _finishSwipe(card, cards.length),
            onDetails: () => _showDetails(card),
            nextChild: _index + 1 < cards.length
                ? _profileCard(cards[_index + 1])
                : null,
            child: _profileCard(card),
          ),
          const SizedBox(height: 18),
          if (_inputLocked)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: LinearProgressIndicator(),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _roundAction(
                Icons.undo_rounded,
                AppColors.gold,
                _lastSwipe == null || _inputLocked ? null : _undo,
              ),
              const SizedBox(width: 22),
              _roundAction(
                Icons.close,
                AppColors.danger,
                _inputLocked ? null : () => _deckKey.currentState?.swipe(-1),
              ),
              const SizedBox(width: 22),
              _roundAction(
                Icons.favorite,
                AppColors.coral,
                _inputLocked ? null : () => _deckKey.currentState?.swipe(1),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _profileCard(DiscoveryCard card) {
    return Container(
      height: 500,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        color: AppColors.ink,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(gradient: AppGradients.blurredAvatar),
            ),
          ),
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: card.blurredAvatarUrl == null
                  ? const Center(
                      child: Icon(
                        Icons.person,
                        size: 180,
                        color: Colors.white30,
                      ),
                    )
                  : ProfileImage(
                      card.blurredAvatarUrl!,
                      fit: BoxFit.cover,
                      fallback: const Center(
                        child: Icon(
                          Icons.person,
                          size: 180,
                          color: Colors.white30,
                        ),
                      ),
                    ),
            ),
          ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black87],
                ),
              ),
            ),
          ),
          Positioned(
            top: 14,
            left: 14,
            child: Pill(
              card.distanceBucket,
              icon: Icons.location_on_outlined,
              color: Colors.white,
            ),
          ),
          Positioned(top: 14, right: 14, child: _voicePill(card)),
          Positioned(
            left: 20,
            right: 20,
            bottom: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        card.alias,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    if (card.isVerified) ...[
                      const SizedBox(width: 8),
                      const VerifiedBadge(),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${card.ageYears}  ·  Active recently',
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: card.interests
                      .map((tag) => Pill(tag, color: Colors.white70))
                      .toList(),
                ),
                const SizedBox(height: 34),
                Center(
                  child: TextButton(
                    onPressed: _busy ? null : () => _showDetails(card),
                    child: const Text(
                      'Drag up for more',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _topBar(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: BrandHeaderLogo()),
        const SizedBox(width: 10),
        _squareAction(
          Icons.tune_rounded,
          AppColors.surface,
          _busy || _loading || _profile == null ? null : _showFilters,
        ),
        const SizedBox(width: 10),
        _squareAction(
          Icons.bolt_rounded,
          AppColors.gold,
          _busy
              ? null
              : () async {
                  await _stopVoice();
                  if (context.mounted) await context.push('/app/boost');
                  _reload();
                },
        ),
      ],
    );
  }

  Widget _squareAction(IconData icon, Color background, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.line),
        ),
        child: Icon(
          icon,
          color: background == AppColors.gold ? AppColors.ink : AppColors.text,
        ),
      ),
    );
  }

  Widget _voicePill(DiscoveryCard card) {
    final isPlaying = _playingProfileId == card.profileId;
    final isBuffering = _bufferingProfileId == card.profileId;
    final duration = card.audioDurationSeconds == null
        ? '0:12'
        : '0:${card.audioDurationSeconds!.round().toString().padLeft(2, '0')}';
    return GestureDetector(
      onTap: _busy || isBuffering ? null : () => _toggleVoice(card),
      child: Container(
        padding: const EdgeInsets.fromLTRB(5, 5, 10, 5),
        decoration: BoxDecoration(
          color: AppColors.ink.withValues(alpha: .78),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 27,
              height: 27,
              decoration: const BoxDecoration(
                color: AppColors.accent,
                shape: BoxShape.circle,
              ),
              child: isBuffering
                  ? const Padding(
                      padding: EdgeInsets.all(7),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.text,
                      ),
                    )
                  : Icon(
                      isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: AppColors.text,
                      size: 17,
                    ),
            ),
            const SizedBox(width: 7),
            const Icon(Icons.graphic_eq, color: AppColors.accentSoft, size: 18),
            const SizedBox(width: 5),
            Text(
              duration,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleVoice(DiscoveryCard card) async {
    final requestId = ++_voiceRequest;
    try {
      if (_playingProfileId == card.profileId && _audioPlayer.playing) {
        await _audioPlayer.pause();
        if (mounted) setState(() => _playingProfileId = null);
        return;
      }
      setState(() => _bufferingProfileId = card.profileId);
      final fresh = await ref
          .read(apiClientProvider)
          .discoveryProfile(card.profileId);
      if (!mounted || requestId != _voiceRequest) return;
      if (fresh.audioUrl == null) {
        _message('This profile has no available voice capsule.');
        return;
      }
      await _audioPlayer.setUrl(fresh.audioUrl!);
      if (!mounted || requestId != _voiceRequest) return;
      if (mounted) {
        setState(() {
          _playingProfileId = card.profileId;
          _bufferingProfileId = null;
        });
      }
      await _audioPlayer.play();
      if (mounted &&
          requestId == _voiceRequest &&
          _playingProfileId == card.profileId) {
        setState(() => _playingProfileId = null);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _playingProfileId = null);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Voice capsule could not be played.')),
        );
      }
    } finally {
      if (mounted &&
          requestId == _voiceRequest &&
          _bufferingProfileId != null) {
        setState(() => _bufferingProfileId = null);
      }
    }
  }

  Future<void> _showFilters() async {
    if (_busy || _loading || (_deckKey.currentState?.isAnimating ?? false)) {
      return;
    }
    await _stopVoice();
    if (!mounted) return;
    var distanceKm = _distanceKm;
    var ageRange = _ageRange;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.strongLine,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Filters',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Location',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    Text(
                      'Within ${distanceKm.round()} km',
                      style: const TextStyle(color: AppColors.accentSoft),
                    ),
                  ],
                ),
                Slider(
                  value: distanceKm,
                  min: 1,
                  max: 50,
                  divisions: 49,
                  label: '${distanceKm.round()} km',
                  onChanged: (value) => setModalState(() => distanceKm = value),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Age range',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    Text(
                      '${ageRange.start.round()}–${ageRange.end.round()}',
                      style: const TextStyle(color: AppColors.accentSoft),
                    ),
                  ],
                ),
                RangeSlider(
                  values: ageRange,
                  min: 18,
                  max: 100,
                  divisions: 82,
                  labels: RangeLabels(
                    '${ageRange.start.round()}',
                    '${ageRange.end.round()}',
                  ),
                  onChanged: (value) => setModalState(() => ageRange = value),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton(
                      onPressed: () async {
                        final saved = await _saveFilters(
                          15,
                          const RangeValues(18, 35),
                        );
                        if (saved && context.mounted) Navigator.pop(context);
                      },
                      child: const Text('Clear filters'),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          final saved = await _saveFilters(
                            distanceKm,
                            ageRange,
                          );
                          if (saved && context.mounted) Navigator.pop(context);
                        },
                        child: const Text('Apply filters'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyState(BuildContext context, Object? failure) {
    final error = failure is ApiException
        ? failure.code
        : failure == null
        ? null
        : 'network_error';
    return AppPage(
      child: SingleChildScrollView(
        child: Column(
          children: [
            _topBar(context),
            const SizedBox(height: 60),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.explore_off_outlined,
                  size: 60,
                  color: AppColors.accent,
                ),
                const SizedBox(height: 20),
                Text(
                  error == null
                      ? _hadCandidates
                            ? 'You’re all caught up nearby'
                            : 'No profiles match your preferences yet'
                      : _errorText(error),
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  error == null
                      ? _cards.isNotEmpty
                            ? 'Your likes are saved. You can browse undecided profiles again or adjust your filters.'
                            : 'Your likes are saved. New people will appear here as they become available.'
                      : 'Your profile and private photos stay protected while you resolve this.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted),
                ),
                const SizedBox(height: 20),
                if (error == null && _cards.isNotEmpty)
                  FilledButton(
                    onPressed: () => setState(() => _index = 0),
                    child: const Text('Browse again'),
                  ),
                if (error == null) ...[
                  OutlinedButton(
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => const SentLikesSheet(),
                    ),
                    child: const Text('View likes sent'),
                  ),
                  TextButton(
                    onPressed: () => _showFilters(),
                    child: const Text('Adjust discovery filters'),
                  ),
                ],
                if (_paging)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(),
                  ),
                if (_pageError != null)
                  Text(_pageError!, textAlign: TextAlign.center),
                OutlinedButton(
                  onPressed: _paging
                      ? null
                      : () => _pageError != null && _nextCursor != null
                            ? _loadMore()
                            : _recover(error),
                  child: Text(
                    _pageError != null
                        ? 'Retry loading profiles'
                        : error == null
                        ? 'Check for new people'
                        : _recoveryLabel(error),
                  ),
                ),
                if (_lastSwipe != null)
                  TextButton(
                    onPressed: _busy ? null : _undo,
                    child: Text(
                      _lastSwipe!.action == 'like'
                          ? 'Undo last like'
                          : 'Undo last pass',
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _roundAction(IconData icon, Color color, VoidCallback? onPressed) {
    return IconButton.filledTonal(
      onPressed: onPressed,
      icon: Icon(icon, color: color),
      iconSize: 32,
      style: IconButton.styleFrom(
        padding: const EdgeInsets.all(14),
        backgroundColor: color.withValues(alpha: .14),
      ),
    );
  }

  Future<bool> _loadMore() async {
    if (_paging || _nextCursor == null) return !_paging;
    final epoch = _loadEpoch;
    final owner = ref.read(authControllerProvider).session?.userId;
    final cursor = _nextCursor!;
    setState(() {
      _paging = true;
      _pageError = null;
    });
    try {
      final page = await ref
          .read(apiClientProvider)
          .discoveryPage(cursor: cursor);
      if (!mounted ||
          epoch != _loadEpoch ||
          owner != ref.read(authControllerProvider).session?.userId) {
        return false;
      }
      if (page.nextCursor == cursor ||
          (page.nextCursor != null && _usedCursors.contains(page.nextCursor))) {
        throw const ApiException('cursor_invalid');
      }
      setState(() {
        _usedCursors.add(cursor);
        final existing = _cards.map((card) => card.profileId).toSet();
        _cards = [
          ..._cards,
          ...page.items.where(
            (card) =>
                !_decidedIds.contains(card.profileId) &&
                existing.add(card.profileId),
          ),
        ];
        _nextCursor = page.nextCursor;
        _hadCandidates = _hadCandidates || page.items.isNotEmpty;
      });
      _preload(_cards, _index);
      return true;
    } catch (error) {
      if (mounted &&
          epoch == _loadEpoch &&
          owner == ref.read(authControllerProvider).session?.userId) {
        setState(
          () => _pageError =
              error is ApiException && error.code == 'cursor_invalid'
              ? 'Your browsing session changed. Check for new people to continue.'
              : 'Could not load the next profiles. Your place is kept.',
        );
        if (error is ApiException && error.code == 'cursor_invalid') {
          _nextCursor = null;
        }
      }
      return false;
    } finally {
      if (mounted && epoch == _loadEpoch) setState(() => _paging = false);
    }
  }

  bool _prepareBrowse(int direction) {
    if (_inputLocked || (direction > 0 && _index == 0)) return false;
    unawaited(_stopVoice());
    return true;
  }

  void _prefetchIfNeeded() {
    if (!mounted ||
        !_visible ||
        !_foreground ||
        _loading ||
        _paging ||
        _pageError != null ||
        _nextCursor == null ||
        _cards.length - _index > 3) {
      return;
    }
    unawaited(_loadMore());
  }

  Widget _moreProfilesState(BuildContext context) {
    return AppPage(
      child: Column(
        children: [
          _topBar(context),
          const SizedBox(height: 96),
          if (_paging) const CircularProgressIndicator(),
          const SizedBox(height: 20),
          Text(
            _paging ? 'Loading more profiles' : 'More profiles could not load',
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            _pageError ?? 'You can keep browsing the profiles already loaded.',
            style: const TextStyle(color: AppColors.muted),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          if (_cards.isNotEmpty)
            OutlinedButton(
              onPressed: () {
                setState(
                  () => _index = (_index - 1).clamp(0, _cards.length - 1),
                );
                _preload(_cards, _index);
              },
              child: const Text('Previous profile'),
            ),
          if (!_paging)
            FilledButton(
              onPressed: () => _nextCursor == null ? _reload() : _loadMore(),
              child: const Text('Retry loading profiles'),
            ),
          const SizedBox(height: 48),
        ],
      ),
    );
  }

  void _finishBrowse(int direction) {
    setState(
      () =>
          _index = (_index + (direction < 0 ? 1 : -1)).clamp(0, _cards.length),
    );
    _preload(_cards, _index);
  }

  Future<bool> _submitSwipe(DiscoveryCard card, int direction) async {
    if (_inputLocked) return false;
    final owner = ref.read(authControllerProvider).session?.userId;
    final action = direction < 0 ? 'pass' : 'like';
    final key = '${card.profileId}:$action';
    final clientId = _pendingIds.putIfAbsent(key, () => const Uuid().v4());
    setState(() => _busy = true);
    await _stopVoice();
    if (!mounted || owner != ref.read(authControllerProvider).session?.userId) {
      return false;
    }
    try {
      final outcome = await ref
          .read(apiClientProvider)
          .swipe(
            profileId: card.profileId,
            action: action,
            clientSwipeId: clientId,
          );
      if (!mounted ||
          owner != ref.read(authControllerProvider).session?.userId) {
        return false;
      }
      _outcome = outcome;
      // A matched like is withdrawn by closing the match, not by undo.
      _lastSwipe = outcome.isMatch
          ? null
          : (card: card, id: outcome.clientSwipeId ?? clientId, action: action);
      _pendingIds.remove(key);
      return true;
    } on ApiException catch (error) {
      if (mounted &&
          owner == ref.read(authControllerProvider).session?.userId) {
        setState(() => _busy = false);
        _message(_errorText(error.code), retry: _reload);
      }
      return false;
    } catch (_) {
      if (mounted &&
          owner == ref.read(authControllerProvider).session?.userId) {
        setState(() => _busy = false);
        _message('Could not send your swipe. Try again.');
      }
      return false;
    }
  }

  void _finishSwipe(DiscoveryCard card, int count) {
    final outcome = _outcome;
    setState(() {
      _decidedIds.add(card.profileId);
      _cards = _cards
          .where((item) => item.profileId != card.profileId)
          .toList();
      _busy = false;
      _outcome = null;
    });
    _preload(_cards, _index);
    if (_index >= _cards.length && _nextCursor != null) {
      unawaited(_loadMore());
    }
    if (outcome?.isMatch != true) {
      _message(_lastSwipe?.action == 'like' ? 'Like sent' : 'Profile passed');
    }
    if (outcome?.isMatch == true && outcome?.matchId != null) {
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text("It's a match!"),
          content: Text('You and ${card.alias} liked each other. Say hello.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Keep discovering'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                context.push('/app/matches/${outcome!.matchId}');
              },
              child: const Text('Send a message'),
            ),
          ],
        ),
      );
    }
  }

  void _preload(List<DiscoveryCard> cards, int index) {
    final owner = ref.read(authControllerProvider).session?.userId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_visible ||
          owner != ref.read(authControllerProvider).session?.userId) {
        return;
      }
      _prefetchIfNeeded();
      final cache = ref.read(profileImageCacheProvider);
      for (final card in cards.skip(index + 1).take(2)) {
        final url = card.blurredAvatarUrl;
        if (url != null) {
          unawaited(
            precacheImage(
              cache.image(url, 512),
              context,
              onError: (_, _) => cache.remove(url),
            ),
          );
        }
      }
    });
  }

  Future<void> _undo() async {
    final last = _lastSwipe;
    if (last == null || _busy || _deckKey.currentState?.isAnimating == true) {
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(apiClientProvider).undoPass(last.id);
      if (!mounted) return;
      final restored = await ref
          .read(apiClientProvider)
          .discoveryProfile(last.card.profileId);
      if (!mounted) return;
      final remaining = _cards.where(
        (card) => card.profileId != restored.profileId,
      );
      final cards = [restored, ...remaining];
      _decidedIds.remove(restored.profileId);
      _lastSwipe = null;
      setState(() {
        _busy = false;
        _index = 0;
        _cards = cards;
        _request = Future.value(cards);
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      if (error.code == 'premium_required') {
        context.push('/app/store', extra: 0);
      } else {
        if (error.code == 'like_already_matched' ||
            error.code == 'swipe_not_found') {
          _lastSwipe = null;
        }
        _message(_errorText(error.code));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        _message('Could not undo that ${last.action}. Try again.');
      }
    }
  }

  Future<bool> _saveFilters(double distance, RangeValues ages) async {
    if (_busy) return false;
    setState(() => _busy = true);
    try {
      await ref.read(apiClientProvider).updateProfile({
        'max_distance_km': distance.round(),
        'min_age_pref': ages.start.round(),
        'max_age_pref': ages.end.round(),
      });
      if (!mounted) return false;
      _busy = false;
      _hadCandidates = false;
      _cards = const [];
      _index = 0;
      _reload();
      return true;
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => _busy = false);
        _message(_errorText(error.code));
      }
      return false;
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        _message('Could not save filters. Try again.');
      }
      return false;
    }
  }

  void _message(String text, {VoidCallback? retry}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          action: retry == null
              ? null
              : SnackBarAction(label: 'Refresh', onPressed: retry),
        ),
      );
  }

  String _errorText(String code) => switch (code) {
    'cursor_invalid' =>
      'Your browsing session expired. Refresh to see available profiles.',
    'location_consent_required' =>
      'Allow location processing to find people nearby.',
    'sensitive_data_consent_required' || 'matching_preferences_required' =>
      'Choose your private matching preferences to continue.',
    'location_permission_denied' =>
      'Allow location access to find people nearby.',
    'location_permission_denied_forever' =>
      'Enable location access in your phone settings.',
    'location_services_disabled' => 'Switch on your phone location service.',
    'location_required' ||
    'location_stale' => 'Refresh your location to find people nearby.',
    'location_flagged' =>
      'Your location could not be verified. Try again from your current location.',
    'location_timeout' || 'location_accuracy_too_low' =>
      'Could not get an accurate location. Try again with a clearer GPS signal.',
    'profile_paused' => 'Your discovery profile is paused.',
    'profile_incomplete' => 'Complete your profile before discovering people.',
    'verification_required_before_discovery' =>
      'Verify your profile before discovering people.',
    'session_expired' ||
    'refresh_token_invalid' => 'Sign in again to continue.',
    'profile_not_eligible' || 'profile_not_found' =>
      'This profile is no longer available. Refresh your feed.',
    'rate_limited' =>
      'You are moving quickly. Please wait a moment and try again.',
    'only_latest_pass_can_be_undone' =>
      'Only your most recent pass can be undone.',
    'like_already_matched' =>
      'You already matched. Close the conversation from Matches instead.',
    'swipe_not_found' || 'pass_not_found' => 'Nothing to undo.',
    'swipe_already_recorded' =>
      'This action was already recorded. Refresh your feed.',
    _ => 'Could not connect. Check your connection and try again.',
  };

  String _recoveryLabel(String code) => switch (code) {
    'location_consent_required' ||
    'sensitive_data_consent_required' ||
    'matching_preferences_required' => 'Review privacy choices',
    'location_permission_denied_forever' ||
    'location_services_disabled' => 'Open settings',
    'profile_paused' => 'Resume my profile',
    'profile_incomplete' => 'Complete profile',
    'session_expired' || 'refresh_token_invalid' => 'Sign in',
    'verification_required_before_discovery' => 'Open Safety center',
    _ => 'Try again',
  };

  Future<void> _recover(String? code) async {
    if (code == 'location_permission_denied_forever') {
      await Geolocator.openAppSettings();
      return;
    }
    if (code == 'location_services_disabled') {
      await Geolocator.openLocationSettings();
      return;
    }
    if (code == 'profile_incomplete') {
      context.go('/onboarding/1');
      return;
    }
    if (code == 'verification_required_before_discovery') {
      context.go('/app/safety');
      return;
    }
    if (code == 'session_expired' || code == 'refresh_token_invalid') {
      await ref.read(apiClientProvider).store.clear();
      if (mounted) context.go('/auth');
      return;
    }
    if (code == 'location_consent_required' ||
        code == 'sensitive_data_consent_required' ||
        code == 'matching_preferences_required') {
      await _reviewPrivacy();
      return;
    }
    try {
      if (code == 'profile_paused') {
        await ref.read(apiClientProvider).updateProfile({
          'is_discoverable': true,
        });
      }
      ref.read(discoveryLocationProvider).invalidate();
      _reload();
    } on ApiException catch (error) {
      _message(_errorText(error.code));
    }
  }

  Future<void> _reviewPrivacy() async {
    var location = false;
    var matching = false;
    String? target;
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Your privacy choices'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: location,
                  onChanged: (value) => update(() => location = value ?? false),
                  title: const Text('Location'),
                  subtitle: const Text(
                    'Find people nearby using an approximate area. Your exact spot is never shown.',
                  ),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: matching,
                  onChanged: (value) => update(() => matching = value ?? false),
                  title: const Text('Matching details'),
                  subtitle: const Text(
                    'Use your gender and preferences privately to find mutual matches.',
                  ),
                ),
                const Text('Who would you like to meet?'),
                Wrap(
                  spacing: 6,
                  children:
                      {
                            'M': 'Men',
                            'W': 'Women',
                            'NB': 'Non-binary',
                            'ALL': 'Everyone',
                          }.entries
                          .map(
                            (item) => ChoiceChip(
                              label: Text(item.value),
                              selected: target == item.key,
                              onSelected: (_) =>
                                  update(() => target = item.key),
                            ),
                          )
                          .toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: location && matching && target != null
                  ? () => Navigator.pop(dialogContext, target)
                  : null,
              child: const Text('Save choices'),
            ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    try {
      final api = ref.read(apiClientProvider);
      await api.recordConsent(
        type: 'location',
        version: ref.read(consentDocumentsProvider).version,
        granted: true,
      );
      await api.recordConsent(
        type: 'sensitive_data',
        version: ref.read(consentDocumentsProvider).version,
        granted: true,
      );
      await api.updatePreferences([selected]);
      ref.read(discoveryLocationProvider).invalidate();
      _reload();
    } on ApiException catch (error) {
      _message(_errorText(error.code));
    }
  }

  Future<void> _showDetails(DiscoveryCard card) async {
    if (_busy) return;
    await _stopVoice();
    if (!mounted) return;
    final detailsRequest = ref
        .read(apiClientProvider)
        .discoveryProfile(card.profileId);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: FutureBuilder<DiscoveryCard>(
            future: detailsRequest,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _errorText(
                        snapshot.error is ApiException
                            ? (snapshot.error as ApiException).code
                            : 'network_error',
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ],
                );
              }
              if (!snapshot.hasData) {
                return const ContentSkeleton(content: SkeletonContent.cards);
              }
              final details = snapshot.data!;
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            details.alias,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        if (details.isVerified) const VerifiedBadge(),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    Text(
                      '${details.ageYears}${details.heightCm == null ? '' : ' · ${details.heightCm} cm'} · ${details.distanceBucket}',
                      style: const TextStyle(color: AppColors.secondaryText),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      details.bio.isEmpty
                          ? 'Say hello to get to know them.'
                          : details.bio,
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: details.interests
                          .map((item) => Pill(item))
                          .toList(),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Photos stay private until you both agree to reveal.',
                      style: TextStyle(color: AppColors.secondaryText),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
