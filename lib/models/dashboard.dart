class DashboardMetric {
  const DashboardMetric({
    required this.label,
    required this.value,
    this.trend,
    this.helper,
  });

  final String label;
  final String value;
  final String? trend;
  final String? helper;
}

class DashboardSummary {
  const DashboardSummary({
    required this.companyId,
    required this.date,
    required this.deliveries,
    required this.earnings,
    required this.km,
    required this.activeDrivers,
    required this.pendingRoutes,
    required this.completedShifts,
  });

  final String companyId;
  final String date;
  final int deliveries;
  final double earnings;
  final double km;
  final int activeDrivers;
  final int pendingRoutes;
  final int completedShifts;

  double get avgEarningsPerDelivery =>
      deliveries == 0 ? 0 : earnings / deliveries;

  double get avgDeliveriesPerDriver =>
      activeDrivers == 0 ? 0 : deliveries / activeDrivers;

  double get utilizationRate =>
      activeDrivers == 0 ? 0 : (completedShifts / activeDrivers) * 100;

  List<DashboardMetric> metrics() {
    return [
      DashboardMetric(
        label: 'Entregas',
        value: deliveries.toString(),
        trend: '+12%',
        helper: 'comparado ao dia anterior',
      ),
      DashboardMetric(
        label: 'Faturamento',
        value: 'R\$ ${earnings.toStringAsFixed(2)}',
        trend: '+8%',
        helper: 'em vendas do turno',
      ),
      DashboardMetric(
        label: 'Km',
        value: '${km.toStringAsFixed(1)} km',
        trend: '-3%',
        helper: 'quilometragem total',
      ),
      DashboardMetric(
        label: 'Ativos',
        value: activeDrivers.toString(),
        trend: 'OK',
        helper: 'entregadores online',
      ),
    ];
  }
}
