import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:rota_max/app.dart';
import 'package:rota_max/core/theme/app_theme.dart';
import 'package:rota_max/models/delivery.dart';
import 'package:rota_max/providers/app_state.dart';
import 'package:rota_max/screens/edit_route_screen.dart';
import 'package:rota_max/screens/routes_history_screen.dart';
import 'package:rota_max/screens/startup_screen.dart';

import 'helpers/test_state.dart';

List<Delivery> seed() {
  final t = DateTime(2026, 11, 8, 8);
  return [
    for (var i = 1; i <= 3; i++)
      Delivery(
        id: i,
        customerName: 'Cliente $i',
        address: 'Rua $i',
        number: '$i',
        latitude: -23.69 - i / 100,
        longitude: -46.56,
        createdAt: t.add(Duration(minutes: i)),
      ),
  ];
}

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));

  Future<void> setPhoneView(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> pumpScreen(
    WidgetTester tester,
    AppState state,
    Widget screen,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp(theme: AppTheme.dark(), home: screen),
      ),
    );
    await tester.pumpAndSettle();
  }

  String number(WidgetTester tester, int id) =>
      tester.widget<Text>(find.byKey(Key('stop-number-$id'))).data!;

  testWidgets('seta para cima troca a numeração e desfazer volta',
      (tester) async {
    await setPhoneView(tester);
    final state = buildTestState(deliveries: seed());
    await state.load();
    await pumpScreen(tester, state, const EditRouteScreen());

    expect(number(tester, 1), '1');
    expect(number(tester, 3), '3');

    await tester.tap(find.byKey(const Key('stop-up-3')));
    await tester.pumpAndSettle();
    expect(number(tester, 3), '2');
    expect(number(tester, 2), '3');
    expect(state.activeRoute!.manuallyEdited, isTrue);

    await tester.tap(find.byKey(const Key('stop-down-1')));
    await tester.pumpAndSettle();
    expect(number(tester, 1), '2');
    expect(number(tester, 3), '1');

    await tester.tap(find.byKey(const Key('edit-route-undo')));
    await tester.pumpAndSettle();
    expect(number(tester, 1), '1');
    expect(number(tester, 3), '2');

    await tester.tap(find.byKey(const Key('edit-route-undo')));
    await tester.pumpAndSettle();
    expect(number(tester, 3), '3');
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('edit-route-undo')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('arrastar pela alça muda a ordem', (tester) async {
    await setPhoneView(tester);
    final state = buildTestState(deliveries: seed());
    await state.load();
    await pumpScreen(tester, state, const EditRouteScreen());

    final handle = find.byKey(const Key('stop-drag-1'));
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump(const Duration(milliseconds: 50));
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(0, 40));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(number(tester, 1), isNot('1'));
    expect(state.pending.first.id, isNot(1));
  });

  testWidgets('cadeado e alfinete', (tester) async {
    await setPhoneView(tester);
    final state = buildTestState(deliveries: seed());
    await state.load();
    await pumpScreen(tester, state, const EditRouteScreen());

    await tester.tap(find.byKey(const Key('stop-lock-2')));
    await tester.pumpAndSettle();
    expect(state.pending[1].locked, isTrue);
    expect(find.byIcon(Icons.lock), findsOneWidget);

    await tester.tap(find.byKey(const Key('stop-pin-3')));
    await tester.pumpAndSettle();
    expect(state.pending[2].fixedPosition, 2);
    expect(find.byIcon(Icons.push_pin), findsOneWidget);

    await tester.tap(find.text('Recalcular respeitando travas'));
    await tester.pumpAndSettle();
    expect(state.message, contains('Travas respeitadas'));
    expect(state.pending.map((d) => d.id), [1, 2, 3]);
  });

  testWidgets('aba Rota abre "Editar ordem"', (tester) async {
    await setPhoneView(tester);
    final state = buildTestState(deliveries: seed());
    await state.load();
    await tester.pumpWidget(RotaMaxApp(state: state, showSplash: false));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('home-edit-order')),
      200,
    );
    await tester.tap(find.byKey(const Key('home-edit-order')));
    await tester.pumpAndSettle();
    expect(find.text('Editar ordem'), findsOneWidget);
    expect(find.byKey(const Key('stop-number-1')), findsOneWidget);

    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(find.byType(EditRouteScreen), findsNothing);
  });

  testWidgets('histórico de rotas: excluir pede confirmação', (tester) async {
    await setPhoneView(tester);
    final state = buildTestState(deliveries: seed());
    await state.load();
    await state.organizeRoute();
    await pumpScreen(tester, state, const RoutesHistoryScreen());

    expect(find.textContaining('3 parada(s)'), findsOneWidget);
    expect(find.text('ATIVA'), findsOneWidget);

    await tester.tap(find.byKey(Key('route-${state.activeRoute!.id}')));
    await tester.pumpAndSettle();
    expect(find.text('Cliente 1'), findsOneWidget);
    expect(find.text('Reabrir esta rota'), findsNothing); // já está ativa

    await tester.tap(find.text('Excluir rota'));
    await tester.pumpAndSettle();
    expect(find.text('Excluir rota?'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(state.activeRoute, isNotNull);

    await tester.tap(find.text('Excluir rota'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excluir'));
    await tester.pumpAndSettle();

    expect(state.activeRoute, isNull);
    expect(state.pending, hasLength(3)); // entregas continuam
    expect(find.text('Nenhuma rota ainda. Organize a rota na aba Rota.'),
        findsOneWidget);
  });

  testWidgets('banco que não abre mostra "Tentar de novo"', (tester) async {
    await setPhoneView(tester);
    var attempts = 0;
    await tester.pumpWidget(
      AppBootstrap(
        showSplash: false,
        open: () async {
          attempts++;
          if (attempts == 1) {
            throw Exception('database is locked');
          }
          final state = buildTestState();
          await state.load();
          return state;
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Não foi possível abrir os dados'), findsOneWidget);

    await tester.tap(find.text('Tentar de novo'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.text('Não foi possível abrir os dados'), findsNothing);
    expect(find.text('Rota Max'), findsOneWidget);
  });
}
