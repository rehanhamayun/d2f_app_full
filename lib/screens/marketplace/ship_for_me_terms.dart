import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/theme.dart';

/// Ship For Me terms & conditions acceptance screen.
/// Customer must actively accept before registering a purchase.
class ShipForMeTermsScreen extends StatefulWidget {
  final String agreementId;
  final String version;
  final String title;
  final String content;
  const ShipForMeTermsScreen({
    super.key,
    required this.agreementId,
    required this.version,
    required this.title,
    required this.content,
  });

  @override
  State<ShipForMeTermsScreen> createState() => _ShipForMeTermsScreenState();
}

class _ShipForMeTermsScreenState extends State<ShipForMeTermsScreen> {
  bool _accepted = false;
  bool _busy = false;

  Future<void> _accept() async {
    setState(() => _busy = true);
    try {
      await Api.I.acceptShipForMeTerms(
        agreementId: widget.agreementId,
        version: widget.version,
      );
      if (!mounted) return;
      setState(() => _accepted = true);
      Navigator.pop(context, true);
    } on ApiException catch (error) {
      _fail(error.message);
    } catch (_) {
      _fail('Could not accept terms. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(title: const Text('Ship For Me terms')),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: AppColors.goldSoft, borderRadius: BorderRadius.circular(14)),
                    child: Row(
                      children: [
                        const Icon(Icons.description_rounded, size: 20, color: AppColors.gold),
                        const SizedBox(width: 10),
                        Expanded(child: Text('Version ${widget.version}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.gold))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(widget.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.navy, letterSpacing: -.3)),
                  const SizedBox(height: 16),
                  Text(widget.content, style: const TextStyle(fontSize: 12, height: 1.7, color: AppColors.textGrey)),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: AppColors.coralSoft, borderRadius: BorderRadius.circular(14)),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.warning_amber_rounded, size: 20, color: AppColors.coral),
                        SizedBox(height: 8),
                        Text('Important', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppColors.coral)),
                        SizedBox(height: 6),
                        Text('By accepting, you agree to D2F’s prohibited-items policy, inspection authorization, customs obligations, storage fees, and liability limits. Prohibited shipments will be blocked and may be returned at your cost.', style: TextStyle(fontSize: 11, height: 1.6, color: AppColors.textGrey)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
            child: Column(
              children: [
                Row(
                  children: [
                    Checkbox(
                      value: _accepted,
                      onChanged: (_) => setState(() => _accepted = !_accepted),
                      activeColor: AppColors.coral,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          text: 'I accept the Ship For Me terms and conditions (v${widget.version}) ',
                          style: const TextStyle(fontSize: 12, color: AppColors.textGrey),
                          children: [
                            TextSpan(
                              text: '(opens terms)',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.coral),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton(
                    onPressed: _accepted && !_busy ? _accept : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: _accepted ? AppColors.coral : AppColors.coralSoft,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
                    ),
                    child: _busy
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                        : const Text('Accept and continue', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
