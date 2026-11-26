import '../../../core/widgets/app_surfaces.dart';
import '../../../core/widgets/loading_skeleton.dart';
import '../../../core/widgets/profile_image.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/auth/auth_controller.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/verified_badge.dart';
import 'profile_controller.dart';
import 'profile_device.dart';
import 'profile_sheets.dart';
import '../../onboarding/application/consent_documents.dart';

class BackendProfileScreen extends ConsumerStatefulWidget {
  const BackendProfileScreen({super.key});
  @override
  ConsumerState<BackendProfileScreen> createState() =>
      _BackendProfileScreenState();
}

class _BackendProfileScreenState extends ConsumerState<BackendProfileScreen>
    with WidgetsBindingObserver {
  bool _busy = false, _playing = false;
  bool _buffering = false, _visible = true, _foreground = true;
  int _voiceEpoch = 0;
  late final ProfilePlayer _player;
  ApiClient get _api => ref.read(apiClientProvider);
  @override
  void initState() {
    super.initState();
    _player = ref.read(profilePlayerProvider)();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _voiceEpoch++;
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    ref.read(profileProvider.notifier).setActive(_foreground && _visible);
    if (state != AppLifecycleState.resumed) unawaited(_stopVoice());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.valuesOf(context).enabled;
    if (_visible == visible) return;
    _visible = visible;
    ref.read(profileProvider.notifier).setActive(visible && _foreground);
    if (!visible) unawaited(_stopVoice());
  }

  void _message(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          backgroundColor: error ? AppColors.danger : AppColors.teal,
        ),
      );
  }

  Future<void> _perform(
    Future<void> Function() operation, {
    bool reload = true,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await operation();
      if (mounted && reload) {
        await ref.read(profileProvider.notifier).afterMutation();
      }
    } on ApiException catch (e) {
      _message(profileError(e.code), error: true);
      if (mounted && reload) {
        unawaited(ref.read(profileProvider.notifier).afterMutation());
      }
    } catch (_) {
      _message(
        'Could not complete this request. Please try again.',
        error: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setPaused(bool paused) => _perform(() async {
    final owner = ref.read(authControllerProvider).session?.userId;
    await ref.read(profileProvider.notifier).setDiscoverable(!paused);
    if (mounted && ref.read(authControllerProvider).session?.userId == owner) {
      _message(
        paused ? 'Your profile is paused.' : 'Your profile is visible again.',
      );
    }
  }, reload: false);

  Future<void> _save(Map<String, dynamic> values) async {
    await _api.updateProfile(values);
    _message('Profile updated.');
  }

  Future<void> _edit(ProfileSummary profile, {bool interest = false}) =>
      _perform(() async {
        final values = await showDialog<Map<String, dynamic>>(
          context: context,
          builder: (_) =>
              ProfileTextEditor(profile: profile, interestOnly: interest),
        );
        if (values != null && mounted) await _save(values);
      });
  Future<void> _preferences(ProfileSummary profile) => _perform(() async {
    final values = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ProfilePreferencesSheet(profile: profile),
    );
    if (values != null && mounted) await _save(values);
  });
  Future<void> _consents() => _perform(() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const ProfileConsentSheet(),
    );
  });
  Future<bool> _confirm(String title, String message, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> _media(String kind) => _perform(() async {
    await _stopVoice();
    if (!mounted) return;
    if (kind == 'audio') {
      final consents = await _api.consents();
      if (!mounted) return;
      if (!consents.any((c) => c.type == 'voice' && c.granted)) {
        if (!await _confirm(
          'Allow voice capsule processing?',
          'Allow AnonymoKE to store and play your voice capsule to people you appear to. You can withdraw this in Privacy and consents.',
          'Allow and record',
        )) {
          return;
        }
        await _api.recordConsent(
          type: 'voice',
          version: ref.read(consentDocumentsProvider).version,
          granted: true,
        );
      }
    }
    if (!mounted) return;
    final uploaded = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ProfileMediaSheet(kind: kind),
    );
    if (uploaded == true) {
      _message(
        'Upload received. Your profile updates after processing checks.',
      );
    }
  });
  Future<void> _removeMedia(String kind) => _perform(() async {
    if (!await _confirm(
      'Delete ${kind == 'audio' ? 'voice capsule' : 'photo'}?',
      'This removes saved ${kind == 'audio' ? 'voice recordings' : 'profile photos'} from your account. You can upload a replacement later.',
      'Delete',
    )) {
      return;
    }
    await _stopVoice();
    await _api.deleteMedia(kind);
    _message('Media deleted.');
  });
  Future<void> _download() => _perform(() async {
    final payload = await _api.exportMyData();
    if (!mounted) return;
    final saved = await ref.read(profileExportProvider)(payload);
    if (saved) _message('Your data export was saved.');
  }, reload: false);
  Future<void> _delete(ProfileSummary profile) => _perform(() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => ProfileTextEditor(profile: profile, deleting: true),
    );
    if (result?['delete'] != true || !mounted) return;
    await _stopVoice();
    await _api.deleteAccount();
    if (!mounted) return;
    await ref.read(authControllerProvider.notifier).clearDeletedAccount();
    if (mounted) context.go('/auth');
  }, reload: false);
  Future<void> _stopVoice() async {
    _voiceEpoch++;
    await _player.pause();
    if (mounted && (_playing || _buffering)) {
      setState(() {
        _playing = false;
        _buffering = false;
      });
    }
  }

  Future<void> _playVoice() async {
    if (_buffering) return;
    if (_playing) {
      await _stopVoice();
      return;
    }
    final epoch = ++_voiceEpoch;
    setState(() => _buffering = true);
    try {
      final fresh = await _api.profile();
      if (!mounted || epoch != _voiceEpoch) return;
      if (fresh.audioUrl == null) {
        _message(
          'Your voice capsule is unavailable. Check voice consent and refresh.',
          error: true,
        );
        return;
      }
      setState(() {
        _playing = true;
        _buffering = false;
      });
      await _player.play(fresh.audioUrl!);
    } catch (_) {
      _message('Could not play your capsule. Please try again.', error: true);
    } finally {
      if (mounted && epoch == _voiceEpoch) {
        setState(() {
          _playing = false;
          _buffering = false;
        });
      }
    }
  }

  Future<void> _preview() => _perform(() async {
    final profile = await _api.profile();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 390),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'How others see you',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: AspectRatio(
                    aspectRatio: .78,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: AppGradients.blurredAvatar,
                          ),
                        ),
                        if (profile.blurredAvatarUrl != null)
                          ProfileImage(
                            profile.blurredAvatarUrl!,
                            fit: BoxFit.cover,
                            fallback: const Icon(
                              Icons.person,
                              size: 100,
                              color: Colors.white24,
                            ),
                          )
                        else
                          const Icon(
                            Icons.person,
                            size: 100,
                            color: Colors.white24,
                          ),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Colors.black87],
                            ),
                          ),
                        ),
                        Positioned(
                          left: 18,
                          right: 18,
                          bottom: 18,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      profile.alias,
                                      style: const TextStyle(
                                        fontSize: 23,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  if ([
                                    'verified',
                                    'age_verified',
                                  ].contains(profile.verificationLevel))
                                    const VerifiedBadge(),
                                ],
                              ),
                              Text(
                                '${profile.ageYears}${profile.heightCm == null ? '' : ' · ${profile.heightCm} cm'}',
                              ),
                              if (profile.bio.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(profile.bio),
                                ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: profile.interests
                                    .map((s) => Pill(s))
                                    .toList(),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Your private photo, birthday and matching preferences are never shown in discovery.',
                  style: TextStyle(
                    color: AppColors.secondaryText,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }, reload: false);

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(profileProvider);
    ref.listen(profileProvider, (previous, next) {
      if (next.profile?.audioUrl == null && _playing) unawaited(_stopVoice());
    });
    final profile = state.profile;
    return PinnedTabBody(
      header: profile == null
          ? (state.error == null
                ? const ProfileHeaderSkeleton()
                : const Text(
                    'Profile',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
                  ))
          : Row(
              children: [
                _avatar(profile),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.alias,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${profile.ageYears}${profile.heightCm == null ? '' : ' · ${profile.heightCm} cm'}',
                        style: const TextStyle(color: AppColors.secondaryText),
                      ),
                      const SizedBox(height: 6),
                      if ([
                        'verified',
                        'age_verified',
                      ].contains(profile.verificationLevel))
                        const VerifiedBadge(),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Edit profile',
                  onPressed: _busy ? null : () => _edit(profile),
                  icon: const Icon(
                    Icons.edit_outlined,
                    size: 20,
                    color: AppColors.secondaryText,
                  ),
                ),
              ],
            ),
      child: RefreshIndicator(
        onRefresh: () => ref.read(profileProvider.notifier).refresh(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 28),
          children: [
            if (state.error != null) ...[
              Text(
                state.error == 'session_expired'
                    ? 'Your session has expired. Please sign in again.'
                    : state.error!,
                style: const TextStyle(color: AppColors.coral),
              ),
              TextButton(
                onPressed: state.error == 'session_expired'
                    ? () => context.go('/auth')
                    : () => ref.read(profileProvider.notifier).refresh(),
                child: Text(
                  state.error == 'session_expired' ? 'Sign in' : 'Try again',
                ),
              ),
            ],
            if (profile == null && state.error == null)
              const ContentSkeleton(content: SkeletonContent.profile),
            if (profile != null) ...[
              OutlinedButton.icon(
                onPressed: _busy ? null : _preview,
                icon: const Icon(
                  Icons.visibility_outlined,
                  color: AppColors.accentSoft,
                ),
                label: const Text('See how others see me'),
              ),
              const SizedBox(height: 12),
              _premium(state),
              const SizedBox(height: 12),
              _voice(profile),
              if (profile.audioDurationMs > 0)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _busy ? null : () => _removeMedia('audio'),
                    child: const Text(
                      'Delete voice capsule',
                      style: TextStyle(color: AppColors.coral),
                    ),
                  ),
                ),
              for (final kind in ['avatar', 'audio'])
                if (state.media.where((m) => m.kind == kind).isNotEmpty)
                  _mediaStatus(state.media.firstWhere((m) => m.kind == kind)),
              if (state.perksError != null)
                Text(
                  state.perksError!,
                  style: const TextStyle(
                    color: AppColors.secondaryText,
                    fontSize: 12,
                  ),
                ),
              if (state.mediaError != null)
                Text(
                  state.mediaError!,
                  style: const TextStyle(
                    color: AppColors.secondaryText,
                    fontSize: 12,
                  ),
                ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: profile.interests
                    .map(
                      (item) => InputChip(
                        label: Text(item),
                        onDeleted: _busy
                            ? null
                            : () => _perform(
                                () => _save({
                                  'interests': profile.interests
                                      .where((s) => s != item)
                                      .toList(),
                                }),
                              ),
                      ),
                    )
                    .toList(),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _busy || profile.interests.length >= 10
                      ? null
                      : () => _edit(profile, interest: true),
                  child: const Text('+ Add interest'),
                ),
              ),
              _settings(profile),
              if (_busy && (ModalRoute.of(context)?.isCurrent ?? true))
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _avatar(ProfileSummary profile) => SizedBox(
    width: 88,
    height: 88,
    child: Stack(
      children: [
        ClipOval(
          child: SizedBox(
            width: 88,
            height: 88,
            child: profile.avatarUrl == null
                ? const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: AppGradients.blurredAvatar,
                    ),
                    child: Icon(Icons.person, size: 44, color: Colors.white54),
                  )
                : ProfileImage(
                    profile.avatarThumbnailUrl ?? profile.avatarUrl!,
                    decodeSize: 256,
                    fit: BoxFit.cover,
                    fallback: const ColoredBox(
                      color: AppColors.surfaceRaised,
                      child: Icon(Icons.person, size: 44),
                    ),
                  ),
          ),
        ),
        Positioned(
          bottom: 0,
          right: 0,
          child: Semantics(
            label: 'Change profile photo',
            button: true,
            child: InkWell(
              onTap: _busy ? null : () => _media('avatar'),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.camera_alt_outlined, size: 19),
              ),
            ),
          ),
        ),
      ],
    ),
  );
  Widget _premium(ProfileState state) {
    final now = DateTime.now();
    final items = state.entitlements
        .where(
          (e) =>
              e.quantity > 0 &&
              (e.expiresAt == null || e.expiresAt!.isAfter(now)),
        )
        .toList();
    final premium = items.where((e) => e.kind == 'premium').toList()
      ..sort(
        (a, b) => (b.expiresAt ?? DateTime(9999)).compareTo(
          a.expiresAt ?? DateTime(9999),
        ),
      );
    final active = premium.isNotEmpty;
    final boosts = items
        .where((e) => e.kind == 'boost')
        .fold<int>(0, (sum, e) => sum + e.quantity);
    final days = active && premium.first.expiresAt != null
        ? (premium.first.expiresAt!.difference(now).inSeconds / 86400).ceil()
        : null;
    return _panel(
      gradient: AppGradients.premium,
      child: _ProfileSummaryRow(
        children: [
          _icon(Icons.star_rounded),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Weekly Premium',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 3),
                Text(
                  active
                      ? '${days == null ? 'Active' : '$days days left'} · $boosts boost${boosts == 1 ? '' : 's'} ready'
                      : 'Unlimited swipes and more',
                  style: const TextStyle(
                    color: AppColors.secondaryText,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          CardActionButton(
            label: active ? 'Boost' : 'View plans',
            gold: true,
            onPressed: _busy
                ? null
                : () => _perform(() async {
                    await context.push(
                      active ? '/app/boost' : '/app/store',
                      extra: 0,
                    );
                  }),
          ),
        ],
      ),
    );
  }

  Widget _voice(ProfileSummary profile) => _panel(
    child: _ProfileSummaryRow(
      children: [
        Semantics(
          label: _playing ? 'Pause voice capsule' : 'Play voice capsule',
          button: true,
          child: InkWell(
            onTap: _busy || _buffering || profile.audioDurationMs <= 0
                ? null
                : _playVoice,
            child: _buffering
                ? const SizedBox(
                    width: 40,
                    height: 40,
                    child: Padding(
                      padding: EdgeInsets.all(10),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : _icon(
                    _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'My voice capsule',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 3),
              Text(
                profile.audioDurationMs <= 0
                    ? 'No voice capsule yet'
                    : '0:${(profile.audioDurationMs ~/ 1000).toString().padLeft(2, '0')} · voice disguise ${profile.audioDisguised ? 'on' : 'off'}',
                style: const TextStyle(
                  color: AppColors.secondaryText,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        CardActionButton(
          label: profile.audioDurationMs <= 0 ? 'Record' : 'Re-record',
          outlined: true,
          onPressed: _busy ? null : () => _media('audio'),
        ),
      ],
    ),
  );
  Widget _mediaStatus(MediaAssetSummary asset) =>
      asset.status == 'processing' || asset.status == 'pending'
      ? Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            '${asset.kind == 'avatar' ? 'Photo' : 'Voice capsule'} is processing. Your profile updates when checks finish.',
            style: const TextStyle(
              color: AppColors.secondaryText,
              fontSize: 12,
            ),
          ),
        )
      : asset.status == 'rejected'
      ? Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Last ${asset.kind == 'avatar' ? 'photo' : 'voice'} upload: ${profileError(asset.rejectionCode)}',
            style: const TextStyle(color: AppColors.coral, fontSize: 12),
          ),
        )
      : const SizedBox.shrink();
  Widget _settings(ProfileSummary profile) => _panel(
    padding: EdgeInsets.zero,
    child: Column(
      children: [
        _setting(
          'Discovery preferences',
          onTap: _busy ? null : () => _preferences(profile),
        ),
        _setting('Privacy and consents', onTap: _busy ? null : _consents),
        _setting(
          'Pause my profile',
          onTap: _busy ? null : () => _setPaused(profile.isDiscoverable),
          trailing: Switch.adaptive(
            key: const Key('profile-pause-switch'),
            value: !profile.isDiscoverable,
            onChanged: _busy ? null : _setPaused,
          ),
        ),
        _setting('Download my data', onTap: _busy ? null : _download),
        _setting(
          'Delete account and purge data',
          danger: true,
          onTap: _busy ? null : () => _delete(profile),
        ),
        if (profile.hasAvatar)
          _setting(
            'Delete profile photo',
            danger: true,
            onTap: _busy ? null : () => _removeMedia('avatar'),
          ),
      ],
    ),
  );
  Widget _setting(
    String title, {
    VoidCallback? onTap,
    Widget? trailing,
    bool danger = false,
  }) => InkWell(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: danger ? AppColors.coral : AppColors.text,
                fontWeight: danger ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          if (trailing != null)
            trailing
          else if (!danger)
            const Icon(Icons.chevron_right, color: AppColors.secondaryText),
        ],
      ),
    ),
  );
  Widget _icon(IconData icon) => Container(
    width: 40,
    height: 40,
    decoration: BoxDecoration(
      color: AppColors.accent,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Icon(icon, color: Colors.white),
  );
  Widget _panel({
    required Widget child,
    Gradient? gradient,
    EdgeInsetsGeometry padding = const EdgeInsets.all(14),
  }) => Container(
    width: double.infinity,
    padding: padding,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: gradient == null ? AppColors.surfaceRaised : null,
      gradient: gradient,
      borderRadius: BorderRadius.circular(18),
    ),
    child: child,
  );
}

class _ProfileSummaryRow extends StatelessWidget {
  const _ProfileSummaryRow({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 285 ||
          MediaQuery.textScalerOf(context).scale(12) > 15) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: children.take(3).toList()),
            const SizedBox(height: 10),
            Align(alignment: Alignment.centerRight, child: children.last),
          ],
        );
      }
      return Row(children: children);
    },
  );
}
