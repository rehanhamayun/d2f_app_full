import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../widgets/common.dart';

/// Update Parcel Status (design screen 10). Shows only the server-allowed
/// forward statuses; backend re-validates every transition.
class UpdateStatusScreen extends StatefulWidget {
  final Parcel parcel;

  const UpdateStatusScreen({super.key, required this.parcel});

  @override
  State<UpdateStatusScreen> createState() => _UpdateStatusScreenState();
}

class _UpdateStatusScreenState extends State<UpdateStatusScreen> {
  String? _selected;
  String? _location;
  final _note = TextEditingController();
  bool _saving = false;
  String? _error;

  late final List<String> _allowed =
      kAllowedTransitions[widget.parcel.status] ?? [];

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selected == null) {
      setState(() => _error = 'Select a new status first.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await Api.I.updateStatus(
        widget.parcel.id,
        status: _selected!,
        location: _location,
        note: _note.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Status updated to ${statusLabel(_selected!)}')),
      );
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.parcel;
    final updatedOn = DateFormat('MMMM d, yyyy').format(p.updatedAt);

    return Scaffold(
      appBar: D2FAppBar(
        title: const Text('Update Parcel Status'),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          // Current status banner
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.blueSoft,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'SHIPMENT UPDATE  /  CURRENT STATUS',
                  style: TextStyle(
                    color: AppColors.textGrey,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  statusLabel(p.status),
                  style: AppTheme.heading.copyWith(
                    fontSize: 30,
                    color: AppColors.navy,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  statusHeadline(p.status),
                  style: AppTheme.body.copyWith(
                    color: AppColors.textGrey,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today_rounded,
                      size: 13,
                      color: AppColors.textGrey,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        'Updated on $updatedOn',
                        style: AppTheme.caption.copyWith(
                          color: AppColors.textGrey,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          const Text('Select new status', style: AppTheme.sectionTitle),
          const SizedBox(height: 4),
          Text(
            'Choose the next update for this parcel.',
            style: AppTheme.caption,
          ),
          const SizedBox(height: 12),

          for (final status in _allowed) ...[
            _StatusOption(
              status: status,
              selected: _selected == status,
              onSelect: () => setState(() {
                _selected = status;
                _error = null;
              }),
            ),
            const SizedBox(height: 10),
          ],

          const SizedBox(height: 6),
          const Text(
            'Location',
            style: TextStyle(
              color: AppColors.navy,
              fontWeight: FontWeight.w700,
              fontSize: 13.5,
            ),
          ),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _location,
            items: [
              for (final l in kEventLocations)
                DropdownMenuItem(
                  value: l,
                  child: Text(l, style: AppTheme.body),
                ),
            ],
            onChanged: (v) => setState(() => _location = v),
            decoration: const InputDecoration(
              hintText: 'Select location',
              prefixIcon: Icon(Icons.place_rounded),
            ),
          ),
          const SizedBox(height: 14),

          Text.rich(
            TextSpan(
              text: 'Notes ',
              style: const TextStyle(
                color: AppColors.navy,
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
              ),
              children: const [
                TextSpan(
                  text: '(optional)',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: AppColors.textGrey,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _note,
            maxLength: 250,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Add a note about this update...',
              counterStyle: TextStyle(color: AppColors.textGrey, fontSize: 11),
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.coralSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    color: AppColors.coral,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        color: AppColors.coral,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 18),
          PrimaryButton(
            label: 'Update Status',
            loading: _saving,
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}

class _StatusOption extends StatelessWidget {
  final String status;
  final bool selected;
  final VoidCallback onSelect;

  const _StatusOption({
    required this.status,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final v = StatusVisual.of(status);
    return GestureDetector(
      onTap: onSelect,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.blueSoft.withValues(alpha: 0.8)
              : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppColors.blue : AppColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: selected ? AppColors.blue : AppColors.textGrey,
            ),
            const SizedBox(width: 10),
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: v.tileBg,
                shape: BoxShape.circle,
              ),
              child: Icon(_iconFor(status), color: v.tileIcon, size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    statusLabel(status),
                    style: const TextStyle(
                      color: AppColors.navy,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    _descFor(status),
                    style: const TextStyle(
                      color: AppColors.textGrey,
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(String status) => switch (status) {
    'PROCESSING' => Icons.settings_rounded,
    'IN_TRANSIT' => Icons.local_shipping_rounded,
    'ARRIVED_LOME' => Icons.anchor_rounded,
    'READY_FOR_PICKUP' => Icons.storefront_rounded,
    'DELIVERED' => Icons.check_circle_rounded,
    _ => Icons.inventory_2_rounded,
  };

  String _descFor(String status) => switch (status) {
    'PROCESSING' => 'Parcel received and being prepared for shipment.',
    'IN_TRANSIT' => 'Parcel is on the way to West Africa.',
    'ARRIVED_LOME' => 'Parcel has arrived at our Lomé facility.',
    'READY_FOR_PICKUP' => 'Parcel is ready to be collected in West Africa.',
    'DELIVERED' => 'Parcel has been delivered to the recipient.',
    _ => '',
  };
}
