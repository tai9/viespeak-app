import 'package:intl/intl.dart';

final _defaultTimestampFormat = DateFormat('yyyy-MM-dd, HH:mm');
final _zoneSuffixPattern = RegExp(r'[+-]\d{2}:?\d{2}$');

/// Formats an ISO-8601 timestamp string into a human-readable local time.
///
/// Backend timestamps without an explicit zone are treated as UTC before
/// being converted to the device's local time.
String formatTimestamp(String raw, {DateFormat? format}) {
  if (raw.isEmpty) return '';
  final hasZone = raw.endsWith('Z') || _zoneSuffixPattern.hasMatch(raw);
  final parsed = DateTime.tryParse(hasZone ? raw : '${raw}Z');
  if (parsed == null) return '';
  return (format ?? _defaultTimestampFormat).format(parsed.toLocal());
}
