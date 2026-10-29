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

/// How the customer's goods reach D2F. PICKUP = our staff collects them from
/// the customer's address at the scheduled time; DROP_OFF = the customer
/// brings them to the D2F warehouse.
enum DeliveryMode { PICKUP, DROP_OFF }

DeliveryMode deliveryModeFrom(String? s) =>
    s == 'PICKUP' ? DeliveryMode.PICKUP : DeliveryMode.DROP_OFF;

extension DeliveryModeX on DeliveryMode {
  String get apiName => name; // PICKUP | DROP_OFF

  String get label => switch (this) {
    DeliveryMode.PICKUP => 'D2F pickup',
    DeliveryMode.DROP_OFF => 'Drop off at warehouse',
  };

  String get shortLabel => switch (this) {
    DeliveryMode.PICKUP => 'Pickup',
    DeliveryMode.DROP_OFF => 'Drop-off',
  };

  String get tagline => switch (this) {
    DeliveryMode.PICKUP => 'Our team comes to collect your items',
    DeliveryMode.DROP_OFF => 'Bring your items to our warehouse',
  };

  IconData get icon => switch (this) {
    DeliveryMode.PICKUP => Icons.local_shipping_outlined,
    DeliveryMode.DROP_OFF => Icons.storefront_outlined,
  };
}

extension ShippingMethodX on ShippingMethod {
  String get label => switch (this) {
    ShippingMethod.AIR => 'Air Cargo',
    ShippingMethod.SEA => 'Sea',
    ShippingMethod.ROAD => 'Road',
  };

  String get tagline => switch (this) {
    ShippingMethod.AIR => 'Fast & reliable',
    ShippingMethod.SEA => 'Cost-effective',
    ShippingMethod.ROAD => 'Door-to-door coverage',
  };

  IconData get icon => switch (this) {
    ShippingMethod.AIR => Icons.flight_takeoff_rounded,
    ShippingMethod.SEA => Icons.directions_boat_rounded,
    ShippingMethod.ROAD => Icons.local_shipping_rounded,
  };
}

/// Canonical M1 statuses (forward-only lifecycle, enforced server-side).
/// Pickup requests move through two extra stages before warehouse intake.
const List<String> kParcelStatuses = [
  'REQUESTED',
  'PICKUP_SCHEDULED',
  'PICKED_UP',
  'RECEIVED',
  'PROCESSING',
  'IN_TRANSIT',
  'ARRIVED_LOME',
  'ARRIVED_DESTINATION',
  'READY_FOR_PICKUP',
  'OUT_FOR_DELIVERY',
  'RELEASED',
  'DELIVERED',
];

const Map<String, List<String>> kAllowedTransitions = {
  'REQUESTED': ['RECEIVED', 'PICKUP_SCHEDULED'],
  'PICKUP_SCHEDULED': ['PICKED_UP'],
  'PICKED_UP': ['RECEIVED'],
  'RECEIVED': ['PROCESSING'],
  'PROCESSING': ['IN_TRANSIT'],
  'IN_TRANSIT': ['ARRIVED_LOME', 'ARRIVED_DESTINATION'],
  'ARRIVED_LOME': ['READY_FOR_PICKUP', 'OUT_FOR_DELIVERY'],
  'ARRIVED_DESTINATION': ['READY_FOR_PICKUP', 'OUT_FOR_DELIVERY'],
  'READY_FOR_PICKUP': ['DELIVERED', 'OUT_FOR_DELIVERY', 'RELEASED'],
  'OUT_FOR_DELIVERY': ['DELIVERED'],
  'RELEASED': ['DELIVERED'],
  'DELIVERED': [],
};

/// Stages that only exist when D2F collects the goods. A drop-off shipment
/// goes straight from REQUESTED to RECEIVED at the warehouse.
const Set<String> kPickupOnlyStatuses = {'PICKUP_SCHEDULED', 'PICKED_UP'};

/// Mode-aware view of the transition map, mirroring the server rule.
List<String> allowedStatusesFor(Parcel parcel) {
  if (parcel.serviceType == 'AIR_TRAVELLER') return const [];
  if (parcel.deliveryMode == DeliveryMode.PICKUP &&
      parcel.status == 'REQUESTED')
    return const ['PICKUP_SCHEDULED'];
  final base = kAllowedTransitions[parcel.status] ?? const [];
  return base
      .where(
        (s) =>
            parcel.deliveryMode == DeliveryMode.PICKUP ||
            !kPickupOnlyStatuses.contains(s),
      )
      .toList();
}

/// Intake, appointments and driver handovers use their dedicated custody screens.
List<String> staffStatusOptionsFor(Parcel parcel) {
  if (parcel.status == 'OUT_FOR_DELIVERY') return const [];
  return allowedStatusesFor(parcel)
      .where(
        (s) =>
            ![
              'PICKUP_SCHEDULED',
              'PICKED_UP',
              'RECEIVED',
              'OUT_FOR_DELIVERY',
              'RELEASED',
            ].contains(s) &&
            (parcel.warehouseReceived ||
                !['PROCESSING', 'IN_TRANSIT'].contains(s)),
      )
      .toList();
}

/// Physical updates that require staff to confirm they handled the parcel at
/// the selected facility.
const Set<String> kConfirmationStatuses = {
  'RECEIVED',
  'IN_TRANSIT',
  'ARRIVED_LOME',
  'ARRIVED_DESTINATION',
  'READY_FOR_PICKUP',
  'OUT_FOR_DELIVERY',
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
  'UNDER_REVIEW' => 'Under D2F Review',
  'TRAVELLER_PROPOSED' => 'Traveller Review Pending',
  'TRAVELLER_ACCEPTED' => 'Traveller Accepted',
  'TRAVELLER_ASSIGNED' => 'Traveller Confirmed',
  'PAYMENT_CONFIRMED' => 'Payment Confirmed',
  'DOMESTIC_IN_TRANSIT' => 'Domestic Shipping in Transit',
  'RECEIVED_BY_D2F' => 'Received by D2F',
  'HANDOVER_AUTHORIZED' => 'Collection Authorized',
  'HANDED_TO_TRAVELLER' => 'Collected by Traveller',
  'TRAVELLER_DEPARTED' => 'Traveller Departed',
  'REJECTED' => 'Contents Rejected',
  'REQUESTED' => 'Request Submitted',
  'PICKUP_SCHEDULED' => 'Pickup Scheduled',
  'PICKED_UP' => 'Pickup Confirmed',
  'RECEIVED' => 'Received at Warehouse',
  'PROCESSING' => 'Processing',
  'IN_TRANSIT' => 'In Transit',
  'ARRIVED_LOME' => 'Arrived in Lomé',
  'ARRIVED_DESTINATION' => 'Arrived at Destination',
  'RELEASED' => 'Released',
  'READY_FOR_PICKUP' => 'Ready for Pickup',
  'OUT_FOR_DELIVERY' => 'Out for Delivery',
  'DELIVERED' => 'Delivered',
  _ => status,
};

/// Compact chip labels for tight list rows.
String statusShortLabel(String status) => switch (status) {
  'REQUESTED' => 'Requested',
  'PICKUP_SCHEDULED' => 'Scheduled',
  'PICKED_UP' => 'Pickup Confirmed',
  'RECEIVED' => 'Received at Warehouse',
  'PROCESSING' => 'Processing',
  'IN_TRANSIT' => 'In Transit',
  'ARRIVED_LOME' => 'Arrived',
  'ARRIVED_DESTINATION' => 'Arrived',
  'RELEASED' => 'Released',
  'READY_FOR_PICKUP' => 'Ready',
  'OUT_FOR_DELIVERY' => 'Out for Delivery',
  'DELIVERED' => 'Delivered',
  _ => status,
};

/// Short operational sub-label shown under chips / list cards.
String statusSubLabel(String status) => switch (status) {
  'REQUESTED' => 'Awaiting D2F intake confirmation',
  'PICKUP_SCHEDULED' => 'Collection confirmed with the customer',
  'PICKED_UP' => 'Collected, arriving at the warehouse',
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
  'OUT_FOR_DELIVERY' => 'Your parcel is with the assigned delivery driver. Delivery is confirmed after the actual recipient handover.',
  'REQUESTED' => 'Your shipment request is awaiting D2F confirmation.',
  'PICKUP_SCHEDULED' =>
    'A D2F team member will collect your items at the agreed time.',
  'PICKED_UP' => 'Your items are collected and on their way to our warehouse.',
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
    createdAt:
        DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
  );
}

/// One thing the customer is sending, itemized under a shipment request.
class ParcelItem {
  final String id;
  final String name;
  final String? details;
  final int quantity;
  final double? weightKg;
  final int position;
  final String type; // BOX | SUITCASE | BARREL | …, see kParcelItemTypes
  final double? lengthCm;
  final double? widthCm;
  final double? heightCm;
  final String? packageCode; // allocated once the goods enter D2F custody
  final DateTime? collectedAt; // observed by staff at a pickup collection
  final String? notCollectedReason; // recorded when a package was not on hand

  const ParcelItem({
    required this.id,
    required this.name,
    this.details,
    required this.quantity,
    this.weightKg,
    required this.position,
    this.type = 'BOX',
    this.lengthCm,
    this.widthCm,
    this.heightCm,
    this.packageCode,
    this.collectedAt,
    this.notCollectedReason,
  });

  factory ParcelItem.fromJson(Map<String, dynamic> j) => ParcelItem(
    id: j['id'] as String,
    name: j['name'] as String? ?? '',
    details: j['details'] as String?,
    quantity: (j['quantity'] as num?)?.toInt() ?? 1,
    weightKg: (j['weightKg'] as num?)?.toDouble(),
    position: (j['position'] as num?)?.toInt() ?? 0,
    type: j['type'] as String? ?? 'BOX',
    lengthCm: (j['lengthCm'] as num?)?.toDouble(),
    widthCm: (j['widthCm'] as num?)?.toDouble(),
    heightCm: (j['heightCm'] as num?)?.toDouble(),
    packageCode: j['packageCode'] as String?,
    collectedAt: j['collectedAt'] == null
        ? null
        : DateTime.tryParse(j['collectedAt'] as String),
    notCollectedReason: j['notCollectedReason'] as String?,
  );

  Map<String, dynamic> toCreateJson() => {
    'name': name,
    if (details != null && details!.isNotEmpty) 'details': details,
    'quantity': quantity,
    if (weightKg != null) 'weightKg': weightKg,
    'type': type,
    if (lengthCm != null && widthCm != null && heightCm != null) ...{
      'lengthCm': lengthCm,
      'widthCm': widthCm,
      'heightCm': heightCm,
    },
  };

  String get typeLabel => parcelItemTypeLabel(type);

  /// True once the pickup crew recorded this package as not on hand.
  bool get missed => notCollectedReason != null && collectedAt == null;

  /// "Box 2 of 6" style display name; falls back to the type label.
  String displayName(int itemCount) =>
      '$typeLabel ${position + 1} of $itemCount';
}

/// Metadata of a photo of the goods attached to the shipment. Image bytes are
/// served separately from the API so lists stay light.
class ParcelImageMeta {
  final String id;
  final String fileName;
  final String contentType;
  final int sizeBytes;
  final DateTime? createdAt;
  final String? itemId; // set when the photo documents one declared package

  const ParcelImageMeta({
    required this.id,
    required this.fileName,
    required this.contentType,
    required this.sizeBytes,
    this.createdAt,
    this.itemId,
  });

  factory ParcelImageMeta.fromJson(Map<String, dynamic> j) => ParcelImageMeta(
    id: j['id'] as String,
    fileName: j['fileName'] as String? ?? 'photo',
    contentType: j['contentType'] as String? ?? 'image/jpeg',
    sizeBytes: (j['sizeBytes'] as num?)?.toInt() ?? 0,
    createdAt: j['createdAt'] == null
        ? null
        : DateTime.tryParse(j['createdAt'] as String),
    itemId: j['itemId'] as String?,
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
  final String serviceType;
  final String? connectBookingId;
  final String? awbNumber, airline, flightNumber;
  final String status;
  final DeliveryMode deliveryMode;
  final DateTime? pickupScheduledAt;
  final DateTime? pickupPreferredAt, pickupConfirmedAt, warehouseReceivedAt;
  final String? pickupDriverId, pickupTargetLocationId, warehouseReceivedById;
  final String? locationId;
  bool get warehouseReceived => warehouseReceivedAt != null;
  final DateTime? restrictionsAcknowledgedAt;
  final List<ParcelItem> items;
  final List<ParcelImageMeta> images;
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

  /// Total declared pieces across the itemized goods list.
  int get totalPieces =>
      items.isEmpty ? 0 : items.fold(0, (sum, item) => sum + item.quantity);

  /// Packages the pickup crew recorded as not on hand.
  List<ParcelItem> get missedItems =>
      items.where((item) => item.missed).toList();

  /// True when a collection observed fewer packages than were declared.
  bool get hasCollectionDiscrepancy =>
      items.isNotEmpty && missedItems.isNotEmpty;

  /// Photos documenting one declared package ([itemId]) or the shipment.
  List<ParcelImageMeta> photosFor(String? itemId) =>
      images.where((image) => image.itemId == itemId).toList();

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
    this.serviceType = 'SEA',
    this.connectBookingId,
    this.awbNumber,
    this.airline,
    this.flightNumber,
    required this.status,
    this.deliveryMode = DeliveryMode.DROP_OFF,
    this.pickupScheduledAt,
    this.pickupPreferredAt,
    this.pickupConfirmedAt,
    this.warehouseReceivedAt,
    this.locationId,
    this.pickupDriverId,
    this.pickupTargetLocationId,
    this.warehouseReceivedById,
    this.restrictionsAcknowledgedAt,
    this.items = const [],
    this.images = const [],
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
    serviceType:
        j['serviceType'] as String? ??
        (j['method'] == 'AIR' ? 'AIR_CARGO' : j['method'] as String? ?? 'SEA'),
    connectBookingId: j['connectBooking']?['id'] as String?,
    awbNumber: j['awbNumber'] as String?,
    airline: j['airline'] as String?,
    flightNumber: j['flightNumber'] as String?,
    notes: j['notes'] as String?,
    status: j['status'] as String? ?? 'RECEIVED',
    deliveryMode: deliveryModeFrom(j['deliveryMode'] as String?),
    pickupScheduledAt: j['pickupScheduledAt'] == null
        ? null
        : DateTime.tryParse(j['pickupScheduledAt'] as String),
    pickupPreferredAt: DateTime.tryParse(
      j['pickupPreferredAt'] as String? ?? '',
    ),
    pickupConfirmedAt: DateTime.tryParse(
      j['pickupConfirmedAt'] as String? ?? '',
    ),
    warehouseReceivedAt: DateTime.tryParse(
      j['warehouseReceivedAt'] as String? ?? '',
    ),
    locationId: j['locationId'] as String?,
    pickupDriverId: j['pickupDriverId'] as String?,
    pickupTargetLocationId: j['pickupTargetLocationId'] as String?,
    warehouseReceivedById: j['warehouseReceivedById'] as String?,
    restrictionsAcknowledgedAt: j['restrictionsAcknowledgedAt'] == null
        ? null
        : DateTime.tryParse(j['restrictionsAcknowledgedAt'] as String),
    items: (j['items'] as List<dynamic>? ?? [])
        .map((e) => ParcelItem.fromJson(e as Map<String, dynamic>))
        .toList(),
    images: (j['images'] as List<dynamic>? ?? [])
        .map((e) => ParcelImageMeta.fromJson(e as Map<String, dynamic>))
        .toList(),
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
    'SUITCASE' => 'Suitcase',
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

/// Declared package types for goods lines. Each goods line is one physical
/// package the warehouse staff handle, count and label individually.
const List<String> kParcelItemTypes = [
  'BOX',
  'SUITCASE',
  'BARREL',
  'TV',
  'APPLIANCE',
  'FURNITURE',
  'PALLET',
  'VEHICLE',
  'DOCUMENTS',
  'OTHER',
];

String parcelItemTypeLabel(String type) => switch (type) {
  'BOX' => 'Box',
  'SUITCASE' => 'Suitcase',
  'BARREL' => 'Barrel',
  'TV' => 'TV / Electronics',
  'APPLIANCE' => 'Appliance',
  'FURNITURE' => 'Furniture',
  'PALLET' => 'Pallet',
  'VEHICLE' => 'Vehicle',
  'DOCUMENTS' => 'Documents',
  'OTHER' => 'Other',
  _ => type,
};

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

String routeCity(String value) => _foldRouteText(value.split(',').first.trim());

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
  if (origin == null || destination == null) {
    return 'Select an origin and destination.';
  }
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
