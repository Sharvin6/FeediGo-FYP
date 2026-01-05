/*
  DonationDetailsScreen shows real-time detailed info of a donation with status, 
  expiry, location, photo, and optional description, allowing edits if pending.”

  - State Management: StatelessWidget with StreamBuilder provides reactive UI; no local state needed.
  - Firestore Integration:
      - Uses FirebaseFirestore.instance.collection('donations').doc(donationId) to reference the donation.
      - snapshots() provides a real-time stream of changes.
  - UI Components:
      - _StatusChip: Maps donation status to colored chip with semantic label.
      - _infoCard: Shows icon + label + value for fields like expiry and pickup.
      - _sectionCard: For description or other text-heavy sections.
*/

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Screen to display detailed information of a single donation
class DonationDetailsScreen extends StatelessWidget {
  const DonationDetailsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Retrieve donation ID passed via Navigator arguments
    final donationId = ModalRoute.of(context)!.settings.arguments as String;

    // Primary app color
    const orange = Color.fromARGB(255, 255, 109, 36);

    // Firestore reference to this donation document
    final ref = FirebaseFirestore.instance
        .collection('donations')
        .doc(donationId);

    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F7),
      appBar: AppBar(
        backgroundColor: orange,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Donation Details',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
      body: SafeArea(
        // Listen to real-time updates from Firestore using StreamBuilder
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: ref.snapshots(),
          builder: (context, snap) {
            if (!snap.hasData) {
              // Show loading spinner while waiting for data
              return const Center(child: CircularProgressIndicator());
            }

            // Extract data from snapshot
            final data = snap.data!.data();
            if (data == null) {
              return const Center(child: Text('Donation not found.'));
            }

            // Extract and assign fields with fallback values
            final title =
                (data['foodName'] ?? data['title'] ?? 'Donation') as String;
            final qty = (data['quantity'] ?? '') as String;
            final status = (data['status'] ?? 'pending') as String;
            final photo = data['photoUrl'] as String?;
            final expiry = _fmtDate(data['expiryAt']); // Format expiry date
            final address = (data['pickupInfo']?['address'] ?? '') as String;
            final posted = _relative(data['createdAt']); // Relative posted time

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              children: [
                // --- Header Card with title, quantity, status, photo ---
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title + status chip row
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
                          _StatusChip(status: status), // Status indicator
                        ],
                      ),
                      const SizedBox(height: 6),
                      // Quantity display if available
                      if (qty.isNotEmpty)
                        Text(
                          qty,
                          style: const TextStyle(
                            color: Colors.black54,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      // Relative posted time
                      if (posted != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Posted $posted',
                          style: const TextStyle(
                            color: Colors.black45,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      // Display donation photo if exists
                      if (photo != null && photo.isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            photo,
                            height: 180,
                            fit: BoxFit.cover,
                          ),
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // --- Info Card: Donation Details (expiry date, pickup location) ---
                _infoCard(
                  title: 'Donation Details',
                  items: [
                    (Icons.schedule, 'Expiry Date', expiry ?? '-'),
                    (
                      Icons.place,
                      'Pickup Location',
                      address.isEmpty ? '-' : address,
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // --- Section Card: Description (optional) ---
                if ((data['description'] ?? '').toString().isNotEmpty)
                  _sectionCard('Description', data['description'] as String),

                const SizedBox(height: 20),

                // --- Edit Button: Only show if status is pending ---
                if (status.toLowerCase() == 'pending') ...[
                  Center(
                    child: TextButton(
                      onPressed: () {
                        Navigator.pushNamed(
                          context,
                          '/edit_donation',
                          arguments: donationId,
                        );
                      },
                      child: const Text(
                        'Edit',
                        style: TextStyle(
                          decoration: TextDecoration.underline,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  // --- Helper: Format Timestamp to DD/MM/YYYY ---
  static String? _fmtDate(dynamic ts) {
    if (ts is Timestamp) {
      final d = ts.toDate();
      return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    }
    return null;
  }

  // --- Helper: Convert Timestamp to relative time (e.g., 2 hours ago) ---
  static String? _relative(dynamic ts) {
    if (ts is Timestamp) {
      final diff = DateTime.now().difference(ts.toDate());
      if (diff.inMinutes < 1) return 'just now';
      if (diff.inHours < 1) return '${diff.inMinutes} minutes ago';
      if (diff.inHours < 24) return '${diff.inHours} hours ago';
      return '${diff.inDays} days ago';
    }
    return null;
  }

  // --- Info Card Widget: List of label-value pairs with icons ---
  Widget _infoCard({
    required String title,
    required List<(IconData, String, String)> items,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
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
          ...items.map(
            (it) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Icon(it.$1, size: 18, color: Colors.black54),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          it.$2, // Label
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          it.$3, // Value
                          style: const TextStyle(color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Section Card Widget: Used for description or other text sections ---
  Widget _sectionCard(String title, String body) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
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
          const SizedBox(height: 8),
          Text(body),
        ],
      ),
    );
  }
}

/// Custom widget to show status as colored chip
class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final s = status.toLowerCase();
    Color bg, fg;
    String label;

    // Map status to color and label
    if (s == 'accepted') {
      bg = const Color(0xFFE6F6EA);
      fg = const Color(0xFF2E7D32);
      label = 'Approved';
    } else if (s == 'completed') {
      bg = const Color(0xFFE8EAF6);
      fg = const Color(0xFF3F51B5);
      label = 'Completed';
    } else if (s == 'rejected') {
      bg = const Color(0xFFFFEBEE);
      fg = const Color(0xFFC62828);
      label = 'Rejected';
    } else if (s == 'requested') {
      bg = const Color(0xFFFFF4E5);
      fg = const Color(0xFFEF6C00);
      label = 'Requested';
    } else if (s == 'scheduled') {
      bg = const Color(0xFFE3F2FD);
      fg = const Color(0xFF0277BD);
      label = 'Scheduled';
    } else {
      bg = const Color(0xFFFFF4E5);
      fg = const Color(0xFFEF6C00);
      label = 'Pending';
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
