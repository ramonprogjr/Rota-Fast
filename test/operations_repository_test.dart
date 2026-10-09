import 'package:flutter_test/flutter_test.dart';
import 'package:rota_pizza/data/repositories/memory_operations_repository.dart';
import 'package:rota_pizza/models/operations.dart';

void main() {
  test('turno de operação registra status e produtividade', () async {
    final repo = MemoryOperationShiftRepository();
    final shift = OperationShift(
      companyId: 'company-1',
      driverId: 'driver-1',
      startedAt: DateTime(2026, 10, 9, 8, 0),
      title: 'Turno manhã',
      status: ShiftStatus.active,
      routeKm: 28,
      earnings: 460,
      deliveriesCompleted: 4,
      deliveriesPending: 2,
    );

    final saved = await repo.save(shift);
    final byCompany = await repo.getByCompany('company-1');
    final updated = saved.copyWith(status: ShiftStatus.completed, earnings: 500);
    await repo.update(updated);

    expect(saved.title, 'Turno manhã');
    expect(saved.avgEarningsPerDelivery, closeTo(115, 0.001));
    expect(byCompany, isNotEmpty);
    expect((await repo.getById(saved.id!))?.status, ShiftStatus.completed);
  });

  test('snapshot do dashboard calcula média por motorista', () {
    const snapshot = DashboardSnapshot(
      companyId: 'company-1',
      date: '2026-10-09',
      totalDeliveries: 18,
      totalEarnings: 900,
      totalKm: 120,
      activeDrivers: 3,
      completedShifts: 2,
    );

    expect(snapshot.avgDeliveriesPerDriver, closeTo(6, 0.001));
    expect(snapshot.earningsPerKm, closeTo(7.5, 0.001));
  });
}
