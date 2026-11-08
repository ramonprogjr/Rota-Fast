import 'package:sqflite/sqflite.dart';

/// Um erro registrado (tabela `error_log`). Só tipo e local no código:
/// nada de mensagem, que pode ter dados de cliente.
class ErrorLogEntry {
  const ErrorLogEntry({
    required this.source,
    required this.errorType,
    this.location,
    required this.createdAt,
  });

  final String source;
  final String errorType;
  final String? location;
  final DateTime createdAt;
}

abstract class ErrorLogRepository {
  /// Mantém só as [maxEntries] mais recentes.
  static const maxEntries = 50;

  Future<void> record({
    required String source,
    required String errorType,
    String? location,
  });

  Future<List<ErrorLogEntry>> recent();

  Future<int> count();
}

class SqliteErrorLogRepository implements ErrorLogRepository {
  SqliteErrorLogRepository(this._db);

  final Database _db;

  @override
  Future<void> record({
    required String source,
    required String errorType,
    String? location,
  }) async {
    await _db.transaction((txn) async {
      await txn.insert('error_log', {
        'source': source,
        'error_type': errorType,
        'location': location,
        'created_at': DateTime.now().toIso8601String(),
      });
      await txn.rawDelete('''
        DELETE FROM error_log WHERE id NOT IN (
          SELECT id FROM error_log ORDER BY id DESC LIMIT ?
        )
      ''', [ErrorLogRepository.maxEntries]);
    });
  }

  @override
  Future<List<ErrorLogEntry>> recent() async {
    final rows = await _db.query('error_log', orderBy: 'id DESC');
    return [
      for (final row in rows)
        ErrorLogEntry(
          source: row['source'] as String,
          errorType: row['error_type'] as String,
          location: row['location'] as String?,
          createdAt: DateTime.tryParse(row['created_at'] as String? ?? '') ??
              DateTime.now(),
        ),
    ];
  }

  @override
  Future<int> count() async =>
      Sqflite.firstIntValue(
        await _db.rawQuery('SELECT COUNT(*) FROM error_log'),
      ) ??
      0;
}

class MemoryErrorLogRepository implements ErrorLogRepository {
  final List<ErrorLogEntry> _entries = [];

  @override
  Future<void> record({
    required String source,
    required String errorType,
    String? location,
  }) async {
    _entries.insert(
      0,
      ErrorLogEntry(
        source: source,
        errorType: errorType,
        location: location,
        createdAt: DateTime.now(),
      ),
    );
    if (_entries.length > ErrorLogRepository.maxEntries) {
      _entries.removeRange(ErrorLogRepository.maxEntries, _entries.length);
    }
  }

  @override
  Future<List<ErrorLogEntry>> recent() async => List.of(_entries);

  @override
  Future<int> count() async => _entries.length;
}
