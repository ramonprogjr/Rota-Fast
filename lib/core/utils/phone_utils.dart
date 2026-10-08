/// Normaliza telefone brasileiro para dígitos e link do WhatsApp.
class PhoneUtils {
  static String digitsOnly(String input) =>
      input.replaceAll(RegExp(r'\D'), '');

  /// Retorna número com DDI 55 quando possível, ou null se inválido.
  static String? toWhatsAppNumber(String? phone) {
    if (phone == null || phone.trim().isEmpty) {
      return null;
    }
    var digits = digitsOnly(phone);
    if (digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    if (digits.startsWith('55') && digits.length >= 12 && digits.length <= 13) {
      return digits;
    }
    if (digits.length == 10 || digits.length == 11) {
      return '55$digits';
    }
    if (digits.length >= 12 && digits.length <= 13) {
      return digits;
    }
    return null;
  }

  static String? whatsAppUrl(String? phone) {
    final number = toWhatsAppNumber(phone);
    if (number == null) {
      return null;
    }
    return 'https://wa.me/$number';
  }

  static String? telUrl(String? phone) {
    final digits = phone == null ? '' : digitsOnly(phone);
    if (digits.length < 8) {
      return null;
    }
    return 'tel:$digits';
  }

  static bool isValid(String? phone) => toWhatsAppNumber(phone) != null;
}
