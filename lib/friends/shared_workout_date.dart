/// Shared client IDs retain the date selected in the original local record.
/// Legacy RPCs cast a zone-less local ISO key to timestamptz in server UTC.
/// Preserve that civil date without changing IDs, server data or reaction links.
DateTime sharedWorkoutDate(Map<String, dynamic> row) {
  final key = row['client_id'];
  if (key is String &&
      RegExp(r'^\d{4}-\d{2}-\d{2}T').hasMatch(key) &&
      DateTime.tryParse(key) != null) {
    final year = int.parse(key.substring(0, 4));
    final month = int.parse(key.substring(5, 7));
    final day = int.parse(key.substring(8, 10));
    final civil = DateTime.tryParse(
      key.replaceFirst(RegExp(r'(?:Z|[+-]\d{2}:?\d{2})$'), ''),
    );
    if (civil != null &&
        civil.year == year &&
        civil.month == month &&
        civil.day == day) {
      // Keep the original time internally for period/heatmap calculations.
      // Only its display is date-only; no stored timestamp is rewritten.
      return civil;
    }
  }
  // Records without an original ISO key still use their actual timestamp.
  return DateTime.parse(row['performed_at'] as String).toLocal();
}
