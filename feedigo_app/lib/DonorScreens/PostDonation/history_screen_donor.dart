/*
  Donor Donation History Screen
  -This screen fetches donation records from Firebase Firestore for the currently
  signed-in user (donor), allowing filtering by donation status and performing actions
  such as viewing details, editing, deleting, or viewing the schedule/requester info.

  Important Technical Terms / Concepts Used:
    - StatefulWidget: Maintains state across UI rebuilds, here used to track the selected status filter.
    - FirebaseAuth: Provides the current user's authentication details (UID used to fetch donations).
    - FirebaseFirestore: NoSQL cloud database used to store and query donation data.
    - Query & StreamBuilder: Firestore queries are used to filter data; StreamBuilder listens in real-time.
    - ListView.builder: Efficiently renders a scrollable list of donation items.
    - DropdownButtonFormField: Lets users select a donation status filter.
    - Async/Await: Used for asynchronous operations such as deletion confirmation.
    - Timestamp: Firestore timestamp converted to DateTime for display.
    - UI Widgets (Container, Row, Column, ElevatedButton, OutlinedButton, IconButton, etc.): Build the interactive UI.
    - Conditional rendering: Buttons like "Edit", "Delete", "View Schedule" are shown based on donation status.
    - Custom Widgets: _DonationTile and _StatusChip encapsulate reusable UI elements for clarity and maintainability.
*/
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// Main screen displaying donation history for the signed-in user
class DonationHistoryScreen extends StatefulWidget {
  const DonationHistoryScreen({super.key});

  @override
  State<DonationHistoryScreen> createState() => _DonationHistoryScreenState();
}

class _DonationHistoryScreenState extends State<DonationHistoryScreen> {
  // Constant for "All" filter
  static const allKey = 'all';

  // Status filter options (display label -> stored Firestore value)
  final Map<String, String> _statusOptions = {
    'All': allKey,
    'Pending': 'pending',
    'Requested': 'requested',
    'Approved': 'accepted',
    'Scheduled': 'scheduled',
    'Completed': 'completed',
  };

  // Currently selected status filter
  String _selectedStatus = allKey;

  @override
  Widget build(BuildContext context) {
    const orange = Color.fromARGB(255, 255, 109, 36);

    // Get current user's UID
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      // User not signed in
      return const Scaffold(body: Center(child: Text('Not signed in')));
    }

    // Base Firestore query for the current user's donations
    Query<Map<String, dynamic>> donationsQuery = FirebaseFirestore.instance
        .collection('donations')
        .where('donorId', isEqualTo: uid);

    // Apply status filter if not "All"
    if (_selectedStatus != allKey) {
      donationsQuery = donationsQuery.where(
        'status',
        isEqualTo: _selectedStatus,
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F7),
      appBar: AppBar(
        backgroundColor: orange,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Donation History',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 20,
            color: Colors.white,
          ),
        ),
      ),
      body: Column(
        children: [
          // ---------------- Filter Row ----------------
          Container(
            color: const Color(0xFFF3F5F7),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Row(
              children: [
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 4,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedStatus,
                          isExpanded: true,
                          items:
                              _statusOptions.entries.map((e) {
                                return DropdownMenuItem<String>(
                                  value: e.value,
                                  child: Text(e.key),
                                );
                              }).toList(),
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() {
                              _selectedStatus = v; // update filter
                            });
                          },
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  tooltip: 'Clear filter',
                  onPressed: () {
                    setState(() {
                      _selectedStatus = allKey; // reset filter
                    });
                  },
                  icon: const Icon(Icons.clear),
                ),
              ],
            ),
          ),

          // ---------------- Donation List ----------------
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: donationsQuery.snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(child: Text('Error: ${snap.error}'));
                }
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                // Sort donations by createdAt descending
                final docs =
                    (snap.data?.docs ?? []).toList()..sort((a, b) {
                      final ta = a.data()['createdAt'] as Timestamp?;
                      final tb = b.data()['createdAt'] as Timestamp?;
                      return (tb?.toDate() ?? DateTime(0)).compareTo(
                        ta?.toDate() ?? DateTime(0),
                      );
                    });

                // Show empty message if no donations
                if (docs.isEmpty) {
                  return Center(
                    child: Text(
                      _selectedStatus == allKey
                          ? 'No donation history.'
                          : 'No donations with selected status.',
                      style: const TextStyle(color: Colors.black54),
                    ),
                  );
                }

                // List of donations
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final data = docs[i].data();
                    final donationId = docs[i].id;
                    return _DonationTile(
                      id: donationId,
                      data: data,
                      onOpen:
                          () => Navigator.pushNamed(
                            context,
                            '/donation_details',
                            arguments: donationId,
                          ),
                      onEdit:
                          () => Navigator.pushNamed(
                            context,
                            '/edit_donation',
                            arguments: donationId,
                          ),
                      onDelete: () async {
                        final ok = await _confirmDelete(context);
                        if (ok == true) {
                          await FirebaseFirestore.instance
                              .collection('donations')
                              .doc(donationId)
                              .delete();
                        }
                      },
                      onViewRequester: () {
                        Navigator.pushNamed(
                          context,
                          '/requestor_details',
                          arguments: donationId,
                        );
                      },
                      onViewSchedule: () {
                        Navigator.pushNamed(
                          context,
                          '/donor_view_schedule',
                          arguments: donationId,
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

  // Confirm deletion of donation
  Future<bool?> _confirmDelete(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('Delete donation?'),
            content: const Text('This action cannot be undone.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ],
          ),
    );
  }
}

// ---------------- Donation Tile ----------------
class _DonationTile extends StatelessWidget {
  final String id;
  final Map<String, dynamic> data;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onViewRequester;
  final VoidCallback onViewSchedule;

  const _DonationTile({
    required this.id,
    required this.data,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
    required this.onViewRequester,
    required this.onViewSchedule,
  });

  @override
  Widget build(BuildContext context) {
    final name = (data['title'] ?? data['foodName'] ?? 'Donation') as String;
    final status = (data['status'] ?? 'pending') as String;
    final qty = (data['quantity'] ?? '') as String;
    final servings = data['servings'] as int?;
    final expiry = _expiryLabel(data['expiryAt']);
    final created = _relativeTime(data['createdAt']);

    final isScheduled = status.toLowerCase() == 'scheduled';
    final isCompleted = status.toLowerCase() == 'completed';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 14, 10, 12),
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
          // Name + status chip
          Row(
            children: [
              const Icon(Icons.fastfood, color: Colors.orange),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _StatusChip(status: status),
            ],
          ),
          const SizedBox(height: 8),

          // Quantity, servings, expiry
          Row(
            children: [
              if (servings != null && servings > 0) ...[
                const Icon(Icons.set_meal, size: 16, color: Colors.black54),
                const SizedBox(width: 4),
                Text(
                  '$servings servings',
                  style: const TextStyle(color: Colors.black54),
                ),
                const SizedBox(width: 12),
              ],
              if (qty.isNotEmpty) ...[
                const Icon(Icons.scale, size: 16, color: Colors.black54),
                const SizedBox(width: 4),
                Text(qty, style: const TextStyle(color: Colors.black54)),
                const SizedBox(width: 12),
              ],
              if (expiry != null) ...[
                const Icon(Icons.schedule, size: 16, color: Colors.black54),
                const SizedBox(width: 4),
                Text(
                  'Expires: $expiry',
                  style: const TextStyle(color: Colors.black54),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Container(
            height: 2,
            width: double.infinity,
            color: const Color(0xFFEFF1F4),
          ),
          const SizedBox(height: 8),

          // Actions: createdAt + mini buttons
          Row(
            children: [
              Expanded(
                child: Text(
                  created ?? '',
                  style: const TextStyle(color: Colors.black45, fontSize: 12),
                ),
              ),
              _miniBtn(icon: Icons.visibility_outlined, onTap: onOpen),
              const SizedBox(width: 8),
              if (status.toLowerCase() == 'pending') ...[
                _miniBtn(icon: Icons.edit_outlined, onTap: onEdit),
                _miniBtn(
                  icon: Icons.delete_outline,
                  onTap: onDelete,
                  danger: true,
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),

          // Requester button
          if (status.toLowerCase() == 'requested' ||
              status.toLowerCase() == 'accepted') ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.people_outline),
                label: const Text('View Requester Details'),
                onPressed: onViewRequester,
              ),
            ),
          ],

          // Schedule button
          if (isScheduled || isCompleted) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.event_note),
                label: const Text('View Schedule'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0277BD),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: onViewSchedule,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Mini icon button
  Widget _miniBtn({
    required IconData icon,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    final bg = danger ? const Color(0xFFFFEBEE) : const Color(0xFFF3F5F7);
    final fg = danger ? const Color(0xFFC62828) : const Color(0xFF607D8B);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 18, color: fg),
      ),
    );
  }

  // Format expiry date
  String? _expiryLabel(dynamic ts) {
    if (ts is! Timestamp) return null;
    final d = ts.toDate(), now = DateTime.now();
    final isToday =
        d.year == now.year && d.month == now.month && d.day == now.day;
    if (isToday) return 'Today';
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

  // Format relative time for display
  String? _relativeTime(dynamic ts) {
    if (ts is! Timestamp) return null;
    final d = ts.toDate();
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return 'Posted ${diff.inMinutes} minutes ago';
    if (diff.inHours < 24) return 'Posted ${diff.inHours} hours ago';
    return 'Posted ${diff.inDays} days ago';
  }
}

// ---------------- Status Chip ----------------
class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final s = status.toLowerCase();
    Color bg, fg;
    String label;
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
