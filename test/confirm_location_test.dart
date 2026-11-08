import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rota_max/models/geo_result.dart';
import 'package:rota_max/screens/confirm_location_screen.dart';

void main() {
  Future<Future<GeoResult?> Function()> pumpScreen(
    WidgetTester tester, {
    List<GeoResult> candidates = const [],
  }) async {
    GeoResult? result;
    var popped = false;
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await Navigator.of(context).push<GeoResult>(
                MaterialPageRoute(
                  builder: (_) => ConfirmLocationScreen(
                    address: 'Rua Java, 100',
                    candidates: candidates,
                    center: const GeoPoint(-23.69, -46.56),
                  ),
                ),
              );
              popped = true;
            },
            child: const Text('abrir'),
          ),
        ),
      ),
    );
    return () async => popped ? result : null;
  }

  FilledButton useButton(WidgetTester tester) => tester.widget<FilledButton>(
    find.descendant(
      of: find.byKey(const Key('use-this-point')),
      matching: find.byWidgetPredicate((w) => w is FilledButton),
    ),
  );

  testWidgets('sem candidatos: pede para marcar e só libera depois do toque', (
    tester,
  ) async {
    final result = await pumpScreen(tester);
    await tester.pump();
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    expect(find.text('Toque ou arraste para marcar o local'), findsOneWidget);
    expect(find.text('Rua Java, 100'), findsOneWidget);
    expect(useButton(tester).onPressed, isNull);

    await tester.tapAt(const Offset(540, 900));
    // O mapa espera o tempo do toque duplo antes de confirmar o toque.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(useButton(tester).onPressed, isNotNull);
    expect(find.byKey(const Key('draggable-pin')), findsOneWidget);

    await tester.tap(find.byKey(const Key('use-this-point')));
    await tester.pumpAndSettle();
    final picked = await result();
    expect(picked, isNotNull);
    expect(picked!.confirmed, isTrue);
    expect(picked.latitude, closeTo(-23.69, 0.05));
  });

  testWidgets('arrastar o pino muda o ponto', (tester) async {
    final result = await pumpScreen(
      tester,
      candidates: const [
        GeoResult(latitude: -23.69, longitude: -46.56, displayName: 'Rua Java'),
      ],
    );
    await tester.pump();
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('draggable-pin'))),
    );
    await tester.pump();
    for (var i = 0; i < 5; i++) {
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
    }
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('use-this-point')));
    await tester.pumpAndSettle();
    final picked = await result();
    expect(picked, isNotNull);
    // Arrastou para a direita: longitude maior (mais a leste).
    expect(picked!.longitude, greaterThan(-46.56));
    expect(picked.latitude, closeTo(-23.69, 0.001));
  });
}
