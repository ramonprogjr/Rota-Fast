import 'package:flutter_test/flutter_test.dart';
import 'package:rota_max/services/maps_service.dart';

void main() {
  test('Waze por endereço codificado', () {
    final uri = MapsService.wazeAddressUri('Rua São João, 10 - Centro');
    expect(
      uri.toString(),
      'https://waze.com/ul?q=Rua%20S%C3%A3o%20Jo%C3%A3o%2C%2010%20-%20Centro'
      '&navigate=yes',
    );
  });

  test('Waze por coordenada', () {
    expect(
      MapsService.wazeLatLngUri(-23.5, -46.6).toString(),
      'https://waze.com/ul?ll=-23.5,-46.6&navigate=yes',
    );
  });

  test('Google Maps pelo texto do endereço', () {
    expect(
      MapsService.googleNavigationUri('Av. Brasil, 5').toString(),
      'google.navigation:q=Av.%20Brasil%2C%205&mode=d',
    );
    expect(
      MapsService.googleDirectionsUri('Av. Brasil, 5').toString(),
      'https://www.google.com/maps/dir/?api=1&destination=Av.%20Brasil%2C%205'
      '&travelmode=driving',
    );
  });

  test('ordem: endereço primeiro, coordenada como reserva', () {
    final waze = MapsService.navigationUris(
      NavApp.waze,
      address: 'Rua A, 1',
      latitude: -23.5,
      longitude: -46.6,
    );
    expect(waze.first.queryParameters['q'], 'Rua A, 1');
    expect(waze.last.queryParameters['ll'], '-23.5,-46.6');

    final onlyPoint = MapsService.navigationUris(
      NavApp.waze,
      address: '',
      latitude: -23.5,
      longitude: -46.6,
    );
    expect(onlyPoint, hasLength(1));
    expect(onlyPoint.single.queryParameters['ll'], '-23.5,-46.6');

    final google = MapsService.navigationUris(
      NavApp.google,
      latitude: -23.5,
      longitude: -46.6,
    );
    expect(google.first.scheme, 'google.navigation');
    expect(google.last.queryParameters['destination'], '-23.5,-46.6');
  });

  test('ajuste nav_app vira NavApp (perguntar = null)', () {
    expect(NavApp.fromSetting('google'), NavApp.google);
    expect(NavApp.fromSetting('waze'), NavApp.waze);
    expect(NavApp.fromSetting('ask'), isNull);
    expect(NavApp.fromSetting(null), NavApp.google);
  });
}
