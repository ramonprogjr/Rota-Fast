import 'package:rota_max/core/constants/app_constants.dart';
import 'package:rota_max/core/utils/phone_utils.dart';
import 'package:rota_max/models/delivery.dart';

/// Quão seguro o parser está do que leu. Baixa = falta rua ou número.
enum ParseConfidence { high, low }

class ParsedDelivery {
  ParsedDelivery({
    this.customerName,
    this.orderNumber,
    this.phone,
    required this.address,
    this.number,
    this.complement,
    this.neighborhood,
    this.city = AppConstants.defaultCity,
    this.state,
    this.postalCode,
    this.value,
    this.rawLine = '',
  });

  final String? customerName;
  final String? orderNumber;
  final String? phone;

  /// Logradouro. Quando o texto tem vírgulas, vem só a rua; senão, a linha.
  final String address;
  final String? number;
  final String? complement;
  final String? neighborhood;
  final String city;

  /// UF (ex.: SP).
  final String? state;

  /// CEP só com dígitos.
  final String? postalCode;
  final double? value;
  final String rawLine;

  bool get hasAddress {
    final text = address.trim();
    if (text.length < 5) {
      return false;
    }
    return AddressParser.looksLikeAddress('$text ${number ?? ''}');
  }

  /// Baixa quando não há número ou o texto não parece um logradouro.
  ParseConfidence get confidence {
    final hasNumber = number != null && number!.trim().isNotEmpty;
    final hasStreet =
        address.trim().length >= 5 && AddressParser.hasStreetWord(address);
    return hasNumber && hasStreet ? ParseConfidence.high : ParseConfidence.low;
  }

  bool get isLowConfidence => confidence == ParseConfidence.low;

  /// Entrega nova (ainda sem id nem coordenadas) com tudo o que foi lido.
  Delivery toDelivery() {
    return Delivery(
      orderNumber: orderNumber,
      customerName: (customerName ?? '').trim().isEmpty
          ? 'Cliente'
          : customerName!.trim(),
      phone: phone,
      address: address.trim(),
      number: number,
      complement: complement,
      neighborhood: neighborhood,
      postalCode: AddressParser.normalizePostalCode(postalCode),
      city: city,
      state: state,
      value: value,
    );
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
  static final _streetNumberRegex = RegExp(r',\s*(\d+[A-Za-z]?)\b');

  /// CEP: 00000-000 ou 00000000, com ou sem o rótulo "CEP".
  static final cepRegex = RegExp(
    r'(?:\bCEP\b\s*[:.\-]?\s*)?(?<!\d)(\d{5})-?(\d{3})(?!\d)',
    caseSensitive: false,
  );

  static const ufs = {
    'AC', 'AL', 'AP', 'AM', 'BA', 'CE', 'DF', 'ES', 'GO', 'MA', 'MT', 'MS', //
    'MG', 'PA', 'PB', 'PR', 'PE', 'PI', 'RJ', 'RN', 'RS', 'RO', 'RR', 'SC',
    'SP', 'SE', 'TO',
  };

  /// UF depois de "-", "/" ou "," (ex.: "SBC - SP", "Santo André/SP").
  static final _ufRegex = RegExp(
    r'\s*[-/,–—]\s*(AC|AL|AP|AM|BA|CE|DF|ES|GO|MA|MT|MS|MG|PA|PB|PR|PE|PI|RJ|RN|RS|RO|RR|SC|SP|SE|TO)\b(?=\s*(?:[,.;]|$))',
  );
  static final _bairroLabelRegex = RegExp(
    r'\bbairro\s*[:\-]?\s*([^,;]+)',
    caseSensitive: false,
  );
  static final _complementPrefix = RegExp(
    r'^(apto?\.?|apartamento|ap\.?|bloco|bl\.?|casa|fundos|sala|lote|lt\.?|conj(unto)?\.?|andar|km)\b',
    caseSensitive: false,
  );
  static final _numberOnly = RegExp(
    r'^(?:n[ºo°.]?\s*)?(\d{1,5}[A-Za-z]?)$',
    caseSensitive: false,
  );
  static final _trailingNumberRegex = RegExp(
    r'^(.*[A-Za-zÀ-ÿ].*?)\s+(?:n[ºo°]?\s*)?(\d{1,5}[A-Za-z]?)$',
    caseSensitive: false,
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

  /// Texto comparável: minúsculo, sem acento, sem pontuação.
  static String normalizeAddress(String value) {
    return removeAccents(value.toLowerCase())
        .replaceAll(RegExp(r'[.,;\-–—/]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String removeAccents(String value) {
    const from = 'áàâãäéèêëíìîïóòôõöúùûüçñÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑ';
    const to = 'aaaaaeeeeiiiiooooouuuucnAAAAAEEEEIIIIOOOOOUUUUCN';
    final buffer = StringBuffer();
    for (final rune in value.runes) {
      final char = String.fromCharCode(rune);
      final index = from.indexOf(char);
      buffer.write(index < 0 ? char : to[index]);
    }
    return buffer.toString();
  }

  /// CEP só com dígitos, ou null se não tiver 8 dígitos.
  static String? normalizePostalCode(String? value) {
    if (value == null) {
      return null;
    }
    final digits = value.replaceAll(RegExp(r'\D'), '');
    return digits.length == 8 ? digits : null;
  }

  /// 09750000 -> 09750-000.
  static String formatPostalCode(String? digits) {
    final clean = (digits ?? '').replaceAll(RegExp(r'\D'), '');
    if (clean.length <= 5) {
      return clean;
    }
    return '${clean.substring(0, 5)}-${clean.substring(5, clean.length.clamp(5, 8))}';
  }

  /// Assinatura dos campos que definem o local. Se mudar, o pino antigo não
  /// vale mais.
  static String locationSignature({
    required String street,
    String? number,
    String? neighborhood,
    String? city,
    String? postalCode,
  }) {
    return [
      normalizeAddress(street),
      normalizeAddress(number ?? ''),
      normalizeAddress(neighborhood ?? ''),
      normalizeAddress(city ?? ''),
      normalizePostalCode(postalCode) ?? '',
    ].join('|');
  }

  static ParsedDelivery parseLine(String raw) {
    var line = raw.trim();
    String? phone;
    String? orderNumber;
    double? value;
    String? name;
    String? number;
    String? postalCode;
    String? state;
    String? neighborhood;
    String? complement;
    var city = AppConstants.defaultCity;

    final phoneMatch = _phoneRegex.firstMatch(line);
    if (phoneMatch != null) {
      phone = PhoneUtils.toWhatsAppNumber(phoneMatch.group(0));
      line = line.replaceFirst(phoneMatch.group(0)!, ' ').trim();
    }

    final cepMatch = cepRegex.firstMatch(line);
    if (cepMatch != null) {
      postalCode = '${cepMatch.group(1)}${cepMatch.group(2)}';
      line = line.replaceFirst(cepMatch.group(0)!, ' ').trim();
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

    line = _tidy(
      line.replaceAll(
        RegExp(
          r'\b(entregar\s+na|entrega|cliente)\b[:\-]?',
          caseSensitive: false,
        ),
        ' ',
      ),
    );

    final ufMatch = _lastMatch(_ufRegex, line);
    final ufFound = ufMatch != null;
    if (ufMatch != null) {
      state = ufMatch.group(1);
      line = _tidy(line.replaceRange(ufMatch.start, ufMatch.end, ''));
    }

    final bairroMatch = _bairroLabelRegex.firstMatch(line);
    if (bairroMatch != null) {
      neighborhood = _tidy(bairroMatch.group(1)!);
      line = _tidy(line.replaceRange(bairroMatch.start, bairroMatch.end, ''));
    }

    city = _extractCity(line);
    final knownCity = city != AppConstants.defaultCity || _mentionsCity(line);
    if (state == null && knownCity) {
      state = AppConstants.defaultState;
    }

    final split = _splitNameAndAddress(line);
    name = split.$1;
    var address = split.$2;

    final structured = _splitStructured(
      address,
      lastIsCity: ufFound && !knownCity,
    );
    if (structured != null) {
      address = structured.street;
      number = structured.number;
      complement = structured.complement;
      neighborhood ??= structured.neighborhood;
      if (structured.city != null) {
        city = structured.city!;
      }
    } else {
      final explicitNumber = _numberRegex.firstMatch(address);
      if (explicitNumber != null) {
        number = explicitNumber.group(1);
      } else {
        final streetNumber = _streetNumberRegex.firstMatch(address);
        number = streetNumber?.group(1);
      }
      if (number == null) {
        final trailing = _trailingNumberRegex.firstMatch(address);
        if (trailing != null && hasStreetWord(trailing.group(1)!)) {
          address = trailing.group(1)!.trim();
          number = trailing.group(2);
        }
      }
      if (_looksLikeAddress(address) && !_addressLooksComplete(address)) {
        address = '$address, $city';
      }
    }

    return ParsedDelivery(
      customerName: name,
      orderNumber: orderNumber,
      phone: phone,
      address: address,
      number: number,
      complement: complement,
      neighborhood: neighborhood,
      city: city,
      state: state,
      postalCode: postalCode,
      value: value,
      rawLine: raw,
    );
  }

  /// "Rua X, 123, Centro, SBC" -> rua, número, bairro. Null se não der para
  /// separar com segurança.
  static _Structured? _splitStructured(
    String address, {
    bool lastIsCity = false,
  }) {
    final segments = address
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (segments.isEmpty || !hasStreetWord(segments.first)) {
      return null;
    }
    String street;
    String? number;
    var next = 1;
    final trailing = _trailingNumberRegex.firstMatch(segments.first);
    if (trailing != null) {
      street = trailing.group(1)!.trim();
      number = trailing.group(2);
    } else if (segments.length > 1 && _numberOnly.hasMatch(segments[1])) {
      street = segments.first;
      number = _numberOnly.firstMatch(segments[1])!.group(1);
      next = 2;
    } else {
      return null;
    }
    String? complement;
    String? neighborhood;
    String? city;
    var end = segments.length;
    if (lastIsCity &&
        end > next &&
        !_complementPrefix.hasMatch(segments.last)) {
      // "..., Campinas - SP": o último trecho antes da UF é a cidade.
      city = segments.last;
      end--;
    }
    for (var i = next; i < end; i++) {
      final part = segments[i];
      if (_complementPrefix.hasMatch(part)) {
        complement ??= part;
        continue;
      }
      if (_isCityText(part) || ufs.contains(part.toUpperCase())) {
        break;
      }
      if (part.length >= 3 && !RegExp(r'^\d+$').hasMatch(part)) {
        neighborhood = part;
      }
      break;
    }
    return _Structured(
      street: street,
      number: number,
      complement: complement,
      neighborhood: neighborhood,
      city: city,
    );
  }

  static RegExpMatch? _lastMatch(RegExp regex, String text) {
    RegExpMatch? last;
    for (final match in regex.allMatches(text)) {
      last = match;
    }
    return last;
  }

  static String _tidy(String value) => value
      .replaceAll(RegExp(r'\s{2,}'), ' ')
      .replaceAll(RegExp(r'\s+,'), ',')
      .replaceAll(RegExp(r',\s*,'), ',')
      .replaceAll(RegExp(r'^[\s,.\-—]+|[\s,.\-—]+$'), '')
      .trim();

  static bool _isHeader(String line) {
    final lower = line.toLowerCase();
    return lower == 'entregas' ||
        lower == 'endereços' ||
        lower == 'enderecos' ||
        lower.startsWith('rota pizza') ||
        lower.startsWith('rota food') ||
        lower.startsWith('rota max');
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

  /// Tem palavra de logradouro (rua, avenida...).
  static bool hasStreetWord(String value) {
    final lower = removeAccents(value.toLowerCase());
    return RegExp(
      r'\b(rua|r\.|av\.?|avenida|alameda|al\.|travessa|tv\.|estrada|praca|pca\.?|rodovia|rod\.|largo|viela|vila|passagem|servidao)(\s|$)',
    ).hasMatch(lower);
  }

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

  static bool _mentionsCity(String line) {
    final lower = removeAccents(line.toLowerCase());
    return lower.contains('sbc') ||
        lower.contains('sao bernardo') ||
        lower.contains('sao paulo');
  }

  static bool _isCityText(String part) {
    final lower = removeAccents(part.toLowerCase()).trim();
    return lower == 'sbc' ||
        lower.startsWith('sao bernardo') ||
        lower.startsWith('santo andre') ||
        lower.startsWith('sao caetano') ||
        lower.startsWith('sao paulo') ||
        lower == 'diadema' ||
        lower == 'maua' ||
        lower == 'sp';
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

class _Structured {
  const _Structured({
    required this.street,
    this.number,
    this.complement,
    this.neighborhood,
    this.city,
  });

  final String street;
  final String? number;
  final String? complement;
  final String? neighborhood;
  final String? city;
}
