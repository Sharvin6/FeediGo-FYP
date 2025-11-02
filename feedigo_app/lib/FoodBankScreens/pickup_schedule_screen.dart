import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class PickupScheduleScreen extends StatefulWidget {
  const PickupScheduleScreen({super.key});

  @override
  State<PickupScheduleScreen> createState() => _PickupScheduleScreenState();
}

class _PickupScheduleScreenState extends State<PickupScheduleScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFE26A2C);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(body: Center(child: Text('Not signed in')));
    }

    // Donations assigned to this recipient (food bank).
    final donationsStream =
        FirebaseFirestore.instance
            .collection('donations')
            .where('recipientId', isEqualTo: uid)
            .snapshots();

    // All of THIS user's requests (to derive "Your: ..." per donation).
    final myReqsStream =
        FirebaseFirestore.instance
            .collection('donation_requests')
            .where('recipientId', isEqualTo: uid)
            .snapshots();

    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F7),
      appBar: AppBar(
        backgroundColor: orange,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Pickup Schedule',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: Icon(Icons.calendar_today, color: Colors.white),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: donationsStream,
        builder: (context, snap) {
          if (snap.hasError) return _center('Error: ${snap.error}');
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = (snap.data?.docs ?? []);
          final now = DateTime.now();

          // Build donation list (include approved-only and scheduled)
          final items =
              docs.map((d) => _Donation.wrap(d.id, d.data())).where((x) {
                  final notExpired = x.expiry == null || x.expiry!.isAfter(now);
                  final isCompleted =
                      x.status == 'completed'; // <-- exclude these
                  final isApprovedOrScheduled =
                      x.status == 'approved' ||
                      x.status == 'accepted' ||
                      x.status == 'scheduled';

                  // show approved (with or without time) + scheduled, but NEVER completed
                  return !isCompleted &&
                      notExpired &&
                      (x.pickupTime != null || isApprovedOrScheduled);
                }).toList()
                ..sort((a, b) {
                  final ta = a.pickupTime;
                  final tb = b.pickupTime;
                  if (ta == null && tb == null)
                    return a.title.compareTo(b.title);
                  if (ta == null) return 1;
                  if (tb == null) return -1;
                  return ta.compareTo(tb);
                });

          final completedItems =
              docs
                  .map((d) => _Donation.wrap(d.id, d.data()))
                  .where((x) => x.status == 'completed')
                  .toList()
                ..sort((a, b) {
                  final ta = a.pickupTime;
                  final tb = b.pickupTime;
                  if (ta == null && tb == null)
                    return b.title.compareTo(a.title);
                  if (ta == null) return 1;
                  if (tb == null) return -1;
                  return tb.compareTo(ta); // newest first
                });

          if (items.isEmpty) return const _EmptyState();

          // Second stream: user requests → donationId -> newest personal status
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: myReqsStream,
            builder: (context, reqSnap) {
              final Map<String, String> myStatusByDonation = {};
              if (reqSnap.hasData) {
                // Find the latest status per donationId by timestamp
                final latestTs = <String, DateTime>{};
                for (final doc in reqSnap.data!.docs) {
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
              }

              final today = _day(now);
              final tomorrow = _day(now.add(const Duration(days: 1)));

              final todayItems = items.where(
                (x) => x.pickupTime != null && _day(x.pickupTime!) == today,
              );
              final tomorrowItems = items.where(
                (x) => x.pickupTime != null && _day(x.pickupTime!) == tomorrow,
              );
              final laterItems = items.where(
                (x) =>
                    x.pickupTime != null &&
                    _day(x.pickupTime!) != today &&
                    _day(x.pickupTime!) != tomorrow,
              );
              final unscheduledApproved = items.where(
                (x) => x.pickupTime == null,
              );

              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  if (todayItems.isNotEmpty) ...[
                    _sectionHeader('Today - ${_longDate(now)}'),
                    const SizedBox(height: 8),
                    ...todayItems.map(
                      (x) => _cardFor(
                        x,
                        personalStatus: myStatusByDonation[x.id],
                        allowComplete: x.status != 'completed',
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (tomorrowItems.isNotEmpty) ...[
                    _sectionHeader(
                      'Tomorrow - ${_longDate(now.add(const Duration(days: 1)))}',
                    ),
                    const SizedBox(height: 8),
                    ...tomorrowItems.map(
                      (x) =>
                          _cardFor(x, personalStatus: myStatusByDonation[x.id]),
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (laterItems.isNotEmpty) ...[
                    _sectionHeader('Upcoming'),
                    const SizedBox(height: 8),
                    ...laterItems.map(
                      (x) =>
                          _cardFor(x, personalStatus: myStatusByDonation[x.id]),
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (unscheduledApproved.isNotEmpty) ...[
                    _sectionHeader('Approved (Needs Scheduling)'),
                    const SizedBox(height: 8),
                    ...unscheduledApproved.map(
                      (x) => _cardFor(
                        x,
                        personalStatus: myStatusByDonation[x.id],
                        showScheduleOnly: true,
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  if (completedItems.isNotEmpty) ...[
                    _sectionHeader('Completed'),
                    const SizedBox(height: 8),
                    ...completedItems.map(
                      (x) => _cardFor(
                        x,
                        personalStatus: myStatusByDonation[x.id],
                        allowComplete: false,
                      ),
                    ),
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }

  // ---------- widgets ----------

  Widget _sectionHeader(String t) => Text(
    t,
    style: const TextStyle(
      fontWeight: FontWeight.w800,
      fontSize: 14,
      color: Colors.black87,
    ),
  );

  Widget _cardFor(
    _Donation d, {
    bool allowComplete = false,
    bool showScheduleOnly = false,
    String? personalStatus, // "Your: ..." status
  }) {
    final timeLabel = _rangeLabel(d.pickupTime, d.pickupEndTime);
    final address = d.pickupAddress ?? '';
    final fbName = d.foodBankName ?? '';

    final isApprovedOnly = d.status == 'approved' || d.status == 'accepted';
    final hasSchedule = d.pickupTime != null;
    final canSchedule = (isApprovedOnly || showScheduleOnly) && !hasSchedule;
    final canViewSchedule = hasSchedule;
    final canMarkComplete = allowComplete && d.status == 'scheduled' && !_busy;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
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
          // Title + BOTH status chips
          Row(
            children: [
              Expanded(
                child: Text(
                  d.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
              _StatusChip(status: d.status),
              if (personalStatus != null && personalStatus.isNotEmpty) ...[
                const SizedBox(width: 6),
                _StatusChip(status: personalStatus, personal: true),
              ],
            ],
          ),
          const SizedBox(height: 6),

          if (timeLabel != null)
            Text(timeLabel, style: const TextStyle(color: Colors.black87)),
          if (d.pickupPlace != null && d.pickupPlace!.isNotEmpty)
            Text(d.pickupPlace!, style: const TextStyle(color: Colors.black87)),

          if (fbName.isNotEmpty) ...[
            const SizedBox(height: 4),
            RichText(
              text: TextSpan(
                text: 'For: ',
                style: const TextStyle(color: Colors.black54),
                children: [
                  TextSpan(
                    text: fbName,
                    style: const TextStyle(
                      color: Color(0xFFE26A2C),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 10),

          // Actions
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              _SmallButton.icon(
                icon: Icons.map_outlined,
                label: 'View Map',
                onTap: address.isEmpty ? null : () => _openMaps(address),
              ),
              // Always: donor post details
              _SmallButton(
                label: 'View Donation Post',
                onTap:
                    () => Navigator.pushNamed(
                      context,
                      '/fb_donation_details',
                      arguments: d.id,
                    ),
              ),

              // Only one of these shows at a time:
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
                  onPressed: () {
                    Navigator.pushNamed(
                      context,
                      '/create_pickup_details',
                      arguments: d.id,
                    );
                  },
                ),

              if (canViewSchedule)
                _SmallButton(
                  label: 'View Schedule',
                  onTap:
                      () => Navigator.pushNamed(
                        context,
                        '/pickup_schedule_details',
                        arguments: d.id,
                      ),
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

          if (canMarkComplete) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: 150,
              child: ElevatedButton(
                onPressed: () => _markComplete(d),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE26A2C),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('Mark Complete'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _center(String t) =>
      Center(child: Padding(padding: const EdgeInsets.all(16), child: Text(t)));

  // ---------- actions ----------

  Future<void> _markComplete(_Donation d) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final db = FirebaseFirestore.instance;
      final donationRef = db.collection('donations').doc(d.id);

      final batch = db.batch();
      batch.update(donationRef, {
        'status': 'completed',
        'completedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final acceptedReqId = d.acceptedRequestId;
      if (acceptedReqId != null && acceptedReqId.isNotEmpty) {
        final reqRef = db.collection('donation_requests').doc(acceptedReqId);
        batch.update(reqRef, {
          'status': 'completed',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Marked as completed.')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to complete: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------- utils ----------

  static DateTime? _asDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  static String _longDate(DateTime d) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    final wd = weekdays[d.weekday - 1];
    final m = months[d.month - 1];
    return '$wd, $m ${d.day}, ${d.year}';
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

  static Future<void> _openMaps(String address) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(address)}',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

// ---------- Small button ----------

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

// ---------- Status chip (supports "Your: ..." variant) ----------

class _StatusChip extends StatelessWidget {
  final String status;
  final bool personal; // when true -> prefix with "Your: ..."
  const _StatusChip({required this.status, this.personal = false});

  @override
  Widget build(BuildContext context) {
    final s = status.toLowerCase();
    Color bg, fg;
    String label;

    if (s == 'accepted') {
      bg = const Color(0xFFE6F6EA);
      fg = const Color(0xFF2E7D32);
      label = personal ? 'Your: Accepted' : 'Approved';
    } else if (s == 'completed') {
      bg = const Color(0xFFE8EAF6);
      fg = const Color(0xFF3F51B5);
      label = personal ? 'Your: Completed' : 'Completed';
    } else if (s == 'declined') {
      bg = const Color(0xFFFFEBEE);
      fg = const Color(0xFFC62828);
      label = personal ? 'Your: Rejected' : 'Rejected';
    } else if (s == 'scheduled') {
      bg = const Color(0xFFE3F2FD);
      fg = const Color(0xFF0277BD);
      label = personal ? 'Your: Scheduled' : 'Scheduled';
    } else if (s == 'requested') {
      bg = const Color(0xFFFFF4E5);
      fg = const Color(0xFFEF6C00);
      label = personal ? 'Your: Requested' : 'Requested';
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

// ---------- Model wrapper ----------

class _Donation {
  final String id;
  final String title;
  final String status;
  final String? foodBankName;
  final String? pickupAddress;
  final String? pickupPlace;
  final DateTime? pickupTime;
  final DateTime? pickupEndTime;
  final DateTime? expiry;
  final String? acceptedRequestId;

  _Donation({
    required this.id,
    required this.title,
    required this.status,
    this.foodBankName,
    this.pickupAddress,
    this.pickupPlace,
    this.pickupTime,
    this.pickupEndTime,
    this.expiry,
    this.acceptedRequestId,
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
      foodBankName:
          (d['foodBankName'] ?? d['organizationName'] ?? '').toString(),
      pickupAddress: (pickup['address'] ?? '').toString(),
      pickupPlace: (pickup['place'] ?? pickup['locationName'] ?? '').toString(),
      pickupTime: _asDate(pickup['time']),
      pickupEndTime: _asDate(pickup['endTime']),
      expiry: _asDate(d['expiryAt']),
      acceptedRequestId:
          (d['acceptedRequestId'] ?? '').toString().isEmpty
              ? null
              : (d['acceptedRequestId'] as String),
    );
  }
}

// ---------- Empty state ----------

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.event_busy, size: 48, color: Colors.black45),
            SizedBox(height: 12),
            Text(
              'No pickups scheduled',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 6),
            Text(
              'Accepted pickups with or without time will appear here.',
              style: TextStyle(color: Colors.black54),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
