import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/models.dart';

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
/// Base URL defaults to the Android-emulator host alias (10.0.2.2) and can be
/// overridden from the Account tab (useful when demoing on a physical phone
/// against a LAN backend) or at build time via --dart-define=API_BASE_URL=...
class Api {
  Api._();
  static final Api I = Api._();

  static const String defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:4000',
  );

  static const _tokenKey = 'd2f_jwt';
  static const _baseUrlKey = 'd2f_base_url';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Dio? _dio;
  String? _token;
  String? _baseOverride;
  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;
    _baseOverride = await _storage.read(key: _baseUrlKey);
    _token = await _storage.read(key: _tokenKey);
    _dio = _buildDio();
    _ready = true;
  }

  String get currentBaseUrl {
    final o = _baseOverride;
    return (o == null || o.isEmpty) ? defaultBaseUrl : o;
  }

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
    _dio = _buildDio();
  }

  // ── Auth ───────────────────────────────────────────────────────────────────

  Future<User?> restoreSession() async {
    if (_token == null || _token!.isEmpty) return null;
    try {
      return await me();
    } catch (_) {
      await _storage.delete(key: _tokenKey);
      _token = null;
      return null;
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
      return User.fromJson(res.data['user'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  Future<User> me() async {
    try {
      final res = await _dio!.get('/auth/me');
      return User.fromJson(res.data['user'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  Future<void> signOut() async {
    _token = null;
    await _storage.delete(key: _tokenKey);
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

  /// Creates a parcel. Returns the created (or previously-created, when the
  /// same [clientRequestId] is retried) parcel.
  Future<Parcel> createParcel({
    required String customerId,
    required String recipientName,
    String? recipientPhone,
    String? recipientAddress,
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

  /// Records a status update. Accepts UUID or tracking ID.
  Future<void> updateStatus(
    String idOrTracking, {
    required String status,
    String? location,
    String? note,
  }) async {
    try {
      await _dio!.post(
        '/parcels/$idOrTracking/events',
        data: {
          'status': status,
          if (location != null && location.isNotEmpty) 'location': location,
          if (note != null && note.isNotEmpty) 'note': note,
        },
      );
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  ApiException _map(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return ApiException(
        'Connection timed out. Check the server URL in Account.',
      );
    }
    if (e.type == DioExceptionType.connectionError) {
      return ApiException(
        'Cannot reach the D2F server (${e.requestOptions.baseUrl}). Check the server URL in Account.',
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
