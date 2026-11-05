import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../../models/marketplace.dart';
import '../../widgets/auth_widgets.dart';

/// In-app notification center for D2F users.
///
/// Shows marketplace order events, seller lifecycle updates, Buy For Me
/// updates and any other notification D2F sends. Polls for unread counts
/// so the bell badge stays current while the screen is open.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  List<MarketplaceNotification> _notifications = const [];
  bool _loading = true, _failed = false;
  int _unread = 0;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    _startPoll();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _startPoll() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 20), (_) => _refreshCount());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final data = await Api.I.notifications(limit: 50);
      final items = (data['items'] as List?)
          ?.cast<Map<String, dynamic>>()
          .map(MarketplaceNotification.fromJson)
          .toList() ??
          const [];
      final unread = (data['unread'] as num?)?.toInt() ?? 0;
      if (!mounted) return;
      setState(() {
        _notifications = items;
        _unread = unread;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _refreshCount() async {
    try {
      final unread = await Api.I.notificationUnreadCount();
      if (!mounted) return;
      setState(() => _unread = unread);
    } catch (_) {
      // Silently ignore poll failures.
    }
  }

  Future<void> _markRead(String id) async {
    try {
      await Api.I.markNotificationRead(id);
      await _load();
    } catch (_) {
      authMessage(context, 'Could not mark as read. Please try again.');
    }
  }

  Future<void> _markAllRead() async {
    try {
      await Api.I.markAllNotificationsRead();
      await _load();
    } catch (_) {
      authMessage(context, 'Could not mark all as read. Please try again.');
    }
  }

  Future<void> _delete(String id) async {
    try {
      await Api.I.deleteNotification(id);
      await _load();
    } catch (_) {
      authMessage(context, 'Could not delete. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppColors.cream,
        body: Center(child: CircularProgressIndicator(color: AppColors.coral)),
      );
    }
    if (_failed) {
      return Scaffold(
        backgroundColor: AppColors.cream,
        appBar: AppBar(title: const Text('Notifications')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 38, color: AppColors.textGrey),
              const SizedBox(height: 10),
              const Text('Could not load notifications.'),
              const SizedBox(height: 14),
              FilledButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (_notifications.isNotEmpty)
            IconButton(
              tooltip: 'Mark all as read',
              onPressed: _unread == 0 ? null : _markAllRead,
              icon: const Icon(Icons.done_all_rounded),
            ),
        ],
      ),
      body: _notifications.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.notifications_none_rounded, size: 56, color: AppColors.textGrey),
                    SizedBox(height: 14),
                    Text(
                      'No notifications yet',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.navy),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'When D2F has an update for you — an order accepted, an item shipped, a seller application decided — it will appear here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, height: 1.6, color: AppColors.textGrey),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              color: AppColors.coral,
              onRefresh: _load,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
                itemCount: _notifications.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) => _notificationCard(_notifications[index]),
              ),
            ),
    );
  }

  IconData _notificationIcon(String type) => switch (type) {
        'ORDER_REQUESTED' => Icons.request_quote_rounded,
        'ORDER_ACCEPTED' => Icons.check_circle_outline_rounded,
        'ORDER_SHIPPED' => Icons.local_shipping_rounded,
        'ORDER_COMPLETED' => Icons.task_alt_rounded,
        'ORDER_CANCELLED' => Icons.cancel_outlined,
        'SELLER_APPROVED' => Icons.storefront_rounded,
        'SELLER_APPLICATION_UPDATE' => Icons.file_present_rounded,
        'BUY_FOR_ME_UPDATE' => Icons.shopping_bag_rounded,
        _ => Icons.notifications_outlined,
      };

  Color _notificationColor(String type) => switch (type) {
        'ORDER_REQUESTED' => AppColors.blue,
        'ORDER_ACCEPTED' => AppColors.green,
        'ORDER_SHIPPED' => AppColors.blue,
        'ORDER_COMPLETED' => AppColors.green,
        'ORDER_CANCELLED' => AppColors.coral,
        'SELLER_APPROVED' => AppColors.gold,
        'SELLER_APPLICATION_UPDATE' => AppColors.deepPurple,
        'BUY_FOR_ME_UPDATE' => AppColors.deepPurple,
        _ => AppColors.textGrey,
      };

  Widget _notificationCard(MarketplaceNotification n) {
    final icon = _notificationIcon(n.type);
    final color = _notificationColor(n.type);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => !n.read ? _markRead(n.id) : null,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
            color: n.read ? Colors.white : AppColors.blueSoft,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Icon(
                    icon,
                    size: 18,
                    color: color,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            n.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              color: n.read ? AppColors.textGrey : AppColors.navy,
                            ),
                          ),
                        ),
                        if (!n.read)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: AppColors.coral,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    if (n.body != null && n.body!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        n.body!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5, height: 1.5, color: AppColors.textGrey),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          n.typeLabel,
                          style: TextStyle(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w800,
                            color: color,
                            letterSpacing: .6,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _when(n.createdAt),
                          style: const TextStyle(fontSize: 9, color: AppColors.textGrey),
                        ),
                        const Spacer(),
                        InkWell(
                          onTap: () => _delete(n.id),
                          child: const Icon(Icons.close_rounded, size: 16, color: AppColors.textGrey),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _when(DateTime? createdAt) {
    if (createdAt == null) return '—';
    final now = DateTime.now();
    final diff = now.difference(createdAt);
    if (diff.inDays >= 1) return '${diff.inDays}d ago';
    if (diff.inHours >= 1) return '${diff.inHours}h ago';
    if (diff.inMinutes >= 1) return '${diff.inMinutes}m ago';
    return 'Just now';
  }
}
