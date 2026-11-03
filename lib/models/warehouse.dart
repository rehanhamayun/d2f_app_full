import 'models.dart';

class WarehouseLocation {
  final String id, name, code, city, country;
  const WarehouseLocation({
    required this.id,
    required this.name,
    required this.code,
    required this.city,
    required this.country,
  });
  factory WarehouseLocation.fromJson(Map<String, dynamic> j) =>
      WarehouseLocation(
        id: j['id'],
        name: j['name'],
        code: j['code'],
        city: j['city'] ?? '',
        country: j['country'] ?? '',
      );
  String get label => '${city.isEmpty ? name : city}, $country';
}

class FreightContainer {
  final String id, code, status, method;
  final String? sealNumber, notes;
  final WarehouseLocation origin, destination;
  final int parcelCount;
  final List<Parcel> parcels;
  final List<Map<String, dynamic>> events;
  const FreightContainer({
    required this.id,
    required this.code,
    required this.status,
    required this.method,
    this.sealNumber,
    this.notes,
    required this.origin,
    required this.destination,
    required this.parcelCount,
    this.parcels = const [],
    this.events = const [],
  });
  factory FreightContainer.fromJson(Map<String, dynamic> j) => FreightContainer(
    id: j['id'],
    code: j['code'],
    status: j['status'],
    method: j['method'],
    sealNumber: j['sealNumber'],
    notes: j['notes'],
    origin: WarehouseLocation.fromJson(Map<String, dynamic>.from(j['origin'])),
    destination: WarehouseLocation.fromJson(
      Map<String, dynamic>.from(j['destination']),
    ),
    parcelCount:
        j['_count']?['parcels'] ?? (j['parcels'] as List?)?.length ?? 0,
    parcels: (j['parcels'] as List? ?? [])
        .map((p) => Parcel.fromJson(Map<String, dynamic>.from(p)))
        .toList(),
    events: (j['events'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e))
        .toList(),
  );
  String? get nextAction => (method == 'SEA'
      ? const {
          'LOADING': 'DEPARTED',
          'DEPARTED': 'ARRIVED_PORT',
          'ARRIVED_PORT': 'CUSTOMS_CLEARANCE',
          'CUSTOMS_CLEARANCE': 'CUSTOMS_CLEARED',
          'CUSTOMS_CLEARED': 'ARRIVED',
        }
      : const {'LOADING': 'DEPARTED', 'DEPARTED': 'ARRIVED'})[status];
  String get nextActionLabel => switch (nextAction) {
    'DEPARTED' => 'Confirm departure',
    'ARRIVED_PORT' => 'Confirm destination port arrival',
    'CUSTOMS_CLEARANCE' => 'Start customs clearance',
    'CUSTOMS_CLEARED' => 'Confirm customs release',
    'ARRIVED' => 'Confirm destination warehouse receipt',
    _ => 'Completed',
  };
  String get statusLabel => switch (status) {
    'DEPARTED' => 'Departed',
    'ARRIVED' => 'Received at destination warehouse',
    'ARRIVED_PORT' => 'Arrived at destination port',
    'CUSTOMS_CLEARANCE' => 'Customs clearance',
    'CUSTOMS_CLEARED' => 'Customs released',
    _ => 'Loading',
  };
  double get totalWeight => parcels.fold(0, (sum, p) => sum + p.weightKg);
}
