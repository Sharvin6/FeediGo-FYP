import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class AvailableDonationsScreen extends StatefulWidget {
  const AvailableDonationsScreen({super.key});

  @override
  State<AvailableDonationsScreen> createState() =>
      _AvailableDonationsScreenState();
}

class _AvailableDonationsScreenState extends State<AvailableDonationsScreen> {
  String? _foodTypeFilter; // e.g. 'cooked', 'produce', ...

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFE26A2C);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(body: Center(child: Text('Not signed in')));
    }

    // Base query (category filter applied here so indexes stay small)
    Query<Map<String, dynamic>> baseQuery = FirebaseFirestore.instance
        .collection('donations');
    if (_foodTypeFilter != null && _foodTypeFilter!.isNotEmpty) {
      baseQuery = baseQuery.where('category', isEqualTo: _foodTypeFilter);
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F7),
      appBar: AppBar(
        backgroundColor: orange,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Available Donations',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
      body: Column(
        children: [
          _FilterBar(
            value: _foodTypeFilter,
            onChanged: (v) => setState(() => _foodTypeFilter = v),
          ),

          // 1) Stream THIS user's requests first
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream:
                  FirebaseFirestore.instance
                      .collection('donation_requests')
                      .where('recipientId', isEqualTo: uid)
                      .snapshots(),
              builder: (context, myReqSnap) {
                // Build a map: donationId -> newest {status, ts}
                final Map<String, Map<String, dynamic>> myReqByDonation = {};
                for (final d in (myReqSnap.data?.docs ?? [])) {
                  final m = d.data();
                  final did = (m['donationId'] ?? '').toString();
                  final status = (m['status'] ?? '').toString().toLowerCase();
                  final ts =
                      _asDate(m['updatedAt']) ??
                      _asDate(m['createdAt']) ??
                      DateTime.fromMillisecondsSinceEpoch(0);
                  final prev = myReqByDonation[did];
                  if (prev == null || ts.isAfter(prev['ts'] as DateTime)) {
                    myReqByDonation[did] = {'status': status, 'ts': ts};
                  }
                }

                // 2) Stream donations and filter using both sources
                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: baseQuery.snapshots(),
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return _errorBox('Error: ${snap.error}');
                    }
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final now = DateTime.now();

                    final docs =
                        (snap.data?.docs ?? []).where((d) {
                            final data = d.data();
                            final global =
                                (data['status'] as String?)?.toLowerCase() ??
                                'pending';
                            final expiry =
                                _asDate(data['expiryAt']) ?? DateTime(2100);
                            if (!expiry.isAfter(now)) return false;

                            // Hide globally unavailable statuses
                            if (global == 'accepted' ||
                                global == 'completed' ||
                                global == 'scheduled') {
                              return false;
                            }

                            final my =
                                myReqByDonation[d.id]?['status'] as String?;
                            final iRequestedThis = my != null;

                            // Keep if globally pending
                            if (global == 'pending') return true;

                            // Also keep if I requested AND mine is not accepted
                            if (iRequestedThis && my != 'accepted') return true;

                            return false;
                          }).toList()
                          ..sort((a, b) {
                            final ea =
                                _asDate(a.data()['expiryAt']) ?? DateTime(2100);
                            final eb =
                                _asDate(b.data()['expiryAt']) ?? DateTime(2100);
                            return ea.compareTo(eb);
                          });

                    if (docs.isEmpty) return const _EmptyState();

                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      itemCount: docs.length,
                      itemBuilder: (_, i) {
                        final doc = docs[i];
                        final myStatus =
                            myReqByDonation[doc.id]?['status'] as String?;
                        return _DonationCard(
                          id: doc.id,
                          data: doc.data(),
                          personalStatus: myStatus, // shows "Your: …"
                          onDetails:
                              () => Navigator.pushNamed(
                                context,
                                '/fb_donation_details',
                                arguments: doc.id,
                              ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ---------- helpers ----------
  static DateTime? _asDate(dynamic ts) {
    if (ts is Timestamp) return ts.toDate();
    if (ts is DateTime) return ts;
    return null;
  }

  Widget _errorBox(String msg) => Center(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Text(msg, textAlign: TextAlign.center),
    ),
  );
}

// ------------------------ UI pieces ------------------------

class _FilterBar extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;

  const _FilterBar({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF3F5F7),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(
        children: [
          const Text(
            'Food Type:',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButtonFormField<String>(
              value: value?.isEmpty ?? true ? null : value,
              isExpanded: true,
              items: const [
                DropdownMenuItem(value: '', child: Text('All')),
                DropdownMenuItem(value: 'cooked', child: Text('Cooked Meals')),
                DropdownMenuItem(
                  value: 'produce',
                  child: Text('Fresh Produce'),
                ),
                DropdownMenuItem(value: 'bakery', child: Text('Bakery')),
                DropdownMenuItem(
                  value: 'packaged',
                  child: Text('Packaged/Canned'),
                ),
                DropdownMenuItem(value: 'beverage', child: Text('Beverage')),
                DropdownMenuItem(
                  value: 'frozen',
                  child: Text('Frozen/Chilled'),
                ),
                DropdownMenuItem(value: 'dry', child: Text('Dry Goods')),
              ],
              onChanged: (v) => onChanged(v == '' ? null : v),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DonationCard extends StatelessWidget {
  final String id;
  final Map<String, dynamic> data;
  final String? personalStatus; // current user's request status, if any
  final VoidCallback onDetails;

  const _DonationCard({
    required this.id,
    required this.data,
    required this.onDetails,
    this.personalStatus,
  });

  @override
  Widget build(BuildContext context) {
    final title = (data['title'] ?? data['foodName'] ?? 'Donation') as String;
    final status = ((data['status'] ?? 'pending') as String).toLowerCase();
    final qty = (data['quantity'] ?? '') as String;
    final typeLabel = (data['foodTypeLabel'] ?? '') as String;
    final expiry = _asDate(data['expiryAt']);
    final address = (data['pickupInfo']?['address'] ?? '') as String;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title + chips
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _StatusChip(status: status), // global
                const SizedBox(width: 6),
                if (personalStatus != null && personalStatus!.isNotEmpty)
                  _StatusChip(
                    status: personalStatus!,
                    personal: true, // "Your: ..."
                  ),
              ],
            ),
            const SizedBox(height: 6),

            // Chips: type, qty, expiry
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 6,
              children: [
                if (typeLabel.isNotEmpty)
                  _chip(Icons.restaurant_menu, typeLabel),
                if (qty.isNotEmpty) _chip(Icons.scale, qty),
                if (expiry != null) _chip(Icons.schedule, _expiryLabel(expiry)),
              ],
            ),
            const SizedBox(height: 10),

            // Pickup address only (no time)
            if (address.isNotEmpty)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.pin_drop_outlined, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      address,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),

            const SizedBox(height: 12),

            // Actions → only View Details
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onDetails,
                    child: const Text('View Details'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static DateTime? _asDate(dynamic ts) {
    if (ts is Timestamp) return ts.toDate();
    if (ts is DateTime) return ts;
    return null;
  }

  static Widget _chip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F5F7),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.black54),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(fontSize: 12, color: Colors.black87),
          ),
        ],
      ),
    );
  }

  static String _expiryLabel(DateTime d) {
    final now = DateTime.now();
    final isToday =
        d.year == now.year && d.month == now.month && d.day == now.day;
    if (isToday) return 'Expires today';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[d.month - 1]} ${d.day.toString().padLeft(2, '0')}';
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  final bool personal; // when true -> "Your: ..." labels
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
    } else if (s == 'requested') {
      bg = const Color(0xFFFFF4E5);
      fg = const Color(0xFFEF6C00);
      label = personal ? 'Your: Requested' : 'Requested';
    } else if (s == 'scheduled') {
      bg = const Color(0xFFE3F2FD);
      fg = const Color(0xFF0277BD);
      label = personal ? 'Your: Scheduled' : 'Scheduled';
    } else {
      // pending or unknown
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
        style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 12),
      ),
    );
  }
}

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
            Icon(Icons.inbox_outlined, size: 48, color: Colors.black45),
            SizedBox(height: 12),
            Text(
              'No available donations right now',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 6),
            Text(
              'Check back later or adjust your filters.',
              style: TextStyle(color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}
