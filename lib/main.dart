import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:rota_max/core/errors/app_error.dart';
import 'package:rota_max/data/database.dart';
import 'package:rota_max/data/repositories/base_location_repository.dart';
import 'package:rota_max/data/repositories/error_log_repository.dart';
import 'package:rota_max/data/repositories/settings_repository.dart';
import 'package:rota_max/data/repositories/sqlite_delivery_repository.dart';
import 'package:rota_max/data/repositories/shift_repository.dart';
import 'package:rota_max/data/repositories/vehicle_repository.dart';
import 'package:rota_max/providers/app_state.dart';
import 'package:rota_max/screens/startup_screen.dart';
import 'package:rota_max/services/geocoding_service.dart';

void main() {
  runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      installErrorHandlers();
      await initializeDateFormatting('pt_BR');
      runApp(const AppBootstrap(open: openAppState));
    },
    (error, stack) => ErrorReporter.report(error, stack, source: 'zone'),
  );
}

/// Abre o banco e carrega tudo. Se lançar, o [AppBootstrap] mostra
/// "Não foi possível abrir os dados" com "Tentar de novo".
Future<AppState> openAppState() async {
  final db = await AppDatabase.instance.database;
  final errorLog = SqliteErrorLogRepository(db);
  ErrorReporter.sink = errorLog;
  final state = AppState(
    deliveryRepository: SqliteDeliveryRepository(db),
    baseLocationRepository: SqliteBaseLocationRepository(db),
    settingsRepository: SqliteSettingsRepository(db),
    geocodingService: GeocodingService(
      cache: SqliteGeocodeCacheRepository(db),
    ),
    shiftRepository: SqliteShiftRepository(db),
    vehicleRepository: SqliteVehicleRepository(db),
    errorLogRepository: errorLog,
  );
  await state.load();
  return state;
}
