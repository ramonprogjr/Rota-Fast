import 'package:rota_pizza/data/repositories/platform_repository.dart';
import 'package:rota_pizza/models/platform.dart';

class MemoryCompanyRepository implements CompanyRepository {
  MemoryCompanyRepository({List<Company>? initial}) : _companies = {
          for (final item in (initial ?? <Company>[]))
            if (item.id != null) item.id!: item,
        };

  final Map<String, Company> _companies;

  @override
  Future<List<Company>> getAll() async => _companies.values.toList();

  @override
  Future<Company?> getById(String id) async => _companies[id];

  @override
  Future<Company> save(Company company) async {
    final id = company.id ?? DateTime.now().microsecondsSinceEpoch.toString();
    final saved = company.copyWith(id: id);
    _companies[id] = saved;
    return saved;
  }

  @override
  Future<void> delete(String id) async {
    _companies.remove(id);
  }
}

class MemoryDriverRepository implements DriverRepository {
  MemoryDriverRepository({List<DriverProfile>? initial}) : _drivers = {
          for (final item in (initial ?? <DriverProfile>[]))
            if (item.id != null) item.id!: item,
        };

  final Map<String, DriverProfile> _drivers;

  @override
  Future<List<DriverProfile>> getByCompany(String companyId) async {
    return _drivers.values
        .where((driver) => driver.companyId == companyId)
        .toList();
  }

  @override
  Future<DriverProfile?> getById(String id) async => _drivers[id];

  @override
  Future<DriverProfile> save(DriverProfile driver) async {
    final id = driver.id ?? DateTime.now().microsecondsSinceEpoch.toString();
    final saved = driver.copyWith(id: id);
    _drivers[id] = saved;
    return saved;
  }

  @override
  Future<void> update(DriverProfile driver) async {
    if (driver.id == null) {
      return;
    }
    _drivers[driver.id!] = driver;
  }

  @override
  Future<void> delete(String id) async {
    _drivers.remove(id);
  }
}
