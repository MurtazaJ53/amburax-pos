/// Classify a backend HTTP status for the offline outbox.
///
/// A **permanent** rejection means the server will never accept this exact
/// payload (a 4xx validation error), so the command must be moved to the
/// dead-letter queue instead of retried forever — otherwise it wastes retries
/// and, worse, can hide a real data problem. A **transient** failure
/// (network/timeout, 5xx, auth-expiry, rate-limit, or the migration-cutover
/// 409) should keep retrying with backoff.
bool isPermanentOutboxRejection(int? statusCode) {
  if (statusCode == null) return false; // network / timeout -> transient
  // Transient 4xx: 401/403 = token expired (refresh + retry), 429 = rate limit,
  // 409 = domain not yet promoted to postgres_primary (cutover in progress).
  if (statusCode == 401 ||
      statusCode == 403 ||
      statusCode == 409 ||
      statusCode == 429) {
    return false;
  }
  // 400 (bad request), 404 (unknown shop/route), 422 (validation) … -> permanent.
  return statusCode >= 400 && statusCode < 500;
}
