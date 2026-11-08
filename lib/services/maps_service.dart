import 'package:url_launcher/url_launcher.dart';
import 'package:rota_max/core/utils/phone_utils.dart';

/// Apps de navegação externos suportados.
enum NavApp {
  google('Google Maps'),
  waze('Waze');

  const NavApp(this.label);

  final String label;

  /// Valor salvo nos ajustes ('google', 'waze' ou 'ask').
  /// Retorna null para 'ask' (perguntar a cada vez).
  static NavApp? fromSetting(String? value) {
    switch (value) {
      case 'waze':
        return NavApp.waze;
      case 'ask':
        return null;
      default:
        return NavApp.google;
    }
  }
}

class MapsService {
  const MapsService();

  // ---- Construtores de URL (puros, testáveis) ----

  /// Intent nativo do Google Maps em modo direção, pelo texto do endereço.
  static Uri googleNavigationUri(String query) =>
      Uri.parse('google.navigation:q=${Uri.encodeComponent(query)}&mode=d');

  /// Link universal do Google Maps (abre no app ou no navegador).
  static Uri googleDirectionsUri(String destination) => Uri.parse(
        'https://www.google.com/maps/dir/?api=1'
        '&destination=${Uri.encodeComponent(destination)}&travelmode=driving',
      );

  /// Waze pelo texto do endereço.
  static Uri wazeAddressUri(String address) => Uri.parse(
        'https://waze.com/ul?q=${Uri.encodeComponent(address)}&navigate=yes',
      );

  /// Waze por coordenada.
  static Uri wazeLatLngUri(double latitude, double longitude) => Uri.parse(
        'https://waze.com/ul?ll=$latitude,$longitude&navigate=yes',
      );

  /// Ordem de tentativas para um destino: endereço primeiro (mais preciso
  /// no Brasil do que a coordenada do OSM), coordenada como reserva.
  static List<Uri> navigationUris(
    NavApp app, {
    String? address,
    double? latitude,
    double? longitude,
  }) {
    final text = address?.trim() ?? '';
    final hasPoint = latitude != null && longitude != null;
    switch (app) {
      case NavApp.google:
        return [
          if (text.isNotEmpty) ...[
            googleNavigationUri(text),
            googleDirectionsUri(text),
          ],
          if (hasPoint) ...[
            if (text.isEmpty) googleNavigationUri('$latitude,$longitude'),
            googleDirectionsUri('$latitude,$longitude'),
          ],
        ];
      case NavApp.waze:
        return [
          if (text.isNotEmpty) wazeAddressUri(text),
          if (hasPoint) wazeLatLngUri(latitude, longitude),
        ];
    }
  }

  // ---- Abertura ----

  /// Abre a navegação no app escolhido. Se o app não abrir, tenta o
  /// Google Maps como reserva.
  Future<bool> navigate({
    required String address,
    double? latitude,
    double? longitude,
    NavApp app = NavApp.google,
  }) async {
    final uris = navigationUris(
      app,
      address: address,
      latitude: latitude,
      longitude: longitude,
    );
    if (await _launchFirst(uris)) {
      return true;
    }
    if (app != NavApp.google) {
      return _launchFirst(
        navigationUris(
          NavApp.google,
          address: address,
          latitude: latitude,
          longitude: longitude,
        ),
      );
    }
    return false;
  }

  /// Navega até uma coordenada (ex.: posto de combustível).
  Future<bool> navigateToPoint(
    double latitude,
    double longitude, {
    String? label,
    NavApp app = NavApp.google,
  }) =>
      navigate(
        address: '',
        latitude: latitude,
        longitude: longitude,
        app: app,
      );

  Future<bool> _launchFirst(List<Uri> uris) async {
    for (final uri in uris) {
      try {
        if (await canLaunchUrl(uri) &&
            await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          return true;
        }
      } catch (_) {
        // Tenta a próxima opção.
      }
    }
    return false;
  }

  Future<bool> openWhatsApp(String? phone, {String? text}) async {
    if (text != null && text.trim().isNotEmpty) {
      final encoded = Uri.encodeComponent(text);
      final url = Uri.parse('https://wa.me/?text=$encoded');
      return launchUrl(url, mode: LaunchMode.externalApplication);
    }
    final url = PhoneUtils.whatsAppUrl(phone);
    if (url == null) {
      return false;
    }
    return launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Future<bool> call(String? phone) async {
    final url = PhoneUtils.telUrl(phone);
    if (url == null) {
      return false;
    }
    return launchUrl(Uri.parse(url));
  }
}
