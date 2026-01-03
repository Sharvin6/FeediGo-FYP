import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class RequesterDetailsScreen extends StatefulWidget {
  const RequesterDetailsScreen({super.key});

  @override
  State<RequesterDetailsScreen> createState() => _RequesterDetailsScreenState();
}

class _RequesterDetailsScreenState extends State<RequesterDetailsScreen> {
  late final String donationId;
  bool _busy = false;
  String? _selectedAction; // 'accept' or 'decline'

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    donationId = (ModalRoute.of(context)?.settings.arguments as String?) ?? '';
  }

  @override
  Widget build(BuildContext context) {
    const orange = Color.fromARGB(255, 255, 109, 36);
    if (donationId.isEmpty) {
      return const Scaffold(body: Center(child: Text('Invalid donation')));
    }

    final donationRef = FirebaseFirestore.instance
        .collection('donations')
        .doc(donationId);

    final donationStream = donationRef.snapshots();
    final reqsStream =
        FirebaseFirestore.instance
            .collection('donation_requests')
            .where('donationId', isEqualTo: donationId)
            .where('status', whereIn: ['pending', 'accepted', 'rejected'])
            .orderBy('createdAt', descending: true)
            .snapshots();

    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F7),
      appBar: AppBar(
        backgroundColor: orange,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        title: const Text(
          'Requester Details',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: donationStream,
          builder: (context, dSnap) {
            if (dSnap.hasError) {
              return _center('Error: ${dSnap.error}');
            }
            if (!dSnap.hasData || !dSnap.data!.exists) {
              return const Center(child: CircularProgressIndicator());
            }

            final donation = dSnap.data!.data()!;
            final title =
                (donation['title'] ?? donation['foodName'] ?? 'Donation')
                    .toString();
            final qty = (donation['quantity'] ?? '').toString();
            final type = (donation['foodTypeLabel'] ?? '').toString();

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: reqsStream,
              builder: (context, rSnap) {
                if (rSnap.hasError) {
                  return _center('Error: ${rSnap.error}');
                }
                if (!rSnap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final reqDocs = rSnap.data!.docs;
                if (reqDocs.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.inbox_outlined,
                            size: 56,
                            color: Colors.black26,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'No pending requests yet.',
                            style: TextStyle(color: Colors.black54),
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Close'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                // Show the latest request (for now)
                final req = reqDocs.first.data();
                final reqId = reqDocs.first.id;
                final requesterId = (req['recipientId'] ?? '').toString();

                return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  future:
                      FirebaseFirestore.instance
                          .collection('users')
                          .doc(requesterId)
                          .get(),
                  builder: (context, uSnap) {
                    if (uSnap.hasError) {
                      return _center('Failed to load requester.');
                    }
                    final user = uSnap.data?.data() ?? <String, dynamic>{};

                    // ---- Safe getters ----
                    String s(dynamic v) => v == null ? '' : v.toString();
                    Map<String, dynamic> mapOf(dynamic v) =>
                        v is Map ? Map<String, dynamic>.from(v) : {};

                    final bool isOrg = user['isOrganization'] == true;
                    final String email = s(user['email']);

                    // Individual profile
                    final prof = mapOf(user['profile']);
                    final personName = s(prof['name'] ?? prof['displayName']);
                    final personPhone = s(prof['phone']);
                    final personAddr = s(prof['address']);

                    // Organization profile
                    final org = mapOf(user['organization']);
                    final orgName = s(org['organization_name'] ?? org['name']);
                    final orgContact = s(
                      org['contactName'] ?? org['contactPerson'],
                    );
                    final orgPhone = s(org['phone']);
                    final orgAddr = s(org['address']);

                    return ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      children: [
                        _card(
                          title: 'Donation Summary',
                          children: [
                            _row('Food', title),
                            if (type.isNotEmpty) _row('Type', type),
                            if (qty.isNotEmpty) _row('Quantity', qty),
                          ],
                        ),
                        const SizedBox(height: 12),

                        _card(
                          title: 'Requester',
                          children:
                              isOrg
                                  ? [
                                    _row('Organization', orgName),
                                    if (orgContact.isNotEmpty)
                                      _row('Contact Person', orgContact),
                                    if (email.isNotEmpty) _row('Email', email),
                                    if (orgPhone.isNotEmpty)
                                      _row('Phone', orgPhone),
                                    if (orgAddr.isNotEmpty)
                                      _row('Address', orgAddr),
                                  ]
                                  : [
                                    _row(
                                      'Name',
                                      personName.isEmpty ? '—' : personName,
                                    ),
                                    if (email.isNotEmpty) _row('Email', email),
                                    if (personPhone.isNotEmpty)
                                      _row('Phone', personPhone),
                                    if (personAddr.isNotEmpty)
                                      _row('Address', personAddr),
                                  ],
                        ),
                        const SizedBox(height: 16),

                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.check),
                                label: const Text('Accept'),

                                onPressed:
                                    (_busy ||
                                            _selectedAction == 'accept' ||
                                            req['status'] == 'accepted')
                                        ? null
                                        : () {
                                          setState(() {
                                            _selectedAction = 'accept';
                                          });
                                          _accept(reqId, requesterId);
                                        },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor: Colors.grey[400],
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.close),
                                label: const Text('Decline'),
                                onPressed:
                                    (_busy ||
                                            _selectedAction == 'decline' ||
                                            req['status'] == 'rejected')
                                        ? null
                                        : () {
                                          setState(() {
                                            _selectedAction = 'decline';
                                          });
                                          _decline(reqId);
                                        },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor: Colors.grey[400],
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (req['status'] != 'pending') ...[
                          const SizedBox(
                            height: 12,
                          ), // Space between buttons and text
                          Center(
                            child: Text(
                              req['status'] == 'accepted'
                                  ? 'You accepted this request'
                                  : 'You rejected this request',
                              style: const TextStyle(
                                color: Colors.black54,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }

  // ---------- accept / decline ----------

  Future<void> _accept(String reqId, String recipientId) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final db = FirebaseFirestore.instance;
      final donationRef = db.collection('donations').doc(donationId);
      final reqRef = db.collection('donation_requests').doc(reqId);

      final batch = db.batch();

      batch.update(reqRef, {
        'status': 'accepted',
        'updatedAt': FieldValue.serverTimestamp(),
      });

      batch.update(donationRef, {
        'status': 'accepted',
        'acceptedRequestId': reqId,
        'recipientId': recipientId,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final others =
          await db
              .collection('donation_requests')
              .where('donationId', isEqualTo: donationId)
              .where('status', isEqualTo: 'pending')
              .get();

      for (final doc in others.docs) {
        if (doc.id == reqId) continue;
        batch.update(doc.reference, {
          'status': 'rejected',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();
      if (!mounted) return;
      _snack('Request accepted.');
      //Navigator.pop(context);
    } catch (_) {
      _snack('Failed to accept. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decline(String reqId) async {
    if (_busy) return;
    setState(() => _busy = true);

    final db = FirebaseFirestore.instance;
    final donationRef = db.collection('donations').doc(donationId);
    final reqRef = db.collection('donation_requests').doc(reqId);

    try {
      // 1) Mark the request as rejected
      await reqRef.update({
        'status': 'rejected',
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // 2) Re-check pending requests for this donation
      final pendingQuery =
          await db
              .collection('donation_requests')
              .where('donationId', isEqualTo: donationId)
              .where('status', isEqualTo: 'pending')
              .get();

      // 3) If none remain, update the donation doc to "available/no active requests"
      if (pendingQuery.docs.isEmpty) {
        await donationRef.update({
          // pick the status your app treats as "no active requests"
          'status': 'pending', // or 'requested' if that's your app's convention
          'updatedAt': FieldValue.serverTimestamp(),
          'acceptedRequestId': null,
          'recipientId': null,
        });
      }

      if (!mounted) return;
      _snack('Request rejected.');
      //Navigator.pop(context);
    } catch (e, st) {
      debugPrint('Decline failed: $e\n$st');
      _snack('Failed to decline. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------- ui helpers ----------

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Widget _card({required String title, required List<Widget> children}) =>
      _cardImpl(title, children);

  static Widget _cardImpl(String title, List<Widget> children) {
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

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.black54,
              ),
            ),
          ),
          Expanded(child: Text(value.isEmpty ? '—' : value)),
        ],
      ),
    );
  }

  Widget _center(String t) =>
      Center(child: Padding(padding: const EdgeInsets.all(16), child: Text(t)));
}
