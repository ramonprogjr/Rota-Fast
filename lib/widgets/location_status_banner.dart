import 'package:flutter/material.dart';
import 'package:rota_max/core/theme/app_theme.dart';
import 'package:rota_max/services/location_service.dart';

/// Aviso compacto sobre o GPS. Não aparece quando está tudo certo e
/// nunca bloqueia a lista: é só uma faixa com uma ação.
class LocationStatusBanner extends StatelessWidget {
  const LocationStatusBanner({
    super.key,
    required this.reading,
    this.onOpenLocationSettings,
    this.onOpenAppSettings,
    this.onRetry,
    this.busy = false,
    this.now,
  });

  final LocationReading? reading;
  final VoidCallback? onOpenLocationSettings;
  final VoidCallback? onOpenAppSettings;
  final VoidCallback? onRetry;
  final bool busy;

  /// Relógio fixo para testes.
  final DateTime? now;

  /// Texto "há X min" da última posição.
  static String ageLabel(Duration age) {
    if (age.inMinutes < 1) {
      return 'há menos de 1 min';
    }
    if (age.inMinutes < 60) {
      return 'há ${age.inMinutes} min';
    }
    return 'há ${age.inHours} h';
  }

  @override
  Widget build(BuildContext context) {
    final current = reading;
    if (current == null || current.isOk) {
      return const SizedBox.shrink();
    }
    final String title;
    String? subtitle;
    final String actionLabel;
    final VoidCallback? action;
    final IconData icon;
    switch (current.status) {
      case LocationStatus.ok:
        return const SizedBox.shrink();
      case LocationStatus.disabled:
        icon = Icons.location_disabled;
        title = 'GPS desligado';
        subtitle = 'A rota continua; só não dá para mostrar onde você está.';
        actionLabel = 'Ativar';
        action = onOpenLocationSettings;
      case LocationStatus.denied:
        icon = Icons.location_off;
        title = 'Permissão de localização negada';
        actionLabel = 'Permitir';
        action = onRetry;
      case LocationStatus.deniedForever:
        icon = Icons.location_off;
        title = 'Permissão negada';
        subtitle = 'Libere a localização nos ajustes do Android.';
        actionLabel = 'Abrir ajustes';
        action = onOpenAppSettings;
      case LocationStatus.timeout:
      case LocationStatus.unavailable:
        icon = Icons.gps_not_fixed;
        title = 'Sem sinal de GPS';
        final age = current.hasPoint ? current.age(now) : null;
        subtitle = age == null
            ? 'Ainda sem posição.'
            : 'Última posição ${ageLabel(age)}.';
        actionLabel = 'Tentar de novo';
        action = onRetry;
    }
    return Material(
      key: const Key('location-status-banner'),
      color: AppColors.warningSurface,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
        child: Row(
          children: [
            Icon(icon, color: AppColors.warning),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.warning,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 13,
                      ),
                    ),
                ],
              ),
            ),
            TextButton(
              onPressed: busy ? null : action,
              child: Text(busy ? 'Buscando...' : actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}
