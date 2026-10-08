import 'package:rota_pizza/models/delivery.dart';

class Shift {
  Shift({
    this.id,
    required this.startedAt,
    this.endedAt,
    this.gpsKm = 0,
    this.odometerStart,
    this.odometerEnd,
  });

  final int? id;
  final DateTime startedAt;
  final DateTime? endedAt;
  final double gpsKm;
  final double? odometerStart;
  final double? odometerEnd;

  bool get isOpen => endedAt == null;

  Shift copyWith({
    int? id,
    DateTime? startedAt,
    DateTime? endedAt,
    double? gpsKm,
    double? odometerStart,
    double? odometerEnd,
    bool clearEndedAt = false,
  }) {
    return Shift(
      id: id ?? this.id,
      startedAt: startedAt ?? this.startedAt,
      endedAt: clearEndedAt ? null : (endedAt ?? this.endedAt),
      gpsKm: gpsKm ?? this.gpsKm,
      odometerStart: odometerStart ?? this.odometerStart,
      odometerEnd: odometerEnd ?? this.odometerEnd,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'started_at': startedAt.toIso8601String(),
      'ended_at': endedAt?.toIso8601String(),
      'gps_km': gpsKm,
      'odometer_start': odometerStart,
      'odometer_end': odometerEnd,
    };
  }

  factory Shift.fromMap(Map<String, Object?> map) {
    return Shift(
      id: map['id'] as int?,
      startedAt: DateTime.tryParse(map['started_at'] as String? ?? '') ??
          DateTime.now(),
      endedAt: DateTime.tryParse(map['ended_at'] as String? ?? ''),
      gpsKm: (map['gps_km'] as num?)?.toDouble() ?? 0,
      odometerStart: (map['odometer_start'] as num?)?.toDouble(),
      odometerEnd: (map['odometer_end'] as num?)?.toDouble(),
    );
  }
}

class TrackPoint {
  const TrackPoint({
    this.id,
    required this.shiftId,
    required this.latitude,
    required this.longitude,
    required this.recordedAt,
  });

  final int? id;
  final int shiftId;
  final double latitude;
  final double longitude;
  final DateTime recordedAt;

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'shift_id': shiftId,
      'latitude': latitude,
      'longitude': longitude,
      'recorded_at': recordedAt.toIso8601String(),
    };
  }

  factory TrackPoint.fromMap(Map<String, Object?> map) {
    return TrackPoint(
      id: map['id'] as int?,
      shiftId: map['shift_id'] as int,
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      recordedAt:
          DateTime.tryParse(map['recorded_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

class VehicleSettings {
  const VehicleSettings({
    this.gasPriceLiter = 6.0,
    this.kmPerLiter = 30.0,
    this.odometerKm = 0,
    this.lastOilChangeKm = 0,
  });

  final double gasPriceLiter;
  final double kmPerLiter;
  final double odometerKm;
  final double lastOilChangeKm;

  VehicleSettings copyWith({
    double? gasPriceLiter,
    double? kmPerLiter,
    double? odometerKm,
    double? lastOilChangeKm,
  }) {
    return VehicleSettings(
      gasPriceLiter: gasPriceLiter ?? this.gasPriceLiter,
      kmPerLiter: kmPerLiter ?? this.kmPerLiter,
      odometerKm: odometerKm ?? this.odometerKm,
      lastOilChangeKm: lastOilChangeKm ?? this.lastOilChangeKm,
    );
  }
}

class DayReport {
  const DayReport({
    required this.shift,
    required this.points,
    required this.deliveries,
    required this.completed,
    required this.earnings,
    required this.gpsKm,
    required this.gasCost,
    required this.oilKmSinceChange,
    required this.oilKmRemaining,
  });

  final Shift shift;
  final List<TrackPoint> points;
  final int deliveries;
  final List<Delivery> completed;
  final double earnings;
  final double gpsKm;
  final double gasCost;
  final double oilKmSinceChange;
  final double oilKmRemaining;
}
