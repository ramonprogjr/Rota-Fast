import 'package:rota_pizza/data/repositories/operations_repository.dart';
import 'package:rota_pizza/models/operations.dart';

class MemoryOperationShiftRepository implements OperationShiftRepository {
  MemoryOperationShiftRepository({List<OperationShift>? initial}) : _shifts = {
          for (final item in (initial ?? <OperationShift>[]))
            if (item.id != null) item.id!: item,
        };

  final Map<String, OperationShift> _shifts;

  @override
  Future<List<OperationShift>> getByCompany(String companyId) async {
    return _shifts.values
        .where((shift) => shift.companyId == companyId)
        .toList();
  }

  @override
  Future<OperationShift?> getById(String id) async => _shifts[id];

  @override
  Future<OperationShift> save(OperationShift shift) async {
    final id = shift.id ?? DateTime.now().microsecondsSinceEpoch.toString();
    final saved = shift.copyWith(id: id);
    _shifts[id] = saved;
    return saved;
  }

  @override
  Future<void> update(OperationShift shift) async {
    if (shift.id == null) {
      return;
    }
    _shifts[shift.id!] = shift;
  }

  @override
  Future<void> delete(String id) async {
    _shifts.remove(id);
  }
}
