import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/theme.dart';
import '../models/models.dart';
import '../widgets/common.dart';
import 'parcel_detail_screen.dart';

/// "Parcel Registered Successfully!" (design screen 6) with tracking ID,
/// QR code, Code-128 barcode and shipment summary.
class ParcelSuccessScreen extends StatelessWidget {
  final Parcel parcel;

  const ParcelSuccessScreen({super.key, required this.parcel});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            const D2FHomeHeader(onBell: null),
            const SizedBox(height: 4),

            // Celebration header
            const ReferenceArt('success', height: 190),
            const SizedBox(height: 16),
            Text(
              'Parcel registered.\nReady to go!',
              style: AppTheme.display.copyWith(fontSize: 29),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              'Your parcel is registered and ready for shipment.',
              style: AppTheme.caption.copyWith(height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            const SizedBox(height: 6),

            // Tracking number card
            SectionCard(
              tint: AppColors.blueSoft,
              raised: true,
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'TRACKING NUMBER',
                              style: TextStyle(
                                color: AppColors.textGrey,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              parcel.trackingId,
                              style: const TextStyle(
                                color: AppColors.navy,
                                fontSize: 21,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => copyToClipboard(
                          context,
                          parcel.trackingId,
                          message: 'Tracking number copied',
                        ),
                        icon: const Icon(
                          Icons.copy_rounded,
                          color: AppColors.blue,
                        ),
                        tooltip: 'Copy',
                      ),
                    ],
                  ),
                  const Divider(color: AppColors.border, height: 28),
                  Row(
                    children: [
                      // QR
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: QrImageView(
                          data: parcel.trackingId,
                          version: QrVersions.auto,
                          size: 96,
                          eyeStyle: const QrEyeStyle(
                            eyeShape: QrEyeShape.square,
                            color: AppColors.navy,
                          ),
                          dataModuleStyle: const QrDataModuleStyle(
                            color: AppColors.navy,
                            dataModuleShape: QrDataModuleShape.square,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(width: 1, height: 80, color: AppColors.border),
                      const SizedBox(width: 12),
                      // Barcode
                      Expanded(
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: BarcodeWidget(
                                barcode: Barcode.code128(),
                                data: parcel.trackingId,
                                width: 170,
                                height: 56,
                                color: Colors.black,
                                drawText: false,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              parcel.trackingId,
                              style: const TextStyle(
                                color: AppColors.navy,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Scan to track', style: AppTheme.caption),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Shipment summary
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Shipment Summary', style: AppTheme.sectionTitle),
            ),
            const SizedBox(height: 10),
            SectionCard(
              tint: AppColors.goldSoft,
              child: Row(
                children: [
                  Expanded(
                    child: _SummaryCell(
                      icon: Icons.place_rounded,
                      tint: AppColors.coralSoft,
                      iconColor: AppColors.coral,
                      label: 'DESTINATION',
                      value: parcel.destination.split(',').first.trim(),
                      sub:
                          parcel.destination
                              .split(',')
                              .skip(1)
                              .join(',')
                              .trim()
                              .isEmpty
                          ? null
                          : parcel.destination
                                .split(',')
                                .skip(1)
                                .join(',')
                                .trim(),
                    ),
                  ),
                  Container(width: 1, height: 64, color: AppColors.border),
                  Expanded(
                    child: _SummaryCell(
                      icon: parcel.method.icon,
                      tint: AppColors.blueSoft,
                      iconColor: AppColors.blue,
                      label: 'SHIPPING METHOD',
                      value: parcel.method.label,
                      sub: parcel.method.tagline,
                    ),
                  ),
                  Container(width: 1, height: 64, color: AppColors.border),
                  Expanded(
                    child: _SummaryCell(
                      icon: Icons.scale_rounded,
                      tint: AppColors.goldSoft,
                      iconColor: AppColors.gold,
                      label: 'WEIGHT',
                      value: '${_fmtWeight(parcel.weightKg)} kg',
                      sub: 'Package weight',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),

            PrimaryButton(
              label: 'View Parcel',
              onPressed: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ParcelDetailScreen(parcelId: parcel.id),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            OutlineButton2(
              label: 'Register Another Parcel',
              onPressed: () => Navigator.pop(context, 'another'),
            ),
          ],
        ),
      ),
    );
  }

  String _fmtWeight(double w) =>
      w == w.roundToDouble() ? w.toStringAsFixed(0) : w.toStringAsFixed(1);
}

class _SummaryCell extends StatelessWidget {
  final IconData icon;
  final Color tint;
  final Color iconColor;
  final String label;
  final String value;
  final String? sub;

  const _SummaryCell({
    required this.icon,
    required this.tint,
    required this.iconColor,
    required this.label,
    required this.value,
    this.sub,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: tint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textGrey,
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.navy,
              fontSize: 14.5,
              fontWeight: FontWeight.w900,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (sub != null)
            Text(
              sub!,
              style: const TextStyle(color: AppColors.textGrey, fontSize: 10.5),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }
}
