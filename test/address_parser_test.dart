import 'package:flutter_test/flutter_test.dart';
import 'package:rota_pizza/core/utils/address_parser.dart';

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
}
