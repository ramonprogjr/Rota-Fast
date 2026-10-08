class AppConstants {
  static const appName = 'Rota Food';
  static const tagline = 'Seu caminho. Suas entregas.';
  static const defaultCity = 'São Bernardo do Campo';
  static const defaultState = 'SP';
  static const defaultBaseName = 'Estabelecimento';
  static const nominatimUserAgent =
      'RotaFood/1.1 (planejador de entregas; uso pessoal)';
  static const nominatimSearchUrl =
      'https://nominatim.openstreetmap.org/search';
  static const nominatimMinInterval = Duration(milliseconds: 1100);
  static const motoSpeedKmh = 28.0;
  static const splashDuration = Duration(seconds: 2);
  static const oilIntervalKm = 1000.0;
  static const oilWarnBelowKm = 100.0;
  static const maxTicketPhotos = 5;
  static const osmTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const osmUserAgentPackage = 'com.rotapizza.rota_pizza';
}
