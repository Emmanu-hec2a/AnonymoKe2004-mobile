import 'package:flutter_riverpod/flutter_riverpod.dart';

final onboardingTodayProvider = Provider<DateTime Function()>(
  (_) => () {
    final kenya = DateTime.now().toUtc().add(const Duration(hours: 3));
    return DateTime(kenya.year, kenya.month, kenya.day);
  },
);

class AboutYouValidation {
  static DateTime? parseDate(String? input) {
    final value = input?.trim() ?? '';
    final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    final display = RegExp(
      r'^(\d{1,2})\s*/\s*(\d{1,2})\s*/\s*(\d{4})$',
    ).firstMatch(value);
    if (iso == null && display == null) return null;
    final year = int.parse(iso?.group(1) ?? display!.group(3)!);
    final month = int.parse(iso?.group(2) ?? display!.group(2)!);
    final day = int.parse(iso?.group(3) ?? display!.group(1)!);
    if (year < 1 || month < 1 || month > 12 || day < 1 || day > 31) return null;
    final date = DateTime(year, month, day);
    return date.year == year && date.month == month && date.day == day
        ? date
        : null;
  }

  static String isoDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  static String displayDate(String? value) {
    final date = parseDate(value);
    return date == null
        ? ''
        : '${date.day.toString().padLeft(2, '0')} / ${date.month.toString().padLeft(2, '0')} / ${date.year.toString().padLeft(4, '0')}';
  }

  static int age(DateTime birthDate, DateTime today) =>
      today.year -
      birthDate.year -
      ((today.month < birthDate.month ||
              (today.month == birthDate.month && today.day < birthDate.day))
          ? 1
          : 0);

  static String? aliasError(String? value) {
    final alias = value?.trim() ?? '';
    if (alias.runes.length < 2 || alias.runes.length > 40) {
      return 'Use 2–40 characters for your alias.';
    }
    if (RegExp(r'[\x00-\x1F\x7F]').hasMatch(alias)) {
      return 'Use a single line for your alias.';
    }
    return null;
  }

  static String? dateError(String? value, DateTime today) {
    final date = parseDate(value);
    if (date == null) return 'Enter a valid date as DD / MM / YYYY.';
    if (date.isAfter(DateTime(today.year, today.month, today.day))) {
      return 'Your date of birth cannot be in the future.';
    }
    final years = age(date, today);
    if (years < 18) return 'You must be 18 or older to use AnonymoKE.';
    if (years > 100) {
      return 'Check your date of birth. Ages up to 100 are supported.';
    }
    return null;
  }

  static String? heightError(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final height = int.tryParse(text);
    return height != null && height >= 100 && height <= 250
        ? null
        : 'Enter a height between 100 and 250 cm.';
  }
}
