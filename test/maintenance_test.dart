import 'package:flutter_test/flutter_test.dart';
import 'package:rota_max/core/utils/maintenance.dart';

void main() {
  test('óleo restante e aviso com 10% do intervalo', () {
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
    // Van: troca a cada 10.000 km, aviso a partir de 9.000 km rodados.
    expect(
      MaintenanceCalc.shouldWarnOil(
        odometerKm: 58999,
        lastOilChangeKm: 50000,
        intervalKm: 10000,
      ),
      isFalse,
    );
    expect(
      MaintenanceCalc.shouldWarnOil(
        odometerKm: 59000,
        lastOilChangeKm: 50000,
        intervalKm: 10000,
      ),
      isTrue,
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
      oilIntervalKm: 5000,
      vehicleName: 'Fiorino',
    );
    expect(text, contains('Rota Max'));
    expect(text, contains('8'));
    expect(text, contains('42,5'));
    expect(text, contains('200 km'));
    expect(text, contains('a cada 5000 km'));
    expect(text, contains('Veículo: Fiorino'));
  });
}
