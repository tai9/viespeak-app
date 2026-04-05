/// Returns true when the cached `/quota` payload indicates the user has
/// no runway left for today — either their seconds counter is depleted
/// or they've already hit the per-day session cap.
///
/// Computed locally from the pre-fetched quota so callers can block the
/// start button without round-tripping to the backend just to get a 429.
bool isQuotaExhausted(Map<String, dynamic>? quota) {
  if (quota == null) return false;
  final remaining = quota['remaining_seconds'];
  final maxSessions = quota['max_sessions'];
  final sessionsToday = quota['sessions_today'];
  if (remaining is int && remaining <= 0) return true;
  if (maxSessions is int &&
      sessionsToday is int &&
      sessionsToday >= maxSessions) {
    return true;
  }
  return false;
}
