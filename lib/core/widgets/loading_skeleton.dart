import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class SkeletonShimmer extends StatefulWidget {
  const SkeletonShimmer({required this.child, required this.label, super.key});
  final Widget child;
  final String label;

  @override
  State<SkeletonShimmer> createState() => _SkeletonShimmerState();
}

class _SkeletonShimmerState extends State<SkeletonShimmer>
    with SingleTickerProviderStateMixin {
  late final _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1450),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled) {
      _animation.stop();
    } else if (!_animation.isAnimating) {
      _animation.repeat();
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.label,
    liveRegion: true,
    child: ExcludeSemantics(
      child: IgnorePointer(
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _animation,
            child: widget.child,
            builder: (context, child) => ShaderMask(
              blendMode: BlendMode.srcATop,
              shaderCallback: (bounds) {
                final width = bounds.width;
                return const LinearGradient(
                  colors: [
                    AppColors.surfaceRaised,
                    AppColors.strongLine,
                    AppColors.surfaceRaised,
                  ],
                  stops: [0, .5, 1],
                ).createShader(
                  Rect.fromLTWH(
                    -width + _animation.value * width * 2.5,
                    0,
                    width,
                    bounds.height,
                  ),
                );
              },
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
}

class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    required this.height,
    this.width,
    this.radius = 12,
    super.key,
  });
  final double height;
  final double? width;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: AppColors.surfaceRaised,
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}

enum SkeletonContent { matches, safety, profile, discover, chat, cards }

class ContentSkeleton extends StatelessWidget {
  const ContentSkeleton({required this.content, super.key});
  final SkeletonContent content;

  @override
  Widget build(BuildContext context) => SkeletonShimmer(
    label: 'Loading ${content.name}',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: switch (content) {
        SkeletonContent.matches => [
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(
              4,
              (_) => const SkeletonBox(height: 58, width: 58, radius: 40),
            ),
          ),
          const SizedBox(height: 26),
          for (var i = 0; i < 6; i++) const _SkeletonRow(),
        ],
        SkeletonContent.safety => [
          const SkeletonBox(height: 154, radius: 20),
          const SizedBox(height: 14),
          const SkeletonBox(height: 182, radius: 20),
          const SizedBox(height: 14),
          const SkeletonBox(height: 76, radius: 20),
          const SizedBox(height: 14),
          const SkeletonBox(height: 110, radius: 20),
        ],
        SkeletonContent.profile => [
          const SkeletonBox(height: 44),
          const SizedBox(height: 14),
          const SkeletonBox(height: 76, radius: 20),
          const SizedBox(height: 14),
          const SkeletonBox(height: 64, radius: 20),
          const SizedBox(height: 18),
          const SkeletonBox(height: 32),
          const SizedBox(height: 20),
          for (var i = 0; i < 5; i++) ...[
            const SkeletonBox(height: 48),
            const SizedBox(height: 3),
          ],
        ],
        SkeletonContent.discover => [
          const SizedBox(height: 16),
          SkeletonBox(
            height: (MediaQuery.sizeOf(context).height * .54)
                .clamp(240, 470)
                .toDouble(),
            radius: 28,
          ),
          const SizedBox(height: 22),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SkeletonBox(height: 48, width: 48, radius: 40),
              SizedBox(width: 24),
              SkeletonBox(height: 60, width: 60, radius: 40),
              SizedBox(width: 24),
              SkeletonBox(height: 68, width: 68, radius: 40),
            ],
          ),
        ],
        SkeletonContent.chat => [
          for (var i = 0; i < 5; i++) ...[
            Align(
              alignment: i.isEven
                  ? Alignment.centerLeft
                  : Alignment.centerRight,
              child: SkeletonBox(
                height: i.isEven ? 54 : 38,
                width: i.isEven ? 190 : 140,
                radius: 18,
              ),
            ),
            const SizedBox(height: 18),
          ],
        ],
        SkeletonContent.cards => [
          for (var i = 0; i < 3; i++) ...[
            const SkeletonBox(height: 80, radius: 18),
            const SizedBox(height: 14),
          ],
        ],
      },
    ),
  );
}

class ProfileHeaderSkeleton extends StatelessWidget {
  const ProfileHeaderSkeleton({super.key});

  @override
  Widget build(BuildContext context) => const SkeletonShimmer(
    label: 'Loading profile',
    child: Row(
      children: [
        SkeletonBox(height: 88, width: 88, radius: 50),
        SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(height: 18, width: 150),
              SizedBox(height: 10),
              SkeletonBox(height: 12, width: 85),
            ],
          ),
        ),
      ],
    ),
  );
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 12),
    child: Row(
      children: [
        SkeletonBox(height: 52, width: 52, radius: 40),
        SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(height: 14, width: 150),
              SizedBox(height: 10),
              SkeletonBox(height: 10, width: 110),
            ],
          ),
        ),
      ],
    ),
  );
}
