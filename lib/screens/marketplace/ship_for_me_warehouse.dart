import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../../widgets/auth_widgets.dart';

/// Shows the customer's D2F warehouse address and unique customer ID
/// for Ship For Me deliveries.
class ShipForMeWarehouseScreen extends StatefulWidget {
  const ShipForMeWarehouseScreen({super.key});

  @override
  State<ShipForMeWarehouseScreen> createState() => _ShipForMeWarehouseScreenState();
}

class _ShipForMeWarehouseScreenState extends State<ShipForMeWarehouseScreen> {
  Map<String, dynamic>? _address;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final addr = await Api.I.getShipForMeWarehouseAddress();
      if (!mounted) return;
      setState(() { _address = addr; _loading = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _copy(String text) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(title: const Text('Your warehouse address')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.coral))
          : _address == null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off_rounded, size: 46, color: AppColors.textGrey),
                      const SizedBox(height: 12),
                      const Text('No warehouse address configured.', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.navy)),
                      const SizedBox(height: 6),
                      Text('Contact D2F support to get your shipping address.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, height: 1.6, color: AppColors.textGrey)),
                    ],
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Ship your purchases to:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textGrey)),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.border)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.local_shipping_rounded, size: 22, color: AppColors.coral),
                                const SizedBox(width: 10),
                                Expanded(child: Text(_address!['label'] ?? 'D2F Warehouse', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.navy))),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(color: AppColors.blueSoft, borderRadius: BorderRadius.circular(10)),
                                  child: Text('CUSTOMER ID', style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: AppColors.blue, letterSpacing: .8)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(_address!['customerWarehouseId'] ?? 'D2F-0000', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 2, color: AppColors.blue)),
                            const SizedBox(height: 16),
                            Text(
                              '${_address!['addressLine1']}\n${_address!['addressLine2'] != null ? '${_address!['addressLine2']}\n' : ''}${_address!['city']}, ${_address!['stateProvince'] ?? ''} ${_address!['postalCode']}\n${_address!['country']}',
                              style: const TextStyle(fontSize: 13, height: 1.6, color: AppColors.textGrey),
                            ),
                            const SizedBox(height: 16),
                            if (_address!['phone'] != null)
                              Row(children: [const Icon(Icons.phone_rounded, size: 16, color: AppColors.textGrey), const SizedBox(width: 8), Text(_address!['phone'], style: const TextStyle(fontSize: 12, color: AppColors.textGrey))]),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: OutlinedButton.icon(
                          onPressed: () => _copy(_address!['customerWarehouseId'].toString()),
                          icon: const Icon(Icons.copy_rounded, size: 18, color: AppColors.coral),
                          label: const Text('Copy customer ID', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.coral)),
                          style: OutlinedButton.styleFrom(side: BorderSide(color: AppColors.coral.withValues(alpha: .5)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: OutlinedButton.icon(
                          onPressed: () => _copy(
                            '${_address!['addressLine1']}, ${_address!['city']}, ${_address!['postalCode']}, ${_address!['country']}',
                          ),
                          icon: const Icon(Icons.copy_rounded, size: 18, color: AppColors.blue),
                          label: const Text('Copy full address', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.blue)),
                          style: OutlinedButton.styleFrom(side: BorderSide(color: AppColors.blue.withValues(alpha: .5)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}
