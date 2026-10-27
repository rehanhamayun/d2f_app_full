import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../models/warehouse.dart';
import '../widgets/common.dart';

/// Update Parcel Status (design screen 10). Shows only the server-allowed
/// forward statuses; backend re-validates every transition, facility, proof
/// and confirmation.
class UpdateStatusScreen extends StatefulWidget {
  final Parcel parcel;

  /// Optional loader so widget tests (and previews) can supply facilities
  /// without a live API. Production always uses the organization's facilities.
  final Future<List<WarehouseLocation>> Function()? loadLocations;

  const UpdateStatusScreen({
    super.key,
    required this.parcel,
    this.loadLocations,
  });

  @override
  State<UpdateStatusScreen> createState() => _UpdateStatusScreenState();
}

class _UpdateStatusScreenState extends State<UpdateStatusScreen> {
  String? _selected;
  String? _locationId;
  List<WarehouseLocation> _locations = const [];
  bool _locationsLoading = true;
  String? _locationsError;

  final _note = TextEditingController();
  final _releasedToName = TextEditingController();
  final _releasedToId = TextEditingController();
  final _deliveredToName = TextEditingController();
  final _deliveredToId = TextEditingController();
  final _proofReference = TextEditingController();

  DateTime _releasedAt = DateTime.now();
  DateTime _deliveredAt = DateTime.now();
  String? _proofType;
  bool _confirmed = false;
  bool _saving = false;
  String? _error;

  late final List<String> _allowed =
      kAllowedTransitions[widget.parcel.status] ?? [];

  @override
  void initState() {
    super.initState();
    _loadLocations();
  }

  @override
  void dispose() {
    _note.dispose();
    _releasedToName.dispose();
    _releasedToId.dispose();
    _deliveredToName.dispose();
    _deliveredToId.dispose();
    _proofReference.dispose();
    super.dispose();
  }

  Future<void> _loadLocations() async {
    setState(() {
      _locationsLoading = true;
      _locationsError = null;
    });
    try {
      final list =
          await (widget.loadLocations ?? Api.I.warehouseLocations)();
      if (!mounted) return;
      setState(() {
        _locations = list;
        _locationsLoading = false;
        if (list.length == 1) _locationId = list.first.id;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _locationsLoading = false;
        _locationsError =
            'Could not load D2F facilities. Check the connection and try again.';
      });
    }
  }

  bool get _needsFacility =>
      _selected != null && kFacilityRequiredStatuses.contains(_selected);
  bool get _needsConfirmation =>
      _selected != null && kConfirmationStatuses.contains(_selected);
  bool get _isReleased => _selected == 'RELEASED';
  bool get _isDelivered => _selected == 'DELIVERED';

  void _chooseStatus(String status) {
    setState(() {
      _selected = status;
      _error = null;
      _confirmed = false;
      if (status == 'DELIVERED') {
        if (_deliveredToName.text.trim().isEmpty &&
            widget.parcel.releasedToName != null) {
          _deliveredToName.text = widget.parcel.releasedToName!;
        }
        if (_deliveredToId.text.trim().isEmpty &&
            widget.parcel.releasedToIdNumber != null) {
          _deliveredToId.text = widget.parcel.releasedToIdNumber!;
        }
      }
    });
  }

  Future<DateTime?> _pickDateTime(DateTime initial) async {
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(initial.year - 2),
      lastDate: DateTime.now(),
      helpText: 'Select date',
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      helpText: 'Select time',
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  String? _validate() {
    if (_selected == null) return 'Select a new status first.';
    if (_needsFacility && _locationId == null) {
      return 'Select the D2F facility where this update is taking place.';
    }
    if (_needsConfirmation && !_confirmed) {
      return 'Confirm that you have physically verified this shipment at the selected facility.';
    }
    if (_isReleased) {
      if (_releasedToName.text.trim().isEmpty) {
        return 'Enter the name of the person receiving the parcel.';
      }
      if (_releasedToId.text.trim().isEmpty) {
        return 'Record the handover ID or reference before releasing the parcel.';
      }
    }
    if (_isDelivered) {
      if (_deliveredToName.text.trim().isEmpty) {
        return 'Enter the recipient name before confirming delivery.';
      }
      if (_proofType == null) {
        return 'Select the proof of delivery recorded for this handover.';
      }
      if (_proofReference.text.trim().isEmpty) {
        return 'Record the proof reference (signature, photo, or ID details).';
      }
      if (_proofType == 'ID_CONFIRMATION' &&
          _deliveredToId.text.trim().isEmpty) {
        return 'Record the recipient ID number for an ID-confirmed delivery.';
      }
    }
    return null;
  }

  Future<void> _submit() async {
    final validationError = _validate();
    if (validationError != null) {
      setState(() => _error = validationError);
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
        locationId: _locationId,
        note: _note.text.trim(),
        confirmed: _confirmed,
        releasedToName: _isReleased ? _releasedToName.text.trim() : null,
        releasedToIdNumber: _isReleased ? _releasedToId.text.trim() : null,
        releasedAt: _isReleased ? _releasedAt : null,
        deliveredToName: _isDelivered ? _deliveredToName.text.trim() : null,
        deliveredToIdNumber: _isDelivered ? _deliveredToId.text.trim() : null,
        deliveredAt: _isDelivered ? _deliveredAt : null,
        deliveryProofType: _isDelivered ? _proofType : null,
        deliveryProofReference:
            _isDelivered ? _proofReference.text.trim() : null,
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
              onSelect: () => _chooseStatus(status),
            ),
            const SizedBox(height: 10),
          ],

          if (_allowed.isEmpty) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.greenSoft,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Row(
                children: [
                  Icon(Icons.verified_rounded, color: AppColors.green),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'This parcel has completed its lifecycle. No further status changes are available.',
                      style: TextStyle(
                        color: AppColors.green,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (_selected != null) ...[
            const SizedBox(height: 8),
            if (_needsFacility) ...[
              const Text(
                'Facility',
                style: TextStyle(
                  color: AppColors.navy,
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
              const SizedBox(height: 6),
              if (_locationsLoading)
                const LinearProgressIndicator(
                  minHeight: 3,
                  color: AppColors.blue,
                )
              else if (_locationsError != null)
                _InlineError(
                  message: _locationsError!,
                  onRetry: _loadLocations,
                )
              else
                DropdownButtonFormField<String>(
                  key: ValueKey('facility-$_locationId'),
                  isExpanded: true,
                  initialValue: _locationId,
                  items: [
                    for (final location in _locations)
                      DropdownMenuItem(
                        value: location.id,
                        child: Text(
                          '${location.name} · ${location.label}',
                          style: AppTheme.body,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => _locationId = value),
                  decoration: const InputDecoration(
                    hintText: 'Select D2F facility',
                    prefixIcon: Icon(Icons.warehouse_outlined),
                  ),
                ),
              const SizedBox(height: 6),
              Text(
                'Only the facility where the parcel physically is may confirm this update.',
                style: AppTheme.caption.copyWith(fontSize: 10.5, height: 1.4),
              ),
              const SizedBox(height: 12),
            ],
            if (_needsConfirmation) ...[
              CheckboxListTile(
                value: _confirmed,
                onChanged: (value) =>
                    setState(() => _confirmed = value ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                activeColor: AppColors.blue,
                tileColor: AppColors.goldSoft,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                title: const Text(
                  'I physically verified this shipment',
                  style: TextStyle(
                    color: AppColors.navy,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                subtitle: Text(
                  'Required before recording a physical movement or handover.',
                  style: AppTheme.caption.copyWith(fontSize: 10.5),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (_isReleased) ...[
              _SectionLabel('Handover details'),
              const SizedBox(height: 8),
              _TextField(
                controller: _releasedToName,
                label: 'Received by',
                hint: 'Full name of the person collecting',
                icon: Icons.person_outline_rounded,
                maxLength: 120,
              ),
              const SizedBox(height: 10),
              _TextField(
                controller: _releasedToId,
                label: 'Handover ID / reference',
                hint: 'ID number, collection code, or reference',
                icon: Icons.badge_outlined,
                maxLength: 80,
              ),
              const SizedBox(height: 10),
              _DateTimeField(
                label: 'Handover date and time',
                value: _releasedAt,
                onPick: () async {
                  final picked = await _pickDateTime(_releasedAt);
                  if (picked != null) setState(() => _releasedAt = picked);
                },
              ),
              const SizedBox(height: 12),
            ],
            if (_isDelivered) ...[
              _SectionLabel('Proof of delivery'),
              const SizedBox(height: 8),
              _TextField(
                controller: _deliveredToName,
                label: 'Delivered to',
                hint: 'Recipient full name',
                icon: Icons.person_outline_rounded,
                maxLength: 120,
              ),
              const SizedBox(height: 10),
              _TextField(
                controller: _deliveredToId,
                label: 'Recipient ID / reference',
                hint: 'Required for ID-confirmed delivery',
                icon: Icons.badge_outlined,
                maxLength: 80,
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                key: ValueKey('proof-type-$_proofType'),
                isExpanded: true,
                initialValue: _proofType,
                items: [
                  for (final type in kDeliveryProofTypes)
                    DropdownMenuItem(
                      value: type,
                      child: Text(
                        deliveryProofLabel(type),
                        style: AppTheme.body,
                      ),
                    ),
                ],
                onChanged: (value) => setState(() => _proofType = value),
                decoration: const InputDecoration(
                  labelText: 'Proof type',
                  hintText: 'Select proof of delivery',
                  prefixIcon: Icon(Icons.verified_user_outlined),
                ),
              ),
              const SizedBox(height: 10),
              _TextField(
                controller: _proofReference,
                label: 'Proof reference',
                hint: switch (_proofType) {
                  'SIGNATURE' => 'Signed release form reference',
                  'PHOTO' => 'Photo file name or upload reference',
                  'ID_CONFIRMATION' => 'ID number recorded at handover',
                  'RECIPIENT_CONFIRMATION' => 'Recipient confirmation note',
                  _ => 'Signature, photo, or ID reference',
                },
                icon: Icons.attachment_outlined,
                maxLength: 300,
              ),
              const SizedBox(height: 10),
              _DateTimeField(
                label: 'Delivery date and time',
                value: _deliveredAt,
                onPick: () async {
                  final picked = await _pickDateTime(_deliveredAt);
                  if (picked != null) setState(() => _deliveredAt = picked);
                },
              ),
              const SizedBox(height: 12),
            ],
          ],

          Text.rich(
            TextSpan(
              text: 'Operational note ',
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
            maxLength: 1000,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Add an operational note about this update...',
              counterStyle: TextStyle(color: AppColors.textGrey, fontSize: 11),
            ),
          ),
          Text(
            'Notes are part of the permanent tracking history. Authorized staff can correct an accidental note later without deleting the event.',
            style: AppTheme.caption.copyWith(fontSize: 10.5, height: 1.4),
          ),

          if (_error != null) ...[
            const SizedBox(height: 10),
            _InlineError(message: _error!),
          ],

          const SizedBox(height: 18),
          PrimaryButton(
            label: 'Update Status',
            loading: _saving,
            onPressed: _allowed.isEmpty ? null : _submit,
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: AppColors.navy,
      fontWeight: FontWeight.w800,
      fontSize: 14,
    ),
  );
}

class _TextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final int maxLength;

  const _TextField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    required this.maxLength,
  });

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    maxLength: maxLength,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon),
      counterStyle: const TextStyle(color: AppColors.textGrey, fontSize: 10),
    ),
  );
}

class _DateTimeField extends StatelessWidget {
  final String label;
  final DateTime value;
  final VoidCallback onPick;

  const _DateTimeField({
    required this.label,
    required this.value,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onPick,
    borderRadius: BorderRadius.circular(14),
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.event_available_rounded),
        suffixIcon: const Icon(Icons.edit_calendar_rounded, size: 19),
      ),
      child: Text(
        DateFormat('MMM d, yyyy · h:mm a').format(value),
        style: AppTheme.body.copyWith(fontWeight: FontWeight.w700),
      ),
    ),
  );
}

class _InlineError extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const _InlineError({required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) => Container(
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
            message,
            style: const TextStyle(
              color: AppColors.coral,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (onRetry != null)
          TextButton(
            onPressed: onRetry,
            child: const Text(
              'Retry',
              style: TextStyle(
                color: AppColors.coral,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
      ],
    ),
  );
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
    'ARRIVED_DESTINATION' => Icons.location_on_rounded,
    'RELEASED' => Icons.outbox_rounded,
    'READY_FOR_PICKUP' => Icons.storefront_rounded,
    'DELIVERED' => Icons.check_circle_rounded,
    _ => Icons.inventory_2_rounded,
  };

  String _descFor(String status) => switch (status) {
    'PROCESSING' => 'Parcel received and being prepared for shipment.',
    'IN_TRANSIT' => 'Parcel is on the way to its destination.',
    'ARRIVED_LOME' => 'Parcel has arrived at our Lomé facility.',
    'ARRIVED_DESTINATION' => 'Parcel has arrived at its destination facility.',
    'RELEASED' => 'Parcel has been released for collection or delivery.',
    'READY_FOR_PICKUP' => 'Parcel is ready at the pickup location.',
    'DELIVERED' => 'Parcel has been delivered to the recipient.',
    _ => '',
  };
}
