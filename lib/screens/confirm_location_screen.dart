import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:rota_max/core/constants/app_constants.dart';
import 'package:rota_max/core/theme/app_theme.dart';
import 'package:rota_max/models/geo_result.dart';
import 'package:rota_max/widgets/big_button.dart';

/// Mostra os candidatos no mapa e devolve o ponto escolhido ([GeoResult]
/// com `confirmed: true`).
///
/// O pino pode ser movido tocando no mapa, segurando o dedo em um ponto ou
/// arrastando o próprio pino. Sem candidatos (endereço não encontrado), o mapa
/// abre em [center] e o usuário marca o local na mão.
class ConfirmLocationScreen extends StatefulWidget {
  const ConfirmLocationScreen({
    super.key,
    required this.address,
    this.candidates = const [],
    this.center,
  });

  /// Endereço que está sendo confirmado (mostrado no topo).
  final String address;
  final List<GeoResult> candidates;

  /// Centro inicial quando não há candidatos (ex.: ponto de saída).
  final GeoPoint? center;

  /// Diálogo "não encontrei — marcar no mapa?". Devolve true para abrir o
  /// mapa sem candidatos.
  static Future<bool> askMarkOnMap(BuildContext context, {String? message}) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Endereço não encontrado'),
        content: Text(
          '${message ?? 'Não achei esse endereço.'}\n\nVocê pode marcar o local direto no mapa.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            key: const Key('mark-on-map'),
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.pin_drop),
            label: const Text('Marcar no mapa'),
          ),
        ],
      ),
    ).then((value) => value ?? false);
  }

  @override
  State<ConfirmLocationScreen> createState() => _ConfirmLocationScreenState();
}

class _ConfirmLocationScreenState extends State<ConfirmLocationScreen> {
  final _map = MapController();
  final _mapKey = GlobalKey();
  late int _selected;
  late LatLng _pin;

  /// Sem candidatos, o botão só libera depois que o usuário marcou o ponto.
  late bool _touched;
  bool _dragging = false;
  Offset _grab = Offset.zero;

  /// Quando o dedo saiu do pino. O toque/pressão longa do mapa que vem
  /// junto (ou logo depois) não deve mover o pino para o ponto do dedo.
  DateTime? _pinReleasedAt;

  bool get _manual => widget.candidates.isEmpty;

  @override
  void initState() {
    super.initState();
    _selected = 0;
    _touched = !_manual;
    if (_manual) {
      final center = widget.center;
      _pin = LatLng(
        center?.latitude ?? AppConstants.fallbackLat,
        center?.longitude ?? AppConstants.fallbackLng,
      );
    } else {
      final first = widget.candidates.first;
      _pin = LatLng(first.latitude, first.longitude);
    }
  }

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  Offset? _toMapOffset(Offset global) {
    final box = _mapKey.currentContext?.findRenderObject();
    if (box is! RenderBox) {
      return null;
    }
    return box.globalToLocal(global);
  }

  void _onMapPress(LatLng point) {
    final released = _pinReleasedAt;
    final recent =
        released != null &&
        DateTime.now().difference(released) < const Duration(milliseconds: 600);
    if (_dragging || recent) {
      return;
    }
    _setPin(point);
  }

  void _setPin(LatLng point) {
    setState(() {
      _pin = point;
      _touched = true;
    });
  }

  // O arraste do pino usa eventos brutos de ponteiro: os reconhecedores de
  // arraste do próprio mapa ganhariam a disputa de gestos de um
  // GestureDetector. Enquanto o pino é arrastado, o mapa fica parado.
  void _dragStart(PointerDownEvent event) {
    final local = _toMapOffset(event.position);
    if (local == null) {
      return;
    }
    final tip = _map.camera.latLngToScreenOffset(_pin);
    setState(() {
      _grab = tip - local;
      _dragging = true;
    });
  }

  void _dragUpdate(PointerMoveEvent event) {
    if (!_dragging) {
      return;
    }
    final local = _toMapOffset(event.position);
    if (local == null) {
      return;
    }
    _setPin(_map.camera.screenOffsetToLatLng(local + _grab));
  }

  void _dragEnd(PointerEvent _) {
    _pinReleasedAt = DateTime.now();
    if (_dragging) {
      setState(() => _dragging = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final candidates = widget.candidates;
    return Scaffold(
      appBar: AppBar(title: const Text('Confirmar local')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              widget.address,
              key: const Key('confirm-address'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              _manual ? 'Toque ou arraste para marcar o local' : 'Escolha o ponto certo. Para ajustar, toque no mapa ou arraste o pino.',
              key: const Key('confirm-hint'),
              style: TextStyle(
                color: _manual ? AppColors.warning : AppColors.muted,
                fontWeight: _manual ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: KeyedSubtree(
              key: _mapKey,
              child: FlutterMap(
                mapController: _map,
                options: MapOptions(
                  initialCenter: _pin,
                  initialZoom: _manual ? 15 : 16,
                  interactionOptions: InteractionOptions(
                    flags: _dragging
                        ? InteractiveFlag.none
                        : InteractiveFlag.all & ~InteractiveFlag.rotate,
                  ),
                  onTap: (tap, point) => _onMapPress(point),
                  onLongPress: (tap, point) => _onMapPress(point),
                ),
                children: [
                  TileLayer(
                    urlTemplate: AppConstants.osmTileUrl,
                    userAgentPackageName: AppConstants.osmUserAgentPackage,
                  ),
                  MarkerLayer(
                    markers: [
                      for (var i = 0; i < candidates.length; i++)
                        Marker(
                          point: LatLng(
                            candidates[i].latitude,
                            candidates[i].longitude,
                          ),
                          width: 36,
                          height: 36,
                          child: Icon(
                            Icons.place,
                            color: i == _selected
                                ? AppColors.primary
                                : AppColors.muted,
                            size: 36,
                          ),
                        ),
                      if (_touched)
                        Marker(
                          point: _pin,
                          width: 56,
                          height: 56,
                          alignment: Alignment.topCenter,
                          child: Listener(
                            key: const Key('draggable-pin'),
                            behavior: HitTestBehavior.opaque,
                            onPointerDown: _dragStart,
                            onPointerMove: _dragUpdate,
                            onPointerUp: _dragEnd,
                            onPointerCancel: _dragEnd,
                            child: Icon(
                              Icons.location_on,
                              color: _dragging
                                  ? AppColors.primarySoft
                                  : AppColors.text,
                              size: 56,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (candidates.length > 1)
            SizedBox(
              height: 88,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(8),
                itemCount: candidates.length,
                itemBuilder: (context, index) {
                  final item = candidates[index];
                  final selected = index == _selected;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      selected: selected,
                      label: SizedBox(
                        width: 160,
                        child: Text(
                          item.displayName ?? 'Opção ${index + 1}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      onSelected: (_) {
                        final point = LatLng(item.latitude, item.longitude);
                        setState(() {
                          _selected = index;
                          _pin = point;
                        });
                        _map.move(point, _map.camera.zoom);
                      },
                    ),
                  );
                },
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: BigButton(
              key: const Key('use-this-point'),
              label: _touched ? 'Usar este ponto' : 'Marque o local no mapa',
              icon: Icons.check,
              onPressed: !_touched
                  ? null
                  : () {
                      Navigator.of(context).pop(
                        GeoResult(
                          latitude: _pin.latitude,
                          longitude: _pin.longitude,
                          displayName: candidates.isEmpty
                              ? widget.address
                              : candidates[_selected].displayName,
                          confirmed: true,
                        ),
                      );
                    },
            ),
          ),
        ],
      ),
    );
  }
}
