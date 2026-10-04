/// Historical pace remains stored, but all speed displays use km/h.
double activitySpeedKmh({
  required int durationSeconds,
  required double distanceKm,
  double speedKmh = 0,
  int paceSecondsPerKm = 0,
}) {
  if (durationSeconds > 0 && distanceKm.isFinite && distanceKm > 0) {
    final average = distanceKm * 3600 / durationSeconds;
    if (average.isFinite) return average;
  }
  if (speedKmh.isFinite && speedKmh > 0) return speedKmh;
  return paceSecondsPerKm > 0 ? 3600 / paceSecondsPerKm : 0;
}
