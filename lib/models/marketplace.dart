import 'package:intl/intl.dart';

/// D2F Marketplace + Buy For Me client models.
/// Server keys are camelCase, matching the rest of the API surface.

/// Minor-unit money formatting. XOF has no minor units; other currencies
/// carry two decimals. Never renders a commission value to buyers.
String formatMoney(int? minor, String currency) {
  if (minor == null) return '—';
  const symbols = {'USD': r'$', 'EUR': '€', 'XOF': 'CFA '};
  final xof = currency == 'XOF';
  return NumberFormat.currency(
    locale: 'en_US',
    symbol: symbols[currency] ?? '$currency ',
    decimalDigits: xof ? 0 : 2,
  ).format(xof ? minor : minor / 100);
}

class CategoryCount {
  final String name;
  final int count;
  const CategoryCount(this.name, this.count);
  factory CategoryCount.fromJson(Map<String, dynamic> json) => CategoryCount(
    json['name'] as String? ?? 'Other',
    (json['count'] as num?)?.toInt() ?? 0,
  );
}

class ProductImageMeta {
  final String id;
  final String fileName;
  final String contentType;
  final int sizeBytes;
  final int position;
  const ProductImageMeta({
    required this.id,
    required this.fileName,
    required this.contentType,
    required this.sizeBytes,
    required this.position,
  });
  factory ProductImageMeta.fromJson(Map<String, dynamic> json) =>
      ProductImageMeta(
        id: json['id'] as String,
        fileName: json['fileName'] as String? ?? 'photo',
        contentType: json['contentType'] as String? ?? 'image/jpeg',
        sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
        position: (json['position'] as num?)?.toInt() ?? 0,
      );
}

class SellerSummary {
  final String id;
  final String displayName;
  final String? city;
  final String? country;
  final String? headline;
  final String? category;
  const SellerSummary({
    required this.id,
    required this.displayName,
    this.city,
    this.country,
    this.headline,
    this.category,
  });
  factory SellerSummary.fromJson(Map<String, dynamic> json) => SellerSummary(
    id: json['id'] as String,
    displayName: json['displayName'] as String? ?? 'D2F Seller',
    city: json['city'] as String?,
    country: json['country'] as String?,
    headline: json['headline'] as String?,
    category: json['category'] as String?,
  );
  String get location => [
    city,
    country,
  ].where((part) => part != null && part.isNotEmpty).join(', ');
}

class MarketplaceProduct {
  final String id;
  final String title;
  final String category;
  final String? description;
  final int priceMinor;
  final String currency;
  final String fulfillment; // SELLER | D2F
  final int? stockCount;
  final String? locationCity;
  final String? locationCountry;
  final bool featured;
  final bool soldOut;
  final DateTime? createdAt;
  final List<ProductImageMeta> images;
  final SellerSummary? seller;
  final bool isActive;
  final int ordersCount;

  const MarketplaceProduct({
    required this.id,
    required this.title,
    required this.category,
    this.description,
    required this.priceMinor,
    required this.currency,
    required this.fulfillment,
    this.stockCount,
    this.locationCity,
    this.locationCountry,
    this.featured = false,
    this.soldOut = false,
    this.createdAt,
    this.images = const [],
    this.seller,
    this.isActive = true,
    this.ordersCount = 0,
  });

  factory MarketplaceProduct.fromJson(Map<String, dynamic> json) {
    final imageList =
        (json['images'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final sellerJson = json['seller'] as Map<String, dynamic>?;
    return MarketplaceProduct(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'Product',
      category: json['category'] as String? ?? 'Other',
      description: json['description'] as String?,
      priceMinor: (json['priceMinor'] as num?)?.toInt() ?? 0,
      currency: json['currency'] as String? ?? 'USD',
      fulfillment: json['fulfillment'] as String? ?? 'SELLER',
      stockCount: (json['stockCount'] as num?)?.toInt(),
      locationCity: json['locationCity'] as String?,
      locationCountry: json['locationCountry'] as String?,
      featured: json['featured'] as bool? ?? false,
      soldOut: json['soldOut'] as bool? ?? false,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      images: imageList.map(ProductImageMeta.fromJson).toList(),
      seller: sellerJson == null ? null : SellerSummary.fromJson(sellerJson),
      isActive: json['isActive'] as bool? ?? true,
      ordersCount: ((json['_count'] as Map?)?['orders'] as num?)?.toInt() ?? 0,
    );
  }

  String? get location => [
    locationCity,
    locationCountry,
  ].where((p) => p != null && p.isNotEmpty).join(', ');
  String? get heroImageId => images.isEmpty ? null : images.first.id;

  MarketplaceProduct copyWith({bool? isActive}) => MarketplaceProduct(
    id: id,
    title: title,
    category: category,
    description: description,
    priceMinor: priceMinor,
    currency: currency,
    fulfillment: fulfillment,
    stockCount: stockCount,
    locationCity: locationCity,
    locationCountry: locationCountry,
    featured: featured,
    soldOut: soldOut,
    createdAt: createdAt,
    images: images,
    seller: seller,
    isActive: isActive ?? this.isActive,
    ordersCount: ordersCount,
  );
}

class MarketplaceBrowse {
  final List<MarketplaceProduct> products;
  final int total;
  final int page;
  final int limit;
  final List<CategoryCount> categories;
  final List<CategoryCount> countries;
  const MarketplaceBrowse({
    required this.products,
    required this.total,
    required this.page,
    required this.limit,
    required this.categories,
    required this.countries,
  });
  factory MarketplaceBrowse.fromJson(Map<String, dynamic> json) =>
      MarketplaceBrowse(
        products: ((json['products'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(MarketplaceProduct.fromJson)
            .toList(),
        total: (json['total'] as num?)?.toInt() ?? 0,
        page: (json['page'] as num?)?.toInt() ?? 1,
        limit: (json['limit'] as num?)?.toInt() ?? 24,
        categories: ((json['categories'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(CategoryCount.fromJson)
            .toList(),
        countries: ((json['countries'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(CategoryCount.fromJson)
            .toList(),
      );
}

class OrderProductSummary {
  final String id;
  final String title;
  final String? category;
  final String? imageId;
  const OrderProductSummary({
    required this.id,
    required this.title,
    this.category,
    this.imageId,
  });
  factory OrderProductSummary.fromJson(Map<String, dynamic> json) =>
      OrderProductSummary(
        id: json['id'] as String,
        title: json['title'] as String? ?? 'Product',
        category: json['category'] as String?,
        imageId:
            ((json['images'] as List?)?.cast<Map<String, dynamic>>() ??
                    const [])
                .map((e) => e['id'] as String?)
                .firstWhere((id) => id != null, orElse: () => null),
      );
}

class MarketplaceOrder {
  final String id;
  final String kind; // MARKETPLACE | BUY_FOR_ME
  final String title;
  final String status;
  final int quantity;
  final int? amountMinor;
  final String currency;
  final String? notes;
  final String source; // ADMIN | APP
  final String? deliveryPreference; // SELLER | D2F
  final String? recipientName;
  final String? recipientPhone;
  final String? deliveryAddress;
  final String? deliveryCity;
  final String? deliveryStateProvince;
  final String? deliveryCountry;
  final String? deliveryPostalCode;
  final int? budgetMinor;
  final int? productCostMinor;
  final int? shippingCostMinor;
  final String? paymentStatus;
  final String? paymentTransactionId;
  final String? paymentInstructions;
  final String? deliveryService;
  final String? shippingCarrier;
  final String? shippingTrackingNumber;
  final String? shippingLabelUrl;
  final List<ServiceOrderUpdate> updates;
  final List<ServiceOrderPaymentSubmission> paymentSubmissions;
  final String? sourceUrl;
  final String? trackingRef;
  final String? parcelTrackingId;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final OrderProductSummary? product;
  final SellerSummary? seller;
  // Seller view only — agreed commission, never sent to buyers.
  final int? commissionBps;
  final int? commissionMinor;

  const MarketplaceOrder({
    required this.id,
    required this.kind,
    required this.title,
    required this.status,
    required this.quantity,
    this.amountMinor,
    required this.currency,
    this.notes,
    required this.source,
    this.deliveryPreference,
    this.recipientName,
    this.recipientPhone,
    this.deliveryAddress,
    this.deliveryCity,
    this.deliveryStateProvince,
    this.deliveryCountry,
    this.deliveryPostalCode,
    this.budgetMinor,
    this.productCostMinor,
    this.shippingCostMinor,
    this.paymentStatus,
    this.paymentTransactionId,
    this.paymentInstructions,
    this.deliveryService,
    this.shippingCarrier,
    this.shippingTrackingNumber,
    this.shippingLabelUrl,
    this.updates = const [],
    this.paymentSubmissions = const [],
    this.sourceUrl,
    this.trackingRef,
    this.parcelTrackingId,
    this.createdAt,
    this.updatedAt,
    this.product,
    this.seller,
    this.commissionBps,
    this.commissionMinor,
  });

  factory MarketplaceOrder.fromJson(Map<String, dynamic> json) {
    final productJson = json['product'] as Map<String, dynamic>?;
    final sellerJson = json['seller'] as Map<String, dynamic>?;
    final parcelJson = json['parcel'] as Map<String, dynamic>?;
    return MarketplaceOrder(
      id: json['id'] as String,
      kind: json['kind'] as String? ?? 'MARKETPLACE',
      title: json['title'] as String? ?? 'Order',
      status: json['status'] as String? ?? 'REQUESTED',
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      amountMinor: (json['amountMinor'] as num?)?.toInt(),
      currency: json['currency'] as String? ?? 'USD',
      notes: json['notes'] as String?,
      source: json['source'] as String? ?? 'ADMIN',
      deliveryPreference: json['deliveryPreference'] as String?,
      recipientName: json['recipientName'] as String?,
      recipientPhone: json['recipientPhone'] as String?,
      deliveryAddress: json['deliveryAddress'] as String?,
      deliveryCity: json['deliveryCity'] as String?,
      deliveryStateProvince: json['deliveryStateProvince'] as String?,
      deliveryCountry: json['deliveryCountry'] as String?,
      deliveryPostalCode: json['deliveryPostalCode'] as String?,
      budgetMinor: (json['budgetMinor'] as num?)?.toInt(),
      productCostMinor: (json['productCostMinor'] as num?)?.toInt(),
      shippingCostMinor: (json['shippingCostMinor'] as num?)?.toInt(),
      paymentStatus: json['paymentStatus'] as String?,
      paymentTransactionId: json['paymentTransactionId'] as String?,
      paymentInstructions: json['paymentInstructions'] as String?,
      deliveryService: json['deliveryService'] as String?,
      shippingCarrier: json['shippingCarrier'] as String?,
      shippingTrackingNumber: json['shippingTrackingNumber'] as String?,
      shippingLabelUrl: json['shippingLabelUrl'] as String?,
      updates: ((json['updates'] as List?) ?? const [])
          .cast<Map<String, dynamic>>()
          .map(ServiceOrderUpdate.fromJson)
          .toList(),
      paymentSubmissions: ((json['paymentSubmissions'] as List?) ?? const [])
          .cast<Map<String, dynamic>>()
          .map(ServiceOrderPaymentSubmission.fromJson)
          .toList(),
      sourceUrl: json['sourceUrl'] as String?,
      trackingRef: json['trackingRef'] as String?,
      parcelTrackingId: parcelJson?['trackingId'] as String?,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
      product: productJson == null
          ? null
          : OrderProductSummary.fromJson(productJson),
      seller: sellerJson == null ? null : SellerSummary.fromJson(sellerJson),
      commissionBps: (json['commissionBps'] as num?)?.toInt(),
      commissionMinor: (json['commissionMinor'] as num?)?.toInt(),
    );
  }

  String get reference =>
      'D2F-${id.replaceAll('-', '').substring(0, 8).toUpperCase()}';
  bool get isActive => !const {'COMPLETED', 'CANCELLED'}.contains(status);
  String? get delivery => [
    deliveryCity,
    deliveryCountry,
  ].where((p) => p != null && p.isNotEmpty).join(', ');
}

class ServiceOrderUpdate {
  final String id;
  final String? status;
  final String message;
  final String? deliveryService;
  final String? shippingCarrier;
  final String? shippingTrackingNumber;
  final String? shippingLabelUrl;
  final String? fileName;
  final String? contentType;
  final DateTime? createdAt;

  const ServiceOrderUpdate({
    required this.id,
    this.status,
    required this.message,
    this.deliveryService,
    this.shippingCarrier,
    this.shippingTrackingNumber,
    this.shippingLabelUrl,
    this.fileName,
    this.contentType,
    this.createdAt,
  });

  factory ServiceOrderUpdate.fromJson(Map<String, dynamic> json) =>
      ServiceOrderUpdate(
        id: json['id'] as String,
        status: json['status'] as String?,
        message: json['message'] as String? ?? '',
        deliveryService: json['deliveryService'] as String?,
        shippingCarrier: json['shippingCarrier'] as String?,
        shippingTrackingNumber: json['shippingTrackingNumber'] as String?,
        shippingLabelUrl: json['shippingLabelUrl'] as String?,
        fileName: json['fileName'] as String?,
        contentType: json['contentType'] as String?,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      );
}

class ServiceOrderPaymentSubmission {
  final String id;
  final String method;
  final String transactionId;
  final String status;
  final String? reviewNote;
  final DateTime? createdAt;

  const ServiceOrderPaymentSubmission({
    required this.id,
    required this.method,
    required this.transactionId,
    required this.status,
    this.reviewNote,
    this.createdAt,
  });

  factory ServiceOrderPaymentSubmission.fromJson(Map<String, dynamic> json) =>
      ServiceOrderPaymentSubmission(
        id: json['id'] as String,
        method: json['method'] as String? ?? 'ZELLE',
        transactionId: json['transactionId'] as String? ?? '',
        status: json['status'] as String? ?? 'PENDING',
        reviewNote: json['reviewNote'] as String?,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      );
}

class SellerProfileInfo {
  final String id;
  final String status; // PENDING | APPROVED | REJECTED | SUSPENDED
  final String displayName;
  final String businessType;
  final String? businessName;
  final String? headline;
  final String? bio;
  final String category;
  final String phone;
  final String? email;
  final String country;
  final String? city;
  final int commissionBps;
  final String? reviewNote;
  final DateTime? termsAcceptedAt;
  final DateTime? createdAt;
  final String? profilePictureName;
  final String? bannerName;

  const SellerProfileInfo({
    required this.id,
    required this.status,
    required this.displayName,
    required this.businessType,
    this.businessName,
    this.headline,
    this.bio,
    required this.category,
    required this.phone,
    this.email,
    required this.country,
    this.city,
    required this.commissionBps,
    this.reviewNote,
    this.termsAcceptedAt,
    this.createdAt,
    this.profilePictureName,
    this.bannerName,
  });

  factory SellerProfileInfo.fromJson(Map<String, dynamic> json) =>
      SellerProfileInfo(
        id: json['id'] as String,
        status: json['status'] as String? ?? 'PENDING',
        displayName: json['displayName'] as String? ?? '',
        businessType: json['businessType'] as String? ?? 'INDIVIDUAL',
        businessName: json['businessName'] as String?,
        headline: json['headline'] as String?,
        bio: json['bio'] as String?,
        category: json['category'] as String? ?? '',
        phone: json['phone'] as String? ?? '',
        email: json['email'] as String?,
        country: json['country'] as String? ?? '',
        city: json['city'] as String?,
        commissionBps: (json['commissionBps'] as num?)?.toInt() ?? 1000,
        reviewNote: json['reviewNote'] as String?,
        termsAcceptedAt: DateTime.tryParse(
          json['termsAcceptedAt'] as String? ?? '',
        ),
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
        profilePictureName: json['profilePictureName'] as String?,
        bannerName: json['bannerName'] as String?,
      );

  String get commissionLabel =>
      '${(commissionBps / 100).toStringAsFixed(commissionBps % 100 == 0 ? 0 : 1)}%';
}

class SellerMe {
  final SellerProfileInfo? profile;
  final int productCount;
  final int openOrders;
  const SellerMe({this.profile, this.productCount = 0, this.openOrders = 0});
  factory SellerMe.fromJson(Map<String, dynamic> json) => SellerMe(
    profile: json['profile'] == null
        ? null
        : SellerProfileInfo.fromJson(
            Map<String, dynamic>.from(json['profile'] as Map),
          ),
    productCount: (json['productCount'] as num?)?.toInt() ?? 0,
    openOrders: (json['openOrders'] as num?)?.toInt() ?? 0,
  );
}

/// A notification sent to a signed-in user: marketplace order events, seller
/// lifecycle events, Buy For Me updates and anything else D2F needs to say.
class MarketplaceNotification {
  final String id;
  final String type;
  final String title;
  final String? body;
  final bool read;
  final DateTime? createdAt;

  const MarketplaceNotification({
    required this.id,
    required this.type,
    required this.title,
    this.body,
    required this.read,
    this.createdAt,
  });

  factory MarketplaceNotification.fromJson(Map<String, dynamic> json) =>
      MarketplaceNotification(
        id: json['id'] as String,
        type: json['type'] as String? ?? 'NOTIFICATION',
        title: json['title'] as String? ?? 'D2F',
        body: json['body'] as String?,
        read: json['read'] as bool? ?? false,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      );

  String get typeLabel => switch (type) {
    'ORDER_REQUESTED' => 'Order request',
    'ORDER_ACCEPTED' => 'Order accepted',
    'ORDER_SHIPPED' => 'Order shipped',
    'ORDER_COMPLETED' => 'Order completed',
    'ORDER_CANCELLED' => 'Order cancelled',
    'SELLER_APPROVED' => 'Seller approved',
    'SELLER_APPLICATION_UPDATE' => 'Application update',
    'BUY_FOR_ME_UPDATE' => 'Buy For Me update',
    _ => type.replaceAll('_', ' ').toTitleCase(),
  };
}

extension _TitleCase on String {
  String toTitleCase() =>
      split(' ')
          .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
          .join(' ');
}
