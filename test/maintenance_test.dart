import 'package:flutter_test/flutter_test.dart';
import 'package:rota_pizza/core/utils/maintenance.dart';

void main() {
  test('óleo restante a cada 1000 km', () {
    expect(
      MaintenanceCalc.oilRemainingKm(odometerKm: 12500, lastOilChangeKm: 12000),
      500,
    );
    expect(
      MaintenanceCalc.shouldWarnOil(odometerKm: 12950, lastOilChangeKm: 12000),
      isTrue,
    );
    expect(
      MaintenanceCalc.shouldWarnOil(odometerKm: 12100, lastOilChangeKm: 12000),
      isFalse,
    );
  });

  test('custo de gasolina', () {
    expect(
      MaintenanceCalc.gasCost(km: 30, kmPerLiter: 30, pricePerLiter: 6),
      6,
    );
  });

  test('texto do relatório no WhatsApp', () {
    final text = MaintenanceCalc.whatsAppReport(
      dateLabel: '31/08',
      deliveries: 8,
      earnings: 40,
      gpsKm: 42.5,
      gasCostValue: 8.5,
      oilRemaining: 200,
      money: (value) => 'R\$ ${value.toStringAsFixed(2)}',
    );
    expect(text, contains('Rota Food'));
    expect(text, contains('8'));
    expect(text, contains('42,5'));
    expect(text, contains('200 km'));
  });
}
