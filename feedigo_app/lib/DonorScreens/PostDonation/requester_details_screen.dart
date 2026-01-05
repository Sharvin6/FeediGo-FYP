/*
  RequesterDetailsScreen: 
  This screen is designed for donors to view who has requested a specific donation and either
  accept or decline the request. It fetches data from **Firebase Firestore** and updates the
  donation/request documents atomically using **batched writes**.

  Important Technical Terms / Concepts Used:
    - StatefulWidget: Maintains state across rebuilds, used here to track selected action
      ('accept' or 'decline') and loading state (_busy).
    - ModalRoute: Retrieves route arguments (donationId) passed via Navigator.
    - FirebaseFirestore: NoSQL cloud database from Firebase, storing 'donations', 'donation_requests', and 'users'.
    - StreamBuilder: Listens in real-time to Firestore streams to reflect any updates immediately.
    - FutureBuilder: Fetches one-time data (requester/user profile) asynchronously.
    - Batched Writes: Firestore feature to atomically update multiple documents, used to accept a request
      and reject other pending requests simultaneously.
    - Access Control: UI buttons are disabled when the action is already performed or during async operations.
    - Conditional Rendering: Only shows fields if data exists, differentiates between individual and organization profiles.
    - Safe getters: Functions to safely extract values from Firestore maps, preventing null errors.
    - UI Components: Container, Column, Row, ElevatedButton, ListView used to display data in cards and rows.
    - SnackBar: Shows success/error messages after actions.
    - Async Handling: `_accept` and `_decline` handle Firestore operations asynchronously and update UI accordingly.
*/

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Screen to view and manage requests for a donation
class RequesterDetailsScreen extends StatefulWidget {
  const RequesterDetailsScreen({super.key});

  @override
  State<RequesterDetailsScreen> createState() => _RequesterDetailsScreenState();
}

class _RequesterDetailsScreenState extends State<RequesterDetailsScreen> {
  late final String
  donationId; // Donation document ID passed via route arguments
  bool _busy = false; // Tracks if an async operation is ongoing
  String? _selectedAction; // 'accept' or 'decline', to prevent double-tap

  /// Retrieve donationId from route arguments
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    donationId = (ModalRoute.of(context)?.settings.arguments as String?) ?? '';
  }

  @override
  Widget build(BuildContext context) {
    const orange = Color.fromARGB(255, 255, 109, 36);

    // Guard against invalid donation ID
    if (donationId.isEmpty) {
      return const Scaffold(body: Center(child: Text('Invalid donation')));
    }

    // Firestore references & streams
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
            if (dSnap.hasError) return _center('Error: ${dSnap.error}');
            if (!dSnap.hasData || !dSnap.data!.exists)
              return const Center(child: CircularProgressIndicator());

            final donation = dSnap.data!.data()!;
            final title =
                (donation['title'] ?? donation['foodName'] ?? 'Donation')
                    .toString();
            final qty = (donation['quantity'] ?? '').toString();
            final type = (donation['foodTypeLabel'] ?? '').toString();

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: reqsStream,
              builder: (context, rSnap) {
                if (rSnap.hasError) return _center('Error: ${rSnap.error}');
                if (!rSnap.hasData)
                  return const Center(child: CircularProgressIndicator());

                final reqDocs = rSnap.data!.docs;

                // No requests found
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

                // Show the latest request
                final req = reqDocs.first.data();
                final reqId = reqDocs.first.id;
                final requesterId = (req['recipientId'] ?? '').toString();

                // Fetch requester profile info
                return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  future:
                      FirebaseFirestore.instance
                          .collection('users')
                          .doc(requesterId)
                          .get(),
                  builder: (context, uSnap) {
                    if (uSnap.hasError)
                      return _center('Failed to load requester.');
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

                    // Display donation & requester info
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      children: [
                        // Donation summary card
                        _card(
                          title: 'Donation Summary',
                          children: [
                            _row('Food', title),
                            if (type.isNotEmpty) _row('Type', type),
                            if (qty.isNotEmpty) _row('Quantity', qty),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Requester info card
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

                        // Accept / Decline buttons
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
                                          setState(
                                            () => _selectedAction = 'accept',
                                          );
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
                                          setState(
                                            () => _selectedAction = 'decline',
                                          );
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

                        // Show status text after action
                        if (req['status'] != 'pending') ...[
                          const SizedBox(height: 12),
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

  // ---------- Firestore Actions ----------

  /// Accepts a donation request and rejects other pending requests
  Future<void> _accept(String reqId, String recipientId) async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      final db = FirebaseFirestore.instance;
      final donationRef = db.collection('donations').doc(donationId);
      final reqRef = db.collection('donation_requests').doc(reqId);

      final batch = db.batch();

      // Update the selected request as accepted
      batch.update(reqRef, {
        'status': 'accepted',
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Update donation doc with accepted request info
      batch.update(donationRef, {
        'status': 'accepted',
        'acceptedRequestId': reqId,
        'recipientId': recipientId,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Reject other pending requests
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
    } catch (_) {
      _snack('Failed to accept. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Declines a donation request and updates donation if no pending requests remain
  Future<void> _decline(String reqId) async {
    if (_busy) return;
    setState(() => _busy = true);

    final db = FirebaseFirestore.instance;
    final donationRef = db.collection('donations').doc(donationId);
    final reqRef = db.collection('donation_requests').doc(reqId);

    try {
      await reqRef.update({
        'status': 'rejected',
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final pendingQuery =
          await db
              .collection('donation_requests')
              .where('donationId', isEqualTo: donationId)
              .where('status', isEqualTo: 'pending')
              .get();

      if (pendingQuery.docs.isEmpty) {
        await donationRef.update({
          'status': 'pending', // no active requests
          'updatedAt': FieldValue.serverTimestamp(),
          'acceptedRequestId': null,
          'recipientId': null,
        });
      }

      if (!mounted) return;
      _snack('Request rejected.');
    } catch (e, st) {
      debugPrint('Decline failed: $e\n$st');
      _snack('Failed to decline. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------- UI Helpers ----------

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Widget _card({required String title, required List<Widget> children}) =>
      _cardImpl(title, children);

  static Widget _cardImpl(String title, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(14),
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
