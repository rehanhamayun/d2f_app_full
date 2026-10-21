import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/models.dart';
import '../core/theme.dart';
import 'auth_widgets.dart';

Future<ShipmentRoute?> showRoutePlanner(
  BuildContext context,
  ShipmentRoute route,
) => showModalBottomSheet<ShipmentRoute>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: authCanvas,
  clipBehavior: Clip.antiAlias,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
  ),
  sheetAnimationStyle: AnimationStyle(
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 420),
    reverseDuration: const Duration(milliseconds: 260),
  ),
  builder: (_) => RoutePlannerSheet(initialRoute: route),
);

class RoutePlannerCard extends StatefulWidget {
  final ValueChanged<ShipmentRoute> onRouteSelected;
  final ShipmentRoute initialRoute;
  const RoutePlannerCard({
    super.key,
    required this.onRouteSelected,
    this.initialRoute = const ShipmentRoute(
      origin: 'Omaha, NE, USA',
      destination: 'Lomé, Togo',
    ),
  });
  @override
  State<RoutePlannerCard> createState() => _RoutePlannerCardState();
}

class _RoutePlannerCardState extends State<RoutePlannerCard> {
  late ShipmentRoute _route;
  @override
  void initState() {
    super.initState();
    _route = widget.initialRoute;
  }

  Future<void> _open() async {
    final route = await showRoutePlanner(context, _route);
    if (route == null || !mounted) return;
    setState(() => _route = route);
    widget.onRouteSelected(route);
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Plan a shipment from ${_route.origin} to ${_route.destination}',
    child: Material(
      color: AppColors.goldSoft,
      borderRadius: BorderRadius.circular(23),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const ValueKey('home-route-planner'),
        onTap: _open,
        child: Ink(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.goldSoft, AppColors.goldSoft],
            ),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(
                children: [
                  Icon(Icons.public_rounded, size: 17, color: AppColors.navy),
                  SizedBox(width: 7),
                  Text(
                    'YOUR NEXT SHIPMENT',
                    style: TextStyle(
                      color: AppColors.navy,
                      fontSize: 9,
                      letterSpacing: 1.3,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Spacer(),
                  Icon(Icons.north_east_rounded, size: 18, color: authNavy),
                ],
              ),
              const SizedBox(height: 20),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                child: Row(
                  key: ValueKey('${_route.origin}-${_route.destination}'),
                  children: [
                    Expanded(child: _location('FROM', _route.origin)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Icon(
                        _route.method.icon,
                        color: AppColors.navy,
                        size: 24,
                      ),
                    ),
                    Expanded(
                      child: _location('TO', _route.destination, right: true),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              const Divider(color: AppColors.border, height: 1),
              const SizedBox(height: 13),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'USA & Europe ↔ West Africa',
                      style: TextStyle(color: authMuted, fontSize: 10),
                    ),
                  ),
                  const Text(
                    'Plan a route',
                    style: TextStyle(
                      color: AppColors.navy,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 5),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 17,
                    color: AppColors.navy,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
  Widget _location(String label, String place, {bool right = false}) {
    final parts = place.split(',');
    return Column(
      crossAxisAlignment: right
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textGrey,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          parts.first.trim(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: authNavy,
            fontSize: 21,
            fontWeight: FontWeight.w800,
            letterSpacing: -.5,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          parts.skip(1).join(',').trim(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: AppColors.textGrey, fontSize: 11),
        ),
      ],
    );
  }
}

class RoutePlannerSheet extends StatefulWidget {
  final ShipmentRoute initialRoute;
  const RoutePlannerSheet({super.key, required this.initialRoute});
  @override
  State<RoutePlannerSheet> createState() => _RoutePlannerSheetState();
}

class _RoutePlannerSheetState extends State<RoutePlannerSheet> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _origin, _destination;
  final _originFocus = FocusNode(), _destinationFocus = FocusNode();
  late ShippingMethod _method;
  int _swaps = 0;
  @override
  void initState() {
    super.initState();
    _origin = TextEditingController(text: widget.initialRoute.origin);
    _destination = TextEditingController(text: widget.initialRoute.destination);
    _method = widget.initialRoute.method;
  }

  @override
  void dispose() {
    _origin.dispose();
    _destination.dispose();
    _originFocus.dispose();
    _destinationFocus.dispose();
    super.dispose();
  }

  void _swap() {
    FocusScope.of(context).unfocus();
    final previous = _origin.text;
    setState(() {
      _origin.text = _destination.text;
      _destination.text = previous;
      _swaps++;
    });
    HapticFeedback.selectionClick();
  }

  void _useRoute() {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    Navigator.pop(
      context,
      ShipmentRoute(
        origin: _origin.text.trim(),
        destination: _destination.text.trim(),
        method: _method,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedPadding(
    duration: const Duration(milliseconds: 200),
    curve: Curves.easeOutCubic,
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight:
            (MediaQuery.sizeOf(context).height * .9 -
                    MediaQuery.viewInsetsOf(context).bottom)
                .clamp(160.0, 900.0),
      ),
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(24, 10, 24, 24),
        child: SafeArea(
          top: false,
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD7DFEB),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 19),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Choose your route',
                        style: TextStyle(
                          color: authNavy,
                          fontSize: 23,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -.6,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close route planner',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: authMuted,
                        size: 21,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                const Text(
                  'USA & Europe ↔ West Africa. In either direction.',
                  style: TextStyle(color: authMuted, fontSize: 12, height: 1.5),
                ),
                const SizedBox(height: 23),
                _locationField(
                  'FROM',
                  'route-origin',
                  _origin,
                  _originFocus,
                  Icons.trip_origin_rounded,
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: IconButton.filledTonal(
                      key: const ValueKey('route-swap'),
                      tooltip: 'Swap origin and destination',
                      onPressed: _swap,
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFFFFF2C8),
                        foregroundColor: authNavy,
                      ),
                      icon: AnimatedRotation(
                        turns: _swaps / 2,
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.easeOutCubic,
                        child: const Icon(Icons.swap_vert_rounded, size: 23),
                      ),
                    ),
                  ),
                ),
                _locationField(
                  'TO',
                  'route-destination',
                  _destination,
                  _destinationFocus,
                  Icons.location_on_outlined,
                ),
                const SizedBox(height: 10),
                const Text(
                  'Type a city and country, or choose a location suggestion.',
                  style: TextStyle(
                    color: authMuted,
                    fontSize: 10.5,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 22),
                const Text(
                  'HOW WOULD YOU LIKE TO SHIP?',
                  style: TextStyle(
                    color: authMuted,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    for (final method in ShippingMethod.values) ...[
                      if (method != ShippingMethod.AIR)
                        const SizedBox(width: 8),
                      Expanded(
                        child: Semantics(
                          selected: _method == method,
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              key: ValueKey(
                                'route-method-${method.name.toLowerCase()}',
                              ),
                              borderRadius: BorderRadius.circular(14),
                              onTap: () => setState(() => _method = method),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 13,
                                ),
                                decoration: BoxDecoration(
                                  color: _method == method
                                      ? authNavy
                                      : Colors.white,
                                  border: Border.all(
                                    color: _method == method
                                        ? authNavy
                                        : const Color(0xFFDDE4EE),
                                  ),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      method.icon,
                                      color: _method == method
                                          ? const Color(0xFFFFD140)
                                          : authMuted,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      method.label,
                                      style: TextStyle(
                                        color: _method == method
                                            ? Colors.white
                                            : authNavy,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 25),
                GoldButton(
                  key: const ValueKey('route-use'),
                  label: 'Use this route',
                  onPressed: _useRoute,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _locationField(
    String label,
    String fieldKey,
    TextEditingController controller,
    FocusNode focus,
    IconData icon,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          color: authMuted,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
        ),
      ),
      const SizedBox(height: 8),
      LayoutBuilder(
        builder: (context, constraints) => RawAutocomplete<String>(
          textEditingController: controller,
          focusNode: focus,
          optionsBuilder: (value) {
            final query = value.text.toLowerCase().trim();
            return kShippingLocationOptions
                .where(
                  (option) =>
                      query.isEmpty || option.toLowerCase().contains(query),
                )
                .take(5);
          },
          optionsViewBuilder: (context, select, options) => Align(
            alignment: Alignment.topLeft,
            child: Material(
              color: Colors.white,
              elevation: 4,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                width: constraints.maxWidth,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: ListView(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    children: [
                      for (final option in options)
                        ListTile(
                          dense: true,
                          leading: const Icon(
                            Icons.place_outlined,
                            size: 18,
                            color: authMuted,
                          ),
                          title: Text(
                            option,
                            style: const TextStyle(
                              color: authNavy,
                              fontSize: 12,
                            ),
                          ),
                          onTap: () => select(option),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          fieldViewBuilder: (context, text, node, submit) => TextFormField(
            key: ValueKey(fieldKey),
            controller: text,
            focusNode: node,
            keyboardType: TextInputType.streetAddress,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (_) {
              submit();
              if (fieldKey == 'route-origin') _destinationFocus.requestFocus();
            },
            validator: (value) {
              final place = value?.trim() ?? '';
              if (place.length < 3 || place.length > 120) {
                return 'Enter a city and country (3–120 characters).';
              }
              if (fieldKey == 'route-destination' &&
                  place.toLowerCase() == _origin.text.trim().toLowerCase()) {
                return 'Origin and destination must be different.';
              }
              return null;
            },
            style: const TextStyle(
              color: authNavy,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              hintText: 'City, country',
              prefixIcon: Icon(icon, size: 21, color: authNavy),
              filled: true,
              fillColor: Colors.white,
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: const BorderSide(color: authBlue, width: 1.3),
              ),
            ),
          ),
        ),
      ),
    ],
  );
}
