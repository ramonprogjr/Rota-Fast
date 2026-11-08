import 'package:rota_max/models/geo_result.dart';
import 'package:rota_max/services/routing/route_plan_input.dart';

/// Matriz de deslocamento entre pontos. `seconds[i][j]` é o tempo de ir do
/// ponto `i` ao `j`. `null` = trecho inalcançável.
class TravelMatrix {
  TravelMatrix({required this.seconds, required this.meters});

  final List<List<double?>> seconds;
  final List<List<double?>> meters;

  int get size => seconds.length;
}

abstract class DistanceMatrixProvider {
  Future<TravelMatrix> matrix(List<GeoPoint> points, RoutingProfile profile);
}

/// Falha ao obter a matriz da malha viária. O motor captura e usa o fallback.
class RoutingException implements Exception {
  RoutingException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => statusCode == null
      ? 'RoutingException: $message'
      : 'RoutingException($statusCode): $message';
}
