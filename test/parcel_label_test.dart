import 'dart:io';

import 'package:d2f_application/models/models.dart';
import 'package:d2f_application/services/parcel_label.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'registered physical packages produce separate scannable label pages',
    () async {
      final parcel = Parcel.fromJson({
        'id': 'package-label-qa',
        'trackingId': 'D2F000000000125',
        'customerId': 'c1',
        'recipientName': 'Koffi Mensah',
        'recipientPhone': '+228 90 12 34 56',
        'recipientAddress': '12 Route d’Aného, Quartier Bè, Lomé, Togo',
        'packageType': 'BOX',
        'weightKg': 12,
        'origin': 'Omaha, NE, USA',
        'destination': 'Lomé, Togo',
        'method': 'SEA',
        'status': 'RECEIVED',
        'items': [
          {
            'id': 'i1',
            'name': 'Books and clothing',
            'type': 'BOX',
            'quantity': 4,
            'position': 0,
            'weightKg': 12,
            'lengthCm': 60,
            'widthCm': 40,
            'heightCm': 45,
            'packageCode': 'D2F000000000125-P01',
          },
          {
            'id': 'i2',
            'name': 'Household goods',
            'type': 'BARREL',
            'quantity': 1,
            'position': 1,
            'notCollectedReason': 'Not ready at collection',
          },
          {
            'id': 'i3',
            'name': 'Personal belongings',
            'type': 'SUITCASE',
            'quantity': 1,
            'position': 2,
            'weightKg': 18,
            'packageCode': 'D2F000000000125-P03',
          },
        ],
      });
      final bytes = await ParcelLabel.generate(parcel);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      await File('/tmp/d2f-package-labels.pdf').writeAsBytes(bytes);
    },
  );

  test(
    'saved parcel produces a 4x6 PDF with its original tracking identity',
    () async {
      final parcel = Parcel.fromJson({
        'id': 'label-qa-uuid',
        'trackingId': 'D2F-2026-000125',
        'customerId': 'c1',
        'recipientName': 'Koffi Mensah',
        'recipientPhone': '+228 90 12 34 56',
        'recipientAddress': '12 Route d’Aného, Quartier Bè, Lomé, Togo',
        'packageType': 'BOX',
        'weightKg': 2.5,
        'origin': 'Omaha, NE, USA',
        'destination': 'Lomé, Togo',
        'method': 'SEA',
        'status': 'RECEIVED',
        'createdAt': '2026-10-20T10:00:00Z',
      });
      final bytes = await ParcelLabel.generate(parcel);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(bytes.length, greaterThan(5000));
      expect(ParcelLabel.format.width, 288);
      expect(ParcelLabel.format.height, 432);
      expect(ParcelLabel.filename(parcel), 'D2F-2026-000125-label.pdf');
      expect(parcel.trackingId, 'D2F-2026-000125');
      final file = File('output/pdf/D2F-shipping-label-example.pdf');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      const channel = MethodChannel('d2f/labels');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        messenger.setMockMethodCallHandler(channel, null);
      });
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'savePdf');
        expect(call.arguments['name'], 'D2F-2026-000125-label.pdf');
        expect(
          String.fromCharCodes((call.arguments['bytes'] as List<int>).take(5)),
          '%PDF-',
        );
        return true;
      });
      expect(await ParcelLabel.save(parcel), isTrue);
      messenger.setMockMethodCallHandler(channel, (_) async => false);
      expect(
        await ParcelLabel.save(parcel),
        isFalse,
        reason: 'Cancelling the document picker is not a successful save.',
      );
    },
  );
}
