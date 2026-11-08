import 'package:rota_max/core/constants/app_constants.dart';
import 'package:rota_max/core/utils/haversine.dart';
import 'package:rota_max/models/geo_result.dart';
import 'package:rota_max/services/routing/distance_matrix.dart';
import 'package:rota_max/services/routing/route_plan_input.dart';

/// Matriz estimada sem dados de ruas: linha reta × [roadFactor], tempo pela
/// velocidade média. Nunca falha e não usa rede.
class HaversineMatrix implements DistanceMatrixProvider {
  const HaversineMatrix(
    this.speedKmh, {
    this.roadFactor = AppConstants.roadFactor,
  });

  final double speedKmh;
  final double roadFactor;

  /// Metros estimados entre dois pontos.
  double meters(GeoPoint a, GeoPoint b) =>
      haversineKm(a.latitude, a.longitude, b.latitude, b.longitude) *
      1000 *
      roadFactor;

  /// Segundos estimados para percorrer [meters].
  double secondsFor(double meters) {
    final speed = speedKmh > 0 ? speedKmh : AppConstants.motoSpeedKmh;
    return meters / (speed / 3.6);
  }

  TravelMatrix build(List<GeoPoint> points) {
    final n = points.length;
    final meterRows = List.generate(n, (_) => List<double?>.filled(n, 0));
    final secondRows = List.generate(n, (_) => List<double?>.filled(n, 0));
    for (var i = 0; i < n; i++) {
      for (var j = i + 1; j < n; j++) {
        final m = meters(points[i], points[j]);
        final s = secondsFor(m);
        meterRows[i][j] = m;
        meterRows[j][i] = m;
        secondRows[i][j] = s;
        secondRows[j][i] = s;
      }
    }
    return TravelMatrix(seconds: secondRows, meters: meterRows);
  }

  @override
  Future<TravelMatrix> matrix(
    List<GeoPoint> points,
    RoutingProfile profile,
  ) async =>
      build(points);
}
