import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rota_max/core/theme/app_theme.dart';
import 'package:rota_max/models/geo_result.dart';
import 'package:rota_max/services/address_autocomplete_service.dart';

/// Campo de endereço com sugestões (OpenRouteService).
///
/// Espera [debounce] depois da última tecla, mostra até [maxSuggestions]
/// opções logo abaixo do campo e chama [onSelected] quando o usuário escolhe
/// uma. Sem chave, sem rede ou sem resultado funciona como campo de texto
/// comum.
class AddressAutocompleteField extends StatefulWidget {
  const AddressAutocompleteField({
    super.key,
    required this.controller,
    required this.onSelected,
    this.service,
    this.focus,
    this.fieldKey,
    this.decoration = const InputDecoration(labelText: 'Rua / Avenida'),
    this.validator,
    this.debounce = const Duration(milliseconds: 400),
    this.maxSuggestions = 5,
  });

  final TextEditingController controller;
  final ValueChanged<AddressSuggestion> onSelected;

  /// Padrão: [AddressAutocompleteService.shared].
  final AddressAutocompleteService? service;

  /// Ponto para priorizar resultados próximos (ex.: ponto de saída).
  final GeoPoint? focus;

  /// Chave do TextFormField interno (útil em testes).
  final Key? fieldKey;
  final InputDecoration decoration;
  final FormFieldValidator<String>? validator;
  final Duration debounce;
  final int maxSuggestions;

  @override
  State<AddressAutocompleteField> createState() =>
      _AddressAutocompleteFieldState();
}

class _AddressAutocompleteFieldState extends State<AddressAutocompleteField> {
  Timer? _timer;
  List<AddressSuggestion> _suggestions = const [];
  bool _loading = false;
  int _request = 0;

  AddressAutocompleteService get _service =>
      widget.service ?? AddressAutocompleteService.shared;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _onChanged(String text) {
    _timer?.cancel();
    if (text.trim().length < _service.minChars) {
      _request++;
      if (_suggestions.isNotEmpty || _loading) {
        setState(() {
          _suggestions = const [];
          _loading = false;
        });
      }
      return;
    }
    _timer = Timer(widget.debounce, () => _fetch(text));
  }

  Future<void> _fetch(String text) async {
    final id = ++_request;
    if (_service.enabled) {
      setState(() => _loading = true);
    }
    final results = await _service.suggest(text, focus: widget.focus);
    if (!mounted || id != _request) {
      return;
    }
    setState(() {
      _loading = false;
      _suggestions = results.take(widget.maxSuggestions).toList();
    });
  }

  void _select(AddressSuggestion suggestion) {
    _timer?.cancel();
    _request++;
    _service.cancel();
    setState(() {
      _suggestions = const [];
      _loading = false;
    });
    widget.onSelected(suggestion);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          key: widget.fieldKey,
          controller: widget.controller,
          textCapitalization: TextCapitalization.words,
          decoration: widget.decoration.copyWith(
            suffixIcon: _loading
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : widget.decoration.suffixIcon,
          ),
          validator: widget.validator,
          onChanged: _onChanged,
        ),
        if (_suggestions.isNotEmpty)
          Card(
            margin: const EdgeInsets.only(top: 4),
            child: Column(
              children: [
                for (var i = 0; i < _suggestions.length; i++)
                  ListTile(
                    key: Key('address-suggestion-$i'),
                    dense: true,
                    leading: const Icon(Icons.place, color: AppColors.primary),
                    title: Text(
                      _suggestions[i].label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => _select(_suggestions[i]),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
