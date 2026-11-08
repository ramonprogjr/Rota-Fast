import 'package:flutter/material.dart';
import 'package:rota_max/models/delivery.dart';
import 'package:rota_max/providers/app_state.dart';
import 'package:rota_max/services/maps_service.dart';

/// Pergunta em qual app navegar (ajuste "perguntar sempre").
Future<NavApp?> askNavApp(BuildContext context) {
  return showModalBottomSheet<NavApp>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              'Navegar com',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          for (final app in NavApp.values)
            ListTile(
              key: Key('nav-app-${app.name}'),
              leading: Icon(
                app == NavApp.waze ? Icons.directions_car : Icons.map,
              ),
              title: Text(app.label),
              onTap: () => Navigator.of(sheetContext).pop(app),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

void _navigationFailed(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Não foi possível abrir a navegação.')),
  );
}

/// Navega até a parada respeitando o app escolhido nos ajustes.
Future<void> navigateToDelivery(
  BuildContext context,
  AppState state,
  Delivery delivery,
) async {
  final outcome = await state.navigateTo(delivery);
  if (!context.mounted) {
    return;
  }
  switch (outcome) {
    case NavOutcome.opened:
      return;
    case NavOutcome.failed:
      _navigationFailed(context);
      return;
    case NavOutcome.needsChoice:
      final app = await askNavApp(context);
      if (app == null || !context.mounted) {
        return;
      }
      final ok = await state.navigateWith(delivery, app);
      if (!ok && context.mounted) {
        _navigationFailed(context);
      }
  }
}

/// Navega até uma coordenada (ex.: posto) com o app dos ajustes.
Future<void> navigateToPoint(
  BuildContext context,
  AppState state,
  double latitude,
  double longitude, {
  String? label,
}) async {
  var app = state.preferredNavApp;
  if (app == null) {
    app = await askNavApp(context);
    if (app == null || !context.mounted) {
      return;
    }
  }
  final ok = await state.maps.navigateToPoint(
    latitude,
    longitude,
    label: label,
    app: app,
  );
  if (!ok && context.mounted) {
    _navigationFailed(context);
  }
}
