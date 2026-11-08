import 'package:rota_max/data/repositories/memory_delivery_repository.dart';
import 'package:rota_max/data/repositories/base_location_repository.dart';
import 'package:rota_max/data/repositories/settings_repository.dart';
import 'package:rota_max/models/delivery.dart';
import 'package:rota_max/models/geo_result.dart';
import 'package:rota_max/models/base_location.dart';
import 'package:rota_max/providers/app_state.dart';
import 'package:rota_max/services/geocoding_service.dart';

class FakeGeocodingService extends GeocodingService {
  FakeGeocodingService({this.result})
      : super(cache: MemoryGeocodeCacheRepository());

  GeoResult? result;

  @override
  Future<GeoResult?> geocode(String rawQuery) async {
    return result ??
        const GeoResult(
          latitude: -23.6944,
          longitude: -46.5654,
          displayName: 'São Bernardo do Campo',
        );
  }

  @override
  Future<List<GeoResult>> search(
    String rawQuery, {
    String? street,
    String? number,
    String? neighborhood,
    String? city,
  }) async {
    final item = await geocode(rawQuery);
    return item == null ? [] : [item];
  }
}

AppState buildTestState({
  List<Delivery>? deliveries,
  BaseLocation? baseLocation,
  GeoResult? geo,
}) {
  return AppState(
    deliveryRepository: MemoryDeliveryRepository(deliveries),
    baseLocationRepository: MemoryBaseLocationRepository(
      baseLocation ??
          BaseLocation(
            name: 'Base Teste',
            address: 'Rua Central, 100',
            latitude: -23.6944,
            longitude: -46.5654,
          ),
    ),
    settingsRepository: MemorySettingsRepository(),
    geocodingService: FakeGeocodingService(result: geo),
  );
}
