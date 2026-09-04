/// Compares two dotted version strings such as "1.12.3" (a trailing
/// build suffix like "+4", as found in `pubspec.yaml`'s
/// `version: 1.0.0+4`, is ignored).
///
/// Returns a negative number if [a] < [b], zero if they're equal, and
/// a positive number if [a] > [b] — the same contract as
/// `Comparable.compareTo`.
int compareVersions(String a, String b) {
  final partsA = _parse(a);
  final partsB = _parse(b);
  final length = partsA.length > partsB.length ? partsA.length : partsB.length;

  for (var i = 0; i < length; i++) {
    final valueA = i < partsA.length ? partsA[i] : 0;
    final valueB = i < partsB.length ? partsB[i] : 0;
    if (valueA != valueB) return valueA.compareTo(valueB);
  }
  return 0;
}

List<int> _parse(String version) {
  final core = version.split('+').first.trim();
  if (core.isEmpty) return const [0];
  return core
      .split('.')
      .map((part) {
        final digits = part.replaceAll(RegExp(r'[^0-9]'), '');
        return digits.isEmpty ? 0 : int.parse(digits);
      })
      .toList(growable: false);
}
