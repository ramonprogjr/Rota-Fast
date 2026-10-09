import 'package:flutter_test/flutter_test.dart';
import 'package:rota_pizza/data/repositories/memory_platform_repository.dart';
import 'package:rota_pizza/models/platform.dart';

void main() {
  test('empresa mantém dados básicos e identidade', () {
    final company = Company(
      id: 'company-1',
      name: 'Rota Max Delivery',
      city: 'São Bernardo do Campo',
      plan: 'pro',
      isActive: true,
    );

    expect(company.id, 'company-1');
    expect(company.name, 'Rota Max Delivery');
    expect(company.plan, 'pro');
    expect(company.isActive, isTrue);
  });

  test('perfil do entregador respeita status e permissões', () {
    final driver = DriverProfile(
      id: 'driver-1',
      companyId: 'company-1',
      fullName: 'João da Silva',
      phone: '5511999999999',
      role: UserRole.driver,
      vehicleType: 'Moto',
      status: DriverStatus.available,
      isActive: true,
    );

    expect(driver.fullName, 'João da Silva');
    expect(driver.isAvailableForRoute, isTrue);
    expect(driver.canManageTeam, isFalse);
  });

  test('métricas de operação calculam média por entrega', () {
    const metrics = OperationMetrics(
      date: '2026-10-09',
      deliveries: 8,
      earnings: 1200,
      km: 60,
      driversActive: 3,
    );

    expect(metrics.avgEarningsPerDelivery, closeTo(150, 0.001));
    expect(metrics.kmPerDelivery, closeTo(7.5, 0.001));
  });

  test('repositório em memória salva empresa e entregador por companhia', () async {
    final companies = MemoryCompanyRepository();
    final drivers = MemoryDriverRepository();

    final company = await companies.save(
      Company(name: 'Rota Max', city: 'São Bernardo do Campo'),
    );

    final driver = await drivers.save(
      DriverProfile(
        companyId: company.id!,
        fullName: 'Maria Souza',
        phone: '551188887777',
        role: UserRole.driver,
        vehicleType: 'Moto',
      ),
    );

    final byCompany = await drivers.getByCompany(company.id!);
    final savedCompany = await companies.getById(company.id!);

    expect(savedCompany?.name, 'Rota Max');
    expect(byCompany, isNotEmpty);
    expect(driver.fullName, 'Maria Souza');
    expect(byCompany.first.id, driver.id);
  });
}
