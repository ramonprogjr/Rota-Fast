class Pizzeria {
  Pizzeria({
    this.id = 1,
    this.name = 'Estabelecimento',
    this.address = '',
    this.city = 'São Bernardo do Campo',
    this.latitude,
    this.longitude,
  });

  final int id;
  final String name;
  final String address;
  final String city;
  final double? latitude;
  final double? longitude;

  bool get hasCoordinates => latitude != null && longitude != null;

  bool get isConfigured => address.trim().isNotEmpty && hasCoordinates;

  String get fullAddress {
    if (address.trim().isEmpty) {
      return city;
    }
    if (address.toLowerCase().contains(city.toLowerCase())) {
      return address;
    }
    return '$address, $city';
  }

  Pizzeria copyWith({
    int? id,
    String? name,
    String? address,
    String? city,
    double? latitude,
    double? longitude,
    bool clearCoordinates = false,
  }) {
    return Pizzeria(
      id: id ?? this.id,
      name: name ?? this.name,
      address: address ?? this.address,
      city: city ?? this.city,
      latitude: clearCoordinates ? null : (latitude ?? this.latitude),
      longitude: clearCoordinates ? null : (longitude ?? this.longitude),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'address': address,
      'city': city,
      'latitude': latitude,
      'longitude': longitude,
    };
  }

  factory Pizzeria.fromMap(Map<String, Object?> map) {
    return Pizzeria(
      id: (map['id'] as int?) ?? 1,
      name: (map['name'] as String?) ?? 'Estabelecimento',
      address: (map['address'] as String?) ?? '',
      city: (map['city'] as String?) ?? 'São Bernardo do Campo',
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
    );
  }
}
