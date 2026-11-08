import 'package:rota_max/models/delivery.dart';
import 'package:rota_max/models/geo_result.dart';
import 'package:rota_max/models/vehicle.dart';

/// Perfil de deslocamento usado na malha viária.
/// ORS: `driving-car` / `driving-hgv`.
enum RoutingProfile { car, hgv }

/// Van e caminhão usam o perfil de veículo pesado; o resto, carro.
RoutingProfile profileFor(VehicleType type) {
  switch (type) {
    case VehicleType.van:
    case VehicleType.truck:
      return RoutingProfile.hgv;
    case VehicleType.motorcycle:
    case VehicleType.car:
    case VehicleType.utility:
      return RoutingProfile.car;
  }
}

/// Restrição de uma parada na otimização.
///
/// - [locked]: a parada fica no mesmo índice que ocupa hoje em
///   [RoutingRequest.stops] (contado entre as paradas roteáveis).
/// - [fixedPosition]: índice (base 0) que a parada deve ocupar em
///   [RoutingResult.ordered]. Vence [locked].
class StopConstraint {
  const StopConstraint({
    required this.deliveryId,
    this.locked = false,
    this.fixedPosition,
  });

  final int deliveryId;
  final bool locked;
  final int? fixedPosition;
}

class RoutingRequest {
  const RoutingRequest({
    required this.origin,
    this.end,
    required this.stops,
    this.constraints = const {},
    required this.speedKmh,
    this.profile = RoutingProfile.car,
  });

  final GeoPoint origin;

  /// Ponto final opcional. Sem ele a rota termina na última parada.
  final GeoPoint? end;

  /// Paradas abertas na ordem ATUAL.
  final List<Delivery> stops;

  /// Restrições indexadas por id da entrega.
  final Map<int, StopConstraint> constraints;
  final double speedKmh;
  final RoutingProfile profile;
}

class RoutingResult {
  const RoutingResult({
    required this.ordered,
    required this.totalKm,
    required this.totalTime,
    required this.baselineKm,
    required this.baselineTime,
    this.unroutable = const [],
    required this.usedRoadNetwork,
    this.warning,
  });

  /// Todas as paradas roteáveis, cada uma uma única vez.
  final List<Delivery> ordered;
  final double totalKm;
  final Duration totalTime;

  /// Custo de visitar as mesmas paradas na ordem de cadastro (`createdAt`).
  final double baselineKm;
  final Duration baselineTime;

  /// Paradas sem coordenada ou inalcançáveis na malha. Não estão em [ordered].
  final List<Delivery> unroutable;
  final bool usedRoadNetwork;
  final String? warning;
}

abstract class RouteEngine {
  Future<RoutingResult> plan(RoutingRequest request);
}
