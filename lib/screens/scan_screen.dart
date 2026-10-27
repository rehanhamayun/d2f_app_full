import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../core/tracking_code.dart';
import '../widgets/common.dart';
import 'parcel_detail_screen.dart';

/// Scan Parcel / Manual Tracking Lookup (screen map #6).
/// Camera scan of a parcel QR/Code-128, plus manual fallback field.
class ScanScreen extends StatefulWidget {
  final bool returnTracking;
  const ScanScreen({super.key, this.returnTracking = false});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    formats: const [BarcodeFormat.qrCode, BarcodeFormat.code128],
  );
  final _manual = TextEditingController();

  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    _manual.dispose();
    super.dispose();
  }

  Future<void> _handleBarcode(BarcodeCapture capture) async {
    if (_busy) return;
    for (final barcode in capture.barcodes) {
      final code = barcode.rawValue;
      if (code == null || code.trim().isEmpty) continue;
      await _lookup(code.trim(), scanned: true);
      break;
    }
  }

  Future<void> _lookup(String code, {bool scanned = false}) async {
    if (_busy || code.trim().isEmpty) return;
    final trackingId = normalizeTrackingCode(code);
    if (trackingId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'This code is not a D2F tracking number. Try the number printed below the barcode.',
            ),
          ),
        );
      }
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _busy = true);
    // Pause camera while navigating so repeated frames don't re-trigger.
    try {
      await _controller.stop();
    } catch (_) {}
    try {
      if (widget.returnTracking) {
        if (mounted) Navigator.pop(context, trackingId);
        return;
      }
      final parcel = await Api.I.parcelDetail(trackingId);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ParcelDetailScreen(parcelId: parcel.id),
        ),
      );
      if (mounted) setState(() => _busy = false);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.statusCode == 404 ? 'No parcel found for $code' : e.message,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lookup failed. Please try again.')),
      );
    } finally {
      try {
        if (mounted && !widget.returnTracking) await _controller.start();
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: D2FAppBar(title: const Text('Scan Parcel')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const ScreenIntro(
                  title: 'Scan. Track. Done.',
                  subtitle: 'Align the QR code or barcode inside the frame.',
                ),
                const SizedBox(height: 20),
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: SizedBox(
                    height: (constraints.maxHeight - 280).clamp(200.0, 430.0),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        MobileScanner(
                          controller: _controller,
                          onDetect: _handleBarcode,
                          errorBuilder: (context, error) => Container(
                            color: AppColors.navy,
                            padding: const EdgeInsets.all(28),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.videocam_off_outlined,
                                    color: Colors.white,
                                    size: 36,
                                  ),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'Camera unavailable',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Use the tracking number below to find your parcel.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: .7),
                                      fontSize: 12,
                                      height: 1.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        IgnorePointer(
                          child: Center(
                            child: Container(
                              width: 210,
                              height: 170,
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: .7),
                                  width: 2,
                                ),
                                borderRadius: BorderRadius.circular(22),
                              ),
                              child: Center(
                                child: Container(
                                  height: 2,
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.coral,
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.coral.withValues(
                                          alpha: .5,
                                        ),
                                        blurRadius: 10,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const Positioned(
                          bottom: 18,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: Text(
                              'QR CODE  ·  BARCODE',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                letterSpacing: 2,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        if (_busy)
                          Container(
                            color: Colors.black.withValues(alpha: .35),
                            child: const Center(
                              child: CircularProgressIndicator(
                                color: Colors.white,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                SectionCard(
                  tint: AppColors.goldSoft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Have a tracking number?',
                        style: AppTheme.sectionTitle,
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Enter it below to look up your parcel.',
                        style: AppTheme.caption,
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _manual,
                        textCapitalization: TextCapitalization.characters,
                        textInputAction: TextInputAction.go,
                        onSubmitted: (v) => _lookup(v.trim()),
                        decoration: const InputDecoration(
                          hintText: 'D2F-2026-000101',
                          prefixIcon: Icon(Icons.tag_rounded),
                        ),
                      ),
                      const SizedBox(height: 12),
                      PrimaryButton(
                        label: 'Find Parcel',
                        loading: _busy,
                        onPressed: () => _lookup(_manual.text.trim()),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
