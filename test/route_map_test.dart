import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:rota_max/core/theme/app_theme.dart';
import 'package:rota_max/data/repositories/base_location_repository.dart';
import 'package:rota_max/data/repositories/memory_delivery_repository.dart';
import 'package:rota_max/data/repositories/settings_repository.dart';
import 'package:rota_max/models/base_location.dart';
import 'package:rota_max/models/delivery.dart';
import 'package:rota_max/models/geo_result.dart';
import 'package:rota_max/providers/app_state.dart';
import 'package:rota_max/screens/route_map_screen.dart';
import 'package:rota_max/services/fuel_station_service.dart';
import 'package:rota_max/services/location_service.dart';
import 'package:rota_max/widgets/location_status_banner.dart';

import 'helpers/fake_geolocator.dart';
import 'helpers/test_state.dart';

AppState _state(FakeGeolocator fake, {List<Delivery>? deliveries}) {
  return AppState(
    deliveryRepository: MemoryDeliveryRepository(deliveries),
    baseLocationRepository: MemoryBaseLocationRepository(
      BaseLocation(
        name: 'Base',
        address: 'Rua Central, 100',
        latitude: -23.6944,
        longitude: -46.5654,
      ),
    ),
    settingsRepository: MemorySettingsRepository(),
    geocodingService: FakeGeocodingService(),
    locationService: LocationService(
      adapter: fake,
      sleep: (_) async {},
    ),
  );
}

Widget _wrap(Widget child, {AppState? state}) {
  final app = MaterialApp(theme: AppTheme.dark(), home: child);
  if (state == null) {
    return app;
  }
  return ChangeNotifierProvider<AppState>.value(value: state, child: app);
}

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));

  group('LocationStatusBanner', () {
    final now = DateTime(2026, 11, 8, 10);

    Future<void> pumpBanner(
      WidgetTester tester,
      LocationReading? reading, {
      VoidCallback? onRetry,
      VoidCallback? onLocation,
      VoidCallback? onApp,
    }) =>
        tester.pumpWidget(
          _wrap(
            Scaffold(
              body: LocationStatusBanner(
                reading: reading,
                now: now,
                onRetry: onRetry,
                onOpenLocationSettings: onLocation,
                onOpenAppSettings: onApp,
              ),
            ),
          ),
        );

    testWidgets('não mostra nada sem leitura ou com GPS ok', (tester) async {
      await pumpBanner(tester, null);
      expect(find.byKey(const Key('location-status-banner')), findsNothing);
      await pumpBanner(
        tester,
        LocationReading(
          point: const GeoPoint(-23.6, -46.5),
          status: LocationStatus.ok,
          at: now,
        ),
      );
      expect(find.byKey(const Key('location-status-banner')), findsNothing);
    });

    testWidgets('GPS desligado oferece Ativar', (tester) async {
      var opened = 0;
      await pumpBanner(
        tester,
        const LocationReading(status: LocationStatus.disabled),
        onLocation: () => opened++,
      );
      expect(find.text('GPS desligado'), findsOneWidget);
      await tester.tap(find.text('Ativar'));
      expect(opened, 1);
    });

    testWidgets('permissão negada para sempre abre ajustes', (tester) async {
      var opened = 0;
      await pumpBanner(
        tester,
        const LocationReading(status: LocationStatus.deniedForever),
        onApp: () => opened++,
      );
      expect(find.text('Permissão negada'), findsOneWidget);
      await tester.tap(find.text('Abrir ajustes'));
      expect(opened, 1);
    });

    testWidgets('permissão negada pede de novo', (tester) async {
      var retried = 0;
      await pumpBanner(
        tester,
        const LocationReading(status: LocationStatus.denied),
        onRetry: () => retried++,
      );
      await tester.tap(find.text('Permitir'));
      expect(retried, 1);
    });

    testWidgets('sem sinal mostra a idade da última posição', (tester) async {
      var retried = 0;
      await pumpBanner(
        tester,
        LocationReading(
          point: const GeoPoint(-23.6, -46.5),
          status: LocationStatus.timeout,
          at: now.subtract(const Duration(minutes: 5)),
          stale: true,
        ),
        onRetry: () => retried++,
      );
      expect(find.text('Sem sinal de GPS'), findsOneWidget);
      expect(find.text('Última posição há 5 min.'), findsOneWidget);
      await tester.tap(find.text('Tentar de novo'));
      expect(retried, 1);
    });
  });

  group('RouteMapScreen', () {
    Future<void> setPhoneView(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    List<Delivery> stops() => [
          Delivery(
            id: 1,
            customerName: 'Ana',
            address: 'Rua A, 10',
            latitude: -23.69,
            longitude: -46.56,
            routeOrder: 0,
          ),
          Delivery(
            id: 2,
            customerName: 'Bruno',
            address: 'Rua B, 20',
            latitude: -23.70,
            longitude: -46.57,
            routeOrder: 1,
          ),
          Delivery(
            id: 3,
            customerName: 'Carla',
            address: 'Rua C, 30',
            routeOrder: 2,
          ),
          Delivery(
            id: 4,
            customerName: 'Davi',
            address: 'Rua D, 40',
            latitude: -23.68,
            longitude: -46.55,
            status: DeliveryStatus.delivered,
            deliveredAt: DateTime.now(),
          ),
        ];

    testWidgets('monta com paradas e posição desatualizada', (tester) async {
      await setPhoneView(tester);
      final fake = FakeGeolocator(
        currentError: TimeoutException('sem sinal'),
        lastKnown: LocationFix(
          -23.695,
          -46.566,
          DateTime.now().subtract(const Duration(minutes: 6)),
        ),
      );
      final state = _state(fake, deliveries: stops());
      await state.load();
      await tester.pumpAndSettle();
      expect(state.location!.stale, isTrue);

      final fuel = FuelStationService(
        client: MockClient(
          (request) async => http.Response(
            '{"elements":[{"type":"node","id":9,"lat":-23.69,"lon":-46.56,'
            '"tags":{"name":"Posto 9","fuel:diesel":"yes"}}]}',
            200,
          ),
        ),
      );
      await tester.pumpWidget(
        _wrap(
          RouteMapScreen(
            showTiles: false,
            refreshOnOpen: false,
            fuelService: fuel,
          ),
          state: state,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('stop-marker-1')), findsOneWidget);
      expect(find.byKey(const Key('stop-marker-2')), findsOneWidget);
      expect(find.byKey(const Key('stop-marker-3')), findsNothing);
      expect(find.byKey(const Key('user-marker')), findsOneWidget);
      expect(find.text('desatualizada'), findsOneWidget);
      expect(find.text('Sem sinal de GPS'), findsOneWidget);
      expect(find.byKey(const Key('map-next-stop')), findsOneWidget);
      expect(find.text('Ana'), findsOneWidget);
      expect(find.textContaining('linha reta'), findsOneWidget);
      expect(find.textContaining('sem localização'), findsOneWidget);

      await tester.tap(find.byKey(const Key('toggle-fuel')));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.list), findsOneWidget);
      await tester.tap(find.byIcon(Icons.list));
      await tester.pumpAndSettle();
      expect(find.text('Posto 9'), findsOneWidget);
      expect(find.text('Preços não disponíveis.'), findsOneWidget);

      await tester.tap(find.byTooltip('Ver a rota inteira'), warnIfMissed: false);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('monta sem paradas e sem GPS', (tester) async {
      await setPhoneView(tester);
      final state = _state(FakeGeolocator(serviceEnabled: false));
      await state.load();
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        _wrap(
          const RouteMapScreen(showTiles: false, refreshOnOpen: false),
          state: state,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('GPS desligado'), findsOneWidget);
      expect(find.byKey(const Key('user-marker')), findsNothing);
      expect(find.byKey(const Key('map-next-stop')), findsNothing);
    });

    testWidgets('com "perguntar", Navegar mostra a escolha do app',
        (tester) async {
      await setPhoneView(tester);
      final state = _state(
        FakeGeolocator(permission: LocationPermission.deniedForever),
        deliveries: stops(),
      );
      await state.load();
      await state.setNavApp('ask');
      await tester.pumpAndSettle();
      expect(await state.navigateTo(state.nextStop!), NavOutcome.needsChoice);
      await tester.pumpWidget(
        _wrap(
          const RouteMapScreen(showTiles: false, refreshOnOpen: false),
          state: state,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Permissão negada'), findsOneWidget);
      await tester.tap(find.text('Navegar'));
      await tester.pumpAndSettle();
      expect(find.text('Navegar com'), findsOneWidget);
      expect(find.byKey(const Key('nav-app-waze')), findsOneWidget);
      expect(find.byKey(const Key('nav-app-google')), findsOneWidget);
    });
  });
}
