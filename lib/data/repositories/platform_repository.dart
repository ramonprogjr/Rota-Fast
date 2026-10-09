import 'package:rota_pizza/models/platform.dart';

abstract class CompanyRepository {
  Future<List<Company>> getAll();
  Future<Company?> getById(String id);
  Future<Company> save(Company company);
  Future<void> delete(String id);
}

abstract class DriverRepository {
  Future<List<DriverProfile>> getByCompany(String companyId);
  Future<DriverProfile?> getById(String id);
  Future<DriverProfile> save(DriverProfile driver);
  Future<void> update(DriverProfile driver);
  Future<void> delete(String id);
}
