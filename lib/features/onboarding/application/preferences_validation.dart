class PreferencesValidation {
  static const minimumAge = 18, maximumAge = 100;
  static const minimumDistance = 1, maximumDistance = 50;
  static const genders = {
    'M': 'Men',
    'W': 'Women',
    'NB': 'Non-binary',
    'ALL': 'Everyone',
  };

  static String? gendersError(List<String> values) {
    if (values.isEmpty) return 'Choose who you would like to meet.';
    if (values.length > 3 ||
        values.any((value) => !genders.containsKey(value)) ||
        values.toSet().length != values.length ||
        (values.contains('ALL') && values.length != 1)) {
      return 'Choose valid matching preferences.';
    }
    return null;
  }

  static String? agesError(int minimum, int maximum) =>
      minimum < minimumAge || maximum > maximumAge || minimum > maximum
      ? 'Choose an age range between 18 and 100.'
      : null;

  static String? distanceError(int distance) =>
      distance < minimumDistance || distance > maximumDistance
      ? 'Choose a distance between 1 and 50 km.'
      : null;

  static List<String> toggleGender(List<String> current, String code) {
    if (!genders.containsKey(code)) throw ArgumentError.value(code, 'code');
    if (code == 'ALL') {
      return current.length == 1 && current.single == 'ALL'
          ? const []
          : const ['ALL'];
    }
    final selected = current.where((value) => value != 'ALL').toSet();
    selected.contains(code) ? selected.remove(code) : selected.add(code);
    return List.unmodifiable(genders.keys.where(selected.contains));
  }
}
