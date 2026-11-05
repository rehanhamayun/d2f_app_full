import 'dart:convert';

import 'package:flutter/services.dart';

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/models.dart';
import '../models/marketplace.dart';
import '../models/warehouse.dart';

/// Thrown for any API failure with a human-friendly message.
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, [this.statusCode]);

  @override
  String toString() => message;
}

/// Singleton API client for the D2F backend.
///
/// Base URL defaults to the hosted Railway API and can be
/// overridden from the Account tab (useful when demoing on a physical phone
/// against a LAN backend) or at build time via --dart-define=API_BASE_URL=...
class Api {
  Api._();
  static final Api I = Api._();

  static const String defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://d2f-api-production.up.railway.app',
  );

  static const _tokenKey = 'd2f_jwt';
  static const _baseUrlKey = 'd2f_base_url';
  static const _printIdentityKey = 'd2f_print_identity_v1';
  Map<String, dynamic>? _printIdentity;
  bool offlinePrintingOnly = false;

  // A remembered operational identity unlocks cached labels only for 24 hours.
  // This never authorizes an API mutation or an offline shipment update.
  User? get offlinePrintingUser {
    final record = _printIdentity;
    if (record == null ||
        _token == null ||
        record['token'] != _token ||
        record['origin'] != currentBaseUrl)
      return null;
    final age =
        DateTime.now().millisecondsSinceEpoch - (record['verifiedAt'] as int);
    if (age < 0 || age > const Duration(hours: 24).inMilliseconds) return null;
    return User.fromJson(Map<String, dynamic>.from(record['user']));
  }

  User? enterOfflinePrinting() {
    final user = offlinePrintingUser;
    offlinePrintingOnly = user != null;
    return user;
  }

  Future<void> _rememberPrintIdentity(Map<String, dynamic> data) async {
    offlinePrintingOnly = false;
    final user = User.fromJson(data);
    if (!(user.isStaff || user.role == UserRole.DRIVER)) {
      _printIdentity = null;
      await _storage.delete(key: _printIdentityKey);
      return;
    }
    _printIdentity = {
      'token': _token,
      'origin': currentBaseUrl,
      'verifiedAt': DateTime.now().millisecondsSinceEpoch,
      'user': data,
    };
    // Never persist an identity for a session the user chose not to remember.
    if (await _storage.read(key: _tokenKey) == _token)
      await _storage.write(
        key: _printIdentityKey,
        value: jsonEncode(_printIdentity),
      );
  }

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Dio? _dio;
  String? _token;
  String? _baseOverride;
  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;
    _baseOverride = await _storage.read(key: _baseUrlKey);
    _token = await _storage.read(key: _tokenKey);
    try {
      final raw = await _storage.read(key: _printIdentityKey);
      if (raw != null)
        _printIdentity = Map<String, dynamic>.from(jsonDecode(raw));
    } catch (_) {
      _printIdentity = null;
    }
    _dio = _buildDio();
    _ready = true;
  }

  String get currentBaseUrl {
    final o = _baseOverride;
    return (o == null || o.isEmpty) ? defaultBaseUrl : o;
  }

  /// Configured JWT (null when there is no remembered session). Lets the auth
  /// provider skip restore work entirely for fresh installs.
  String? get sessionToken => _token;

  Dio _buildDio() {
    final d = Dio(
      BaseOptions(
        baseUrl: currentBaseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 60),
        headers: {'Content-Type': 'application/json'},
      ),
    );
    d.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final token = _token;
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
      ),
    );
    return d;
  }

  Future<void> setBaseUrl(String url) async {
    final clean = url.trim().replaceAll(RegExp(r'/+$'), '');
    if (clean.isEmpty || clean == defaultBaseUrl) {
      _baseOverride = null;
      await _storage.delete(key: _baseUrlKey);
    } else {
      _baseOverride = clean;
      await _storage.write(key: _baseUrlKey, value: clean);
    }
    _printIdentity = null;
    offlinePrintingOnly = false;
    await _storage.delete(key: _printIdentityKey);
    _dio = _buildDio();
  }

  // ── Auth ───────────────────────────────────────────────────────────────────

  Future<User?> restoreSession() async {
    if (_token == null || _token!.isEmpty) return null;
    final restoringToken = _token;
    try {
      return await me();
    } on ApiException catch (error) {
      // A temporary outage must not erase a remembered login. Only the server
      // rejecting this session can invalidate it, and never a newer sign-in.
      if (error.statusCode == 401 && _token == restoringToken) {
        await signOut();
      }
      return error.statusCode == 401 ||
              (error.statusCode != null && error.statusCode! < 500)
          ? null
          : enterOfflinePrinting();
    } catch (_) {
      return enterOfflinePrinting();
    }
  }

  Future<User> signIn(
    String email,
    String password, {
    bool remember = true,
  }) async {
    try {
      final res = await _dio!.post(
        '/auth/login',
        data: {'email': email.trim(), 'password': password},
      );
      _token = res.data['token'] as String;
      if (remember) {
        await _storage.write(key: _tokenKey, value: _token!);
      } else {
        await _storage.delete(key: _tokenKey);
      }
      await _rememberPrintIdentity(Map<String, dynamic>.from(res.data['user']));
      return User.fromJson(res.data['user'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  /// Creates a role-aware account and stores the returned session token
  /// (new accounts always stay remembered).
  Future<User> signUp(
    String fullName,
    String email,
    String password, {
    String? phone,
    UserRole role = UserRole.CUSTOMER,
    String? invitation,
  }) async {
    try {
      // Older deployments registered everybody as staff. Check capabilities
      // before submitting any account details to that legacy endpoint.
      try {
        final capabilities = await _dio!.get('/auth/config');
        if (capabilities.data['registrationVersion'] != 2) {
          throw ApiException(
            'The D2F server needs an update before account creation is available.',
          );
        }
      } on DioException catch (error) {
        if (error.response?.statusCode == 404) {
          throw ApiException(
            'The D2F server needs an update before account creation is available.',
          );
        }
        rethrow;
      }
      final res = await _dio!.post(
        '/auth/register',
        data: {
          'fullName': fullName.trim(),
          'email': email.trim(),
          'password': password,
          'role': role.name,
          'invitation': ?invitation,
          if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
        },
      );
      final user = User.fromJson(res.data['user'] as Map<String, dynamic>);
      if (user.role != role) {
        throw ApiException(
          'The server returned an unexpected account role. Please contact D2F support.',
        );
      }
      _token = res.data['token'] as String;
      await _storage.write(key: _tokenKey, value: _token!);
      return user;
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  Future<Map<String, dynamic>> startSocialSignIn(String provider) async {
    try {
      final response = await _dio!.post('/auth/social/$provider/start');
      return Map<String, dynamic>.from(response.data as Map);
    } on DioException catch (error) {
      throw _map(error);
    }
  }

  Future<User?> completeSocialSignIn(
    String id,
    String secret, {
    bool Function()? isActive,
  }) async {
    try {
      final response = await _dio!.post(
        '/auth/social/status',
        data: {'id': id, 'secret': secret},
      );
      if (response.data['pending'] == true || isActive?.call() == false) {
        return null;
      }
      _token = response.data['token'] as String;
      await _storage.write(key: _tokenKey, value: _token!);
      return User.fromJson(
        Map<String, dynamic>.from(response.data['user'] as Map),
      );
    } on DioException catch (error) {
      throw _map(error);
    }
  }

  Future<String> requestPasswordReset(String email) async {
    try {
      final response = await _dio!.post(
        '/auth/password/forgot',
        data: {'email': email},
      );
      return response.data['ticket'] as String;
    } on DioException catch (error) {
      throw _map(error);
    }
  }

  Future<void> resetPassword(
    String ticket,
    String code,
    String password,
  ) async {
    try {
      await _dio!.post(
        '/auth/password/reset',
        data: {'ticket': ticket, 'code': code, 'password': password},
      );
    } on DioException catch (error) {
      throw _map(error);
    }
  }

  Future<Map<String, dynamic>> trackShipment(String trackingId) async {
    try {
      final response = await _dio!.get(
        '/tracking/${Uri.encodeComponent(trackingId.trim())}',
      );
      return Map<String, dynamic>.from(response.data as Map);
    } on DioException catch (error) {
      throw _map(error);
    }
  }

  Future<User> me() async {
    final requestedToken = _token;
    try {
      final res = await _dio!.get('/auth/me');
      if (_token == requestedToken)
        await _rememberPrintIdentity(
          Map<String, dynamic>.from(res.data['user']),
        );
      return User.fromJson(res.data['user'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  Future<User> updateProfile({required String fullName, String? phone}) async {
    try {
      final response = await _dio!.patch(
        '/auth/me',
        data: {'fullName': fullName, 'phone': phone},
      );
      return User.fromJson(response.data['user'] as Map<String, dynamic>);
    } on DioException catch (error) {
      throw _map(error);
    }
  }

  Future<bool> connectionHealthy() async {
    try {
      return (await _dio!.get('/health')).data['database'] == 'connected';
    } catch (_) {
      return false;
    }
  }

  Future<void> signOut() async {
    final cached = _printIdentity == null
        ? null
        : User.fromJson(Map<String, dynamic>.from(_printIdentity!['user']));
    if (cached != null) {
      try {
        await const MethodChannel('d2f/printer').invokeMethod('purgeLabels', {
          'ownerId': '${Uri.parse(currentBaseUrl).host}:${cached.id}',
        });
      } catch (_) {
        /* Non-Android platforms do not have a label cache. */
      }
    }
    _printIdentity = null;
    offlinePrintingOnly = false;
    await _storage.delete(key: _printIdentityKey);
    _token = null;
    await _storage.delete(key: _tokenKey);
  }

  Future<dynamic> shipmentOperation(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? data,
  }) async {
    if (offlinePrintingOnly)
      throw ApiException(
        'Offline printing mode. Reconnect and sign in to access live operations or sync history.',
      );
    try {
      final response = await _dio!.request(
        path,
        data: data,
        options: Options(method: method),
      );
      return response.data;
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  /// Authenticated D2F Connect API, separate from cargo operations.
  Future<dynamic> connect(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? data,
  }) async {
    try {
      final response = await _dio!.request(
        '/connect$path',
        data: data,
        options: Options(method: method),
      );
      return response.data;
    } on DioException catch (error) {
      throw _map(error);
    }
  }

  Future<Uint8List> connectPaymentImage(
    String bookingId,
    String submissionId,
  ) => _imageBytes(
    '/connect/bookings/$bookingId/payment-submissions/$submissionId/image',
  );
  Future<void> submitConnectPaymentEvidence(
    String bookingId, {
    required String method,
    required int instructionsVersion,
    required String transactionId,
    required Uint8List bytes,
  }) async {
    final mime = bytes.length > 8 && bytes[0] == 137 && bytes[1] == 80
        ? 'image/png'
        : bytes.length > 12 && String.fromCharCodes(bytes.take(4)) == 'RIFF'
        ? 'image/webp'
        : 'image/jpeg';
    try {
      await _dio!.post(
        '/connect/bookings/$bookingId/payment-submissions',
        queryParameters: {
          'method': method,
          'instructionsVersion': instructionsVersion,
          'accepted': 'true',
          if (transactionId.isNotEmpty) 'transactionId': transactionId,
        },
        data: bytes,
        options: Options(contentType: mime),
      );
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  // ── Customers ──────────────────────────────────────────────────────────────

  Future<List<Customer>> customers({String? q}) async {
    try {
      final res = await _dio!.get(
        '/customers',
        queryParameters: q == null || q.isEmpty ? null : {'q': q},
      );
      return (res.data as List)
          .map((j) => Customer.fromJson(j as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  Future<Customer> createCustomer({
    required String displayName,
    String? email,
    String? phone,
    String? address,
    String? city,
    String? country,
  }) async {
    try {
      final res = await _dio!.post(
        '/customers',
        data: {
          'displayName': displayName,
          if (email != null && email.isNotEmpty) 'email': email,
          if (phone != null && phone.isNotEmpty) 'phone': phone,
          if (address != null && address.isNotEmpty) 'address': address,
          if (city != null && city.isNotEmpty) 'city': city,
          if (country != null && country.isNotEmpty) 'country': country,
        },
      );
      return Customer.fromJson(res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  // ── Parcels ────────────────────────────────────────────────────────────────

  Future<List<Parcel>> customerParcels({bool tracking = false}) async {
    try {
      final res = await _dio!.get(
        '/customer/parcels',
        queryParameters: tracking ? {'scope': 'tracking'} : null,
      );
      return (res.data as List)
          .map((j) => Parcel.fromJson(j as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  Future<List<Parcel>> customerTrackingParcels() =>
      customerParcels(tracking: true);

  Future<Parcel> customerParcelDetail(String parcelId) async {
    try {
      final res = await _dio!.get('/customer/parcels/$parcelId');
      return Parcel.fromJson(res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  /// Creates a shipment request. Returns the created (or previously-created,
  /// when the same [clientRequestId] is retried) shipment with its itemized
  /// goods list.
  Future<Parcel> createCustomerParcel({
    required String recipientName,
    required String recipientPhone,
    required String recipientAddress,
    required String packageType,
    required double weightKg,
    required String origin,
    required String destination,
    required String method,
    required String deliveryMode,
    bool restrictionsAcknowledged = false,
    String? pickupAddress,
    DateTime? pickupScheduledAt,
    List<ParcelItem> items = const [],
    String? notes,
    required String clientRequestId,
  }) async {
    try {
      final res = await _dio!.post(
        '/customer/parcels',
        data: {
          'recipientName': recipientName,
          'recipientPhone': recipientPhone,
          'recipientAddress': recipientAddress,
          'packageType': packageType,
          'weightKg': weightKg,
          'origin': origin,
          'destination': destination,
          'method': method,
          'deliveryMode': deliveryMode,
          'restrictionsAcknowledged': restrictionsAcknowledged,
          if (pickupAddress != null && pickupAddress.isNotEmpty)
            'pickupAddress': pickupAddress,
          if (pickupScheduledAt != null)
            'pickupScheduledAt': pickupScheduledAt.toUtc().toIso8601String(),
          if (items.isNotEmpty)
            'items': [for (final item in items) item.toCreateJson()],
          if (notes != null && notes.isNotEmpty) 'notes': notes,
          'clientRequestId': clientRequestId,
        },
      );
      return Parcel.fromJson(res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  // ── Goods photos (optional, customer-attached) ────────────────────────────

  /// Uploads one photo of the goods. The bytes travel in the request body;
  /// metadata rides as query parameters.
  Future<ParcelImageMeta> addParcelImage(
    String parcelId,
    Uint8List bytes, {
    required String fileName,
    required String contentType,
    String? label,
    String? itemId,
  }) async {
    try {
      final query = {
        'name': fileName,
        if (label != null && label.isNotEmpty) 'label': label,
        if (itemId != null && itemId.isNotEmpty) 'itemId': itemId,
      };
      final res = await _dio!.post(
        '/customer/parcels/$parcelId/images',
        queryParameters: query,
        data: bytes,
        options: Options(
          contentType: contentType,
          headers: {'Content-Length': bytes.length},
        ),
      );
      return ParcelImageMeta.fromJson(res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  /// Removes a photo the customer attached (only before warehouse intake).
  Future<void> deleteCustomerParcelImage(
    String parcelId,
    String imageId,
  ) async {
    try {
      await _dio!.delete('/customer/parcels/$parcelId/images/$imageId');
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  /// Image bytes for the customer's own parcel.
  Future<Uint8List> customerParcelImageBytes(String parcelId, String imageId) =>
      _imageBytes('/customer/parcels/$parcelId/images/$imageId/raw');

  /// Image bytes for staff and admin record views.
  Future<Uint8List> parcelImageBytes(String parcelId, String imageId) =>
      _imageBytes('/parcels/$parcelId/images/$imageId/raw');

  Future<Uint8List> _imageBytes(String path) async {
    try {
      final res = await _dio!.get(
        path,
        options: Options(responseType: ResponseType.bytes),
      );
      return res.data as Uint8List;
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  Future<List<Parcel>> parcels({String? q, String? status}) async {
    try {
      final res = await _dio!.get(
        '/parcels',
        queryParameters: {
          if (q != null && q.isNotEmpty) 'q': q,
          if (status != null && status != 'ALL') 'status': status,
        },
      );
      return (res.data as List)
          .map((j) => Parcel.fromJson(j as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  Future<Map<String, int>> parcelStats() async {
    try {
      final res = await _dio!.get('/parcels/stats');
      return (res.data as Map).map(
        (k, v) => MapEntry(k.toString(), (v as num).toInt()),
      );
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  /// Rows and counters from one server snapshot. Use this instead of separate
  /// list/stats calls so filter chips cannot disagree with the visible rows.
  Future<ParcelBoardResult> parcelBoard({
    String? q,
    String? status,
    int limit = 500,
    int offset = 0,
  }) async {
    try {
      final res = await _dio!.get(
        '/parcels/board',
        queryParameters: {
          if (q != null && q.isNotEmpty) 'q': q,
          if (status != null && status != 'ALL') 'status': status,
          'limit': limit,
          'offset': offset,
        },
      );
      return ParcelBoardResult.fromJson(
        Map<String, dynamic>.from(res.data as Map),
      );
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  /// Creates a parcel. Returns the created (or previously-created, when the
  /// same [clientRequestId] is retried) parcel.
  Future<Parcel> createParcel({
    required String customerId,
    required String recipientName,
    String? recipientPhone,
    String? recipientAddress,
    String? pickupAddress,
    required String packageType,
    required double weightKg,
    required String origin,
    required String destination,
    required String method,
    String? notes,
    String? clientRequestId,
  }) async {
    try {
      final res = await _dio!.post(
        '/parcels',
        data: {
          'customerId': customerId,
          'recipientName': recipientName,
          if (recipientPhone != null && recipientPhone.isNotEmpty)
            'recipientPhone': recipientPhone,
          if (recipientAddress != null && recipientAddress.isNotEmpty)
            'recipientAddress': recipientAddress,
          if (pickupAddress != null && pickupAddress.isNotEmpty)
            'pickupAddress': pickupAddress,
          'packageType': packageType,
          'weightKg': weightKg,
          'origin': origin,
          'destination': destination,
          'method': method,
          if (notes != null && notes.isNotEmpty) 'notes': notes,
          if (clientRequestId != null && clientRequestId.isNotEmpty)
            'clientRequestId': clientRequestId,
        },
      );
      return Parcel.fromJson(res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  /// Full parcel detail incl. event history. Accepts UUID or tracking ID.
  Future<Parcel> parcelDetail(String idOrTracking) async {
    try {
      final res = await _dio!.get('/parcels/$idOrTracking');
      return Parcel.fromJson(res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  /// Records a status update. Accepts UUID or tracking ID. Physical updates
  /// must name a facility and set [confirmed] after staff verification.
  Future<void> updateStatus(
    String idOrTracking, {
    required String status,
    String? locationId,
    String? location,
    String? note,
    Map<String, dynamic>? operationalNote,
    bool confirmed = false,
    List<({String itemId, String reason})> missedItems = const [],
    String? releasedToName,
    String? releasedToIdNumber,
    DateTime? releasedAt,
    String? deliveredToName,
    String? deliveredToIdNumber,
    DateTime? deliveredAt,
    String? deliveryProofType,
    String? deliveryProofReference,
  }) async {
    try {
      await _dio!.post(
        '/parcels/$idOrTracking/events',
        data: {
          'status': status,
          ...?operationalNote,
          if (locationId != null && locationId.isNotEmpty)
            'locationId': locationId,
          if (location != null && location.isNotEmpty) 'location': location,
          if (note != null && note.isNotEmpty) 'note': note,
          if (confirmed) 'confirmed': true,
          if (missedItems.isNotEmpty)
            'missedItems': [
              for (final missed in missedItems)
                {'itemId': missed.itemId, 'reason': missed.reason},
            ],
          if (releasedToName != null && releasedToName.isNotEmpty)
            'releasedToName': releasedToName,
          if (releasedToIdNumber != null && releasedToIdNumber.isNotEmpty)
            'releasedToIdNumber': releasedToIdNumber,
          if (releasedAt != null) 'releasedAt': releasedAt.toIso8601String(),
          if (deliveredToName != null && deliveredToName.isNotEmpty)
            'deliveredToName': deliveredToName,
          if (deliveredToIdNumber != null && deliveredToIdNumber.isNotEmpty)
            'deliveredToIdNumber': deliveredToIdNumber,
          if (deliveredAt != null) 'deliveredAt': deliveredAt.toIso8601String(),
          if (deliveryProofType != null && deliveryProofType.isNotEmpty)
            'deliveryProofType': deliveryProofType,
          if (deliveryProofReference != null &&
              deliveryProofReference.isNotEmpty)
            'deliveryProofReference': deliveryProofReference,
        },
      );
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  /// Corrects an operational note in place. The original event, actor,
  /// timestamp and location remain; the server records the before/after audit.
  Future<void> correctParcelNote(
    String parcelId,
    String eventId,
    String note,
  ) async {
    try {
      await _dio!.patch(
        '/parcels/$parcelId/events/$eventId/note',
        data: {'note': note},
      );
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  Future<User> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      final response = await _dio!.post(
        '/auth/password/change',
        data: {'currentPassword': currentPassword, 'newPassword': newPassword},
      );
      _token = response.data['token'] as String;
      await _storage.write(key: _tokenKey, value: _token!);
      return User.fromJson(
        Map<String, dynamic>.from(response.data['user'] as Map),
      );
    } on DioException catch (error) {
      throw _map(error);
    }
  }

  // ── Marketplace (customer storefront) ─────────────────────────────────────

  Future<MarketplaceBrowse> marketplaceProducts({
    String? q,
    String? category,
    String? country,
    bool featured = false,
    int page = 1,
  }) async {
    try {
      final response = await _dio!.get(
        '/marketplace/products',
        queryParameters: {
          if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
          if (category != null && category.isNotEmpty) 'category': category,
          if (country != null && country.isNotEmpty) 'country': country,
          if (featured) 'featured': 'true',
          'page': page,
        },
      );
      return MarketplaceBrowse.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  Future<MarketplaceProduct> marketplaceProduct(String id) async {
    try {
      final response = await _dio!.get('/marketplace/products/$id');
      return MarketplaceProduct.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  Future<Uint8List> marketplaceProductImage(String productId, String imageId) =>
      _imageBytes('/marketplace/products/$productId/images/$imageId/raw');

  Future<List<MarketplaceOrder>> marketplaceOrders() async {
    try {
      final response = await _dio!.get('/marketplace/orders');
      return (response.data as List)
          .cast<Map<String, dynamic>>()
          .map(MarketplaceOrder.fromJson)
          .toList();
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  Future<MarketplaceOrder> createMarketplaceOrder({
    required String productId,
    required int quantity,
    required String deliveryPreference,
    String? recipientName,
    required String recipientPhone,
    required String deliveryAddress,
    required String deliveryCity,
    required String deliveryCountry,
    String? notes,
  }) async {
    try {
      final response = await _dio!.post(
        '/marketplace/orders',
        data: {
          'productId': productId,
          'quantity': quantity,
          'deliveryPreference': deliveryPreference,
          if (recipientName != null && recipientName.trim().isNotEmpty)
            'recipientName': recipientName.trim(),
          'recipientPhone': recipientPhone.trim(),
          'deliveryAddress': deliveryAddress.trim(),
          'deliveryCity': deliveryCity.trim(),
          'deliveryCountry': deliveryCountry.trim(),
          if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
        },
      );
      return MarketplaceOrder.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  Future<MarketplaceOrder> cancelMarketplaceOrder(String id) async {
    try {
      final response = await _dio!.post('/marketplace/orders/$id/cancel');
      return MarketplaceOrder.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  // ── Buy For Me (customer purchase requests) ───────────────────────────────

  Future<List<MarketplaceOrder>> buyForMeRequests() async {
    try {
      final response = await _dio!.get('/buy-for-me/requests');
      return (response.data as List)
          .cast<Map<String, dynamic>>()
          .map(MarketplaceOrder.fromJson)
          .toList();
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  Future<MarketplaceOrder> createBuyForMeRequest({
    required String title,
    String? sourceUrl,
    required int quantity,
    int? budgetMinor,
    required String currency,
    String? notes,
  }) async {
    try {
      final response = await _dio!.post(
        '/buy-for-me/requests',
        data: {
          'title': title.trim(),
          if (sourceUrl != null && sourceUrl.trim().isNotEmpty)
            'sourceUrl': sourceUrl.trim(),
          'quantity': quantity,
          if (budgetMinor != null) 'budgetMinor': budgetMinor,
          'currency': currency,
          if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
        },
      );
      return MarketplaceOrder.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  /// decision: accept | decline | cancel
  Future<MarketplaceOrder> buyForMeDecision(String id, String decision) async {
    try {
      final response = await _dio!.post('/buy-for-me/requests/$id/$decision');
      return MarketplaceOrder.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  // ── Seller Studio ─────────────────────────────────────────────────────────

  Future<SellerMe> sellerMe() async {
    try {
      final response = await _dio!.get('/seller/me');
      return SellerMe.fromJson(Map<String, dynamic>.from(response.data as Map));
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  /// Shop branding bytes for the signed-in seller (profile photo | banner).
  Future<Uint8List> sellerBrandingImageBytes(String slot) =>
      _imageBytes('/seller/me/$slot');

  Future<Map<String, dynamic>> uploadSellerBrandingImage(
    String slot,
    Uint8List bytes, {
    required String fileName,
    required String contentType,
  }) async {
    try {
      final response = await _dio!.post(
        '/seller/me/$slot',
        queryParameters: {'name': fileName},
        data: bytes,
        options: Options(
          contentType: contentType,
          headers: {'Content-Length': bytes.length},
        ),
      );
      return Map<String, dynamic>.from(response.data as Map);
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  Future<SellerProfileInfo> submitSellerApplication({
    required String displayName,
    required String businessType,
    String? businessName,
    String? headline,
    String? bio,
    required String category,
    required String country,
    String? city,
    String? address,
    required String phone,
    required bool terms,
  }) async {
    try {
      final response = await _dio!.post(
        '/seller/application',
        data: {
          'displayName': displayName.trim(),
          'businessType': businessType,
          if (businessName != null && businessName.trim().isNotEmpty)
            'businessName': businessName.trim(),
          if (headline != null && headline.trim().isNotEmpty)
            'headline': headline.trim(),
          if (bio != null && bio.trim().isNotEmpty) 'bio': bio.trim(),
          'category': category.trim(),
          'country': country.trim(),
          if (city != null && city.trim().isNotEmpty) 'city': city.trim(),
          if (address != null && address.trim().isNotEmpty) 'address': address.trim(),
          'phone': phone.trim(),
          'terms': terms,
        },
      );
      return SellerProfileInfo.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  Future<List<MarketplaceProduct>> sellerProducts() async {
    try {
      final response = await _dio!.get('/seller/products');
      return (response.data as List)
          .cast<Map<String, dynamic>>()
          .map(MarketplaceProduct.fromJson)
          .toList();
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  Future<MarketplaceProduct> createSellerProduct({
    required String title,
    required String category,
    String? description,
    required int priceMinor,
    required String currency,
    required String fulfillment,
    int? stockCount,
    String? locationCity,
    String? locationCountry,
  }) async {
    try {
      final response = await _dio!.post(
        '/seller/products',
        data: {
          'title': title.trim(),
          'category': category.trim(),
          if (description != null && description.trim().isNotEmpty)
            'description': description.trim(),
          'priceMinor': priceMinor,
          'currency': currency,
          'fulfillment': fulfillment,
          'stockCount': ?stockCount,
          if (locationCity != null && locationCity.trim().isNotEmpty)
            'locationCity': locationCity.trim(),
          if (locationCountry != null && locationCountry.trim().isNotEmpty)
            'locationCountry': locationCountry.trim(),
        },
      );
      return MarketplaceProduct.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  Future<MarketplaceProduct> updateSellerProduct(
    String id, {
    String? title,
    String? category,
    String? description,
    int? priceMinor,
    String? currency,
    String? fulfillment,
    int? stockCount,
    bool clearStock = false,
    bool? isActive,
    String? locationCity,
    String? locationCountry,
  }) async {
    try {
      final response = await _dio!.patch(
        '/seller/products/$id',
        data: {
          if (title != null) 'title': title.trim(),
          if (category != null) 'category': category.trim(),
          if (description != null) 'description': description.trim(),
          if (priceMinor != null) 'priceMinor': priceMinor,
          if (currency != null) 'currency': currency,
          if (fulfillment != null) 'fulfillment': fulfillment,
          if (clearStock)
            'stockCount': null
          else if (stockCount != null)
            'stockCount': stockCount,
          if (isActive != null) 'isActive': isActive,
          if (locationCity != null) 'locationCity': locationCity.trim(),
          if (locationCountry != null) 'locationCountry': locationCountry.trim(),
        },
      );
      return MarketplaceProduct.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  /// Removes a listing. Listings with orders are paused, not erased.
  Future<bool> deleteSellerProduct(String id) async {
    try {
      final response = await _dio!.delete('/seller/products/$id');
      return (response.data as Map?)?['archived'] as bool? ?? false;
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  Future<ProductImageMeta> uploadSellerProductImage(
    String productId,
    Uint8List bytes, {
    required String fileName,
    required String contentType,
  }) async {
    try {
      final response = await _dio!.post(
        '/seller/products/$productId/images',
        queryParameters: {'name': fileName},
        data: bytes,
        options: Options(
          contentType: contentType,
          headers: {'Content-Length': bytes.length},
        ),
      );
      return ProductImageMeta.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  Future<void> deleteSellerProductImage(String productId, String imageId) async {
    try {
      await _dio!.delete('/seller/products/$productId/images/$imageId');
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  Future<List<MarketplaceOrder>> sellerOrders({String? status}) async {
    try {
      final response = await _dio!.get(
        '/seller/orders',
        queryParameters: status == null ? null : {'status': status},
      );
      return (response.data as List)
          .cast<Map<String, dynamic>>()
          .map(MarketplaceOrder.fromJson)
          .toList();
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  /// action: accept | decline | cancel | advance | ship | complete
  Future<MarketplaceOrder> sellerOrderAction(
    String id,
    String action, {
    String? reason,
    String? trackingRef,
  }) async {
    try {
      final response = await _dio!.post(
        '/seller/orders/$id/$action',
        data: {
          if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
          if (trackingRef != null && trackingRef.trim().isNotEmpty)
            'trackingRef': trackingRef.trim(),
        },
      );
      return MarketplaceOrder.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  // ── Admin Commerce (seller & order management) ─────────────────────────

  Future<List<Map<String, dynamic>>> adminSellers({String? status}) async {
    try {
      final response = await _dio!.get(
        '/admin/commerce/sellers',
        queryParameters: status == null ? null : {'status': status},
      );
      return (response.data as List).cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  Future<Map<String, dynamic>> adminRegisterSeller({
    required String customerId,
    required String displayName,
    required String businessType,
    String? businessName,
    required String category,
    String? country,
    String? city,
    String? phone,
    int commissionBps = 1000,
    String? headline,
    String? bio,
  }) async {
    try {
      final response = await _dio!.post(
        '/admin/commerce/sellers',
        data: {
          'customerId': customerId,
          'displayName': displayName.trim(),
          'businessType': businessType,
          if (businessName != null && businessName.trim().isNotEmpty)
            'businessName': businessName.trim(),
          'category': category.trim(),
          if (country != null && country.trim().isNotEmpty)
            'country': country.trim(),
          if (city != null && city.trim().isNotEmpty) 'city': city.trim(),
          if (phone != null && phone.trim().isNotEmpty)
            'phone': phone.trim(),
          'commissionBps': commissionBps,
          if (headline != null && headline.trim().isNotEmpty)
            'headline': headline.trim(),
          if (bio != null && bio.trim().isNotEmpty) 'bio': bio.trim(),
        },
      );
      return Map<String, dynamic>.from(response.data as Map);
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  Future<Map<String, dynamic>> adminUpdateSeller(
    String id, {
    required String action,
    String? reviewNote,
    int? commissionBps,
  }) async {
    try {
      final response = await _dio!.patch(
        '/admin/commerce/sellers/$id',
        data: {
          'action': action,
          if (reviewNote != null && reviewNote.trim().isNotEmpty)
            'reviewNote': reviewNote.trim(),
          if (commissionBps != null) 'commissionBps': commissionBps,
        },
      );
      return Map<String, dynamic>.from(response.data as Map);
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  Future<Map<String, dynamic>> adminCommissions({String? from, String? to}) async {
    try {
      final response = await _dio!.get(
        '/admin/commerce/commissions',
        queryParameters: {
          if (from != null && from.isNotEmpty) 'from': from,
          if (to != null && to.isNotEmpty) 'to': to,
        },
      );
      return Map<String, dynamic>.from(response.data as Map);
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  Future<List<Map<String, dynamic>>> adminOrders({String? kind, String? status}) async {
    try {
      final response = await _dio!.get(
        '/admin/commerce/${kind ?? 'marketplace'}',
        queryParameters: status == null ? null : {'status': status},
      );
      return (response.data as List).cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  // ── Notifications ─────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> notifications({int? limit}) async {
    try {
      final response = await _dio!.get(
        '/notifications',
        queryParameters: limit == null ? null : {'limit': limit},
      );
      return Map<String, dynamic>.from(response.data as Map);
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  Future<int> notificationUnreadCount() async {
    try {
      final response = await _dio!.get('/notifications/unread-count');
      return (Map<String, dynamic>.from(response.data as Map)['unread'] as num)
          .toInt();
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  Future<Map<String, dynamic>> markNotificationRead(String id) async {
    try {
      final response = await _dio!.post('/notifications/$id/read');
      return Map<String, dynamic>.from(response.data as Map);
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  Future<int> markAllNotificationsRead() async {
    try {
      final response = await _dio!.post('/notifications/read-all');
      return (Map<String, dynamic>.from(response.data as Map)['count'] as num)
          .toInt();
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  Future<void> deleteNotification(String id) async {
    try {
      await _dio!.delete('/notifications/$id');
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  // Warehouse operations use the same authenticated session as parcel intake.
  Future<List<WarehouseLocation>> warehouseLocations() async {
    final data = await warehouseRequest('/locations');
    return (data as List)
        .map((j) => WarehouseLocation.fromJson(Map<String, dynamic>.from(j)))
        .toList();
  }

  Future<dynamic> warehouseRequest(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? data,
    Map<String, dynamic>? query,
  }) async {
    try {
      return (await _dio!.request(
        '/warehouse$path',
        data: data,
        queryParameters: query,
        options: Options(method: method),
      )).data;
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  Future<FreightContainer> containerDetail(String id) async =>
      FreightContainer.fromJson(
        Map<String, dynamic>.from(
          await warehouseRequest('/containers/${Uri.encodeComponent(id)}'),
        ),
      );

  ApiException _map(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return ApiException(
        'Connection timed out. Check the server URL in Profile.',
      );
    }
    if (e.type == DioExceptionType.connectionError) {
      return ApiException(
        'Cannot reach the D2F server (${e.requestOptions.baseUrl}). Check the server URL in Profile.',
      );
    }
    final data = e.response?.data;
    if (data is Map && data['error'] is String) {
      return ApiException(data['error'] as String, e.response?.statusCode);
    }
    return ApiException(
      'Unexpected error (${e.response?.statusCode ?? 'network'})',
      e.response?.statusCode,
    );
  }
}
