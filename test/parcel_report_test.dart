import 'package:d2f_application/models/models.dart';
import 'package:d2f_application/services/parcel_report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'parcel details report builds a PDF with full identity and history',
    () async {
      final parcel = Parcel.fromJson({
        'id': 'report-qa-uuid',
        'trackingId': 'D2F-2026-000126',
        'customerId': 'c1',
        'recipientName': 'Koffi Mensah',
        'recipientPhone': '+228 90 12 34 56',
        'recipientAddress': '12 Route d’Aného, Quartier Bè, Lomé, Togo',
        'packageType': 'BOX',
        'weightKg': 2.5,
        'origin': 'Omaha, NE, USA',
        'destination': 'Lomé, Togo',
        'method': 'AIR',
        'status': 'IN_TRANSIT',
        'notes': 'Handle with care — ceramics.',
        'createdAt': '2026-10-20T10:00:00Z',
        'updatedAt': '2026-10-20T12:30:00Z',
        'customer': {'id': 'c1', 'displayName': 'Ama Boateng'},
        'events': [
          {
            'id': 'e1',
            'status': 'RECEIVED',
            'note': 'Parcel registered at intake',
            'location': 'Omaha, NE, USA',
            'createdAt': '2026-10-20T10:00:00Z',
            'actor': {'fullName': 'Warehouse Staff'},
          },
          {
            'id': 'e2',
            'status': 'IN_TRANSIT',
            'note': 'Departed Omaha',
            'location': 'Omaha, NE, USA',
            'createdAt': '2026-10-20T12:00:00Z',
            'actor': {'fullName': 'Admin Lead'},
          },
        ],
      });
      final bytes = await ParcelReport.generate(parcel);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(bytes.length, greaterThan(5000));
      expect(ParcelReport.filename(parcel), 'D2F-2026-000126-details.pdf');
    },
  );
}
