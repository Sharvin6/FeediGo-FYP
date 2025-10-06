import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class FoodBankDashboardScreen extends StatelessWidget {
  const FoodBankDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFE26A2C);
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      return const Scaffold(body: Center(child: Text('Not signed in')));
    }

    // Streams we’ll use
    final requestsStream =
        FirebaseFirestore.instance
            .collection('donation_requests')
            .where('recipientId', isEqualTo: uid)
            .snapshots();

    final acceptedDonationsStream =
        FirebaseFirestore.instance
            .collection('donations')
            .where('recipientId', isEqualTo: uid)
            .snapshots();

    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F7),
      appBar: AppBar(
        backgroundColor: orange,
        elevation: 0,
        title: const Text(
          'Food Bank Dashboard',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            onPressed: () {
              Navigator.pushNamed(context, '/settings_screen');
            },
          ),
        ],
      ),
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: requestsStream,
          builder: (context, reqSnap) {
            if (reqSnap.hasError) {
              return _errorBox('Error loading requests: ${reqSnap.error}');
            }
            if (reqSnap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            // Count pending requests
            final pendingRequests =
                (reqSnap.data?.docs ?? [])
                    .where(
                      (d) => (d.data()['status'] ?? 'pending') == 'pending',
                    )
                    .length;

            // Build "Your:" status map (latest per donationId)
            final Map<String, String> myStatusByDonation = {};
            final Map<String, DateTime> latestTs = {};
            for (final doc in (reqSnap.data?.docs ?? [])) {
              final m = doc.data();
              final did = (m['donationId'] ?? '').toString();
              final st = (m['status'] ?? '').toString();
              final ts =
                  _asDate(m['updatedAt']) ??
                  _asDate(m['createdAt']) ??
                  DateTime.fromMillisecondsSinceEpoch(0);
              final prev = latestTs[did];
              if (prev == null || ts.isAfter(prev)) {
                latestTs[did] = ts;
                myStatusByDonation[did] = st;
              }
            }

            // Nest the accepted donations stream
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: acceptedDonationsStream,
              builder: (context, donSnap) {
                if (donSnap.hasError) {
                  return _errorBox(
                    'Error loading accepted donations: ${donSnap.error}',
                  );
                }
                if (donSnap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final acceptedDocs = (donSnap.data?.docs ?? []).toList();

                // Approved = accepted/scheduled (not completed yet)
                final approvedDonations =
                    acceptedDocs.where((d) {
                      final s =
                          ((d.data()['status'] ?? 'pending') as String)
                              .toString();
                      return s == 'accepted' || s == 'scheduled';
                    }).length;

                // Total meals = sum(servings) for completed
                final totalMeals = acceptedDocs.fold<int>(0, (acc, d) {
                  final data = d.data();
                  final status = (data['status'] ?? 'pending') as String;
                  if (status == 'completed') {
                    return acc + ((data['servings'] as int?) ?? 1);
                  }
                  return acc;
                });

                // Build schedule list like in PickupSchedule: accepted/scheduled/completed
                final schedule =
                    acceptedDocs
                        .where((d) {
                          final s =
                              ((d.data()['status'] ?? 'pending') as String)
                                  .toString();
                          return s == 'accepted' || s == 'scheduled';
                        })
                        .map((doc) => _Donation.wrap(doc.id, doc.data()))
                        .toList()
                      ..sort((a, b) {
                        // Sort by pickup time (scheduled first), then title.
                        final ta = a.pickupTime;
                        final tb = b.pickupTime;
                        if (ta == null && tb == null) {
                          return a.title.compareTo(b.title);
                        } else if (ta == null) {
                          return 1;
                        } else if (tb == null) {
                          return -1;
                        }
                        return ta.compareTo(tb);
                      });

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    _OverviewCard(
                      pending: pendingRequests,
                      approved: approvedDonations,
                      meals: totalMeals,
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed:
                            () => Navigator.pushNamed(context, '/request_food'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: orange,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.add_circle_outline),
                        label: const Text('Request Food'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed:
                            () => Navigator.pushNamed(
                              context,
                              '/request_history',
                            ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: orange,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.history),
                        label: const Text('Request History'),
                      ),
                    ),
                    const SizedBox(height: 16),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Pickup Schedule',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        TextButton(
                          onPressed:
                              () => Navigator.pushNamed(
                                context,
                                '/pickup_schedule',
                              ),
                          child: const Text('View All'),
                        ),
                      ],
                    ),

                    if (schedule.isEmpty)
                      _EmptySchedule(
                        onBrowse:
                            () => Navigator.pushNamed(context, '/request_food'),
                      )
                    else
                      ...schedule
                          .take(3) // show only top 3
                          .map(
                            (d) => _ScheduleTile(
                              model: d,
                              personalStatus: myStatusByDonation[d.id],
                              onViewMap: () {
                                final addr = d.pickupAddress ?? '';
                                if (addr.isNotEmpty) _openMaps(addr);
                              },
                              onViewPost:
                                  () => Navigator.pushNamed(
                                    context,
                                    '/fb_donation_details',
                                    arguments: d.id,
                                  ),
                              onSchedule:
                                  () => Navigator.pushNamed(
                                    context,
                                    '/create_pickup_details',
                                    arguments: d.id,
                                  ),
                              onViewSchedule:
                                  () => Navigator.pushNamed(
                                    context,
                                    '/pickup_schedule_details',
                                    arguments: d.id,
                                  ),
                              onConfirmPickup: () {
                                Navigator.pushNamed(
                                  context,
                                  '/confirm_pickup',
                                  arguments: d.id, // pass donationId
                                );
                              },
                            ),
                          ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  static Widget _errorBox(String msg) => Center(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Text(msg, textAlign: TextAlign.center),
    ),
  );

  static DateTime? _asDate(dynamic ts) {
    if (ts is Timestamp) return ts.toDate();
    if (ts is DateTime) return ts;
    return null;
  }

  /// Opens Google Maps. Uses `geo:` on Android, falls back to HTTPS Maps URL, then in-app.
  static Future<void> _openMaps(String address) async {
    final trimmed = address.trim();
    if (trimmed.isEmpty) return;

    final encoded = Uri.encodeComponent(trimmed);
    final geo = Uri.parse('geo:0,0?q=$encoded');
    final https = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$encoded',
    );

    if (Platform.isAndroid && await canLaunchUrl(geo)) {
      await launchUrl(geo, mode: LaunchMode.externalApplication);
      return;
    }

    if (await canLaunchUrl(https)) {
      await launchUrl(https, mode: LaunchMode.externalApplication);
      return;
    }

    // Last resort: open in in-app webview
    await launchUrl(https, mode: LaunchMode.inAppBrowserView);
  }

  Future<bool?> _confirm(
    BuildContext context, {
    required String title,
    required String message,
  }) {
    return showDialog<bool>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Confirm'),
              ),
            ],
          ),
    );
  }
}

// ----------------------- Widgets -----------------------

class _OverviewCard extends StatelessWidget {
  final int pending;
  final int approved;
  final int meals;

  const _OverviewCard({
    required this.pending,
    required this.approved,
    required this.meals,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          _stat('Pending Requests', pending),
          _divider(),
          _stat('Approved Donations', approved),
          _divider(),
          _stat('Total Meals Distributed', meals),
        ],
      ),
    );
  }

  Widget _divider() => Container(
    width: 1,
    height: 42,
    margin: const EdgeInsets.symmetric(horizontal: 10),
    color: Colors.black12,
  );

  Widget _stat(String label, int value) => Expanded(
    child: Column(
      children: [
        Text(
          '$value',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.black54, fontSize: 12),
        ),
      ],
    ),
  );
}

class _ScheduleTile extends StatelessWidget {
  final _Donation model;
  final String? personalStatus;

  final VoidCallback onViewMap;
  final VoidCallback onViewPost;
  final VoidCallback onSchedule;
  final VoidCallback onViewSchedule;
  final VoidCallback onConfirmPickup;

  const _ScheduleTile({
    required this.model,
    required this.personalStatus,
    required this.onViewMap,
    required this.onViewPost,
    required this.onSchedule,
    required this.onViewSchedule,
    required this.onConfirmPickup,
  });

  @override
  Widget build(BuildContext context) {
    final d = model;
    final address = d.pickupAddress ?? '';

    final isApprovedOnly = d.status == 'approved' || d.status == 'accepted';
    final hasSchedule = d.pickupTime != null;
    final canSchedule = (isApprovedOnly) && !hasSchedule;
    final canViewSchedule = hasSchedule;
    final canConfirm = d.status == 'scheduled'; // show Confirm Pickup

    final timeLabel = _rangeLabel(d.pickupTime, d.pickupEndTime);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title + status chips
          Row(
            children: [
              Expanded(
                child: Text(
                  d.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
              _StatusChip(status: d.status),
              if (personalStatus != null && personalStatus!.isNotEmpty) ...[
                const SizedBox(width: 6),
                _StatusChip(status: personalStatus!, personal: true),
              ],
            ],
          ),
          const SizedBox(height: 8),

          if (timeLabel != null)
            Text(timeLabel, style: const TextStyle(color: Colors.black87)),
          if (address.isNotEmpty)
            Text(
              address,
              style: const TextStyle(fontSize: 13, color: Colors.black87),
            ),

          const SizedBox(height: 10),

          // Actions (mirrors PickupSchedule card)
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              _SmallButton.icon(
                icon: Icons.map_outlined,
                label: 'View Map',
                onTap: address.isEmpty ? null : onViewMap,
              ),
              _SmallButton(label: 'View Donation Post', onTap: onViewPost),
              if (canSchedule)
                ElevatedButton.icon(
                  icon: const Icon(Icons.event_available),
                  label: const Text('Schedule Pickup'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: onSchedule,
                ),
              if (canViewSchedule)
                _SmallButton(label: 'View Schedule', onTap: onViewSchedule),
              if (canConfirm)
                ElevatedButton.icon(
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Confirm Pickup'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: onConfirmPickup,
                ),
            ],
          ),

          if (canSchedule) ...[
            const SizedBox(height: 6),
            const Text(
              'Approved – waiting to be scheduled',
              style: TextStyle(color: Colors.black54, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  static String? _rangeLabel(DateTime? start, DateTime? end) {
    if (start == null) return null;
    final s = _timeLabel(start);
    if (end == null) return s;
    return '$s - ${_timeLabel(end)}';
  }

  static String _timeLabel(DateTime d) {
    final hh = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final mm = d.minute.toString().padLeft(2, '0');
    final ap = d.hour >= 12 ? 'PM' : 'AM';
    return '$hh:$mm $ap';
  }
}

class _SmallButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;

  const _SmallButton({required this.label, this.onTap}) : icon = null;
  const _SmallButton.icon({
    required this.icon,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 16), const SizedBox(width: 6)],
        Text(label),
      ],
    );

    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: child,
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  final bool personal; // supports "Your: ..."
  const _StatusChip({required this.status, this.personal = false});

  @override
  Widget build(BuildContext context) {
    final s = status.toLowerCase();
    Color bg, fg;
    String label;
    if (s == 'approved' || s == 'accepted') {
      bg = const Color(0xFFE6F6EA);
      fg = const Color(0xFF2E7D32);
      label = personal ? 'Your: Accepted' : 'Approved';
    } else if (s == 'scheduled') {
      bg = const Color(0xFFE3F2FD);
      fg = const Color(0xFF0277BD);
      label = personal ? 'Your: Scheduled' : 'Scheduled';
    } else if (s == 'completed') {
      bg = const Color(0xFFE8EAF6);
      fg = const Color(0xFF3F51B5);
      label = personal ? 'Your: Completed' : 'Completed';
    } else if (s == 'requested') {
      bg = const Color(0xFFFFF4E5);
      fg = const Color(0xFFEF6C00);
      label = personal ? 'Your: Requested' : 'Requested';
    } else if (s == 'rejected' || s == 'cancelled' || s == 'declined') {
      bg = const Color(0xFFFFEBEE);
      fg = const Color(0xFFC62828);
      label = personal ? 'Your: Rejected' : 'Rejected';
    } else {
      bg = const Color(0xFFFFF4E5);
      fg = const Color(0xFFEF6C00);
      label = personal ? 'Your: Pending' : 'Pending';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }
}

// ----------------------- Model -----------------------

class _Donation {
  final String id;
  final String title;
  final String status;
  final String? pickupAddress;
  final String? pickupPlace;
  final DateTime? pickupTime;
  final DateTime? pickupEndTime;
  final DateTime? expiry;

  _Donation({
    required this.id,
    required this.title,
    required this.status,
    this.pickupAddress,
    this.pickupPlace,
    this.pickupTime,
    this.pickupEndTime,
    this.expiry,
  });

  static _Donation wrap(String id, Map<String, dynamic> d) {
    DateTime? _asDate(dynamic v) {
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      return null;
    }

    final pickup = (d['pickupInfo'] as Map?) ?? {};
    return _Donation(
      id: id,
      title: (d['title'] ?? d['foodName'] ?? 'Donation').toString(),
      status: (d['status'] ?? 'pending').toString().toLowerCase(),
      pickupAddress: (pickup['address'] ?? '').toString(),
      pickupPlace: (pickup['place'] ?? pickup['locationName'] ?? '').toString(),
      pickupTime: _asDate(pickup['time']),
      pickupEndTime: _asDate(pickup['endTime']),
      expiry: _asDate(d['expiryAt']),
    );
  }
}

class _EmptySchedule extends StatelessWidget {
  final VoidCallback onBrowse;
  const _EmptySchedule({required this.onBrowse});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.event_busy, size: 48, color: Colors.black45),
            const SizedBox(height: 10),
            const Text(
              'No pickups scheduled yet',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'Browse donations and request food to schedule a pickup.',
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onBrowse,
              icon: const Icon(Icons.add),
              label: const Text('Request Food'),
            ),
          ],
        ),
      ),
    );
  }
}
