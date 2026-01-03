import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class DonorDashboardScreen extends StatelessWidget {
  const DonorDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const orange = Color.fromARGB(255, 255, 109, 36);

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(body: Center(child: Text('Not signed in')));
    }

    // Keep simple query (no composite index needed)
    final donationsQuery = FirebaseFirestore.instance
        .collection('donations')
        .where('donorId', isEqualTo: uid);

    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F7),
      appBar: AppBar(
        backgroundColor: orange,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Donor Dashboard',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 20,
            color: Colors.white,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            onPressed: () => Navigator.pushNamed(context, '/settings_screen'),
          ),
        ],
      ),
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: donationsQuery.snapshots(),
          builder: (context, snap) {
            if (snap.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Error loading donations:\n${snap.error}',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }

            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            // Sort client-side by createdAt desc
            final docs =
                (snap.data?.docs ?? []).toList()..sort((a, b) {
                  final ta = a.data()['createdAt'];
                  final tb = b.data()['createdAt'];
                  final da = ta is Timestamp ? ta.toDate() : DateTime(0);
                  final db = tb is Timestamp ? tb.toDate() : DateTime(0);
                  return db.compareTo(da);
                });

            final total = docs.length;
            final inProgress =
                docs
                    .where(
                      (d) => (d.data()['status'] ?? 'pending') != 'completed',
                    )
                    .length;
            final mealsHelped = docs.fold<int>(0, (acc, d) {
              final data = d.data();
              final status = (data['status'] ?? 'pending') as String;
              if (status == 'completed') {
                return acc + ((data['servings'] as int?) ?? 1);
              }
              return acc;
            });

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                _ImpactCard(
                  total: total,
                  inProgress: inProgress,
                  meals: mealsHelped,
                ),
                const SizedBox(height: 12),

                SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed:
                        () => Navigator.pushNamed(context, '/post_donation'),
                    icon: const Icon(Icons.add_circle_outline),
                    label: const Text('Post New Donation'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: orange,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Recent Donations',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    TextButton(
                      onPressed:
                          () =>
                              Navigator.pushNamed(context, '/donation_history'),
                      child: const Text('View All'),
                    ),
                  ],
                ),

                if (docs.isEmpty)
                  _EmptyState(
                    onPost:
                        () => Navigator.pushNamed(context, '/post_donation'),
                  )
                else
                  ...docs.take(3).map((doc) {
                    final data = doc.data();
                    return _DonationTile(
                      id: doc.id,
                      data: data,
                      onOpen:
                          () => Navigator.pushNamed(
                            context,
                            '/donation_details',
                            arguments: doc.id,
                          ),
                      onEdit:
                          () => Navigator.pushNamed(
                            context,
                            '/edit_donation',
                            arguments: doc.id,
                          ),
                      onDelete: () async {
                        final ok = await _confirmDelete(context);
                        if (ok == true) {
                          await FirebaseFirestore.instance
                              .collection('donations')
                              .doc(doc.id)
                              .delete();
                        }
                      },
                      onViewRequester:
                          () => Navigator.pushNamed(
                            context,
                            '/requestor_details',
                            arguments: doc.id,
                          ),
                      // NEW: navigate to donor schedule view
                      onViewSchedule:
                          () => Navigator.pushNamed(
                            context,
                            '/donor_view_schedule',
                            arguments: doc.id,
                          ),
                    );
                  }),
              ],
            );
          },
        ),
      ),
    );
  }

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

// === Stats card ===============================================================

class _ImpactCard extends StatelessWidget {
  final int total;
  final int inProgress;
  final int meals;
  const _ImpactCard({
    required this.total,
    required this.inProgress,
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
          _stat('Total Donations', total),
          _divider(),
          _stat('In Progress', inProgress),
          _divider(),
          _stat('Meals Helped', meals),
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

// === Donation Tile (now with "View Schedule" support) ========================

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
          Row(
            children: [
              Expanded(
                child: Text(
                  created ?? '',
                  style: const TextStyle(color: Colors.black45, fontSize: 12),
                ),
              ),

              // View
              _miniBtn(icon: Icons.visibility_outlined, onTap: onOpen),
              const SizedBox(width: 8),

              // Edit and delete— only when pending
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

          // Show "View Requester Details" for requested/accepted
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

          // NEW: Show "View Schedule" when scheduled
          if (isScheduled || isCompleted) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onViewSchedule,
                icon: const Icon(Icons.event_available),
                label: const Text('View Schedule'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0277BD),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

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

// === Status chip =============================================================

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

// === Empty state =============================================================

class _EmptyState extends StatelessWidget {
  final VoidCallback onPost;
  const _EmptyState({required this.onPost});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inbox_outlined, size: 48, color: Colors.black45),
            const SizedBox(height: 12),
            const Text(
              'No donations yet',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'Start by posting your first donation.',
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onPost,
              icon: const Icon(Icons.add),
              label: const Text('Post Donation'),
            ),
          ],
        ),
      ),
    );
  }
}
