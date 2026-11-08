import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:rota_max/app.dart';
import 'package:rota_max/models/delivery.dart';
import 'helpers/test_state.dart';

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));

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
    await tester.pumpWidget(RotaMaxApp(state: state));
    expect(find.text('ROTA MAX'), findsOneWidget);
    expect(find.text('Sua rota. Seu controle. Seu resultado.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  });

  testWidgets('cadastra entrega e mostra na lista', (tester) async {
    await setPhoneView(tester);
    final state = buildTestState();
    await state.load();
    await tester.pumpWidget(RotaMaxApp(state: state, showSplash: false));
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
    await tester.pumpWidget(RotaMaxApp(state: state, showSplash: false));
    await tester.pumpAndSettle();

    // Aparece no card de próxima parada e na lista "Na rota".
    expect(find.text('Maria'), findsNWidgets(2));
    expect(find.text('PRÓXIMA PARADA'), findsOneWidget);
    await tester.tap(find.text('Entregue'));
    await tester.pumpAndSettle();

    expect(state.pending, isEmpty);
    expect(find.text('PRÓXIMA PARADA'), findsNothing);
    await tester.scrollUntilVisible(find.text('Concluídas hoje'), 200);
    expect(find.text('Concluídas hoje'), findsOneWidget);
  });

  testWidgets('não entregue pede motivo e depois dá para tentar de novo',
      (tester) async {
    await setPhoneView(tester);
    final state = buildTestState(
      deliveries: [
        Delivery(
          id: 1,
          customerName: 'Carlos',
          address: 'Rua Jurubatuba, 100',
          latitude: -23.68,
          longitude: -46.56,
        ),
      ],
    );
    await state.load();
    await tester.pumpWidget(RotaMaxApp(state: state, showSplash: false));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Não entregue'));
    await tester.pumpAndSettle();
    expect(find.text('Por que não entregou?'), findsOneWidget);

    // Sem motivo o botão fica desabilitado.
    final save = find.widgetWithText(FilledButton, 'Registrar não entrega');
    expect(tester.widget<FilledButton>(save).onPressed, isNull);

    await tester.tap(find.text('Destinatário ausente'));
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(state.pending, isEmpty);
    expect(state.problems.single.failureReason, FailureReason.recipientAbsent);
    await tester.scrollUntilVisible(find.text('Com problema'), 200);

    await state.retry(state.problems.single);
    await tester.pumpAndSettle();
    expect(state.problems, isEmpty);
    expect(state.pending.single.attempts, 1);
  });
}
