import 'package:url_launcher/url_launcher.dart';
import 'package:rota_pizza/core/utils/phone_utils.dart';

class MapsService {
  const MapsService();

  /// Abre o Google Maps pelo texto do endereço (mais preciso no Brasil
  /// do que a coordenada do OpenStreetMap).
  Future<bool> navigate({
    required String address,
    double? latitude,
    double? longitude,
  }) async {
    final encoded = Uri.encodeComponent(address);
    if (encoded.trim().isNotEmpty) {
      final nav = Uri.parse('google.navigation:q=$encoded&mode=d');
      if (await canLaunchUrl(nav)) {
        return launchUrl(nav, mode: LaunchMode.externalApplication);
      }
      final directions = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$encoded&travelmode=driving',
      );
      if (await canLaunchUrl(directions)) {
        return launchUrl(directions, mode: LaunchMode.externalApplication);
      }
    }

    if (latitude != null && longitude != null) {
      final fallback = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$latitude,$longitude&travelmode=driving',
      );
      return launchUrl(fallback, mode: LaunchMode.externalApplication);
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
