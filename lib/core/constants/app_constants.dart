class AppConstants {
  static const appName = 'Rota Max';
  static const tagline = 'Sua rota. Seu controle. Seu resultado.';
  static const defaultCity = 'São Bernardo do Campo';
  static const defaultState = 'SP';
  /// Centro do mapa quando não há ponto de saída nem candidatos.
  static const fallbackLat = -23.6944;
  static const fallbackLng = -46.5654;
  static const defaultBaseName = 'Ponto de saída';
  static const nominatimUserAgent =
      'RotaMax/1.0 (com.rotamax.app; planejador de entregas)';
  static const nominatimSearchUrl =
      'https://nominatim.openstreetmap.org/search';
  static const nominatimMinInterval = Duration(milliseconds: 1100);
  static const motoSpeedKmh = 28.0;
  static const splashDuration = Duration(seconds: 2);
  static const oilIntervalKm = 1000.0;
  static const oilWarnBelowKm = 100.0;
  static const maxTicketPhotos = 5;
  static const osmTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const osmUserAgentPackage = 'com.rotamax.app';
}
