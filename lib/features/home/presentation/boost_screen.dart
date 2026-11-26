import '../../../core/widgets/loading_skeleton.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';

class BackendBoostScreen extends ConsumerStatefulWidget {
  const BackendBoostScreen({super.key});
  @override
  ConsumerState<BackendBoostScreen> createState() => _BackendBoostScreenState();
}

class _BackendBoostScreenState extends ConsumerState<BackendBoostScreen> {
  late Future<BoostStatus> _request;
  final _activationId = const Uuid().v4();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _request = ref.read(apiClientProvider).boostStatus();
  }

  void _reload() {
    if (mounted) {
      setState(() => _request = ref.read(apiClientProvider).boostStatus());
    }
  }

  Future<void> _activate() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final status = await ref
          .read(apiClientProvider)
          .activateBoost(_activationId);
      if (mounted) setState(() => _request = Future.value(status));
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(switch (error.code) {
              'boost_required' => 'Purchase a Boost before activating it.',
              'location_required' ||
              'location_stale' ||
              'location_consent_required' ||
              'sensitive_data_consent_required' =>
                'Return to Discover and update your location and privacy choices first.',
              'profile_paused' =>
                'Resume your profile before activating a Boost.',
              _ => 'Could not activate your Boost. Try again.',
            }),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AppPage(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.close_rounded),
        ),
        const SizedBox(height: 28),
        Center(
          child: Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: .16),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.bolt_rounded,
              color: AppColors.gold,
              size: 44,
            ),
          ),
        ),
        const SizedBox(height: 22),
        const Center(
          child: Text(
            'Boost your profile',
            style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900),
          ),
        ),
        const SizedBox(height: 7),
        const Text(
          'Be seen by more people nearby for 30 minutes.',
          style: TextStyle(color: AppColors.secondaryText),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 28),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: AppGradients.premium,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.gold.withValues(alpha: .38)),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Profile Boost',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              SizedBox(height: 6),
              Text('Move your profile to the front of nearby discovery cards.'),
              SizedBox(height: 18),
              Text(
                '✓ More visibility in your area\n✓ Active for 30 minutes\n✓ No automatic renewal',
                style: TextStyle(height: 1.8),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        FutureBuilder<BoostStatus>(
          future: _request,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Column(
                children: [
                  const Text('Could not load your Boosts.'),
                  TextButton(
                    onPressed: _reload,
                    child: const Text('Try again'),
                  ),
                ],
              );
            }
            if (!snapshot.hasData) {
              return const ContentSkeleton(content: SkeletonContent.cards);
            }
            final status = snapshot.data!;
            return Column(
              children: [
                if (status.isActive)
                  Text(
                    'Boost active until ${TimeOfDay.fromDateTime(status.activeUntil!.toLocal()).format(context)}',
                    style: const TextStyle(
                      color: AppColors.teal,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                else
                  Text(
                    '${status.availableBoosts} Boost${status.availableBoosts == 1 ? '' : 's'} ready',
                    style: const TextStyle(color: AppColors.secondaryText),
                  ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _busy || status.isActive
                        ? null
                        : status.availableBoosts > 0
                        ? _activate
                        : () async {
                            await context.push('/app/store', extra: 1);
                            _reload();
                          },
                    child: Text(
                      _busy
                          ? 'Activating…'
                          : status.isActive
                          ? 'Boost is active'
                          : status.availableBoosts > 0
                          ? 'Activate a Boost'
                          : 'Boost for KES 50',
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _busy ? null : _reload,
                  child: const Text('Refresh status'),
                ),
              ],
            );
          },
        ),
      ],
    ),
  );
}
