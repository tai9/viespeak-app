/// Returns true when the cached `/quota` payload indicates the user has
/// no runway left for today — their seconds counter is depleted.
///
/// Computed locally from the pre-fetched quota so callers can block the
/// start button without round-tripping to the backend just to get a 429.
bool isQuotaExhausted(Map<String, dynamic>? quota) {
  if (quota == null) return false;
  final remaining = quota['remaining_seconds'];
  if (remaining is int && remaining <= 0) return true;
  return false;
}
