import 'package:flutter/material.dart';

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
  'RECEIVED',
  'PROCESSING',
  'IN_TRANSIT',
  'ARRIVED_LOME',
  'READY_FOR_PICKUP',
  'DELIVERED',
];

const Map<String, List<String>> kAllowedTransitions = {
  'RECEIVED': ['PROCESSING', 'IN_TRANSIT'],
  'PROCESSING': ['IN_TRANSIT', 'ARRIVED_LOME'],
  'IN_TRANSIT': ['ARRIVED_LOME'],
  'ARRIVED_LOME': ['READY_FOR_PICKUP'],
  'READY_FOR_PICKUP': ['DELIVERED'],
  'DELIVERED': [],
};

String statusLabel(String status) => switch (status) {
  'RECEIVED' => 'Received',
  'PROCESSING' => 'Processing',
  'IN_TRANSIT' => 'In Transit',
  'ARRIVED_LOME' => 'Arrived in Lomé',
  'READY_FOR_PICKUP' => 'Ready for Pickup',
  'DELIVERED' => 'Delivered',
  _ => status,
};

/// Compact chip labels for tight list rows.
String statusShortLabel(String status) => switch (status) {
  'RECEIVED' => 'Received',
  'PROCESSING' => 'Processing',
  'IN_TRANSIT' => 'In Transit',
  'ARRIVED_LOME' => 'Arrived',
  'READY_FOR_PICKUP' => 'Ready',
  'DELIVERED' => 'Delivered',
  _ => status,
};

/// Short operational sub-label shown under chips / list cards.
String statusSubLabel(String status) => switch (status) {
  'RECEIVED' => 'At warehouse (USA)',
  'PROCESSING' => 'Being prepared for shipment',
  'IN_TRANSIT' => 'On the way to West Africa',
  'ARRIVED_LOME' => 'Arrived at Lomé facility',
  'READY_FOR_PICKUP' => 'Ready for pickup',
  'DELIVERED' => 'Picked up / delivered',
  _ => '',
};

/// Friendly customer-safe headline for the detail header.
String statusHeadline(String status) => switch (status) {
  'RECEIVED' => 'Your parcel is registered at our warehouse.',
  'PROCESSING' => 'Your parcel is being prepared for shipment.',
  'IN_TRANSIT' => 'Your package is on the way to West Africa. Arriving soon!',
  'ARRIVED_LOME' => 'Your parcel has arrived at our Lomé facility.',
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
  final String? actorName;
  final DateTime createdAt;

  const TrackingEvent({
    required this.id,
    required this.status,
    this.note,
    this.location,
    this.actorName,
    required this.createdAt,
  });

  factory TrackingEvent.fromJson(Map<String, dynamic> j) => TrackingEvent(
    id: j['id'] as String,
    status: j['status'] as String,
    note: j['note'] as String?,
    location: j['location'] as String?,
    actorName: (j['actor'] as Map<String, dynamic>?)?['fullName'] as String?,
    createdAt: DateTime.tryParse(j['createdAt'] as String) ?? DateTime.now(),
  );
}

class Parcel {
  final String id;
  final String trackingId;
  final String customerId;
  final String recipientName;
  final String? recipientPhone;
  final String? recipientAddress;
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

  const Parcel({
    required this.id,
    required this.trackingId,
    required this.customerId,
    required this.recipientName,
    this.recipientPhone,
    this.recipientAddress,
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
  });

  factory Parcel.fromJson(Map<String, dynamic> j) => Parcel(
    id: j['id'] as String,
    trackingId: j['trackingId'] as String,
    customerId: j['customerId'] as String,
    recipientName: j['recipientName'] as String? ?? '',
    recipientPhone: j['recipientPhone'] as String?,
    recipientAddress: j['recipientAddress'] as String?,
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
  );

  /// Country flag emoji derived from the destination string.
  String get destinationFlag {
    final d = destination.toLowerCase();
    if (d.contains('togo')) return '🇹🇬';
    if (d.contains('benin')) return '🇧🇯';
    if (d.contains('burkina')) return '🇧🇫';
    if (d.contains('gabon')) return '🇬🇦';
    if (d.contains('ghana')) return '🇬🇭';
    if (d.contains('senegal')) return '🇸🇳';
    if (d.contains('nigeria')) return '🇳🇬';
    if (d.contains('usa') || d.contains('united states')) return '🇺🇸';
    return '🌍';
  }

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
];

const List<String> kDestinationOptions = [
  'Lomé, Togo',
  'Cotonou, Benin',
  'Ouagadougou, Burkina Faso',
  'Libreville, Gabon',
  'Accra, Ghana',
  'Dakar, Senegal',
  'Lagos, Nigeria',
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

const List<String> kEventLocations = [
  'Omaha, NE, USA',
  'Lomé, Togo',
  'Cotonou, Benin',
  'Ouagadougou, Burkina Faso',
  'Libreville, Gabon',
  'Accra, Ghana',
  'In Transit',
];
