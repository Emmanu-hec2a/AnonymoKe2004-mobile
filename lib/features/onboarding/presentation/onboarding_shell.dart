import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/build_config.dart';
import '../../../core/auth/auth_controller.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../application/onboarding_controller.dart';
import '../application/photo_controller.dart';
import 'about_you_step.dart';
import 'preferences_step.dart';
import 'voice_step.dart';
import 'photo_step.dart';
import 'privacy_step.dart';

class OnboardingShell extends ConsumerStatefulWidget {
  const OnboardingShell({required this.step, super.key});
  final int step;
  @override
  ConsumerState<OnboardingShell> createState() => _OnboardingShellState();
}

class _OnboardingShellState extends ConsumerState<OnboardingShell> {
  Future<void> _next() async {
    if (widget.step != 5) {
      context.go('/onboarding/${widget.step + 1}');
      return;
    }
    final ownerId = ref.read(authControllerProvider).session?.userId;
    bool current() =>
        mounted &&
        widget.step == 5 &&
        ref.read(authControllerProvider).session?.userId == ownerId;
    final controller = ref.read(onboardingControllerProvider.notifier);
    try {
      if (demoMode) {
        await controller.completePreview();
      } else {
        await controller.complete();
      }
      if (!mounted) return;
      if (current()) context.go('/app/discover');
    } catch (error) {
      if (!mounted || !current()) return;
      if (ref.read(onboardingPhotoProvider).rejected ||
          (error is ApiException &&
              const {
                'photo_required',
                'photo_changed',
                'photo_not_ready',
              }.contains(error.code))) {
        context.go('/onboarding/4');
        return;
      }
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ownerId = ref.watch(
      authControllerProvider.select((s) => s.session?.userId),
    );
    final saving = ref.watch(
      onboardingControllerProvider.select((s) => s.isSaving),
    );
    return PopScope(
      canPop: !saving,
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              _progressHeader(),
              Expanded(
                child: switch (widget.step) {
                  1 => AboutYouStep(key: ValueKey(ownerId), onContinue: _next),
                  2 => PreferencesStep(
                    key: ValueKey(ownerId),
                    onContinue: _next,
                  ),
                  3 => VoiceStep(key: ValueKey(ownerId), onContinue: _next),
                  4 => PhotoStep(key: ValueKey(ownerId), onContinue: _next),
                  _ => PrivacyStep(key: ValueKey(ownerId), onContinue: _next),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _progressHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.line),
            ),
            child: IconButton(
              onPressed: ref.watch(onboardingControllerProvider).isSaving
                  ? null
                  : () {
                      if (widget.step > 1) {
                        context.go('/onboarding/${widget.step - 1}');
                      } else if (context.canPop()) {
                        context.pop();
                      } else {
                        context.go('/auth');
                      }
                    },
              icon: const Icon(Icons.chevron_left_rounded),
              padding: EdgeInsets.zero,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  children: [
                    Container(
                      height: 5,
                      decoration: BoxDecoration(
                        color: AppColors.line,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    Container(
                      height: 5,
                      width: constraints.maxWidth * (widget.step / 5),
                      decoration: BoxDecoration(
                        gradient: AppGradients.progress,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(width: 14),
          Text(
            '${widget.step} of 5',
            style: const TextStyle(
              color: AppColors.secondaryText,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
