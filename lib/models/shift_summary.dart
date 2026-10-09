class ShiftSummary {
  const ShiftSummary({
    required this.pendingCount,
    required this.doneCount,
    required this.estimatedKm,
    required this.estimatedDuration,
    required this.earnings,
    required this.doneKm,
  });

  final int pendingCount;
  final int doneCount;
  final double estimatedKm;
  final Duration estimatedDuration;
  final double earnings;
  final double doneKm;

  int get totalCount => pendingCount + doneCount;

  double get avgDeliveryValue => doneCount == 0 ? 0 : earnings / doneCount;

  double get earningsPerKm => estimatedKm <= 0 ? 0 : earnings / estimatedKm;

  double get kmPerDelivery => doneCount == 0 ? 0 : estimatedKm / doneCount;
}

class DayStats {
  const DayStats({
    required this.day,
    required this.deliveries,
    required this.earnings,
    required this.km,
  });

  final DateTime day;
  final int deliveries;
  final double earnings;
  final double km;
}
