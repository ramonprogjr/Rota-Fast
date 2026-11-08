import 'package:flutter_test/flutter_test.dart';
import 'package:rota_max/core/utils/address_parser.dart';

void main() {
  test('separa nome e endereço com traço', () {
    final parsed = AddressParser.parseLine(
      'João — Rua Marechal Deodoro, 1500, Centro, SBC',
    );
    expect(parsed.customerName, 'João');
    expect(parsed.address, contains('Marechal Deodoro'));
    expect(parsed.city, 'São Bernardo do Campo');
    expect(parsed.number, '1500');
  });

  test('extrai pedido, telefone e valor de texto de WhatsApp', () {
    final parsed = AddressParser.parseLine(
      'Maria Silva, Rua das Flores 123, SBC. Pedido 1024. R\$ 5,00. 11 98888-1234',
    );
    expect(parsed.customerName, 'Maria Silva');
    expect(parsed.orderNumber, '1024');
    expect(parsed.value, 5);
    expect(parsed.phone, '5511988881234');
    expect(parsed.hasAddress, isTrue);
  });

  test('lote ignora linhas vazias e cabeçalhos', () {
    const text = '''
Entregas

João — Rua X, 123
Maria — Av. Y, 456

Carlos — Rua Z, 789, Rudge Ramos
''';
    final batch = AddressParser.parseBatch(text);
    expect(batch, hasLength(3));
    expect(batch.map((item) => item.customerName).toList(), [
      'João',
      'Maria',
      'Carlos',
    ]);
  });

  test('rejeita linha sem endereço útil', () {
    expect(AddressParser.parseBatch('ok\nxy'), isEmpty);
  });

  test('lê comanda impressa em várias linhas', () {
    const ticket = '''
PEDIDO 1024
JOAO SILVA
RUA MARECHAL DEODORO 1500
CENTRO SBC
''';
    final parsed = AddressParser.parseTicket(ticket);
    expect(parsed, isNotEmpty);
    expect(parsed.first.address.toLowerCase(), contains('marechal'));
  });

  group('CEP, UF, bairro e confiança', () {
    test('extrai CEP com e sem traço', () {
      final a = AddressParser.parseLine(
        'Ana — Rua das Acácias, 45, Jardim do Mar, SBC, CEP 09750-120',
      );
      expect(a.postalCode, '09750120');
      expect(a.address, 'Rua das Acácias');
      expect(a.number, '45');
      expect(a.neighborhood, 'Jardim do Mar');
      expect(a.state, 'SP');

      final b = AddressParser.parseLine('Rua Java, 100, Centro 09721000');
      expect(b.postalCode, '09721000');
      expect(b.number, '100');
    });

    test('UF depois da cidade com traço ou barra', () {
      final a = AddressParser.parseLine(
        'Pedro - Rua Tiradentes, 300, Vila Bastos, Santo André - SP',
      );
      expect(a.state, 'SP');
      expect(a.city, 'Santo André');
      expect(a.neighborhood, 'Vila Bastos');

      final b = AddressParser.parseLine('Rua XV de Novembro, 50, Centro, Curitiba/PR');
      expect(b.state, 'PR');
      expect(b.city, 'Curitiba');
      expect(b.neighborhood, 'Centro');
    });

    test('bairro com rótulo', () {
      final parsed = AddressParser.parseLine(
        'Rua Joaquim Nabuco 77 Bairro: Nova Petrópolis',
      );
      expect(parsed.neighborhood, 'Nova Petrópolis');
      expect(parsed.number, '77');
    });

    test('bairro depois do número, sem confundir com cidade', () {
      final parsed = AddressParser.parseLine('Carlos — Rua Z, 789, Rudge Ramos');
      expect(parsed.neighborhood, 'Rudge Ramos');
      final noBairro = AddressParser.parseLine('Rua Z, 789, SBC');
      expect(noBairro.neighborhood, isNull);
      expect(noBairro.city, 'São Bernardo do Campo');
    });

    test('complemento não vira bairro', () {
      final parsed = AddressParser.parseLine(
        'Rua das Flores, 10, apto 12, Centro',
      );
      expect(parsed.complement, 'apto 12');
      expect(parsed.neighborhood, 'Centro');
    });

    test('confiança baixa sem número ou sem rua', () {
      expect(
        AddressParser.parseLine('Rua Marechal Deodoro, 1500').confidence,
        ParseConfidence.high,
      );
      expect(
        AddressParser.parseLine('Rua Marechal Deodoro, Centro').isLowConfidence,
        isTrue,
      );
      expect(
        AddressParser.parseLine('Condomínio Azul 45').isLowConfidence,
        isTrue,
      );
    });

    test('telefone não é confundido com CEP', () {
      final parsed = AddressParser.parseLine(
        'Rua A, 12, Centro. 11 98888-1234',
      );
      expect(parsed.postalCode, isNull);
      expect(parsed.phone, '5511988881234');
    });

    test('assinatura de local ignora acento e formatação', () {
      expect(
        AddressParser.locationSignature(
          street: 'Rua São José',
          number: '10',
          postalCode: '09750-000',
        ),
        AddressParser.locationSignature(
          street: 'rua sao jose',
          number: '10',
          postalCode: '09750000',
        ),
      );
      expect(AddressParser.formatPostalCode('09750000'), '09750-000');
    });
  });
}
