import 'package:rota_pizza/models/operations.dart';

abstract class OperationShiftRepository {
  Future<List<OperationShift>> getByCompany(String companyId);
  Future<OperationShift?> getById(String id);
  Future<OperationShift> save(OperationShift shift);
  Future<void> update(OperationShift shift);
  Future<void> delete(String id);
}
