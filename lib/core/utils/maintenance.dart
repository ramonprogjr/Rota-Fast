import 'package:rota_max/core/constants/app_constants.dart';

class MaintenanceCalc {
  static double kmSinceOil({
    required double odometerKm,
    required double lastOilChangeKm,
  }) {
    final value = odometerKm - lastOilChangeKm;
    return value < 0 ? 0 : value;
  }

  static double oilRemainingKm({
    required double odometerKm,
    required double lastOilChangeKm,
    double intervalKm = AppConstants.oilIntervalKm,
  }) {
    final remaining = intervalKm -
        kmSinceOil(odometerKm: odometerKm, lastOilChangeKm: lastOilChangeKm);
    return remaining < 0 ? 0 : remaining;
  }

  /// Avisa quando faltam 10% do intervalo ou menos.
  static bool shouldWarnOil({
    required double odometerKm,
    required double lastOilChangeKm,
    double intervalKm = AppConstants.oilIntervalKm,
  }) {
    return oilRemainingKm(
          odometerKm: odometerKm,
          lastOilChangeKm: lastOilChangeKm,
          intervalKm: intervalKm,
        ) <=
        intervalKm * 0.1;
  }

  static double gasCost({
    required double km,
    required double kmPerLiter,
    required double pricePerLiter,
  }) {
    if (km <= 0 || kmPerLiter <= 0) {
      return 0;
    }
    return (km / kmPerLiter) * pricePerLiter;
  }

  static String whatsAppReport({
    required String dateLabel,
    required int deliveries,
    required double earnings,
    required double gpsKm,
    required double gasCostValue,
    required double oilRemaining,
    required String Function(double value) money,
    double oilIntervalKm = AppConstants.oilIntervalKm,
    String? vehicleName,
  }) {
    final km = gpsKm.toStringAsFixed(1).replaceAll('.', ',');
    final oil = oilRemaining.toStringAsFixed(0);
    final interval = oilIntervalKm.toStringAsFixed(0);
    final vehicleLine =
        vehicleName == null ? '' : 'Veículo: $vehicleName\n';
    return '''
Rota Max — relatório $dateLabel

${vehicleLine}Entregas: $deliveries
Ganhos: ${money(earnings)}
Km GPS: $km km
Combustível estimado: ${money(gasCostValue)}
Óleo: faltam $oil km para a troca (a cada $interval km)
''';
  }
}
