import 'package:flutter_test/flutter_test.dart';
import 'package:rota_max/core/utils/address_parser.dart';
import 'package:rota_max/models/delivery.dart';
import 'package:rota_max/providers/app_state.dart';

import 'helpers/test_state.dart';

void main() {
  final yesterday = DateTime.now().subtract(const Duration(days: 1));

  Delivery open() => Delivery(
    id: 1,
    customerName: 'Maria',
    address: 'Rua Java',
    number: '100',
    neighborhood: 'Centro',
    postalCode: '09721000',
  );

  group('duplicidade', () {
    test('acha parada aberta com o mesmo endereço', () async {
      final state = buildTestState(deliveries: [open()]);
      await state.load();
      final found = state.findDuplicate(
        Delivery(
          customerName: 'Outro',
          address: 'rua java',
          number: '100',
          neighborhood: 'Centro',
        ),
      );
      expect(found?.id, 1);
      expect(
        state.isDuplicateAddress(
          'Rua Java, 100, Centro, São Bernardo do Campo',
        ),
        isTrue,
      );
    });

    test('compara com entregas de hoje em qualquer status', () async {
      final state = buildTestState(
        deliveries: [
          Delivery(
            id: 7,
            customerName: 'Entregue hoje',
            address: 'Av. Kennedy',
            number: '456',
            status: DeliveryStatus.delivered,
            deliveredAt: DateTime.now(),
          ),
          Delivery(
            id: 8,
            customerName: 'Entregue ontem',
            address: 'Rua Velha',
            number: '1',
            status: DeliveryStatus.delivered,
            createdAt: yesterday,
            updatedAt: yesterday,
            deliveredAt: yesterday,
          ),
        ],
      );
      await state.load();
      expect(
        state
            .findDuplicate(
              Delivery(
                customerName: 'x',
                address: 'Av. Kennedy',
                number: '456',
              ),
            )
            ?.id,
        7,
      );
      expect(
        state.findDuplicate(
          Delivery(customerName: 'x', address: 'Rua Velha', number: '1'),
        ),
        isNull,
      );
    });

    test('mesmo CEP e número contam como repetido', () async {
      final state = buildTestState(deliveries: [open()]);
      await state.load();
      final found = state.findDuplicate(
        Delivery(
          customerName: 'x',
          address: 'R. Java (perto do mercado)',
          number: '100',
          postalCode: '09721-000',
        ),
      );
      expect(found?.id, 1);
      expect(
        state.findDuplicate(
          Delivery(
            customerName: 'x',
            address: 'Outra rua',
            number: '101',
            postalCode: '09721000',
          ),
        ),
        isNull,
      );
    });

    test('ignora a própria entrega ao editar', () async {
      final state = buildTestState(deliveries: [open()]);
      await state.load();
      expect(state.findDuplicate(state.items.single), isNull);
    });

    test('saveDelivery bloqueia repetido e salva com allowDuplicate', () async {
      final state = buildTestState(deliveries: [open()]);
      await state.load();
      final copy = Delivery(
        customerName: 'Segunda',
        address: 'Rua Java',
        number: '100',
        neighborhood: 'Centro',
      );
      expect(
        () => state.saveDelivery(copy),
        throwsA(isA<DuplicateAddressException>()),
      );
      expect(state.items, hasLength(1));
      await state.saveDelivery(copy, allowDuplicate: true);
      expect(state.items, hasLength(2));
    });
  });

  group('pino x endereço', () {
    Delivery pinned() => Delivery(
      id: 3,
      customerName: 'Ana',
      address: 'Rua das Flores',
      number: '10',
      latitude: -23.7,
      longitude: -46.5,
      locationConfirmed: true,
    );

    test('mudar o endereço apaga o pino antigo', () async {
      final state = buildTestState(deliveries: [pinned()]);
      await state.load();
      final saved = await state.saveDelivery(
        state.items.single.copyWith(number: '12'),
      );
      expect(saved.hasCoordinates, isFalse);
      expect(saved.locationConfirmed, isFalse);
      expect(state.items.single.hasCoordinates, isFalse);
    });

    test('mudar só o nome mantém o pino', () async {
      final state = buildTestState(deliveries: [pinned()]);
      await state.load();
      final saved = await state.saveDelivery(
        state.items.single.copyWith(customerName: 'Ana Paula'),
      );
      expect(saved.hasCoordinates, isTrue);
      expect(saved.locationConfirmed, isTrue);
    });

    test('endereço novo com pino novo é mantido', () async {
      final state = buildTestState(deliveries: [pinned()]);
      await state.load();
      final saved = await state.saveDelivery(
        state.items.single.copyWith(
          number: '12',
          latitude: -23.71,
          longitude: -46.51,
        ),
      );
      expect(saved.latitude, -23.71);
    });
  });

  group('importação', () {
    test('devolve as repetidas em vez de pular calado', () async {
      final state = buildTestState(deliveries: [open()]);
      await state.load();
      final parsed = AddressParser.parseBatch('''
João — Rua Java, 100, Centro
Pedro — Rua Nova, 5, Centro
Pedro de novo — Rua Nova, 5, Centro
''');
      expect(parsed, hasLength(3));
      final flags = state.duplicatesFor(parsed);
      expect(flags.map((item) => item != null).toList(), [true, false, true]);

      final result = await state.importParsed(parsed);
      expect(result.saved, 1);
      expect(result.duplicates, 2);
      expect(result.duplicateItems.map((item) => item.customerName), [
        'João',
        'Pedro de novo',
      ]);

      final again = await state.importParsed(
        result.duplicateItems,
        includeDuplicates: true,
      );
      expect(again.saved, 2);
      expect(state.items, hasLength(4));
    });

    test('mantém CEP, UF, número e bairro lidos', () async {
      final state = buildTestState();
      await state.load();
      await state.importParsed(
        AddressParser.parseBatch(
          'Ana — Rua das Acácias, 45, Jardim do Mar, SBC - SP, 09750-120',
        ),
      );
      final saved = state.items.single;
      expect(saved.address, 'Rua das Acácias');
      expect(saved.number, '45');
      expect(saved.neighborhood, 'Jardim do Mar');
      expect(saved.postalCode, '09750120');
      expect(saved.state, 'SP');
    });
  });
}
