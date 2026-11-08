import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:rota_max/app.dart';
import 'package:rota_max/data/database.dart';
import 'package:rota_max/data/repositories/base_location_repository.dart';
import 'package:rota_max/data/repositories/settings_repository.dart';
import 'package:rota_max/data/repositories/sqlite_delivery_repository.dart';
import 'package:rota_max/data/repositories/shift_repository.dart';
import 'package:rota_max/data/repositories/vehicle_repository.dart';
import 'package:rota_max/providers/app_state.dart';
import 'package:rota_max/services/geocoding_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pt_BR');
  final db = await AppDatabase.instance.database;
  final state = AppState(
    deliveryRepository: SqliteDeliveryRepository(db),
    baseLocationRepository: SqliteBaseLocationRepository(db),
    settingsRepository: SqliteSettingsRepository(db),
    geocodingService: GeocodingService(
      cache: SqliteGeocodeCacheRepository(db),
    ),
    shiftRepository: SqliteShiftRepository(db),
    vehicleRepository: SqliteVehicleRepository(db),
  );
  await state.load();
  runApp(RotaMaxApp(state: state));
}
