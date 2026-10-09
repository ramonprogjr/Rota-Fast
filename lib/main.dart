import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:rota_pizza/app.dart';
import 'package:rota_pizza/core/config/supabase_config.dart';
import 'package:rota_pizza/data/demo_shift_seed.dart';
import 'package:rota_pizza/data/database.dart';
import 'package:rota_pizza/data/repositories/pizzeria_repository.dart';
import 'package:rota_pizza/data/repositories/settings_repository.dart';
import 'package:rota_pizza/data/repositories/sqlite_delivery_repository.dart';
import 'package:rota_pizza/data/repositories/shift_repository.dart';
import 'package:rota_pizza/providers/app_state.dart';
import 'package:rota_pizza/services/geocoding_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pt_BR');
  await SupabaseConfig.initialize();
  final db = await AppDatabase.instance.database;
  await DemoShiftSeeder.seedIfNeeded(db);
  final state = AppState(
    deliveryRepository: SqliteDeliveryRepository(db),
    pizzeriaRepository: SqlitePizzeriaRepository(db),
    settingsRepository: SqliteSettingsRepository(db),
    geocodingService: GeocodingService(
      cache: SqliteGeocodeCacheRepository(db),
    ),
    shiftRepository: SqliteShiftRepository(db),
  );
  await state.load();
  runApp(RotaPizzaApp(state: state));
}
