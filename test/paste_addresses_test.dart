import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rota_max/models/delivery.dart';
import 'package:rota_max/providers/app_state.dart';
import 'package:rota_max/screens/paste_addresses_screen.dart';

import 'helpers/test_state.dart';

void main() {
  testWidgets('mostra repetidas com caixa de seleção e só salva as marcadas', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = buildTestState(
      deliveries: [
        Delivery(
          id: 1,
          customerName: 'Maria',
          address: 'Rua Java',
          number: '100',
        ),
      ],
    );
    await state.load();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const PasteAddressesScreen(),
                ),
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('paste-field')),
      'João — Rua Java, 100\nPedro — Rua Nova, 5\nAna — Rua Java, 100',
    );
    await tester.pump();

    expect(find.textContaining('2 provável(is) repetida(s)'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNWidgets(2));
    expect(find.text('Localizar todos agora'), findsOneWidget);

    await tester.tap(find.byKey(const Key('paste-duplicate-0')));
    await tester.pump();
    final save = find.byKey(const Key('paste-save'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    // Maria (já existia) + Pedro + João (marcado). Ana ficou de fora.
    expect(state.items.map((item) => item.customerName).toSet(), {
      'Maria',
      'Pedro',
      'João',
    });
  });
}
