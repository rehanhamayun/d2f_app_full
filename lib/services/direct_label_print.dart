import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import '../core/api.dart';
import '../models/models.dart';
import 'parcel_label.dart';

class DirectLabelPrint {
  static const channel = MethodChannel('d2f/printer');
  static String owner(User user) =>
      '${Uri.parse(Api.I.currentBaseUrl).host}:${user.id}';
  static bool permitted(User? u) =>
      u != null && (u.isStaff || u.role == UserRole.DRIVER);
  static Future<dynamic> call(
    String method, [
    Map<String, dynamic>? arguments,
  ]) => channel.invokeMethod(method, arguments);
  static Future<Map<String, dynamic>> settings() async =>
      Map<String, dynamic>.from(await call('settings'));
  static Future<Uint8List> cache(User user, Parcel parcel) async {
    final bytes = await ParcelLabel.generate(parcel);
    await call('cacheLabel', {
      'ownerId': owner(user),
      'parcelId': parcel.id,
      'trackingId': parcel.trackingId,
      'bytes': bytes,
    });
    return bytes;
  }

  static Future<List<Map<String, dynamic>>> rows(
    String method,
    User user,
  ) async => (await call(method, {'ownerId': owner(user)}) as List)
      .map((v) => Map<String, dynamic>.from(v))
      .toList();
  static Future<Map<String, dynamic>> print(
    User user,
    String parcelId,
    String trackingId, {
    bool reprint = false,
    String reason = '',
  }) async {
    final random = Random.secure();
    final id =
        'label-${DateTime.now().microsecondsSinceEpoch}-${List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
    return Map<String, dynamic>.from(
      await call('print', {
        'ownerId': owner(user),
        'parcelId': parcelId,
        'trackingId': trackingId,
        'clientJobId': id,
        'reprint': reprint,
        'reason': reason,
      }),
    );
  }

  static Future<int> sync(User user) async {
    var count = 0;
    for (final job in await rows('history', user)) {
      if (job['synced'] == true || job['status'] == 'PRINTING') continue;
      await Api.I.shipmentOperation(
        '/label-print/history',
        method: 'POST',
        data: {
          for (final k in [
            'clientJobId',
            'parcelId',
            'printerName',
            'printerAddress',
            'labelHash',
            'pages',
            'status',
            'message',
            'source',
            'reason',
            'deviceTimeMs',
          ])
            if (job[k] != null) k: job[k],
        },
      );
      await call('markSynced', {
        'ownerId': owner(user),
        'clientJobId': job['clientJobId'],
      });
      count++;
    }
    return count;
  }
}
