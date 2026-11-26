import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_theme.dart';
import '../application/photo_controller.dart';

class PhotoStep extends ConsumerStatefulWidget {
  const PhotoStep({required this.onContinue, super.key});
  final Future<void> Function() onContinue;
  @override
  ConsumerState<PhotoStep> createState() => _PhotoStepState();
}

class _PhotoStepState extends ConsumerState<PhotoStep> {
  late final OnboardingPhotoController _controller;
  late final Object _lease;
  bool _choosing = false, _advancing = false;
  @override
  void initState() {
    super.initState();
    _controller = ref.read(onboardingPhotoProvider.notifier);
    _lease = _controller.attach();
  }

  @override
  void dispose() {
    _controller.detach(_lease);
    super.dispose();
  }

  Future<void> _choose() async {
    if (_choosing || _advancing || ref.read(onboardingPhotoProvider).busy) {
      return;
    }
    _choosing = true;
    final hasPhoto = ref.read(onboardingPhotoProvider).draft != null;
    try {
      final choice = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        backgroundColor: AppColors.surface,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(
                  Icons.camera_alt_outlined,
                  color: AppColors.accentSoft,
                ),
                title: const Text('Take a photo'),
                onTap: () => Navigator.pop(context, 'camera'),
              ),
              ListTile(
                leading: const Icon(
                  Icons.photo_library_outlined,
                  color: AppColors.accentSoft,
                ),
                title: const Text('Choose from gallery'),
                onTap: () => Navigator.pop(context, 'gallery'),
              ),
              if (hasPhoto)
                ListTile(
                  leading: const Icon(
                    Icons.delete_outline,
                    color: AppColors.danger,
                  ),
                  title: const Text(
                    'Remove photo',
                    style: TextStyle(color: AppColors.danger),
                  ),
                  onTap: () => Navigator.pop(context, 'remove'),
                ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      );
      if (!mounted || choice == null) return;
      if (choice == 'remove') {
        await _controller.remove();
      } else {
        await _controller.pick(
          choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
        );
      }
    } finally {
      _choosing = false;
    }
  }

  Future<void> _continue() async {
    if (_advancing || !_controller.saveDraft()) return;
    setState(() => _advancing = true);
    try {
      await widget.onContinue();
    } finally {
      if (mounted) setState(() => _advancing = false);
    }
  }

  Widget _card(OnboardingPhotoState photo, {required bool private}) {
    final hasPhoto = photo.draft != null;
    final tint = photo.rejected ? AppColors.coral : AppColors.teal;
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: private && !hasPhoto
                ? AppColors.accentSoft.withValues(alpha: .38)
                : AppColors.line,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Material(
            color: AppColors.surface,
            child: InkWell(
              key: Key(private ? 'photo-private-card' : 'photo-blurred-card'),
              onTap: private && !photo.busy && !_advancing ? _choose : null,
              child: Semantics(
                button: private,
                label: private
                    ? photo.rejected
                          ? 'Your private photo needs replacement. Tap to change.'
                          : hasPhoto
                          ? 'Your private photo, selected. Tap to change.'
                          : 'Your private photo. Tap to choose.'
                    : 'Blurred photo preview',
                child: ExcludeSemantics(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (hasPhoto)
                        Image.memory(
                          private
                              ? photo.draft!.privateBytes
                              : photo.draft!.blurredBytes,
                          key: Key(
                            private
                                ? 'photo-private-image'
                                : 'photo-blurred-image',
                          ),
                          fit: BoxFit.cover,
                          filterQuality: private
                              ? FilterQuality.medium
                              : FilterQuality.none,
                          gaplessPlayback: false,
                        )
                      else ...[
                        if (!private)
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: AppGradients.blurredAvatar,
                            ),
                          ),
                        Center(
                          child: SizedBox.square(
                            dimension: 76,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Container(
                                  width: 72,
                                  height: 72,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: private
                                        ? AppColors.accent.withValues(alpha: .1)
                                        : AppColors.ink.withValues(alpha: .12),
                                  ),
                                  child: Icon(
                                    Icons.person_rounded,
                                    size: 48,
                                    color: private
                                        ? AppColors.accentSoft
                                        : AppColors.text.withValues(alpha: .32),
                                  ),
                                ),
                                if (private)
                                  Positioned(
                                    bottom: 0,
                                    right: 0,
                                    child: Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: AppColors.accent,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: AppColors.surface,
                                          width: 2,
                                        ),
                                      ),
                                      child: const Icon(
                                        Icons.add_a_photo_outlined,
                                        size: 14,
                                        color: AppColors.text,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      if (private && hasPhoto)
                        Positioned(
                          top: 10,
                          left: 10,
                          right: 10,
                          child: Align(
                            alignment: Alignment.topLeft,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.ink.withValues(alpha: .84),
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    photo.rejected
                                        ? Icons.error_outline
                                        : Icons.check_rounded,
                                    color: tint,
                                    size: 14,
                                  ),
                                  const SizedBox(width: 5),
                                  Flexible(
                                    child: Text(
                                      photo.rejected
                                          ? 'Change photo'
                                          : 'Selected',
                                      textScaler: MediaQuery.textScalerOf(
                                        context,
                                      ).clamp(maxScaleFactor: 1.3),
                                      style: TextStyle(
                                        color: tint,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      if (private && photo.busy)
                        ColoredBox(
                          color: AppColors.ink.withValues(alpha: .6),
                          child: const Center(
                            child: CircularProgressIndicator(),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _comparison(OnboardingPhotoState photo) {
    const titleStyle = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w700,
      height: 1.3,
    );
    const subtitleStyle = TextStyle(
      fontSize: 12,
      color: AppColors.muted,
      height: 1.3,
    );
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(),
        1: FixedColumnWidth(28),
        2: FlexColumnWidth(),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          children: [
            _card(photo, private: true),
            const Icon(
              Icons.arrow_forward_rounded,
              color: AppColors.muted,
              size: 22,
            ),
            _card(photo, private: false),
          ],
        ),
        const TableRow(
          children: [
            SizedBox(height: 12),
            SizedBox.shrink(),
            SizedBox.shrink(),
          ],
        ),
        const TableRow(
          children: [
            Text('Your photo', textAlign: TextAlign.center, style: titleStyle),
            SizedBox.shrink(),
            Text(
              'What others see',
              textAlign: TextAlign.center,
              style: titleStyle,
            ),
          ],
        ),
        const TableRow(
          children: [SizedBox(height: 4), SizedBox.shrink(), SizedBox.shrink()],
        ),
        const TableRow(
          children: [
            Text('Private', textAlign: TextAlign.center, style: subtitleStyle),
            SizedBox.shrink(),
            Text('Blurred', textAlign: TextAlign.center, style: subtitleStyle),
          ],
        ),
      ],
    );
  }

  Widget _check(String text) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Padding(
        padding: EdgeInsets.only(top: 1),
        child: Icon(Icons.check_rounded, size: 18, color: AppColors.teal),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          text,
          style: const TextStyle(
            color: AppColors.secondaryText,
            fontSize: 13,
            height: 1.4,
          ),
        ),
      ),
    ],
  );

  Widget _body(OnboardingPhotoState photo, bool enabled) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Add your photo',
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
          fontSize: 28,
          height: 1.15,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 10),
      const Text(
        'Use a clear photo of your face. Others only see a blurred version until you both agree to reveal.',
        style: TextStyle(
          color: AppColors.secondaryText,
          fontSize: 14,
          height: 1.45,
        ),
      ),
      const SizedBox(height: 24),
      _comparison(photo),
      if (photo.draft != null && !photo.rejected) ...[
        const SizedBox(height: 6),
        Center(
          child: TextButton.icon(
            key: const Key('photo-choose'),
            onPressed: enabled ? _choose : null,
            icon: const Icon(Icons.cameraswitch_outlined, size: 17),
            label: const Text(
              'Retake or choose another photo',
              textAlign: TextAlign.center,
            ),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.accentSoft,
              textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              minimumSize: const Size(48, 44),
            ),
          ),
        ),
      ],
      const SizedBox(height: 24),
      _check('Just you, with your face clearly visible'),
      const SizedBox(height: 10),
      _check('No sunglasses, heavy filters or group shots'),
      const SizedBox(height: 10),
      _check('No nudity or explicit content'),
      const SizedBox(height: 14),
      const Text(
        'Face checks run when you finish.',
        style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4),
      ),
      if (photo.error != null) ...[
        const SizedBox(height: 16),
        Semantics(
          liveRegion: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline, color: AppColors.coral, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _error(photo.error!),
                  style: const TextStyle(
                    color: AppColors.coral,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ],
  );

  Widget _footer(OnboardingPhotoState photo, bool enabled) {
    final canContinue = photo.draft != null && !photo.rejected;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(top: 1),
              child: Icon(
                Icons.lock_outline_rounded,
                color: AppColors.teal,
                size: 16,
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Your original stays private until you both agree to reveal.',
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            key: Key(canContinue ? 'photo-continue' : 'photo-choose'),
            onPressed: enabled ? (canContinue ? _continue : _choose) : null,
            child: Text(
              canContinue
                  ? 'Continue'
                  : photo.rejected
                  ? 'Choose another photo'
                  : 'Choose a photo',
            ),
          ),
        ),
      ],
    );
  }

  Widget _centered(Widget child, EdgeInsets padding) => Padding(
    padding: padding,
    child: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: child,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final photo = ref.watch(onboardingPhotoProvider);
    final enabled = !photo.busy && !_advancing;
    return LayoutBuilder(
      builder: (context, constraints) {
        final pinActions =
            constraints.maxHeight >= 560 &&
            MediaQuery.textScalerOf(context).scale(14) < 24;
        final body = _centered(
          _body(photo, enabled),
          const EdgeInsets.fromLTRB(24, 24, 24, 20),
        );
        final footer = _centered(
          _footer(photo, enabled),
          const EdgeInsets.fromLTRB(24, 16, 24, 24),
        );
        if (pinActions) {
          return Column(
            children: [
              Expanded(child: SingleChildScrollView(child: body)),
              footer,
            ],
          );
        }
        return SingleChildScrollView(child: Column(children: [body, footer]));
      },
    );
  }

  String _error(String code) => switch (code) {
    'exactly_one_face_required' =>
      'Use a photo with just one clearly visible face.',
    'photo_not_ready' || 'photo_validation_failed' =>
      'This photo has not passed checks. Choose another photo and try again.',
    'photo_size_invalid' => 'Choose a photo smaller than 10 MB.',
    'avatar_dimensions_invalid' =>
      'Choose a clear photo at least 200 × 200 pixels, up to 8000 pixels per side and 32 megapixels.',
    'avatar_still_photo_required' =>
      'Choose a still photo instead of an animation.',
    'photo_invalid' || 'avatar_invalid' || 'avatar_format_invalid' =>
      'This photo could not be opened. Try a JPEG, PNG or WebP photo.',
    'photo_permission_denied' =>
      'Allow camera or photo access in your phone settings, then try again.',
    _ =>
      'Could not access the photo. Check camera or photo access and try again.',
  };
}
