import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rota_max/core/theme/app_theme.dart';
import 'package:rota_max/data/repositories/settings_repository.dart';
import 'package:rota_max/models/delivery.dart';
import 'package:rota_max/models/geo_result.dart';
import 'package:rota_max/providers/app_state.dart';
import 'package:rota_max/screens/add_delivery_screen.dart';
import 'package:rota_max/services/address_autocomplete_service.dart';
import 'package:rota_max/services/draft_store.dart';
import 'package:rota_max/services/geocoding_service.dart';

import 'helpers/test_state.dart';

class _FakeAutocomplete extends AddressAutocompleteService {
  _FakeAutocomplete([this.results = const []]) : super(apiKey: 'fake');

  final List<AddressSuggestion> results;
  final calls = <String>[];

  @override
  Future<List<AddressSuggestion>> suggest(
    String text, {
    GeoPoint? focus,
  }) async {
    calls.add(text);
    return results;
  }
}

class _NothingFound extends GeocodingService {
  _NothingFound() : super(cache: MemoryGeocodeCacheRepository(), orsApiKey: '');

  @override
  Future<List<GeoResult>> search(
    String rawQuery, {
    String? street,
    String? number,
    String? neighborhood,
    String? city,
    String? state,
    String? postalCode,
  }) async => [];
}

const _suggestion = AddressSuggestion(
  label: 'Rua Marechal Deodoro, 1500, Centro, São Bernardo do Campo, SP',
  street: 'Rua Marechal Deodoro',
  number: '1500',
  neighborhood: 'Centro',
  city: 'São Bernardo do Campo',
  state: 'SP',
  postalCode: '09710000',
  lat: -23.71,
  lng: -46.55,
);

void main() {
  Future<void> phone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> open(
    WidgetTester tester,
    AppState state, {
    AddressAutocompleteService? autocomplete,
    DraftStore? drafts,
  }) async {
    await state.load();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => AddDeliveryScreen(
                        autocomplete: autocomplete ?? _FakeAutocomplete(),
                        drafts:
                            drafts ??
                            SettingsDraftStore(MemorySettingsRepository()),
                      ),
                    ),
                  ),
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  Future<void> tapSave(WidgetTester tester) async {
    final save = find.byKey(const Key('save-delivery'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
  }

  testWidgets('mostra "Endereço incompleto" sem número ou bairro', (
    tester,
  ) async {
    await phone(tester);
    await open(tester, buildTestState());

    expect(find.text('Endereço incompleto', findRichText: true), findsNothing);
    await tester.enterText(
      find.byKey(const Key('field-address')),
      'Rua Marechal Deodoro',
    );
    await tester.pump();
    expect(find.byKey(const Key('incomplete-badge')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('field-number')), '1500');
    await tester.pump();
    expect(find.byKey(const Key('incomplete-badge')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('field-neighborhood')),
      'Centro',
    );
    await tester.pump();
    expect(find.byKey(const Key('incomplete-badge')), findsNothing);
  });

  testWidgets('endereço repetido pede confirmação e salva mesmo assim', (
    tester,
  ) async {
    await phone(tester);
    final state = buildTestState(
      deliveries: [
        Delivery(
          id: 1,
          customerName: 'Maria',
          address: 'Rua Java',
          number: '100',
          neighborhood: 'Centro',
        ),
      ],
    );
    await open(tester, state);

    await tester.enterText(find.byKey(const Key('field-address')), 'Rua Java');
    await tester.enterText(find.byKey(const Key('field-number')), '100');
    await tester.enterText(
      find.byKey(const Key('field-neighborhood')),
      'Centro',
    );
    await tapSave(tester);

    expect(find.text('Endereço repetido'), findsOneWidget);
    await tester.tap(find.byKey(const Key('duplicate-cancel')));
    await tester.pumpAndSettle();
    expect(state.items, hasLength(1));
    expect(find.byType(AddDeliveryScreen), findsOneWidget);

    await tapSave(tester);
    await tester.tap(find.text('Salvar mesmo assim'));
    await tester.pumpAndSettle();
    expect(state.items, hasLength(2));
    expect(find.byType(AddDeliveryScreen), findsNothing);
  });

  testWidgets('sugestão preenche campos e CEP vai só com dígitos', (
    tester,
  ) async {
    await phone(tester);
    final fake = _FakeAutocomplete([_suggestion]);
    final state = buildTestState();
    await open(tester, state, autocomplete: fake);

    final field = find.byKey(const Key('field-address'));
    await tester.enterText(field, 'Rua M');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(field, 'Rua Mar');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(field, 'Rua Marec');
    await tester.pump(const Duration(milliseconds: 399));
    expect(fake.calls, isEmpty, reason: 'ainda dentro do debounce');
    await tester.pump(const Duration(milliseconds: 2));
    expect(fake.calls, ['Rua Marec']);
    await tester.pump();

    await tester.tap(find.byKey(const Key('address-suggestion-0')));
    await tester.pumpAndSettle();

    String text(String key) =>
        tester.widget<TextFormField>(find.byKey(Key(key))).controller!.text;
    expect(text('field-address'), 'Rua Marechal Deodoro');
    expect(text('field-number'), '1500');
    expect(text('field-neighborhood'), 'Centro');
    expect(text('field-uf'), 'SP');
    expect(text('field-cep'), '09710-000');
    expect(find.textContaining('Ponto aproximado'), findsOneWidget);

    // Mudar o número invalida o ponto.
    await tester.enterText(find.byKey(const Key('field-number')), '1600');
    await tester.pump();
    expect(find.textContaining('Ponto aproximado'), findsNothing);
    expect(
      find.text('Endereço alterado: localize de novo no mapa.'),
      findsOneWidget,
    );

    await tester.enterText(find.byKey(const Key('field-number')), '1500');
    await tester.pump();
    await tapSave(tester);
    final saved = state.items.single;
    expect(saved.postalCode, '09710000');
    expect(saved.state, 'SP');
    expect(saved.hasCoordinates, isFalse);
  });

  testWidgets('ponto de referência vai para notes', (tester) async {
    await phone(tester);
    final state = buildTestState();
    await open(tester, state);
    await tester.enterText(find.byKey(const Key('field-address')), 'Rua Java');
    await tester.enterText(find.byKey(const Key('field-number')), '10');
    await tester.enterText(
      find.byKey(const Key('field-reference')),
      'Portão azul',
    );
    await tapSave(tester);
    expect(state.items.single.notes, 'Portão azul');
  });

  testWidgets('não encontrado oferece marcar no mapa', (tester) async {
    await phone(tester);
    final state = buildTestState(geocoder: _NothingFound());
    await open(tester, state);
    await tester.enterText(
      find.byKey(const Key('field-address')),
      'Rua Inexistente',
    );
    final locate = find.byKey(const Key('locate-delivery'));
    await tester.ensureVisible(locate);
    await tester.tap(locate);
    await tester.pumpAndSettle();

    expect(find.text('Endereço não encontrado'), findsOneWidget);
    await tester.tap(find.byKey(const Key('mark-on-map')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Toque ou arraste para marcar o local'), findsOneWidget);
    expect(find.byKey(const Key('confirm-address')), findsOneWidget);
  });

  testWidgets('rascunho é guardado ao sair e recuperado ao voltar', (
    tester,
  ) async {
    await phone(tester);
    final drafts = SettingsDraftStore(MemorySettingsRepository());
    final state = buildTestState();
    await open(tester, state, drafts: drafts);
    await tester.enterText(find.byKey(const Key('field-customer')), 'Rita');
    await tester.enterText(find.byKey(const Key('field-address')), 'Rua Java');
    await tester.pageBack();
    await tester.pumpAndSettle();

    final saved = await drafts.load(DraftStore.addDeliveryKey);
    expect(saved?['name'], 'Rita');

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.text('Rascunho recuperado'), findsOneWidget);
    expect(find.text('Rita'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('field-number')), '5');
    await tapSave(tester);
    expect(await drafts.load(DraftStore.addDeliveryKey), isNull);
  });
}
