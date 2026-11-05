import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';
import '../screens/connect_screen.dart';
import '../screens/marketplace/buy_for_me_shop.dart';
import '../screens/marketplace/marketplace_shop.dart';
import 'service_hero.dart';
import 'service_card_art.dart';
import 'common.dart';

/// The service catalogue is shared by customer and operations workspaces.
/// Marketplace and Buy For Me are live against the D2F API; business and
/// load boards remain previews.
enum D2FService {
  shipping(
    'International\nShipping',
    'Air & sea freight',
    Icons.inventory_2_outlined,
    Color(0xFF1761DB),
    Color(0xFFEAF2FF),
  ),
  local(
    'Local Delivery',
    'Omaha, USA',
    Icons.local_shipping_rounded,
    Color(0xFF0395B5),
    Color(0xFFE4F7FC),
  ),
  buy(
    'Buy For Me',
    'Shop & ship',
    Icons.shopping_bag_rounded,
    Color(0xFFDC3765),
    Color(0xFFFFEAF0),
  ),
  marketplace(
    'Marketplace',
    'Discover more',
    Icons.storefront_rounded,
    Color(0xFFE77D10),
    Color(0xFFFFF2DD),
  ),
  connect(
    'D2F Connect',
    'Travel & send',
    Icons.people_alt_rounded,
    Color(0xFF7950D9),
    Color(0xFFF0EAFF),
  ),
  africa(
    'Delivery in Africa',
    'Closer to your door',
    Icons.delivery_dining_rounded,
    Color(0xFF14865F),
    Color(0xFFE4F5EB),
  ),
  business(
    'Business Ads',
    'Grow your reach',
    Icons.campaign_rounded,
    Color(0xFFE57035),
    Color(0xFFFFF0DF),
  ),
  loads(
    'Load Board',
    'Jobs & logistics',
    Icons.local_shipping_rounded,
    Color(0xFF167FA8),
    Color(0xFFE5F4FA),
  );

  final String title, subtitle;
  final IconData icon;
  final Color color, tint;
  const D2FService(this.title, this.subtitle, this.icon, this.color, this.tint);
  String get label => title.replaceAll('\n', ' ');
  bool get isComingSoon => this == business || this == loads;
}

void openD2FService(
  BuildContext context,
  D2FService service, {
  required VoidCallback onShip,
  VoidCallback? onContact,
}) {
  HapticFeedback.selectionClick();
  if (service == D2FService.shipping) {
    onShip();
  } else if (service == D2FService.connect) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const ConnectScreen()),
    );
  } else {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) =>
            D2FServiceScreen(service: service, onContact: onContact),
      ),
    );
  }
}

class ServiceIcon extends StatelessWidget {
  final D2FService service;
  final double size;
  const ServiceIcon({super.key, required this.service, this.size = 48});
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color.lerp(service.color, Colors.white, .25)!, service.color],
      ),
      borderRadius: BorderRadius.circular(size * .30),
      border: Border.all(
        color: Colors.white.withValues(alpha: .65),
        width: 1.5,
      ),
      boxShadow: [
        BoxShadow(
          color: service.color.withValues(alpha: .24),
          blurRadius: 12,
          offset: const Offset(0, 5),
        ),
      ],
    ),
    child: Stack(
      children: [
        Positioned(
          top: 3,
          left: 6,
          right: 6,
          child: Container(
            height: size * .28,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: .22),
                  Colors.white.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),
        Center(
          child: Icon(service.icon, color: Colors.white, size: size * .55),
        ),
      ],
    ),
  );
}

class D2FServiceDirectory extends StatelessWidget {
  final ValueChanged<D2FService> onSelected;
  final List<D2FService> services;
  const D2FServiceDirectory({
    super.key,
    required this.onSelected,
    this.services = const [
      D2FService.shipping,
      D2FService.local,
      D2FService.buy,
      D2FService.africa,
      D2FService.marketplace,
      D2FService.connect,
      D2FService.business,
      D2FService.loads,
    ],
  });
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(1);
      final columns =
          services.length == 2 || constraints.maxWidth < 330 && scale > 1.15
          ? 2
          : 3;
      final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final service in services)
            SizedBox(
              width: width,
              child: Semantics(
                button: true,
                label: '${service.label}, ${service.subtitle}',
                onTap: () => onSelected(service),
                child: ExcludeSemantics(
                  child: Material(
                    color: service == D2FService.shipping
                        ? service.color
                        : service.tint,
                    borderRadius: BorderRadius.circular(17),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      key: ValueKey('service-${service.name}'),
                      onTap: () => onSelected(service),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: IgnorePointer(
                              child: CustomPaint(
                                painter: ServiceCardLineArt(
                                  pattern: service.index,
                                  color: service == D2FService.shipping
                                      ? Colors.white.withValues(alpha: .92)
                                      : AppColors.navy.withValues(alpha: .72),
                                ),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(7, 11, 7, 9),
                            child: Column(
                              children: [
                                ServiceIcon(service: service, size: 34),
                                const SizedBox(height: 7),
                                SizedBox(
                                  height: MediaQuery.textScalerOf(context)
                                      .scale(31),
                                  child: Center(
                                    child: Text(
                                      switch (service) {
                                        D2FService.shipping =>
                                          'International\nShipping',
                                        D2FService.buy =>
                                          'Buy For Me /\nShip For Me',
                                        _ => service.label,
                                      },
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 11,
                                        height: 1.3,
                                        fontWeight: FontWeight.w800,
                                        color: service == D2FService.shipping
                                            ? Colors.white
                                            : Color.lerp(
                                                service.color,
                                                AppColors.navy,
                                                .45,
                                              ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 3),
                                SizedBox(
                                  height: MediaQuery.textScalerOf(context)
                                      .scale(23),
                                  child: Center(
                                    child: Text(
                                      service.isComingSoon
                                          ? 'COMING SOON'
                                          : service.subtitle,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 9,
                                        height: 1.3,
                                        color: service == D2FService.shipping
                                            ? Colors.white
                                            : AppColors.textGrey,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
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
      );
    },
  );
}

class D2FServiceHome extends StatelessWidget {
  final VoidCallback onShip, onTrack, onContact;
  final Widget trackingField, shippingMethods, destinations;
  final ValueChanged<D2FService>? onServiceSelected;
  const D2FServiceHome({
    super.key,
    required this.onShip,
    required this.onTrack,
    required this.onContact,
    required this.trackingField,
    required this.shippingMethods,
    required this.destinations,
    this.onServiceSelected,
  });
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                'assets/images/services_shipping.jpg',
                fit: BoxFit.cover,
                alignment: const Alignment(.55, .2),
                excludeFromSemantics: true,
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF082D61).withValues(alpha: .88),
                      const Color(0xFF12365C).withValues(alpha: .07),
                    ],
                    stops: const [0, .85],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Ship. Deliver. Connect.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      height: 1.12,
                      letterSpacing: -.8,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'From Omaha to Africa. From local to global.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10.5,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 60),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .92),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.public_rounded,
                          color: AppColors.blue,
                          size: 13,
                        ),
                        SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            'USA & Europe ↔ West Africa',
                            style: TextStyle(
                              fontSize: 9,
                              color: AppColors.navy,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: AppColors.navy.withValues(alpha: .06),
              blurRadius: 15,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: trackingField,
      ),
      const SizedBox(height: 10),
      FilledButton(
        key: const ValueKey('home-create-shipment'),
        onPressed: onShip,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.coral,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 46),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                'Create a shipment request',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
              ),
            ),
            SizedBox(width: 10),
            Icon(Icons.arrow_forward_rounded, size: 18),
          ],
        ),
      ),
      const SizedBox(height: 20),
      Row(
        children: [
          const Expanded(
            child: Text(
              'Our services',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -.5,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.blueSoft,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'Made for your everyday',
              style: TextStyle(
                color: AppColors.blue,
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 11),
      D2FServiceDirectory(
        services: const [
          D2FService.shipping,
          D2FService.local,
          D2FService.buy,
          D2FService.africa,
          D2FService.marketplace,
          D2FService.connect,
        ],
        onSelected: (service) => onServiceSelected != null
            ? onServiceSelected!(service)
            : openD2FService(
                context,
                service,
                onShip: onShip,
                onContact: onContact,
              ),
      ),
      const SizedBox(height: 20),
      const Text(
        'Coming soon',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 10),
      D2FServiceDirectory(
        services: const [D2FService.business, D2FService.loads],
        onSelected: (service) => openD2FService(
          context,
          service,
          onShip: onShip,
          onContact: onContact,
        ),
      ),
      const SizedBox(height: 18),
      Material(
        color: const Color(0xFF38226D),
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const ValueKey('home-connect-feature'),
          onTap: () =>
              openD2FService(context, D2FService.connect, onShip: onShip),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 112),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Image.asset(
                    'assets/images/services_connect.jpg',
                    fit: BoxFit.cover,
                    alignment: Alignment.centerRight,
                    excludeFromSemantics: true,
                  ),
                ),
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Color(0xFF38226D),
                          Color(0x8838226D),
                          Color(0x0038226D),
                        ],
                        stops: [0, .6, 1],
                      ),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: FractionallySizedBox(
                    widthFactor: .72,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Travel. Support. Connect.',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            height: 1.2,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 7),
                        Text(
                          'Verified travellers. Small parcels.\nEvery handover managed by D2F.',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      const SizedBox(height: 22),
      Row(
        children: [
          const Expanded(
            child: Text(
              'How would you like to send?',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ),
          IconButton(
            tooltip: 'Track all shipments',
            onPressed: onTrack,
            icon: const Icon(Icons.location_on_outlined, color: AppColors.blue),
          ),
        ],
      ),
      const SizedBox(height: 8),
      shippingMethods,
      const SizedBox(height: 18),
      destinations,
      const SizedBox(height: 12),
      Center(
        child: TextButton.icon(
          onPressed: onContact,
          icon: const Icon(Icons.support_agent_rounded, size: 18),
          label: const Text(
            'A real team, ready to help',
            style: TextStyle(fontSize: 12),
          ),
        ),
      ),
    ],
  );
}

class _SectionHeading extends StatelessWidget {
  final String title;
  final String? subtitle;
  const _SectionHeading({required this.title, this.subtitle});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(
          fontSize: 19,
          letterSpacing: -.6,
          fontWeight: FontWeight.w800,
        ),
      ),
      if (subtitle != null) ...[
        const SizedBox(height: 5),
        Text(
          subtitle!,
          style: const TextStyle(
            fontSize: 11,
            height: 1.5,
            color: AppColors.textGrey,
          ),
        ),
      ],
    ],
  );
}

/// Dedicated, navigable service views. Marketplace and Buy For Me run
/// against the live API; previews never invent inventory or prices.
class D2FServiceScreen extends StatefulWidget {
  final D2FService service;
  final VoidCallback? onContact, onProfile, onNotifications;
  final bool embedded;
  const D2FServiceScreen({
    super.key,
    required this.service,
    this.onContact,
    this.onProfile,
    this.onNotifications,
    this.embedded = false,
  });
  @override
  State<D2FServiceScreen> createState() => _D2FServiceScreenState();
}

class _D2FServiceScreenState extends State<D2FServiceScreen> {
  String _country = 'Togo';

  void _contact() {
    if (widget.onContact != null) {
      widget.onContact!();
    } else {
      Clipboard.setData(const ClipboardData(text: 'info@d2fshipping.com'));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Support email copied: info@d2fshipping.com'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    final immersive = service == D2FService.buy || service == D2FService.marketplace;
    if (immersive) {
      return Scaffold(
        backgroundColor: AppColors.cream,
        appBar: widget.embedded
            ? null
            : AppBar(
                title: Text(service.label),
                actions: [
                  IconButton(
                    onPressed: _contact,
                    tooltip: 'Contact D2F',
                    icon: const Icon(Icons.support_agent_rounded),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
        body: SafeArea(
          top: widget.embedded,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Column(
                children: [
                  if (widget.embedded)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          D2FHomeHeader(
                            onBell: widget.onNotifications,
                            onProfile: widget.onProfile,
                            dense: true,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            service == D2FService.buy
                                ? 'Buy For Me / Ship For Me'
                                : service.label,
                            style: TextStyle(
                              color: service.color,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -.8,
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                      ),
                    ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: service == D2FService.marketplace
                          ? const MarketplaceShop()
                          : const BuyForMeShop(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: widget.embedded
          ? null
          : AppBar(
              title: Text(service.label),
              actions: [
                IconButton(
                  onPressed: _contact,
                  tooltip: 'Contact D2F',
                  icon: const Icon(Icons.support_agent_rounded),
                ),
                const SizedBox(width: 8),
              ],
            ),
      body: SafeArea(
        top: widget.embedded,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListView(
              key: PageStorageKey('service-page-${service.name}'),
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
              children: [
                if (widget.embedded) ...[
                  D2FHomeHeader(
                    onBell: widget.onNotifications,
                    onProfile: widget.onProfile,
                    dense: true,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    service == D2FService.buy
                        ? 'Buy For Me / Ship For Me'
                        : service.label,
                    style: TextStyle(
                      color: service.color,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.8,
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                if (service == D2FService.local)
                  ..._local()
                else if (service == D2FService.africa)
                  ..._africa()
                else if (service.isComingSoon)
                  ..._planned(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _notice(String text) => Container(
    margin: const EdgeInsets.only(top: 18),
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: widget.service.tint,
      borderRadius: BorderRadius.circular(15),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.auto_awesome_rounded, color: widget.service.color, size: 18),
        const SizedBox(width: 9),
        Expanded(
          child: Text(text, style: const TextStyle(fontSize: 11, height: 1.6)),
        ),
      ],
    ),
  );

  Widget _contactButton(String label) => Padding(
    padding: const EdgeInsets.only(top: 20),
    child: FilledButton(
      key: const ValueKey('service-contact'),
      onPressed: _contact,
      style: FilledButton.styleFrom(
        backgroundColor: widget.service.color,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
            ),
          ),
          const SizedBox(width: 12),
          const Icon(Icons.arrow_forward_rounded, size: 19),
        ],
      ),
    ),
  );

  List<Widget> _local() => [
    const ServiceHero(
      image: 'shipping',
      eyebrow: 'LOCAL / OMAHA, USA',
      title: 'Across the city.\nCloser to your door.',
      description: 'Pickup and delivery enquiries for homes,\nshops and businesses in the Omaha area.',
      color: Color(0xFF075A76),
    ),
    _notice(
      'Contact D2F to confirm pickup coverage, item requirements and delivery availability. In-app local booking is coming soon.',
    ),
    const SizedBox(height: 24),
    const _SectionHeading(title: 'A helping hand, around town'),
    const SizedBox(height: 12),
    _feature(
      Icons.home_rounded,
      'Home pickups',
      'Discuss collecting parcels from your address.',
    ),
    _feature(
      Icons.storefront_rounded,
      'Store & business deliveries',
      'Ask about moving items between shops, businesses and customers.',
    ),
    _feature(
      Icons.chair_rounded,
      'Larger items',
      'Check handling and transport options before arranging a pickup.',
    ),
    _contactButton('Enquire about Omaha delivery'),
  ];

  List<Widget> _africa() => [
    const ServiceHero(
      image: 'delivery',
      eyebrow: '05 / DELIVERY AFRICA',
      title: 'The last mile.\nA little more local.',
      description: 'From the warehouse to your neighbourhood.\nExplore D2F’s delivery plans for West Africa.',
      color: Color(0xFF0A513C),
    ),
    _notice(
      'Delivery options and coverage must be confirmed by D2F. In-app local delivery booking is coming soon.',
    ),
    const SizedBox(height: 24),
    const _SectionHeading(
      title: 'Where do you need us?',
      subtitle: 'Select a country for your enquiry.',
    ),
    const SizedBox(height: 12),
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final country in ['Togo', 'Benin', 'Ghana', 'Other'])
          ChoiceChip(
            key: ValueKey('delivery-country-$country'),
            label: Text(country),
            selected: _country == country,
            onSelected: (_) => setState(() => _country = country),
            selectedColor: widget.service.tint,
            labelStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
            showCheckmark: false,
          ),
      ],
    ),
    const SizedBox(height: 18),
    _SectionHeading(
      title: _country == 'Other'
          ? 'Let’s explore your destination'
          : 'Delivery enquiries · $_country',
    ),
    const SizedBox(height: 12),
    _feature(
      Icons.delivery_dining_rounded,
      'Local pickup & delivery',
      'Ask about pickups from homes, shops and businesses.',
    ),
    _feature(
      Icons.inventory_2_rounded,
      'Warehouse to door',
      'Find out about forwarding a received parcel to your address.',
    ),
    _feature(
      Icons.anchor_rounded,
      'Port to warehouse',
      'Discuss receiving and transferring your arriving goods.',
    ),
    _feature(
      Icons.storefront_rounded,
      'Business deliveries',
      'Explore delivery arrangements for your customers.',
    ),
    _contactButton(
      'Ask about ${_country == 'Other' ? 'a destination' : 'delivery in $_country'}',
    ),
  ];

  List<Widget> _planned() => [
    Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: widget.service.tint,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ServiceIcon(service: widget.service, size: 58),
          const SizedBox(height: 22),
          Text(widget.service.label, style: AppTheme.display),
          const SizedBox(height: 12),
          const Text(
            'COMING SOON',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 1.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            widget.service == D2FService.business
                ? 'A future space for businesses to reach the D2F community.'
                : 'A future space for eligible jobs and logistics opportunities.',
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textGrey,
              height: 1.7,
            ),
          ),
        ],
      ),
    ),
    _notice(
      'Coming soon · This service is not available for bookings or submissions yet.',
    ),
    _contactButton('Contact D2F'),
  ];

  Widget _feature(IconData icon, String title, String description) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: widget.service.tint,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: widget.service.color, size: 23),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 11,
                    height: 1.6,
                    color: AppColors.textGrey,
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

