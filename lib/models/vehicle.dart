/// Tipos de veículo com valores iniciais sugeridos. Tudo pode ser
/// ajustado pelo motorista no cadastro.
enum VehicleType {
  motorcycle('Moto', kmPerLiter: 35, avgSpeedKmh: 28, oilIntervalKm: 1000),
  car('Carro', kmPerLiter: 12, avgSpeedKmh: 24, oilIntervalKm: 5000),
  utility('Utilitário', kmPerLiter: 10, avgSpeedKmh: 22, oilIntervalKm: 5000),
  van('Van', kmPerLiter: 8, avgSpeedKmh: 20, oilIntervalKm: 10000),
  truck('Caminhão leve (VUC)',
      kmPerLiter: 5, avgSpeedKmh: 18, oilIntervalKm: 10000);

  const VehicleType(
    this.label, {
    required this.kmPerLiter,
    required this.avgSpeedKmh,
    required this.oilIntervalKm,
  });

  final String label;
  final double kmPerLiter;
  final double avgSpeedKmh;
  final double oilIntervalKm;

  static VehicleType fromName(Object? value) => values.firstWhere(
        (item) => item.name == value,
        orElse: () => VehicleType.motorcycle,
      );
}

enum FuelType {
  gasoline('Gasolina'),
  ethanol('Etanol'),
  flex('Flex'),
  diesel('Diesel');

  const FuelType(this.label);

  final String label;

  static FuelType fromName(Object? value) => values.firstWhere(
        (item) => item.name == value,
        orElse: () => FuelType.gasoline,
      );
}

class Vehicle {
  Vehicle({
    this.id,
    required this.name,
    required this.type,
    this.plate,
    FuelType? fuelType,
    double? kmPerLiter,
    this.fuelPrice = 6.0,
    double? avgSpeedKmh,
    this.odometerKm = 0,
    double? oilIntervalKm,
    this.lastOilChangeKm = 0,
    this.isActive = false,
    DateTime? createdAt,
  })  : fuelType = fuelType ??
            (type == VehicleType.van || type == VehicleType.truck
                ? FuelType.diesel
                : FuelType.gasoline),
        kmPerLiter = kmPerLiter ?? type.kmPerLiter,
        avgSpeedKmh = avgSpeedKmh ?? type.avgSpeedKmh,
        oilIntervalKm = oilIntervalKm ?? type.oilIntervalKm,
        createdAt = createdAt ?? DateTime.now();

  /// Veículo usado quando ainda não há nenhum cadastrado.
  factory Vehicle.fallback() => Vehicle(
        name: 'Minha moto',
        type: VehicleType.motorcycle,
        isActive: true,
      );

  final int? id;
  final String name;
  final VehicleType type;
  final String? plate;
  final FuelType fuelType;
  final double kmPerLiter;
  final double fuelPrice;
  final double avgSpeedKmh;
  final double odometerKm;
  final double oilIntervalKm;
  final double lastOilChangeKm;
  final bool isActive;
  final DateTime createdAt;

  /// Km rodados desde a última troca de óleo.
  double get kmSinceOil {
    final value = odometerKm - lastOilChangeKm;
    return value < 0 ? 0 : value;
  }

  double get oilRemainingKm {
    final value = oilIntervalKm - kmSinceOil;
    return value < 0 ? 0 : value;
  }

  /// Progresso até a próxima troca (0 a 1).
  double get oilProgress =>
      oilIntervalKm <= 0 ? 0 : (kmSinceOil / oilIntervalKm).clamp(0.0, 1.0);

  /// Avisa quando faltam 10% do intervalo ou menos.
  bool get oilWarning =>
      oilIntervalKm > 0 && oilRemainingKm <= oilIntervalKm * 0.1;

  /// Custo de combustível de um trecho.
  double fuelCost(double km) =>
      km <= 0 || kmPerLiter <= 0 ? 0 : km / kmPerLiter * fuelPrice;

  Vehicle copyWith({
    int? id,
    String? name,
    VehicleType? type,
    String? plate,
    FuelType? fuelType,
    double? kmPerLiter,
    double? fuelPrice,
    double? avgSpeedKmh,
    double? odometerKm,
    double? oilIntervalKm,
    double? lastOilChangeKm,
    bool? isActive,
  }) {
    return Vehicle(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      plate: plate ?? this.plate,
      fuelType: fuelType ?? this.fuelType,
      kmPerLiter: kmPerLiter ?? this.kmPerLiter,
      fuelPrice: fuelPrice ?? this.fuelPrice,
      avgSpeedKmh: avgSpeedKmh ?? this.avgSpeedKmh,
      odometerKm: odometerKm ?? this.odometerKm,
      oilIntervalKm: oilIntervalKm ?? this.oilIntervalKm,
      lastOilChangeKm: lastOilChangeKm ?? this.lastOilChangeKm,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'type': type.name,
        'plate': plate,
        'fuel_type': fuelType.name,
        'km_per_liter': kmPerLiter,
        'fuel_price': fuelPrice,
        'avg_speed_kmh': avgSpeedKmh,
        'odometer_km': odometerKm,
        'oil_interval_km': oilIntervalKm,
        'last_oil_change_km': lastOilChangeKm,
        'is_active': isActive ? 1 : 0,
        'created_at': createdAt.toIso8601String(),
      };

  factory Vehicle.fromMap(Map<String, Object?> map) => Vehicle(
        id: map['id'] as int?,
        name: (map['name'] as String?) ?? 'Veículo',
        type: VehicleType.fromName(map['type']),
        plate: map['plate'] as String?,
        fuelType: FuelType.fromName(map['fuel_type']),
        kmPerLiter: (map['km_per_liter'] as num?)?.toDouble(),
        fuelPrice: (map['fuel_price'] as num?)?.toDouble() ?? 6.0,
        avgSpeedKmh: (map['avg_speed_kmh'] as num?)?.toDouble(),
        odometerKm: (map['odometer_km'] as num?)?.toDouble() ?? 0,
        oilIntervalKm: (map['oil_interval_km'] as num?)?.toDouble(),
        lastOilChangeKm: (map['last_oil_change_km'] as num?)?.toDouble() ?? 0,
        isActive: (map['is_active'] as int?) == 1,
        createdAt: DateTime.tryParse(map['created_at'] as String? ?? ''),
      );
}

class OilChange {
  const OilChange({
    this.id,
    required this.vehicleId,
    required this.odometerKm,
    required this.changedAt,
    this.note,
  });

  final int? id;
  final int vehicleId;
  final double odometerKm;
  final DateTime changedAt;
  final String? note;

  Map<String, Object?> toMap() => {
        'id': id,
        'vehicle_id': vehicleId,
        'odometer_km': odometerKm,
        'changed_at': changedAt.toIso8601String(),
        'note': note,
      };

  factory OilChange.fromMap(Map<String, Object?> map) => OilChange(
        id: map['id'] as int?,
        vehicleId: map['vehicle_id'] as int,
        odometerKm: (map['odometer_km'] as num).toDouble(),
        changedAt: DateTime.tryParse(map['changed_at'] as String? ?? '') ??
            DateTime.now(),
        note: map['note'] as String?,
      );
}
