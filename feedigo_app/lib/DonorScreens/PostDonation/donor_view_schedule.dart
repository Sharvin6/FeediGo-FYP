import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class DonorViewScheduleScreen extends StatefulWidget {
  const DonorViewScheduleScreen({super.key});

  @override
  State<DonorViewScheduleScreen> createState() =>
      _DonorViewScheduleScreenState();
}

class _DonorViewScheduleScreenState extends State<DonorViewScheduleScreen> {
  late final String donationId;
  bool _gotArgs = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_gotArgs) return;
    donationId = (ModalRoute.of(context)?.settings.arguments as String?) ?? '';
    _gotArgs = true;
  }

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFE26A2C);

    if (donationId.isEmpty) {
      return const Scaffold(body: Center(child: Text('Invalid donation id')));
    }

    final donationRef = FirebaseFirestore.instance
        .collection('donations')
        .doc(donationId);

    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F7),
      appBar: AppBar(
        backgroundColor: orange,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Pickup Schedule (Donor)',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: donationRef.snapshots(),
        builder: (context, dSnap) {
          if (dSnap.hasError) {
            return _center('Error: ${dSnap.error}');
          }
          if (!dSnap.hasData || !dSnap.data!.exists) {
            return const Center(child: CircularProgressIndicator());
          }

          final d = dSnap.data!.data()!;
          DateTime? asDate(dynamic v) {
            if (v is Timestamp) return v.toDate();
            if (v is DateTime) return v;
            return null;
          }

          final title = (d['title'] ?? d['foodName'] ?? 'Donation').toString();
          final qty = (d['quantity'] ?? '').toString();
          final status = (d['status'] ?? 'pending').toString().toLowerCase();
          final expiry = asDate(d['expiryAt']);
          final address = (d['pickupInfo']?['address'] ?? '').toString();
          final notes = (d['pickupInfo']?['notes'] ?? '').toString();
          final scheduledTime = asDate(d['pickupInfo']?['time']);
          final recipientId = (d['recipientId'] ?? '').toString();
          final donorId = (d['donorId'] ?? '').toString();

          // Optional: guard so only the donor sees this screen for their donation
          final myUid = FirebaseAuth.instance.currentUser?.uid;
          final isDonor = myUid != null && donorId == myUid;

          // Recipient contact stream
          final recipientStream =
              recipientId.isEmpty
                  ? null
                  : FirebaseFirestore.instance
                      .collection('users')
                      .doc(recipientId)
                      .snapshots();

          // Whether we have proofs
          final hasProofs =
              (d['pickupProof'] is Map) &&
              (((d['pickupProof']['photos'] ?? []) as List).isNotEmpty ||
                  ((d['pickupProof']['note'] ?? '') as String)
                      .toString()
                      .isNotEmpty);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              if (!isDonor)
                _warn('You are viewing a donation that is not yours.'),

              _summaryCard(
                title: title,
                qty: qty,
                expiry: expiry,
                address: address,
                status: status,
              ),
              const SizedBox(height: 12),

              // Recipient Contact (read-only)
              if (recipientStream != null)
                StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: recipientStream,
                  builder: (context, uSnap) {
                    if (uSnap.hasError) {
                      return _contactCard(
                        header: 'Recipient Contact',
                        orgName: null,
                        personName: null,
                        phone: null,
                        loading: false,
                        error: 'Unable to load recipient contact.',
                      );
                    }
                    if (!uSnap.hasData || !uSnap.data!.exists) {
                      return _contactCard(
                        header: 'Recipient Contact',
                        orgName: null,
                        personName: null,
                        phone: null,
                        loading: true,
                      );
                    }
                    final u = uSnap.data!.data()!;
                    final isOrg = u['isOrganization'] == true;

                    final orgName =
                        isOrg
                            ? (u['organization']?['organization_name']
                                    as String?) ??
                                (u['organization']?['name'] as String?) ??
                                ''
                            : null;
                    final personName =
                        isOrg
                            ? (u['organization']?['contactPerson']
                                    as String?) ??
                                (u['organization']?['contactName']
                                    as String?) ??
                                ''
                            : (u['profile']?['name'] as String?) ??
                                (u['profile']?['displayName'] as String?) ??
                                '';
                    final phone =
                        isOrg
                            ? (u['organization']?['phone'] as String?) ?? ''
                            : (u['profile']?['phone'] as String?) ?? '';

                    return _contactCard(
                      header: 'Recipient Contact',
                      orgName: orgName,
                      personName: personName,
                      phone: phone,
                    );
                  },
                )
              else
                _contactCard(
                  header: 'Recipient Contact',
                  orgName: null,
                  personName: null,
                  phone: null,
                  error: 'Recipient contact unavailable.',
                ),

              const SizedBox(height: 12),

              // Schedule info & actions
              _formCard(
                children: [
                  _fieldLabel('Pickup Date'),
                  _readOnlyField(
                    value:
                        scheduledTime == null
                            ? '-'
                            : _formatDate(scheduledTime),
                    icon: Icons.event,
                  ),
                  const SizedBox(height: 14),
                  _fieldLabel('Pickup Time'),
                  _readOnlyField(
                    value:
                        scheduledTime == null
                            ? '-'
                            : _formatTimeOfDay(
                              TimeOfDay.fromDateTime(scheduledTime),
                            ),
                    icon: Icons.schedule,
                  ),

                  if (notes.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _fieldLabel('Additional Notes'),
                    _readOnlyMultiline(notes),
                  ],
                ],
              ),

              const SizedBox(height: 12),

              // View proofs (if completed)
              if (status == 'completed' && hasProofs)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pushNamed(
                        context,
                        '/confirm_pickup',
                        arguments: {
                          'donationId': donationId,
                          'readOnly':
                              true, // your ConfirmPickupScreen should respect this
                        },
                      );
                    },
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('View Pickup Proofs'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3F51B5),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  // ---------- helpers & small UI ----------

  Widget _summaryCard({
    required String title,
    required String qty,
    required DateTime? expiry,
    required String address,
    required String status,
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
              const Text(
                'Donation Summary',
                style: TextStyle(
                  color: Color(0xFFE26A2C),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              _StatusChip(status: status),
            ],
          ),
          const SizedBox(height: 8),
          _kv('Food Item:', title),
          if (qty.isNotEmpty) _kv('Quantity:', qty),
          if (expiry != null) _kv('Expiry Date:', _formatDate(expiry)),
          if (address.isNotEmpty) _kv('Pickup Address:', address),
        ],
      ),
    );
  }

  Widget _contactCard({
    required String header,
    required String? orgName,
    required String? personName,
    required String? phone,
    bool loading = false,
    String? error,
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
          Text(
            header,
            style: const TextStyle(
              color: Color(0xFFE26A2C),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          if (loading) const LinearProgressIndicator(minHeight: 2),
          if (!loading && error != null) ...[
            Text(error, style: const TextStyle(color: Colors.black54)),
          ] else if (!loading) ...[
            if ((orgName ?? '').isNotEmpty) _kv('Organization:', orgName!),
            if ((personName ?? '').isNotEmpty)
              _kv('Contact Name:', personName!),
            if ((phone ?? '').isNotEmpty)
              Row(
                children: [
                  SizedBox(
                    width: 140,
                    child: Text(
                      'Phone:',
                      style: const TextStyle(
                        color: Colors.black54,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Expanded(
                    child: InkWell(
                      onTap: () => _launchPhone(phone!),
                      child: Text(
                        phone!,
                        style: const TextStyle(
                          color: Colors.blue,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            if ((orgName ?? '').isEmpty &&
                (personName ?? '').isEmpty &&
                (phone ?? '').isEmpty)
              const Text('—', style: TextStyle(color: Colors.black54)),
          ],
        ],
      ),
    );
  }

  Widget _formCard({required List<Widget> children}) {
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
        children: children,
      ),
    );
  }

  Widget _readOnlyField({
    required String value,
    required IconData icon,
    Widget? trailing,
  }) {
    return InputDecorator(
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(value, style: const TextStyle(color: Colors.black87)),
          ),
          if (trailing != null) const SizedBox(width: 8),
          if (trailing != null) trailing,
          Icon(icon, color: Colors.orange),
        ],
      ),
    );
  }

  Widget _readOnlyMultiline(String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFBDBDBD)),
        borderRadius: BorderRadius.circular(4),
        color: Colors.white,
      ),
      child: Text(value, style: const TextStyle(color: Colors.black87)),
    );
  }

  Widget _fieldLabel(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      t,
      style: const TextStyle(
        fontWeight: FontWeight.w700,
        color: Colors.black87,
      ),
    ),
  );

  Widget _kv(String k, String v) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        SizedBox(
          width: 140,
          child: Text(
            k,
            style: const TextStyle(
              color: Colors.black54,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(child: Text(v)),
      ],
    ),
  );

  String _formatDate(DateTime d) {
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
    return '${m[d.month - 1]} ${d.day}, ${d.year}';
  }

  String _formatTimeOfDay(TimeOfDay t) {
    final hh = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final mm = t.minute.toString().padLeft(2, '0');
    final ap = t.hour >= 12 ? 'PM' : 'AM';
    return '$hh:$mm $ap';
  }

  Widget _warn(String t) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF4E5),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline, color: Color(0xFFEF6C00)),
        const SizedBox(width: 8),
        Expanded(child: Text(t, style: const TextStyle(color: Colors.black87))),
      ],
    ),
  );

  Widget _center(String t) =>
      Center(child: Padding(padding: const EdgeInsets.all(16), child: Text(t)));

  // --- launchers ---

  static Future<void> _openMaps(String address) async {
    if (address.isEmpty) return;
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeComponent(address)}',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  static Future<void> _launchPhone(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

/// Status chip (matches style used elsewhere)
class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final s = status.toLowerCase();
    Color bg, fg;
    String label;

    if (s == 'approved' || s == 'accepted') {
      bg = const Color(0xFFE6F6EA);
      fg = const Color(0xFF2E7D32);
      label = 'Approved';
    } else if (s == 'scheduled') {
      bg = const Color(0xFFE3F2FD);
      fg = const Color(0xFF0277BD);
      label = 'Scheduled';
    } else if (s == 'completed') {
      bg = const Color(0xFFE8EAF6);
      fg = const Color(0xFF3F51B5);
      label = 'Completed';
    } else if (s == 'requested') {
      bg = const Color(0xFFFFF4E5);
      fg = const Color(0xFFEF6C00);
      label = 'Requested';
    } else if (s == 'rejected' || s == 'cancelled' || s == 'declined') {
      bg = const Color(0xFFFFEBEE);
      fg = const Color(0xFFC62828);
      label = 'Rejected';
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
        style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }
}
