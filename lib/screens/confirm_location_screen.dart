import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:rota_pizza/core/constants/app_constants.dart';
import 'package:rota_pizza/core/theme/app_theme.dart';
import 'package:rota_pizza/models/geo_result.dart';
import 'package:rota_pizza/widgets/big_button.dart';

class ConfirmLocationScreen extends StatefulWidget {
  const ConfirmLocationScreen({
    super.key,
    required this.address,
    required this.candidates,
  });

  final String address;
  final List<GeoResult> candidates;

  @override
  State<ConfirmLocationScreen> createState() => _ConfirmLocationScreenState();
}

class _ConfirmLocationScreenState extends State<ConfirmLocationScreen> {
  late int _selected;
  late LatLng _pin;

  @override
  void initState() {
    super.initState();
    _selected = 0;
    final first = widget.candidates.isEmpty
        ? const GeoResult(latitude: -23.6944, longitude: -46.5654)
        : widget.candidates.first;
    _pin = LatLng(first.latitude, first.longitude);
  }

  @override
  Widget build(BuildContext context) {
    final candidates = widget.candidates;
    return Scaffold(
      appBar: AppBar(title: const Text('Confirmar local')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              widget.address,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Escolha o ponto certo e, se precisar, toque no mapa para ajustar o pino.',
              style: TextStyle(color: AppColors.muted),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: FlutterMap(
              options: MapOptions(
                initialCenter: _pin,
                initialZoom: 16,
                onTap: (tap, point) {
                  setState(() => _pin = point);
                },
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
                              ? AppColors.accent
                              : AppColors.muted,
                          size: 36,
                        ),
                      ),
                    Marker(
                      point: _pin,
                      width: 48,
                      height: 48,
                      child: const Icon(
                        Icons.location_on,
                        color: AppColors.cream,
                        size: 48,
                      ),
                    ),
                  ],
                ),
              ],
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
                        setState(() {
                          _selected = index;
                          _pin = LatLng(item.latitude, item.longitude);
                        });
                      },
                    ),
                  );
                },
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: BigButton(
              label: 'Usar este ponto',
              icon: Icons.check,
              onPressed: () {
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
