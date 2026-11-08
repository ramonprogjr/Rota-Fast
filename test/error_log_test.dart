import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rota_max/core/errors/app_error.dart';
import 'package:rota_max/data/database.dart';
import 'package:rota_max/data/repositories/delivery_repository.dart';
import 'package:rota_max/data/repositories/error_log_repository.dart';
import 'package:rota_max/models/delivery.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  final factories = <String, Future<(ErrorLogRepository, Future<void> Function())> Function()>{
    'sqlite': () async {
      final db = await AppDatabase.open(
        inMemoryDatabasePath,
        factory: databaseFactoryFfiNoIsolate,
      );
      return (SqliteErrorLogRepository(db) as ErrorLogRepository, db.close);
    },
    'memória': () async =>
        (MemoryErrorLogRepository() as ErrorLogRepository, () async {}),
  };

  for (final entry in factories.entries) {
    group(entry.key, () {
      late ErrorLogRepository repo;
      late Future<void> Function() close;

      setUp(() async {
        (repo, close) = await entry.value();
      });

      tearDown(() => close());

      test('guarda só os 50 mais recentes', () async {
        for (var i = 0; i < 55; i++) {
          await repo.record(source: 's$i', errorType: 'StateError');
        }
        expect(await repo.count(), ErrorLogRepository.maxEntries);
        final recent = await repo.recent();
        expect(recent.first.source, 's54');
        expect(recent.last.source, 's5');
      });

      test('reporter grava tipo e local, sem a mensagem', () async {
        ErrorReporter.sink = repo;
        addTearDown(() => ErrorReporter.sink = null);
        try {
          throw StateError('Cliente Maria, Rua das Flores 10');
        } catch (error, stack) {
          await ErrorReporter.report(error, stack, source: 'teste');
        }
        final entry = (await repo.recent()).single;
        expect(entry.source, 'teste');
        expect(entry.errorType, 'StateError');
        expect(entry.location, isNull); // pilha do teste, fora de lib/
        expect('${entry.errorType}${entry.location}', isNot(contains('Maria')));
      });
    });
  }

  test('reporter nunca lança, mesmo com o registro quebrado', () async {
    ErrorReporter.sink = _BrokenLog();
    addTearDown(() => ErrorReporter.sink = null);
    await ErrorReporter.report(Exception('x'), StackTrace.current);
  });

  group('friendlyMessage', () {
    test('usa a mensagem dos erros do app', () {
      expect(friendlyMessage(const AppError('Oi')), 'Oi');
      expect(friendlyMessage(ArgumentError('Falta motivo')), 'Falta motivo');
      expect(friendlyMessage(StateError('Não existe')), 'Não existe');
      expect(
        friendlyMessage(
          InvalidTransition(DeliveryStatus.delivered, DeliveryStatus.failed),
        ),
        contains('Entregue'),
      );
    });

    test('esconde detalhe técnico', () {
      expect(
        friendlyMessage(const SocketException('host lookup failed')),
        contains('Sem internet'),
      );
      expect(
        friendlyMessage(Exception('boom'), fallback: 'Tente de novo.'),
        'Tente de novo.',
      );
    });
  });
}

class _BrokenLog implements ErrorLogRepository {
  @override
  Future<int> count() => throw UnimplementedError();

  @override
  Future<void> record({
    required String source,
    required String errorType,
    String? location,
  }) =>
      throw StateError('disco cheio');

  @override
  Future<List<ErrorLogEntry>> recent() => throw UnimplementedError();
}
