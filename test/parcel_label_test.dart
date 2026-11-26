import 'dart:io';

import 'package:d2f_application/models/models.dart';
import 'package:d2f_application/services/parcel_label.dart';
import 'package:d2f_application/services/invoice_pdf.dart';
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
        'customer': {
          'id': 'c1',
          'displayName': 'Marie Lawson',
          'phone': '+1 402 555 0110',
        },
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
      expect(
        RegExp(r'/Type/Page/').allMatches(String.fromCharCodes(bytes)).length,
        2,
      );
      await File('/tmp/d2f-package-labels.pdf').writeAsBytes(bytes);
      final receipt = await shipmentReceiptPdf(parcel);
      await File('/tmp/d2f-package-receipt.pdf').writeAsBytes(receipt);
    },
  );

  test(
    'three physical packages print three 4x6 pages with a matching receipt',
    () async {
      final parcel = Parcel.fromJson({
        'id': 'three-package-label-qa',
        'trackingId': 'D2F000000000049',
        'customerId': 'customer-qa',
        'customer': {
          'id': 'customer-qa',
          'displayName': 'Marie Lawson',
          'phone': '+1 402 555 0110',
        },
        'recipientName': 'Koffi Mensah',
        'recipientPhone': '+228 90 12 34 56',
        'recipientAddress': '12 Route d’Aného, Quartier Bè, Lomé, Togo',
        'packageType': 'BOX',
        'weightKg': 12,
        'verifiedWeightKg': 12,
        'origin': 'Omaha, NE, USA',
        'destination': 'Lomé, Togo',
        'method': 'SEA',
        'status': 'RECEIVED',
        'warehouseReceivedAt': '2026-11-26T10:00:00Z',
        'items': [
          for (var i = 1; i <= 3; i++)
            {
              'id': 'item-$i',
              'name': 'Goods',
              'type': 'BOX',
              'quantity': 4,
              'position': i - 1,
              'verifiedWeightKg': 4,
              'packageCode': 'D2F000000000049-P0$i',
            },
        ],
      });
      final labels = await ParcelLabel.generate(parcel);
      expect(
        RegExp(r'/Type/Page/').allMatches(String.fromCharCodes(labels)).length,
        3,
      );
      await File('/tmp/d2f-three-package-labels.pdf').writeAsBytes(labels);
      final receipt = await shipmentReceiptPdf(parcel);
      expect(
        RegExp(r'/Type/Page/').allMatches(String.fromCharCodes(receipt)).length,
        1,
      );
      await File('/tmp/d2f-three-package-receipt.pdf').writeAsBytes(receipt);
    },
  );

  test('service invoice renders a paid itemized PDF', () async {
    final data = await invoicePdf({
      'number': 'D2F-CN-D2F000000000049',
      'service': 'D2F Connect',
      'issuedAt': '2026-11-26T10:00:00Z',
      'status': 'Paid',
      'issuer': 'D2F Shipping LLC',
      'buyer': 'Marie Lawson',
      'reference': 'D2F000000000049',
      'route': 'Omaha, United States → Lomé, Togo',
      'currency': 'USD',
      'totalMinor': 14700,
      'lines': [
        {'label': 'International shipping', 'amountMinor': 12500},
        {'label': 'Domestic carrier cost', 'amountMinor': 2200},
      ],
    });
    expect(
      RegExp(r'/Type/Page/').allMatches(String.fromCharCodes(data)).length,
      1,
    );
    await File('/tmp/d2f-connect-invoice.pdf').writeAsBytes(data);
  });

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
      expect(bytes, isNotEmpty);
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
