import 'dart:math';

/// Distância em linha reta entre dois pontos (km).
double haversineKm(
  double lat1,
  double lon1,
  double lat2,
  double lon2,
) {
  const earthRadiusKm = 6371.0;
  final dLat = _toRad(lat2 - lat1);
  final dLon = _toRad(lon2 - lon1);
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(_toRad(lat1)) * cos(_toRad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
  final c = 2 * atan2(sqrt(a), sqrt(1 - a));
  return earthRadiusKm * c;
}

Duration estimateTravelTime(double km, {double speedKmh = 28}) {
  if (km <= 0 || speedKmh <= 0) {
    return Duration.zero;
  }
  final minutes = ((km / speedKmh) * 60).ceil();
  return Duration(minutes: minutes);
}

String formatKm(double km) {
  if (km < 0.1) {
    return '${(km * 1000).round()} m';
  }
  return '${km.toStringAsFixed(1).replaceAll('.', ',')} km';
}

String formatDuration(Duration duration) {
  final total = duration.inMinutes;
  if (total < 1) {
    return '< 1 min';
  }
  if (total < 60) {
    return '~$total min';
  }
  final hours = total ~/ 60;
  final minutes = total % 60;
  if (minutes == 0) {
    return '~${hours}h';
  }
  return '~${hours}h ${minutes.toString().padLeft(2, '0')}min';
}

double _toRad(double degrees) => degrees * pi / 180;
