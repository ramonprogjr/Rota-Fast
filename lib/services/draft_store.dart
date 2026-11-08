import 'dart:convert';

import 'package:rota_max/data/repositories/settings_repository.dart';

/// Rascunho de formulário (o que o usuário digitou e ainda não salvou).
///
// TODO(integração): o pacote C traz AppState.saveDraft/loadDraft/clearDraft.
// Quando entrar, esta interface pode virar um adaptador para eles.
abstract class DraftStore {
  static const addDeliveryKey = 'draft_add_delivery';
  static const scanKey = 'draft_scan';

  Future<Map<String, dynamic>?> load(String key);
  Future<void> save(String key, Map<String, dynamic> data);
  Future<void> clear(String key);
}

/// Guarda o rascunho como JSON na tabela de configurações.
class SettingsDraftStore implements DraftStore {
  SettingsDraftStore(this._settings);

  final SettingsRepository _settings;

  @override
  Future<Map<String, dynamic>?> load(String key) async {
    try {
      final raw = await _settings.get(key);
      if (raw == null || raw.trim().isEmpty) {
        return null;
      }
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(String key, Map<String, dynamic> data) async {
    try {
      await _settings.set(key, jsonEncode(data));
    } catch (_) {
      // Rascunho é conveniência: falha ao gravar não pode travar a tela.
    }
  }

  /// O repositório não tem remoção; valor vazio conta como "sem rascunho".
  @override
  Future<void> clear(String key) async {
    try {
      await _settings.set(key, '');
    } catch (_) {}
  }
}
