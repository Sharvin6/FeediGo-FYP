// lib/screens/beneficiary_request_history_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class BeneficiaryRequestHistoryScreen extends StatelessWidget {
  const BeneficiaryRequestHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFE26A2C);
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      return const Scaffold(body: Center(child: Text('Not signed in')));
    }

    // All requests by this recipient (order on server)
    final requestsQuery = FirebaseFirestore.instance
        .collection('donation_requests')
        .where('recipientId', isEqualTo: uid)
        .orderBy('createdAt', descending: true);

    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F7),
      appBar: AppBar(
        backgroundColor: orange,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Request History',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: requestsQuery.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final reqDocs = (snap.data?.docs ?? []);
          if (reqDocs.isEmpty) return const _EmptyState();

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: reqDocs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final req = reqDocs[i].data();
              final donationId = (req['donationId'] as String?) ?? '';
              if (donationId.isEmpty) return const SizedBox.shrink();

              // Pull donation for richer card content + global status
              return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                future:
                    FirebaseFirestore.instance
                        .collection('donations')
                        .doc(donationId)
                        .get(),
                builder: (context, donationSnap) {
                  final loading =
                      donationSnap.connectionState == ConnectionState.waiting;
                  final donation =
                      (donationSnap.data?.data() ?? <String, dynamic>{});

                  return _RequestCard(
                    isLoading: loading && !donationSnap.hasData,
                    donationId: donationId,
                    requestData: req,
                    donationData: donation,
                    onViewDetails: () {
                      Navigator.pushNamed(
                        context,
                        '/beneficiary_donation_details',
                        arguments: donationId,
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

/// ---------- Card widget ----------
class _RequestCard extends StatelessWidget {
  final bool isLoading;
  final String donationId;
  final Map<String, dynamic> requestData;
  final Map<String, dynamic> donationData;
  final VoidCallback onViewDetails;

  const _RequestCard({
    required this.isLoading,
    required this.donationId,
    required this.requestData,
    required this.donationData,
    required this.onViewDetails,
  });

  @override
  Widget build(BuildContext context) {
    const chipGap = SizedBox(height: 8);

    // Personal (this request) status
    final personalStatus =
        (requestData['status'] as String? ?? 'pending').toLowerCase();

    // Global donation status
    final globalStatus =
        (donationData['status'] as String? ?? 'pending').toLowerCase();

    // Map donation fields
    final title =
        (donationData['title'] ?? donationData['foodName'] ?? 'Donation')
            as String;
    final quantity = (donationData['quantity'] ?? '') as String;
    final expiry = _dateLabel(donationData['expiryAt']);
    final location =
        (donationData['pickupInfo'] is Map &&
                donationData['pickupInfo']['address'] != null)
            ? donationData['pickupInfo']['address'] as String
            : '';
    final donor =
        (donationData['donorName'] ?? donationData['organizationName'] ?? '')
            as String;

    return Container(
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
          // Title + chips
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
              Wrap(
                spacing: 6,
                children: [
                  _StatusChip(status: globalStatus), // global
                  _StatusChip(status: personalStatus, personal: true), // yours
                ],
              ),
            ],
          ),
          chipGap,
          if (quantity.isNotEmpty) _iconLine(Icons.restaurant, quantity),
          if (expiry != null) ...[
            const SizedBox(height: 6),
            _iconLine(Icons.calendar_today, expiry),
          ],
          if (location.isNotEmpty) ...[
            const SizedBox(height: 6),
            _iconLine(Icons.place_outlined, location),
          ],
          if (donor.isNotEmpty) ...[
            const SizedBox(height: 6),
            _iconLine(Icons.account_circle_outlined, donor),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton(
              onPressed: isLoading ? null : onViewDetails,
              child: const Text('View Details'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _iconLine(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.black54),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: const TextStyle(color: Colors.black87)),
        ),
      ],
    );
  }

  String? _dateLabel(dynamic ts) {
    if (ts is! Timestamp) return null;
    final d = ts.toDate();
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
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }
}

/// ---------- Status chip ----------
class _StatusChip extends StatelessWidget {
  final String status;
  final bool personal; // when true → "Your: …"
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
    } else if (s == 'completed') {
      bg = const Color(0xFFE8EAF6);
      fg = const Color(0xFF3F51B5);
      label = personal ? 'Your: Completed' : 'Completed';
    } else if (s == 'rejected' || s == 'declined' || s == 'cancelled') {
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

/// ---------- Empty state ----------
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.history_toggle_off, size: 48, color: Colors.black45),
            SizedBox(height: 12),
            Text(
              'No requests yet',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 6),
            Text(
              'When you request a donation, it will appear here.',
              style: TextStyle(color: Colors.black54),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
