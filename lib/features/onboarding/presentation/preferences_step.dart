import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../application/onboarding_controller.dart';
import '../application/preferences_validation.dart';

class PreferencesStep extends ConsumerStatefulWidget {
  const PreferencesStep({required this.onContinue, super.key});
  final Future<void> Function() onContinue;

  @override
  ConsumerState<PreferencesStep> createState() => _PreferencesStepState();
}

class _PreferencesStepState extends ConsumerState<PreferencesStep> {
  bool _attempted = false, _advancing = false;
  final _selection = GlobalKey(), _ages = GlobalKey(), _distance = GlobalKey();

  Future<void> _submit() async {
    if (_advancing) return;
    final draft = ref.read(onboardingControllerProvider);
    setState(() => _attempted = true);
    if (PreferencesValidation.gendersError(draft.targetGenders) != null ||
        PreferencesValidation.agesError(draft.minAge, draft.maxAge) != null ||
        PreferencesValidation.distanceError(draft.maxDistanceKm) != null) {
      final target =
          PreferencesValidation.gendersError(draft.targetGenders) != null
          ? _selection.currentContext
          : PreferencesValidation.agesError(draft.minAge, draft.maxAge) != null
          ? _ages.currentContext
          : _distance.currentContext;
      if (target != null) {
        await Scrollable.ensureVisible(
          target,
          alignment: .1,
          duration: const Duration(milliseconds: 200),
        );
      }
      return;
    }
    setState(() => _advancing = true);
    try {
      await widget.onContinue();
    } finally {
      if (mounted) setState(() => _advancing = false);
    }
  }

  Widget _error(String? message) => message == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Semantics(
            liveRegion: true,
            child: Text(
              message,
              style: const TextStyle(color: AppColors.danger, fontSize: 12),
            ),
          ),
        );

  Widget _label(String title, String value, {Key? key}) => Row(
    key: key,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: Text(title)),
      const SizedBox(width: 12),
      Flexible(
        child: Text(
          value,
          textAlign: TextAlign.end,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    ],
  );

  Widget _limits(String start, String end) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(start, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
      Text(end, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(onboardingControllerProvider);
    final controller = ref.read(onboardingControllerProvider.notifier);
    final enabled = !_advancing && !draft.isSaving;
    // Invalid restored values must remain editable without triggering slider assertions.
    final start = draft.minAge.clamp(18, 100).toDouble();
    final end = draft.maxAge.clamp(start.toInt(), 100).toDouble();
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: IntrinsicHeight(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 26, 24, 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionTitle(
                    'Who do you want to meet?',
                    subtitle: 'You can change this any time.',
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'Show me',
                    key: _selection,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  Semantics(
                    container: true,
                    label: 'Who you want to meet. Choose one or more.',
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: PreferencesValidation.genders.entries.map((
                        entry,
                      ) {
                        final selected = draft.targetGenders.contains(
                          entry.key,
                        );
                        return FilterChip(
                          key: Key('meet-${entry.key}'),
                          label: Text(entry.value),
                          selected: selected,
                          showCheckmark: false,
                          onSelected: enabled
                              ? (_) => controller.setTargetGenders(
                                  PreferencesValidation.toggleGender(
                                    draft.targetGenders,
                                    entry.key,
                                  ),
                                )
                              : null,
                          selectedColor: AppColors.accent.withValues(
                            alpha: .12,
                          ),
                          backgroundColor: AppColors.surface,
                          side: BorderSide(
                            color: selected ? AppColors.accent : AppColors.line,
                            width: selected ? 1.5 : 1,
                          ),
                          labelStyle: TextStyle(
                            color: AppColors.text,
                            fontWeight: selected
                                ? FontWeight.w800
                                : FontWeight.w500,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          shape: const StadiumBorder(),
                        );
                      }).toList(),
                    ),
                  ),
                  if (_attempted)
                    _error(
                      PreferencesValidation.gendersError(draft.targetGenders),
                    ),
                  const SizedBox(height: 12),
                  const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.lock_outline, size: 14, color: AppColors.teal),
                      SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          'Private. Never shown on your profile or to anyone else.',
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  _label(
                    'Age range',
                    '${draft.minAge} to ${draft.maxAge}',
                    key: _ages,
                  ),
                  const SizedBox(height: 8),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      activeTrackColor: AppColors.coral,
                      inactiveTrackColor: AppColors.line,
                      rangeTrackShape: const _BrandRangeTrack(),
                      rangeThumbShape: const RoundRangeSliderThumbShape(
                        enabledThumbRadius: 12,
                      ),
                      thumbColor: AppColors.text,
                      overlayColor: AppColors.accent.withValues(alpha: .16),
                      activeTickMarkColor: Colors.transparent,
                      inactiveTickMarkColor: Colors.transparent,
                    ),
                    child: RangeSlider(
                      key: const Key('meet-age-range'),
                      values: RangeValues(start, end),
                      min: 18,
                      max: 100,
                      divisions: 82,
                      labels: RangeLabels('${draft.minAge}', '${draft.maxAge}'),
                      semanticFormatterCallback: (value) =>
                          '${value.round()} years',
                      onChanged: enabled
                          ? (value) => controller.setAgeRange(
                              value.start.round(),
                              value.end.round(),
                            )
                          : null,
                    ),
                  ),
                  _limits('18', '100'),
                  if (_attempted)
                    _error(
                      PreferencesValidation.agesError(
                        draft.minAge,
                        draft.maxAge,
                      ),
                    ),
                  const SizedBox(height: 24),
                  _label(
                    'Distance',
                    'Within ${draft.maxDistanceKm} km',
                    key: _distance,
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 6,
                      activeTrackColor: AppColors.accentBright,
                      inactiveTrackColor: AppColors.text,
                      thumbColor: AppColors.accentBright,
                      overlayColor: AppColors.accent.withValues(alpha: .16),
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 8,
                      ),
                      activeTickMarkColor: Colors.transparent,
                      inactiveTickMarkColor: Colors.transparent,
                    ),
                    child: Slider(
                      key: const Key('meet-distance'),
                      value: draft.maxDistanceKm.clamp(1, 50).toDouble(),
                      min: 1,
                      max: 50,
                      divisions: 49,
                      label: '${draft.maxDistanceKm} km',
                      semanticFormatterCallback: (value) =>
                          'Within ${value.round()} kilometres',
                      onChanged: enabled
                          ? (value) => controller.setDistance(value.round())
                          : null,
                    ),
                  ),
                  _limits('1 km', '50 km'),
                  if (_attempted)
                    _error(
                      PreferencesValidation.distanceError(draft.maxDistanceKm),
                    ),
                  const SizedBox(height: 28),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: AppColors.gold,
                          size: 20,
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Matches are mutual: you only see people who also want to meet someone like you.',
                            style: TextStyle(
                              color: AppColors.secondaryText,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: enabled ? _submit : null,
                      child: const Text('Continue'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandRangeTrack extends RoundedRectRangeSliderTrackShape {
  const _BrandRangeTrack();

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset startThumbCenter,
    required Offset endThumbCenter,
    bool isEnabled = false,
    bool isDiscrete = false,
    required TextDirection textDirection,
    double additionalActiveTrackHeight = 0,
  }) {
    super.paint(
      context,
      offset,
      parentBox: parentBox,
      sliderTheme: sliderTheme,
      enableAnimation: enableAnimation,
      startThumbCenter: startThumbCenter,
      endThumbCenter: endThumbCenter,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
      textDirection: textDirection,
      additionalActiveTrackHeight: 0,
    );
    if (!isEnabled || startThumbCenter.dx == endThumbCenter.dx) return;
    final track = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    final active = Rect.fromLTRB(
      startThumbCenter.dx < endThumbCenter.dx
          ? startThumbCenter.dx
          : endThumbCenter.dx,
      track.top,
      startThumbCenter.dx > endThumbCenter.dx
          ? startThumbCenter.dx
          : endThumbCenter.dx,
      track.bottom,
    );
    context.canvas.drawRRect(
      RRect.fromRectAndRadius(active, Radius.circular(track.height / 2)),
      Paint()..shader = AppGradients.progress.createShader(active),
    );
  }
}
