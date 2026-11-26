import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../application/about_you_validation.dart';
import '../application/onboarding_controller.dart';

class AboutYouStep extends ConsumerStatefulWidget {
  const AboutYouStep({required this.onContinue, super.key});
  final Future<void> Function() onContinue;
  @override
  ConsumerState<AboutYouStep> createState() => _AboutYouStepState();
}

class _AboutYouStepState extends ConsumerState<AboutYouStep>
    with WidgetsBindingObserver {
  final _form = GlobalKey<FormState>();
  final _genderField = GlobalKey<FormFieldState<String>>();
  final _aliasFocus = FocusNode(),
      _dateFocus = FocusNode(),
      _heightFocus = FocusNode();
  late final TextEditingController _alias, _date, _height;
  bool _attempted = false, _advancing = false;
  DateTime get _today => ref.read(onboardingTodayProvider)();
  OnboardingController get _controller =>
      ref.read(onboardingControllerProvider.notifier);

  @override
  void initState() {
    super.initState();
    final draft = ref.read(onboardingControllerProvider);
    _alias = TextEditingController(text: draft.alias);
    _date = TextEditingController(
      text: AboutYouValidation.displayDate(draft.birthDate),
    );
    _height = TextEditingController(text: draft.heightCm?.toString() ?? '');
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _alias.dispose();
    _date.dispose();
    _height.dispose();
    _aliasFocus.dispose();
    _dateFocus.dispose();
    _heightFocus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) setState(() {});
  }

  Future<void> _submit() async {
    if (_advancing) return;
    setState(() => _attempted = true);
    if (!_form.currentState!.validate()) {
      if (AboutYouValidation.aliasError(_alias.text) != null) {
        _aliasFocus.requestFocus();
      } else if (![
        'M',
        'W',
        'NB',
      ].contains(ref.read(onboardingControllerProvider).gender)) {
        FocusScope.of(context).unfocus();
        final fieldContext = _genderField.currentContext;
        if (fieldContext != null) {
          await Scrollable.ensureVisible(
            fieldContext,
            alignment: .2,
            duration: const Duration(milliseconds: 200),
          );
        }
      } else if (AboutYouValidation.dateError(_date.text, _today) != null) {
        _dateFocus.requestFocus();
      } else if (AboutYouValidation.heightError(_height.text) != null) {
        _heightFocus.requestFocus();
      }
      return;
    }
    _controller.setAlias(_alias.text);
    _controller.setBirthDate(_date.text);
    _controller.setHeight(_height.text);
    final normalized = AboutYouValidation.displayDate(
      ref.read(onboardingControllerProvider).birthDate,
    );
    _date.value = TextEditingValue(
      text: normalized,
      selection: TextSelection.collapsed(offset: normalized.length),
    );
    FocusScope.of(context).unfocus();
    setState(() => _advancing = true);
    try {
      await widget.onContinue();
    } finally {
      if (mounted) setState(() => _advancing = false);
    }
  }

  DateTime _yearsAgo(int years) {
    final today = _today;
    final lastDay = DateTime(today.year - years, today.month + 1, 0).day;
    return DateTime(
      today.year - years,
      today.month,
      today.day.clamp(1, lastDay),
    );
  }

  Future<void> _pickDate() async {
    FocusScope.of(context).unfocus();
    final first = _yearsAgo(101).add(const Duration(days: 1)),
        last = _yearsAgo(18);
    final current = AboutYouValidation.parseDate(_date.text);
    final selected = await showDatePicker(
      context: context,
      firstDate: first,
      lastDate: last,
      currentDate: _today,
      initialDate:
          current != null && !current.isBefore(first) && !current.isAfter(last)
          ? current
          : last,
      initialDatePickerMode: DatePickerMode.year,
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      helpText: 'Choose your date of birth',
    );
    if (selected == null || !mounted) return;
    final text = AboutYouValidation.displayDate(
      AboutYouValidation.isoDate(selected),
    );
    _date.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _controller.setBirthDate(text);
    if (_attempted) _form.currentState!.validate();
    setState(() {});
  }

  Widget _dateActions() {
    final date = AboutYouValidation.parseDate(_date.text);
    final age = date == null ? null : AboutYouValidation.age(date, _today);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (age != null && age >= 0)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text(
              'Age $age',
              style: TextStyle(
                color: age >= 18 && age <= 100
                    ? AppColors.teal
                    : AppColors.coral,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        IconButton(
          tooltip: 'Choose date of birth',
          onPressed: _advancing ? null : _pickDate,
          icon: const Icon(
            Icons.calendar_month_outlined,
            size: 20,
            color: AppColors.accentSoft,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(onboardingControllerProvider);
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: IntrinsicHeight(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 26, 24, 30),
              child: Form(
                key: _form,
                autovalidateMode: _attempted
                    ? AutovalidateMode.onUserInteraction
                    : AutovalidateMode.disabled,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionTitle(
                      'About you',
                      subtitle:
                          'Used only to find your matches. Your real name and birthday are never shown.',
                    ),
                    const SizedBox(height: 28),
                    TextFormField(
                      key: const Key('about-alias'),
                      enabled: !_advancing,
                      controller: _alias,
                      focusNode: _aliasFocus,
                      maxLength: 40,
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      inputFormatters: [
                        FilteringTextInputFormatter.singleLineFormatter,
                      ],
                      onChanged: _controller.setAlias,
                      validator: AboutYouValidation.aliasError,
                      decoration: InputDecoration(
                        labelText: 'Your alias',
                        hintText: 'Choose your own alias',
                        counterText: '',
                        suffixIcon: Padding(
                          padding: const EdgeInsets.all(6),
                          child: TextButton(
                            onPressed: _advancing
                                ? null
                                : () {
                                    final value = _controller.shuffleAlias();
                                    _alias.value = TextEditingValue(
                                      text: value,
                                      selection: TextSelection.collapsed(
                                        offset: value.length,
                                      ),
                                    );
                                  },
                            style: TextButton.styleFrom(
                              backgroundColor: AppColors.accent.withValues(
                                alpha: .12,
                              ),
                              foregroundColor: AppColors.accentSoft,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                            ),
                            child: const Text('Shuffle'),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'I am',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 10),
                    FormField<String>(
                      key: _genderField,
                      initialValue: draft.gender,
                      validator: (v) => ['M', 'W', 'NB'].contains(v)
                          ? null
                          : 'Choose your gender.',
                      builder: (field) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children:
                                {'M': 'Man', 'W': 'Woman', 'NB': 'Non-binary'}
                                    .entries
                                    .map(
                                      (e) => ChoiceChip(
                                        label: Text(e.value),
                                        selected: draft.gender == e.key,
                                        showCheckmark: false,
                                        onSelected: _advancing
                                            ? null
                                            : (_) {
                                                field.didChange(e.key);
                                                _controller.setGender(e.key);
                                              },
                                        selectedColor: AppColors.accent
                                            .withValues(alpha: .12),
                                        backgroundColor: AppColors.surface,
                                        side: BorderSide(
                                          color: draft.gender == e.key
                                              ? AppColors.accent
                                              : AppColors.line,
                                          width: draft.gender == e.key
                                              ? 1.5
                                              : 1,
                                        ),
                                        labelStyle: TextStyle(
                                          color: AppColors.text,
                                          fontWeight: draft.gender == e.key
                                              ? FontWeight.w800
                                              : FontWeight.w500,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 10,
                                        ),
                                        shape: const StadiumBorder(),
                                      ),
                                    )
                                    .toList(),
                          ),
                          if (field.hasError)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                field.errorText!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      key: const Key('about-birth-date'),
                      enabled: !_advancing,
                      controller: _date,
                      focusNode: _dateFocus,
                      keyboardType: TextInputType.datetime,
                      textInputAction: TextInputAction.next,
                      maxLength: 18,
                      autocorrect: false,
                      enableSuggestions: false,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9/\- ]')),
                      ],
                      onChanged: _controller.setBirthDate,
                      onFieldSubmitted: (_) => _heightFocus.requestFocus(),
                      validator: (v) => AboutYouValidation.dateError(v, _today),
                      decoration: InputDecoration(
                        labelText: 'Date of birth',
                        hintText: 'DD / MM / YYYY',
                        counterText: '',
                        suffixIcon: _dateActions(),
                        errorMaxLines: 3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'You must be 18 or older. Others see your age, never your birthday.',
                      style: TextStyle(color: AppColors.muted, fontSize: 12),
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      key: const Key('about-height'),
                      enabled: !_advancing,
                      controller: _height,
                      focusNode: _heightFocus,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      maxLength: 3,
                      onChanged: _controller.setHeight,
                      onFieldSubmitted: (_) => _submit(),
                      validator: AboutYouValidation.heightError,
                      decoration: const InputDecoration(
                        labelText: 'Height  Optional',
                        suffixText: 'cm',
                        counterText: '',
                        errorMaxLines: 3,
                      ),
                    ),
                    const SizedBox(height: 28),
                    const Spacer(),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _advancing ? null : _submit,
                        child: const Text('Continue'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
