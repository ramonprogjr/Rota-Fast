import 'package:flutter_test/flutter_test.dart';
import 'package:rota_pizza/data/repositories/memory_auth_repository.dart';
import 'package:rota_pizza/models/auth.dart';
import 'package:rota_pizza/models/dashboard.dart';

void main() {
  test('sessão valida mantém usuário e expiração', () async {
    final repo = MemoryAuthRepository(
      seedUsers: [
        AppUser(
          id: 'user-1',
          companyId: 'company-1',
          fullName: 'Maria Souza',
          email: 'maria@rotamax.com',
          role: AppRole.manager,
        ),
      ],
    );

    final session = await repo.signInWithEmail(
      email: 'maria@rotamax.com',
      password: '123456',
    );

    expect(session, isNotNull);
    expect(session!.user.fullName, 'Maria Souza');
    expect(session.isValid, isTrue);
    expect((await repo.currentSession())?.user.id, 'user-1');
  });

  test('dashboard calcula métricas da operação', () {
    const summary = DashboardSummary(
      companyId: 'company-1',
      date: '2026-10-09',
      deliveries: 60,
      earnings: 2400,
      km: 180,
      activeDrivers: 4,
      pendingRoutes: 8,
      completedShifts: 3,
    );

    expect(summary.avgEarningsPerDelivery, closeTo(40, 0.001));
    expect(summary.avgDeliveriesPerDriver, closeTo(15, 0.001));
    expect(summary.metrics(), hasLength(4));
  });
}
