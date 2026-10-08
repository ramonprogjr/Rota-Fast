class GeoResult {
  const GeoResult({
    required this.latitude,
    required this.longitude,
    this.displayName,
    this.confirmed = false,
  });

  final double latitude;
  final double longitude;
  final String? displayName;
  final bool confirmed;

  GeoResult copyWith({
    double? latitude,
    double? longitude,
    String? displayName,
    bool? confirmed,
  }) {
    return GeoResult(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      displayName: displayName ?? this.displayName,
      confirmed: confirmed ?? this.confirmed,
    );
  }
}

class GeoPoint {
  const GeoPoint(this.latitude, this.longitude);

  final double latitude;
  final double longitude;
}
