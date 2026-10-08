import 'package:rota_pizza/core/constants/app_constants.dart';

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

  static bool shouldWarnOil({
    required double odometerKm,
    required double lastOilChangeKm,
  }) {
    return oilRemainingKm(
          odometerKm: odometerKm,
          lastOilChangeKm: lastOilChangeKm,
        ) <=
        AppConstants.oilWarnBelowKm;
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
  }) {
    final km = gpsKm.toStringAsFixed(1).replaceAll('.', ',');
    final oil = oilRemaining.toStringAsFixed(0);
    return '''
Rota Food — relatório $dateLabel

Entregas: $deliveries
Ganhos: ${money(earnings)}
Km GPS: $km km
Gasolina estimada: ${money(gasCostValue)}
Óleo: faltam $oil km para a troca (a cada 1000 km)
''';
  }
}
