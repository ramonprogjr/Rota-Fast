import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:rota_max/core/errors/app_error.dart';
import 'package:rota_max/data/repositories/base_location_repository.dart';
import 'package:rota_max/data/repositories/error_log_repository.dart';
import 'package:rota_max/data/repositories/memory_delivery_repository.dart';
import 'package:rota_max/data/repositories/settings_repository.dart';
import 'package:rota_max/data/repositories/shift_repository.dart';
import 'package:rota_max/data/repositories/vehicle_repository.dart';
import 'package:rota_max/models/base_location.dart';
import 'package:rota_max/models/delivery.dart';
import 'package:rota_max/models/vehicle.dart';
import 'package:rota_max/providers/app_state.dart';
import 'package:rota_max/screens/startup_screen.dart';
import 'package:rota_max/services/geocoding_service.dart';

/// Versão de visualização no navegador (site local com moldura de celular).
///
/// Mesmo app, mesmas telas, mas com dados de exemplo em memória: nada é
/// gravado e recarregar a página volta ao começo. Recursos que só existem
/// no Android (OCR da câmera, GPS em segundo plano do turno) não funcionam
/// aqui. Para gerar: tool/preview.ps1.
void main() {
  runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      installErrorHandlers();
      await initializeDateFormatting('pt_BR');
      runApp(const AppBootstrap(open: openPreviewState));
    },
    (error, stack) => ErrorReporter.report(error, stack, source: 'zone'),
  );
}

Future<AppState> openPreviewState() async {
  final errorLog = MemoryErrorLogRepository();
  ErrorReporter.sink = errorLog;
  final state = AppState(
    deliveryRepository: MemoryDeliveryRepository(_sampleDeliveries()),
    baseLocationRepository: MemoryBaseLocationRepository(
      BaseLocation(
        name: 'Centro de distribuição',
        address: 'Rua Marechal Deodoro, 980',
        city: 'São Bernardo do Campo',
        latitude: -23.6939,
        longitude: -46.5648,
      ),
    ),
    settingsRepository: MemorySettingsRepository(),
    geocodingService: GeocodingService(cache: MemoryGeocodeCacheRepository()),
    shiftRepository: MemoryShiftRepository(),
    vehicleRepository: MemoryVehicleRepository([
      Vehicle(
        name: 'Fiorino branca',
        type: VehicleType.utility,
        plate: 'ABC1D23',
        odometerKm: 48210,
        lastOilChangeKm: 43700,
        isActive: true,
      ),
      Vehicle(
        name: 'Moto reserva',
        type: VehicleType.motorcycle,
        odometerKm: 23180,
        lastOilChangeKm: 22300,
      ),
    ]),
    errorLogRepository: errorLog,
  );
  await state.load();
  return state;
}

/// Oito entregas espalhadas por São Bernardo, cadastradas fora de ordem de
/// propósito, para o "Organizar rota" mostrar a economia.
List<Delivery> _sampleDeliveries() {
  final start = DateTime.now().subtract(const Duration(hours: 1));
  var minute = 0;
  Delivery stop(
    String name,
    String street,
    String number,
    String neighborhood,
    double lat,
    double lng, {
    String? phone,
    String? notes,
    String? postalCode,
    DeliveryPriority priority = DeliveryPriority.normal,
  }) {
    minute += 3;
    return Delivery(
      customerName: name,
      address: street,
      number: number,
      neighborhood: neighborhood,
      city: 'São Bernardo do Campo',
      state: 'SP',
      postalCode: postalCode,
      phone: phone,
      notes: notes,
      latitude: lat,
      longitude: lng,
      locationConfirmed: true,
      priority: priority,
      createdAt: start.add(Duration(minutes: minute)),
    );
  }

  return [
    stop('Marina Alves', 'Rua João de Barros', '412', 'Jardim do Mar',
        -23.6860, -46.5480,
        phone: '11987654321', postalCode: '09750000'),
    stop('Carlos Menezes', 'Avenida Kennedy', '1500', 'Jardim do Mar',
        -23.6905, -46.5530),
    stop('Padaria Estrela', 'Rua Jurubatuba', '210', 'Centro',
        -23.7105, -46.5520,
        notes: 'Entregar no balcão, falar com a Joana',
        priority: DeliveryPriority.urgent),
    stop('Rafael Souza', 'Rua Marechal Deodoro', '2200', 'Centro',
        -23.6995, -46.5560),
    stop('Clínica Vida', 'Avenida Pereira Barreto', '1800', 'Baeta Neves',
        -23.6790, -46.5650,
        priority: DeliveryPriority.high),
    stop('Juliana Prado', 'Rua Tiradentes', '95', 'Rudge Ramos',
        -23.6700, -46.5720),
    stop('Mercadinho Bom Preço', 'Avenida Lucas Nogueira Garcez', '620',
        'Vila Euclides', -23.7020, -46.5430),
    stop('Bruno Lima', 'Rua Américo Brasiliense', '33', 'Centro',
        -23.7060, -46.5600,
        phone: '11912345678'),
  ];
}
