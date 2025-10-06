// lib/screens/beneficiary_donation_details_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class BeneficiaryDonationDetailsScreen extends StatefulWidget {
  const BeneficiaryDonationDetailsScreen({super.key});

  @override
  State<BeneficiaryDonationDetailsScreen> createState() =>
      _BeneficiaryDonationDetailsScreenState();
}

class _BeneficiaryDonationDetailsScreenState
    extends State<BeneficiaryDonationDetailsScreen> {
  late final String donationId;
  final String? uid = FirebaseAuth.instance.currentUser?.uid;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    donationId = (ModalRoute.of(context)?.settings.arguments as String?) ?? '';
  }

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFE26A2C);
    if (donationId.isEmpty || uid == null) {
      return const Scaffold(body: Center(child: Text('Invalid donation')));
    }

    final donationRef = FirebaseFirestore.instance
        .collection('donations')
        .doc(donationId);

    final donationStream = donationRef.snapshots();
    final myReqStream =
        FirebaseFirestore.instance
            .collection('donation_requests')
            .where('donationId', isEqualTo: donationId)
            .where('recipientId', isEqualTo: uid)
            .limit(1)
            .snapshots();

    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F7),
      appBar: AppBar(
        backgroundColor: orange,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Donation Details',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: donationStream,
          builder: (context, snap) {
            if (snap.hasError) {
              return _center('Error: ${snap.error}');
            }
            if (!snap.hasData || !snap.data!.exists) {
              return const Center(child: CircularProgressIndicator());
            }
            final d = snap.data!.data()!;
            final title = (d['title'] ?? d['foodName'] ?? 'Donation') as String;
            final qty = (d['quantity'] ?? '') as String;
            final photoUrl = d['photoUrl'] as String?;
            final status = (d['status'] ?? 'pending') as String; // GLOBAL
            final desc = (d['description'] ?? '') as String;
            final type = (d['foodTypeLabel'] ?? '') as String;
            final donorId = (d['donorId'] ?? '') as String;

            final expiry = _asDate(d['expiryAt']);
            final pickupAddr = (d['pickupInfo']?['address'] ?? '') as String;

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: myReqStream,
              builder: (context, reqSnap) {
                final hasReq = (reqSnap.data?.docs ?? []).isNotEmpty;
                final reqDoc = hasReq ? reqSnap.data!.docs.first : null;
                final reqStatus =
                    hasReq
                        ? (reqDoc!.data()['status'] as String? ?? 'pending')
                        : null; // PERSONAL

                final canRequest = status == 'pending' && !hasReq;
                final canCancel = hasReq && reqStatus == 'pending';

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    _heroCard(
                      title: title,
                      qty: qty,
                      globalStatus: status,
                      personalStatus: reqStatus, // personal
                      type: type,
                      photoUrl: photoUrl,
                      createdAt: _asDate(d['createdAt']),
                    ),
                    const SizedBox(height: 12),

                    _sectionCard('Donation Details', [
                      _iconRow(
                        Icons.schedule,
                        'Expiry Date',
                        _expiryLabel(expiry),
                      ),
                      _iconRow(
                        Icons.place_outlined,
                        'Pickup Location',
                        pickupAddr.isEmpty ? '-' : pickupAddr,
                        onTap: () => _openMaps(pickupAddr),
                      ),
                    ]),
                    const SizedBox(height: 12),

                    if (desc.isNotEmpty)
                      _sectionCard('Description', [
                        Text(desc, style: const TextStyle(fontSize: 14)),
                      ]),
                    if (desc.isNotEmpty) const SizedBox(height: 12),

                    _sectionCard('Location Map', [
                      _mapStub(onTap: () => _openMaps(pickupAddr)),
                      const SizedBox(height: 6),
                      Center(
                        child: TextButton.icon(
                          onPressed: () => _openMaps(pickupAddr),
                          icon: const Icon(Icons.directions),
                          label: const Text('Tap to open in Google Maps'),
                          style: TextButton.styleFrom(foregroundColor: orange),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 12),

                    _DonorInfo(donorId: donorId, buildSection: _sectionCard),
                    const SizedBox(height: 16),

                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed:
                                (!canRequest || _busy) ? null : _requestPickup,
                            icon: const Icon(Icons.check_circle_outline),
                            label: const Text('Request Pickup'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed:
                                (!canCancel || _busy)
                                    ? null
                                    : () => _cancelRequest(reqDoc!.id),
                            icon: const Icon(Icons.close),
                            label: const Text('Cancel Request'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (hasReq) ...[
                      const SizedBox(height: 8),
                      Center(
                        child: Text(
                          'Your request: ${reqStatus!.toUpperCase()}',
                          style: const TextStyle(
                            color: Colors.black54,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  // ---------- actions ----------
  Future<void> _requestPickup() async {
    if (_busy || uid == null) return;
    setState(() => _busy = true);
    try {
      final reqs = FirebaseFirestore.instance.collection('donation_requests');
      final donationRef = FirebaseFirestore.instance
          .collection('donations')
          .doc(donationId);

      // prevent duplicates
      final dup =
          await reqs
              .where('donationId', isEqualTo: donationId)
              .where('recipientId', isEqualTo: uid)
              .limit(1)
              .get();

      if (dup.docs.isNotEmpty) {
        _snack('You already requested this donation.');
      } else {
        final doc = await reqs.add({
          'donationId': donationId,
          'recipientId': uid,
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
        });

        await donationRef.update({
          'status': 'requested',
          'updatedAt': FieldValue.serverTimestamp(),
          'lastRequestId': doc.id,
        });

        _snack('Request sent! Waiting for donor approval.');
      }
    } catch (_) {
      _snack('Failed to send request. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelRequest(String requestId) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final donationRef = FirebaseFirestore.instance
          .collection('donations')
          .doc(donationId);

      // delete request
      await FirebaseFirestore.instance
          .collection('donation_requests')
          .doc(requestId)
          .delete();

      // check if any requests left
      final remaining =
          await FirebaseFirestore.instance
              .collection('donation_requests')
              .where('donationId', isEqualTo: donationId)
              .where('status', isEqualTo: 'pending')
              .limit(1)
              .get();

      if (remaining.docs.isEmpty) {
        await donationRef.update({
          'status': 'pending',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      _snack('Request cancelled.');
    } catch (_) {
      _snack('Failed to cancel request.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------- helpers ----------
  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  static DateTime? _asDate(dynamic ts) {
    if (ts is Timestamp) return ts.toDate();
    if (ts is DateTime) return ts;
    return null;
  }

  static String _expiryLabel(DateTime? d) {
    if (d == null) return '-';
    final now = DateTime.now();
    final today =
        d.year == now.year && d.month == now.month && d.day == now.day;
    if (today) return 'Today';
    const m = [
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
    return '${m[d.month - 1]} ${d.day.toString().padLeft(2, '0')}';
  }

  static Future<void> _openMaps(String address) async {
    if (address.isEmpty) return;
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(address)}',
    );
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not launch Maps');
    }
  }

  Widget _center(String t) =>
      Center(child: Padding(padding: const EdgeInsets.all(16), child: Text(t)));

  Widget _heroCard({
    required String title,
    required String qty,
    required String globalStatus,
    required String? personalStatus,
    required String type,
    required String? photoUrl,
    required DateTime? createdAt,
  }) {
    return Container(
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
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Wrap(
                spacing: 6,
                children: [
                  _statusChip(globalStatus), // global
                  if (personalStatus != null && personalStatus.isNotEmpty)
                    _statusChip(personalStatus, personal: true), // personal
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              if (qty.isNotEmpty)
                Text(qty, style: const TextStyle(color: Colors.black87)),
              if (type.isNotEmpty)
                Text(type, style: const TextStyle(color: Colors.black54)),
              if (createdAt != null)
                Text(
                  'Posted ${_relative(createdAt)}',
                  style: const TextStyle(color: Colors.black45, fontSize: 12),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (photoUrl != null && photoUrl.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                photoUrl,
                height: 180,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionCard(String title, List<Widget> children) {
    return Container(
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
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFFE26A2C),
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _iconRow(
    IconData icon,
    String title,
    String value, {
    VoidCallback? onTap,
  }) {
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.black54),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 2),
              GestureDetector(
                onTap: onTap,
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: 13,
                    color: onTap != null ? Colors.blue : Colors.black87,
                    decoration: onTap != null ? TextDecoration.underline : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
    return Padding(padding: const EdgeInsets.only(bottom: 12), child: row);
  }

  Widget _mapStub({required VoidCallback onTap}) => InkWell(
    onTap: onTap,
    child: Container(
      height: 180,
      decoration: BoxDecoration(
        color: const Color(0xFFECEFF1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Center(
        child: Icon(Icons.map, size: 42, color: Colors.white),
      ),
    ),
  );

  Widget _statusChip(String status, {bool personal = false}) {
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
    } else if (s == 'rejected' || s == 'cancelled' || s == 'declined') {
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

  static String _relative(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes} minutes ago';
    if (diff.inHours < 24) return '${diff.inHours} hours ago';
    return '${diff.inDays} days ago';
  }
}

class _DonorInfo extends StatelessWidget {
  final String donorId;
  final Widget Function(String, List<Widget>) buildSection;

  const _DonorInfo({required this.donorId, required this.buildSection});

  @override
  Widget build(BuildContext context) {
    if (donorId.isEmpty) {
      return buildSection('Donor Information', const [
        Text('—', style: TextStyle(fontSize: 14)),
      ]);
    }

    final ref = FirebaseFirestore.instance.collection('users').doc(donorId);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: ref.snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return buildSection('Donor Information', const [
            Text(
              'Error loading donor info',
              style: TextStyle(color: Colors.black54, fontSize: 12),
            ),
          ]);
        }
        if (!snap.hasData || !snap.data!.exists) {
          return buildSection('Donor Information', const [
            LinearProgressIndicator(minHeight: 2),
          ]);
        }

        final u = snap.data!.data()!;
        final isOrg = u['isOrganization'] == true;

        final phone =
            isOrg
                ? (u['organization']?['phone'] as String?) ?? ''
                : (u['profile']?['phone'] as String?) ?? '';

        final contactName =
            isOrg
                ? (u['organization']?['contactName'] as String?) ?? ''
                : (u['profile']?['name'] as String?) ??
                    (u['profile']?['displayName'] as String?) ??
                    '';

        final displayName =
            isOrg
                ? (u['organization']?['organization_name'] as String?) ??
                    (u['organization']?['name'] as String?) ??
                    'Organization'
                : contactName.isNotEmpty
                ? contactName
                : 'Donor';

        return buildSection('Donor Information', [
          Row(
            children: [
              const CircleAvatar(radius: 18, child: Icon(Icons.person)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    if (isOrg && contactName.isNotEmpty)
                      Text(
                        'Contact: $contactName',
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (phone.isNotEmpty)
            _kvRow(
              icon: Icons.phone,
              label: 'Phone',
              value: phone,
              onTap: () => _launchPhone(phone),
            ),
        ]);
      },
    );
  }

  static Widget _kvRow({
    required IconData icon,
    required String label,
    required String value,
    VoidCallback? onTap,
  }) {
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.black54),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            onTap: onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 13,
                    color: onTap != null ? Colors.blue : Colors.black87,
                    decoration:
                        onTap != null
                            ? TextDecoration.underline
                            : TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
    return Padding(padding: const EdgeInsets.only(bottom: 12), child: row);
  }

  static Future<void> _launchPhone(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
