import 'package:flutter/material.dart';

import '../core/service_area.dart';

// ── Enums ────────────────────────────────────────────────────────────────────

enum UserRole { ADMIN, STAFF, CUSTOMER, DRIVER }

UserRole userRoleFrom(String? s) {
  for (final e in UserRole.values) {
    if (e.name == s) return e;
  }
  return UserRole.CUSTOMER;
}

enum ShippingMethod { AIR, SEA, ROAD }

ShippingMethod shippingMethodFrom(String? s) {
  for (final e in ShippingMethod.values) {
    if (e.name == s) return e;
  }
  return ShippingMethod.SEA;
}

extension ShippingMethodX on ShippingMethod {
  String get label => switch (this) {
    ShippingMethod.AIR => 'Air',
    ShippingMethod.SEA => 'Sea',
    ShippingMethod.ROAD => 'Road',
  };

  String get tagline => switch (this) {
    ShippingMethod.AIR => 'Fast & reliable',
    ShippingMethod.SEA => 'Cost-effective',
    ShippingMethod.ROAD => 'Wide coverage',
  };

  IconData get icon => switch (this) {
    ShippingMethod.AIR => Icons.flight_takeoff_rounded,
    ShippingMethod.SEA => Icons.directions_boat_rounded,
    ShippingMethod.ROAD => Icons.local_shipping_rounded,
  };
}

/// Canonical M1 statuses (forward-only lifecycle, enforced server-side).
const List<String> kParcelStatuses = [
  'REQUESTED',
  'RECEIVED',
  'PROCESSING',
  'IN_TRANSIT',
  'ARRIVED_LOME',
  'ARRIVED_DESTINATION',
  'READY_FOR_PICKUP',
  'RELEASED',
  'DELIVERED',
];

const Map<String, List<String>> kAllowedTransitions = {
  'REQUESTED': ['RECEIVED'],
  'RECEIVED': ['PROCESSING'],
  'PROCESSING': ['IN_TRANSIT'],
  'IN_TRANSIT': ['ARRIVED_LOME', 'ARRIVED_DESTINATION'],
  'ARRIVED_LOME': ['READY_FOR_PICKUP'],
  'ARRIVED_DESTINATION': ['READY_FOR_PICKUP'],
  'READY_FOR_PICKUP': ['RELEASED'],
  'RELEASED': ['DELIVERED'],
  'DELIVERED': [],
};

/// Physical updates that require staff to confirm they handled the parcel at
/// the selected facility.
const Set<String> kConfirmationStatuses = {
  'RECEIVED',
  'IN_TRANSIT',
  'ARRIVED_LOME',
  'ARRIVED_DESTINATION',
  'READY_FOR_PICKUP',
  'RELEASED',
  'DELIVERED',
};

/// Every physical update must name the D2F facility where it happened.
/// Processing happens at the facility too, but it does not need the separate
/// "I physically verified this parcel" acknowledgement.
const Set<String> kFacilityRequiredStatuses = {
  ...kConfirmationStatuses,
  'PROCESSING',
};

const List<String> kDeliveryProofTypes = [
  'SIGNATURE',
  'PHOTO',
  'ID_CONFIRMATION',
  'RECIPIENT_CONFIRMATION',
];

String deliveryProofLabel(String type) => switch (type) {
  'SIGNATURE' => 'Signature',
  'PHOTO' => 'Photo',
  'ID_CONFIRMATION' => 'ID confirmation',
  'RECIPIENT_CONFIRMATION' => 'Recipient confirmation',
  _ => type,
};

String statusLabel(String status) => switch (status) {
  'REQUESTED' => 'Request Submitted',
  'RECEIVED' => 'Received',
  'PROCESSING' => 'Processing',
  'IN_TRANSIT' => 'In Transit',
  'ARRIVED_LOME' => 'Arrived in Lomé',
  'ARRIVED_DESTINATION' => 'Arrived at Destination',
  'RELEASED' => 'Released',
  'READY_FOR_PICKUP' => 'Ready for Pickup',
  'DELIVERED' => 'Delivered',
  _ => status,
};

/// Compact chip labels for tight list rows.
String statusShortLabel(String status) => switch (status) {
  'REQUESTED' => 'Requested',
  'RECEIVED' => 'Received',
  'PROCESSING' => 'Processing',
  'IN_TRANSIT' => 'In Transit',
  'ARRIVED_LOME' => 'Arrived',
  'ARRIVED_DESTINATION' => 'Arrived',
  'RELEASED' => 'Released',
  'READY_FOR_PICKUP' => 'Ready',
  'DELIVERED' => 'Delivered',
  _ => status,
};

/// Short operational sub-label shown under chips / list cards.
String statusSubLabel(String status) => switch (status) {
  'REQUESTED' => 'Awaiting D2F intake confirmation',
  'RECEIVED' => 'At warehouse',
  'PROCESSING' => 'Being prepared for shipment',
  'IN_TRANSIT' => 'On the way to destination',
  'ARRIVED_LOME' => 'Arrived at Lomé facility',
  'ARRIVED_DESTINATION' => 'Arrived at destination facility',
  'RELEASED' => 'Released for collection or delivery',
  'READY_FOR_PICKUP' => 'Ready for pickup',
  'DELIVERED' => 'Picked up / delivered',
  _ => '',
};

/// Friendly customer-safe headline for the detail header.
String statusHeadline(String status) => switch (status) {
  'REQUESTED' => 'Your shipment request is awaiting D2F intake confirmation.',
  'RECEIVED' => 'Your parcel is registered at our warehouse.',
  'PROCESSING' => 'Your parcel is being prepared for shipment.',
  'IN_TRANSIT' => 'Your parcel is on the way to its destination.',
  'ARRIVED_LOME' => 'Your parcel has arrived at our Lomé facility.',
  'ARRIVED_DESTINATION' =>
    'Your parcel has arrived at its destination facility.',
  'RELEASED' => 'Your parcel has been released for collection or delivery.',
  'READY_FOR_PICKUP' => 'Your parcel is ready at the pickup location.',
  'DELIVERED' => 'Package successfully delivered to the recipient.',
  _ => '',
};

// ── Models ───────────────────────────────────────────────────────────────────

class User {
  final String id;
  final String email;
  final String fullName;
  final UserRole role;
  final String? phone;
  final String? organizationName;
  final String? locationName;

  const User({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    this.phone,
    this.organizationName,
    this.locationName,
  });

  bool get isStaff => role == UserRole.STAFF || role == UserRole.ADMIN;

  factory User.fromJson(Map<String, dynamic> j) => User(
    id: j['id'] as String,
    email: j['email'] as String,
    fullName: j['fullName'] as String,
    role: userRoleFrom(j['role'] as String?),
    phone: j['phone'] as String?,
    organizationName: j['organizationName'] as String?,
    locationName: j['locationName'] as String?,
  );
}

class Customer {
  final String id;
  final String displayName;
  final String? email;
  final String? phone;
  final String? address;
  final String? city;
  final String? country;
  final DateTime? createdAt;

  const Customer({
    required this.id,
    required this.displayName,
    this.email,
    this.phone,
    this.address,
    this.city,
    this.country,
    this.createdAt,
  });

  factory Customer.fromJson(Map<String, dynamic> j) => Customer(
    id: j['id'] as String,
    displayName: j['displayName'] as String? ?? '',
    email: j['email'] as String?,
    phone: j['phone'] as String?,
    address: j['address'] as String?,
    city: j['city'] as String?,
    country: j['country'] as String?,
    createdAt: j['createdAt'] == null
        ? null
        : DateTime.tryParse(j['createdAt'] as String),
  );
}

class TrackingEvent {
  final String id;
  final String status;
  final String? note;
  final String? location;
  final String? actorId;
  final String? actorName;
  final DateTime createdAt;

  const TrackingEvent({
    required this.id,
    required this.status,
    this.note,
    this.location,
    this.actorId,
    this.actorName,
    required this.createdAt,
  });

  factory TrackingEvent.fromJson(Map<String, dynamic> j) => TrackingEvent(
    id: j['id'] as String,
    status: j['status'] as String,
    note: j['note'] as String?,
    location: j['location'] as String?,
    actorId: j['actorId'] as String?,
    actorName: (j['actor'] as Map<String, dynamic>?)?['fullName'] as String?,
    createdAt: DateTime.tryParse(j['createdAt'] as String) ?? DateTime.now(),
  );
}

class ParcelTransfer {
  final String id;
  final String? fromLocationName;
  final String? toLocationName;
  final String? actorName;
  final String? note;
  final DateTime createdAt;

  const ParcelTransfer({
    required this.id,
    this.fromLocationName,
    this.toLocationName,
    this.actorName,
    this.note,
    required this.createdAt,
  });

  factory ParcelTransfer.fromJson(Map<String, dynamic> j) => ParcelTransfer(
    id: j['id'] as String,
    fromLocationName:
        (j['fromLocation'] as Map<String, dynamic>?)?['name'] as String?,
    toLocationName:
        (j['toLocation'] as Map<String, dynamic>?)?['name'] as String?,
    actorName: (j['actor'] as Map<String, dynamic>?)?['fullName'] as String?,
    note: j['note'] as String?,
    createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ??
        DateTime.now(),
  );
}

class Parcel {
  final String id;
  final String trackingId;
  final String customerId;
  final String recipientName;
  final String? recipientPhone;
  final String? recipientAddress;
  final String? pickupAddress;
  final String packageType;
  final double weightKg;
  final String origin;
  final String destination;
  final ShippingMethod method;
  final String? notes;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Customer? customer;
  final List<TrackingEvent> events;
  final List<ParcelTransfer> transfers;
  final String? releasedToName, releasedToIdNumber;
  final DateTime? releasedAt;
  final String? deliveredToName, deliveredToIdNumber;
  final DateTime? deliveredAt;
  final String? deliveryProofType, deliveryProofReference;
  final String? containerId, containerCode, containerStatus;
  bool get containerManaged =>
      containerId != null && containerStatus != 'ARRIVED';

  const Parcel({
    required this.id,
    required this.trackingId,
    required this.customerId,
    required this.recipientName,
    this.recipientPhone,
    this.recipientAddress,
    this.pickupAddress,
    required this.packageType,
    required this.weightKg,
    required this.origin,
    required this.destination,
    required this.method,
    this.notes,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.customer,
    this.events = const [],
    this.transfers = const [],
    this.releasedToName,
    this.releasedToIdNumber,
    this.releasedAt,
    this.deliveredToName,
    this.deliveredToIdNumber,
    this.deliveredAt,
    this.deliveryProofType,
    this.deliveryProofReference,
    this.containerId,
    this.containerCode,
    this.containerStatus,
  });

  factory Parcel.fromJson(Map<String, dynamic> j) => Parcel(
    containerId: j['containerId'] as String?,
    containerCode: j['container']?['code'] as String?,
    containerStatus: j['container']?['status'] as String?,
    id: j['id'] as String,
    trackingId: j['trackingId'] as String,
    customerId: j['customerId'] as String,
    recipientName: j['recipientName'] as String? ?? '',
    recipientPhone: j['recipientPhone'] as String?,
    recipientAddress: j['recipientAddress'] as String?,
    pickupAddress: j['pickupAddress'] as String?,
    packageType: j['packageType'] as String? ?? 'OTHER',
    weightKg: (j['weightKg'] as num?)?.toDouble() ?? 0,
    origin: j['origin'] as String? ?? '',
    destination: j['destination'] as String? ?? '',
    method: shippingMethodFrom(j['method'] as String?),
    notes: j['notes'] as String?,
    status: j['status'] as String? ?? 'RECEIVED',
    createdAt:
        DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
    updatedAt:
        DateTime.tryParse(j['updatedAt'] as String? ?? '') ?? DateTime.now(),
    customer: j['customer'] == null
        ? null
        : Customer.fromJson(j['customer'] as Map<String, dynamic>),
    events: (j['events'] as List<dynamic>? ?? [])
        .map((e) => TrackingEvent.fromJson(e as Map<String, dynamic>))
        .toList(),
    transfers: (j['transfers'] as List<dynamic>? ?? [])
        .map((e) => ParcelTransfer.fromJson(e as Map<String, dynamic>))
        .toList(),
    releasedToName: j['releasedToName'] as String?,
    releasedToIdNumber: j['releasedToIdNumber'] as String?,
    releasedAt: j['releasedAt'] == null
        ? null
        : DateTime.tryParse(j['releasedAt'] as String),
    deliveredToName: j['deliveredToName'] as String?,
    deliveredToIdNumber: j['deliveredToIdNumber'] as String?,
    deliveredAt: j['deliveredAt'] == null
        ? null
        : DateTime.tryParse(j['deliveredAt'] as String),
    deliveryProofType: j['deliveryProofType'] as String?,
    deliveryProofReference: j['deliveryProofReference'] as String?,
  );

  /// Country flag emoji derived from the destination string.
  String get destinationFlag => serviceCountryFlag(destination);

  String get packageTypeLabel => switch (packageType) {
    'BOX' => 'Box',
    'BARREL' => 'Barrel',
    'TV' => 'TV / Electronics',
    'APPLIANCE' => 'Appliance',
    'FURNITURE' => 'Furniture',
    'PALLET' => 'Pallet',
    'VEHICLE' => 'Vehicle',
    'DOCUMENTS' => 'Documents',
    'OTHER' => 'Other',
    _ => packageType,
  };
}

// ── Reference data (dropdowns) ──────────────────────────────────────────────

const List<String> kOriginOptions = [
  'Omaha, NE, USA',
  'New York, NY, USA',
  'Houston, TX, USA',
  'Atlanta, GA, USA',
  'Brussels, Belgium',
  'Paris, France',
];

const List<String> kTogoDomesticLocations = [
  'Lomé, Togo',
  'Kara, Togo',
  'Sokodé, Togo',
  'Atakpamé, Togo',
  'Kpalimé, Togo',
  'Tsévié, Togo',
  'Aného, Togo',
  'Dapaong, Togo',
  'Bassar, Togo',
  'Notsé, Togo',
];

const List<String> kDestinationOptions = [
  ...kTogoDomesticLocations,
  'Cotonou, Benin',
  'Ouagadougou, Burkina Faso',
  'Libreville, Gabon',
  'Accra, Ghana',
  'Dakar, Senegal',
  'Lagos, Nigeria',
  'Abidjan, Côte d’Ivoire',
];

/// Both directions share the same location suggestions. A route may also use
/// a staff-entered city/country; these are suggestions, not geocoded offices.
const List<String> kShippingLocationOptions = [
  ...kOriginOptions,
  ...kDestinationOptions,
];

class ShipmentRoute {
  final String origin;
  final String destination;
  final ShippingMethod method;
  const ShipmentRoute({
    required this.origin,
    required this.destination,
    this.method = ShippingMethod.AIR,
  });

  ShipmentRoute get reversed =>
      ShipmentRoute(origin: destination, destination: origin, method: method);
}

String _foldRouteText(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[àáâãäå]'), 'a')
    .replaceAll(RegExp(r'[éèêë]'), 'e')
    .replaceAll(RegExp(r'[íìîï]'), 'i')
    .replaceAll(RegExp(r'[óòôõö]'), 'o')
    .replaceAll(RegExp(r'[úùûü]'), 'u')
    .replaceAll('ç', 'c')
    .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
    .trim();

String routeCity(String value) =>
    _foldRouteText(value.split(',').first.trim());

bool sameRouteCity(String a, String b) {
  final left = routeCity(a);
  final right = routeCity(b);
  return left.isNotEmpty && left == right;
}

/// Mirrors the backend route rules so staff see a useful message before the
/// request is sent. Air/sea require different cities; same-city road delivery
/// is allowed only when pickup and delivery addresses genuinely differ.
String? validateRouteSelection({
  required String? origin,
  required String? destination,
  required ShippingMethod method,
  String? pickupAddress,
  String? recipientAddress,
}) {
  if (origin == null || destination == null) return 'Select an origin and destination.';
  if (!sameRouteCity(origin, destination)) return null;
  if (method == ShippingMethod.ROAD) {
    final pickup = pickupAddress?.trim() ?? '';
    final delivery = recipientAddress?.trim() ?? '';
    if (pickup.isEmpty || delivery.isEmpty) {
      return 'Same-city road deliveries require both a pickup address and a delivery address.';
    }
    if (_foldRouteText(pickup) == _foldRouteText(delivery)) {
      return 'Pickup and delivery addresses must be different for a same-city road delivery.';
    }
    return null;
  }
  return 'Air and sea shipments require different origin and destination cities.';
}

/// Legacy display suggestions only. Status updates use the organization's
/// facilities from the API so "In Transit" can never be recorded as a place.
const List<String> kEventLocations = [...kShippingLocationOptions];

/// Result of `/parcels/board`: rows and filter counters are read in the same
/// database snapshot, so a chip count always matches its visible list.
class ParcelBoardResult {
  final List<Parcel> parcels;
  final Map<String, int> counts;
  final int total;
  final int limit;
  final int offset;

  const ParcelBoardResult({
    required this.parcels,
    required this.counts,
    required this.total,
    required this.limit,
    required this.offset,
  });

  factory ParcelBoardResult.fromJson(Map<String, dynamic> j) =>
      ParcelBoardResult(
        parcels: (j['parcels'] as List<dynamic>? ?? [])
            .map((p) => Parcel.fromJson(p as Map<String, dynamic>))
            .toList(),
        counts: (j['counts'] as Map<dynamic, dynamic>? ?? {}).map(
          (key, value) => MapEntry(key.toString(), (value as num).toInt()),
        ),
        total: (j['total'] as num?)?.toInt() ?? 0,
        limit: (j['limit'] as num?)?.toInt() ?? 0,
        offset: (j['offset'] as num?)?.toInt() ?? 0,
      );
}
