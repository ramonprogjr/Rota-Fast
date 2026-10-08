import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rota_pizza/app.dart';
import 'package:rota_pizza/models/delivery.dart';
import 'helpers/test_state.dart';

void main() {
  Future<void> setPhoneView(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('splash mostra o nome do app', (tester) async {
    await setPhoneView(tester);
    final state = buildTestState();
    await state.load();
    await tester.pumpWidget(RotaPizzaApp(state: state));
    expect(find.text('ROTA FOOD'), findsOneWidget);
    expect(find.text('Seu caminho. Suas entregas.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  });

  testWidgets('cadastra entrega e mostra na lista', (tester) async {
    await setPhoneView(tester);
    final state = buildTestState();
    await state.load();
    await tester.pumpWidget(RotaPizzaApp(state: state, showSplash: false));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Adicionar'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('field-customer')),
      'João Silva',
    );
    await tester.enterText(
      find.byKey(const Key('field-address')),
      'Rua Marechal Deodoro, 1500',
    );
    await tester.tap(find.text('Salvar entrega'));
    await tester.pumpAndSettle();

    expect(find.text('João Silva'), findsWidgets);
    expect(state.pending, hasLength(1));
  });

  testWidgets('marca entrega como concluída', (tester) async {
    await setPhoneView(tester);
    final state = buildTestState(
      deliveries: [
        Delivery(
          id: 1,
          customerName: 'Maria',
          address: 'Av. Kennedy, 456',
          latitude: -23.67,
          longitude: -46.55,
        ),
      ],
    );
    await state.load();
    await tester.pumpWidget(RotaPizzaApp(state: state, showSplash: false));
    await tester.pumpAndSettle();

    expect(find.text('Maria'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Entregue'), 200);
    await tester.tap(find.text('Entregue'));
    await tester.pumpAndSettle();

    expect(state.pending, isEmpty);
    expect(find.text('Concluídas hoje'), findsOneWidget);
  });
}
