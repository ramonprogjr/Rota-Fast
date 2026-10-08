import 'package:rota_pizza/core/constants/app_constants.dart';
import 'package:rota_pizza/core/utils/phone_utils.dart';

class ParsedDelivery {
  ParsedDelivery({
    this.customerName,
    this.orderNumber,
    this.phone,
    required this.address,
    this.number,
    this.neighborhood,
    this.city = AppConstants.defaultCity,
    this.value,
    this.rawLine = '',
  });

  final String? customerName;
  final String? orderNumber;
  final String? phone;
  final String address;
  final String? number;
  final String? neighborhood;
  final String city;
  final double? value;
  final String rawLine;

  bool get hasAddress {
    final text = address.trim();
    if (text.length < 5) {
      return false;
    }
    return AddressParser.looksLikeAddress(text);
  }
}

class AddressParser {
  static final _phoneRegex = RegExp(
    r'(?:\+?55\s*)?\(?\d{2}\)?\s*9?\d{4}[-\s]?\d{4}',
  );
  static final _orderRegex = RegExp(
    r'(?:pedido\s*)?#\s*(\d{2,8})',
    caseSensitive: false,
  );
  static final _orderLooseRegex = RegExp(
    r'(?:pedido|n[uú]mero)\s*[:\-]?\s*#?\s*(\d{2,8})',
    caseSensitive: false,
  );
  static final _valueRegex = RegExp(
    r'R\$\s*(\d{1,4}(?:[.,]\d{1,2})?)',
    caseSensitive: false,
  );
  static final _numberRegex = RegExp(
    r'(?:n[uú]mero|n[ºo°]?)\s*[:\-]?\s*(\d+[A-Za-z]?)',
    caseSensitive: false,
  );
  static final _streetNumberRegex = RegExp(
    r',\s*(\d+[A-Za-z]?)\b',
  );

  static List<ParsedDelivery> parseBatch(String text) {
    final lines = text
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && !_isHeader(line))
        .toList();
    return lines.map(parseLine).where((item) => item.hasAddress).toList();
  }

  static List<ParsedDelivery> parseTicket(String ocrText) {
    final fromLines = parseBatch(ocrText);
    if (fromLines.isNotEmpty) {
      return fromLines;
    }
    final compact = ocrText.replaceAll(RegExp(r'\s+'), ' ').trim();
    final parsed = parseLine(compact);
    return parsed.hasAddress ? [parsed] : [];
  }

  static String normalizeAddress(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[.,]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static ParsedDelivery parseLine(String raw) {
    var line = raw.trim();
    String? phone;
    String? orderNumber;
    double? value;
    String? name;
    String? number;
    var city = AppConstants.defaultCity;

    final phoneMatch = _phoneRegex.firstMatch(line);
    if (phoneMatch != null) {
      phone = PhoneUtils.toWhatsAppNumber(phoneMatch.group(0));
      line = line.replaceFirst(phoneMatch.group(0)!, ' ').trim();
    }

    final orderMatch =
        _orderRegex.firstMatch(line) ?? _orderLooseRegex.firstMatch(line);
    if (orderMatch != null) {
      orderNumber = orderMatch.group(1);
      line = line.replaceFirst(orderMatch.group(0)!, ' ').trim();
    }

    final valueMatch = _valueRegex.firstMatch(line);
    if (valueMatch != null) {
      value = _parseMoney(valueMatch.group(1)!);
      line = line.replaceFirst(valueMatch.group(0)!, ' ').trim();
    }

    line = line
        .replaceAll(
          RegExp(r'\b(entregar\s+na|entrega|cliente)\b[:\-]?',
              caseSensitive: false),
          ' ',
        )
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .replaceAll(RegExp(r'^[\s,.\-—]+|[\s,.\-—]+$'), '')
        .trim();

    city = _extractCity(line);

    final split = _splitNameAndAddress(line);
    name = split.$1;
    var address = split.$2;

    final explicitNumber = _numberRegex.firstMatch(address);
    if (explicitNumber != null) {
      number = explicitNumber.group(1);
    } else {
      final streetNumber = _streetNumberRegex.firstMatch(address);
      number = streetNumber?.group(1);
    }

    if (_looksLikeAddress(address) && !_addressLooksComplete(address)) {
      address = '$address, $city';
    }

    return ParsedDelivery(
      customerName: name,
      orderNumber: orderNumber,
      phone: phone,
      address: address,
      number: number,
      city: city,
      value: value,
      rawLine: raw,
    );
  }

  static bool _isHeader(String line) {
    final lower = line.toLowerCase();
    return lower == 'entregas' ||
        lower == 'endereços' ||
        lower == 'enderecos' ||
        lower.startsWith('rota pizza') ||
        lower.startsWith('rota food');
  }

  static (String?, String) _splitNameAndAddress(String line) {
    for (final separator in [' — ', ' – ', ' - ', ': ']) {
      final index = line.indexOf(separator);
      if (index > 1) {
        final maybeName = line.substring(0, index).trim();
        final rest = line.substring(index + separator.length).trim();
        if (_looksLikeName(maybeName) && rest.length >= 5) {
          return (maybeName, rest);
        }
      }
    }

    final comma = line.indexOf(',');
    if (comma > 1) {
      final maybeName = line.substring(0, comma).trim();
      final rest = line.substring(comma + 1).trim();
      if (_looksLikeName(maybeName) &&
          rest.length >= 8 &&
          _looksLikeAddress(rest)) {
        return (maybeName, rest);
      }
    }

    return (null, line);
  }

  static bool _looksLikeName(String value) {
    if (value.length < 2 || value.length > 48) {
      return false;
    }
    if (_looksLikeAddress(value)) {
      return false;
    }
    return RegExp(r"^[A-Za-zÀ-ÿ][A-Za-zÀ-ÿ'\s.]{1,}$").hasMatch(value);
  }

  static bool looksLikeAddress(String value) => _looksLikeAddress(value);

  static bool _looksLikeAddress(String value) {
    final lower = value.toLowerCase();
    return lower.contains('rua') ||
        lower.contains('av.') ||
        lower.contains('avenida') ||
        lower.contains('alameda') ||
        lower.contains('travessa') ||
        lower.contains('estrada') ||
        lower.contains('praça') ||
        lower.contains('praca') ||
        lower.contains('rodovia') ||
        RegExp(r'\d').hasMatch(value);
  }

  static bool _addressLooksComplete(String address) {
    final lower = address.toLowerCase();
    return lower.contains('são bernardo') ||
        lower.contains('sao bernardo') ||
        lower.contains('sbc') ||
        lower.contains('são paulo') ||
        lower.contains('sao paulo');
  }

  static String _extractCity(String line) {
    final lower = line.toLowerCase();
    if (lower.contains('sbc') ||
        lower.contains('são bernardo') ||
        lower.contains('sao bernardo')) {
      return 'São Bernardo do Campo';
    }
    if (lower.contains('santo andré') || lower.contains('santo andre')) {
      return 'Santo André';
    }
    if (lower.contains('são caetano') || lower.contains('sao caetano')) {
      return 'São Caetano do Sul';
    }
    if (lower.contains('diadema')) {
      return 'Diadema';
    }
    return AppConstants.defaultCity;
  }

  static double _parseMoney(String raw) {
    final normalized = raw.replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(normalized) ??
        double.tryParse(raw.replaceAll(',', '.')) ??
        0;
  }
}
