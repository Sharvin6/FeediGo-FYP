// lib/screens/beneficiary_pickup_schedule_details_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class BeneficiaryPickupScheduleDetailsScreen extends StatefulWidget {
  const BeneficiaryPickupScheduleDetailsScreen({super.key});

  @override
  State<BeneficiaryPickupScheduleDetailsScreen> createState() =>
      _BeneficiaryPickupScheduleDetailsScreenState();
}

class _BeneficiaryPickupScheduleDetailsScreenState
    extends State<BeneficiaryPickupScheduleDetailsScreen> {
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

    final donationRef =
        FirebaseFirestore.instance.collection('donations').doc(donationId);

    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F7),
      appBar: AppBar(
        backgroundColor: orange,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Pickup Details',
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
          final donorId = (d['donorId'] ?? '').toString();

          final recipientId = (d['recipientId'] ?? '').toString();
          final myUid = FirebaseAuth.instance.currentUser?.uid;
          final isRecipient = myUid != null && recipientId == myUid;

          // Allow edit when accepted/scheduled (NOT completed)
          final canEdit = isRecipient &&
              (status == 'accepted' || status == 'approved' || status == 'scheduled');

          // personal status (Your: ...)
          final myReqQuery = FirebaseFirestore.instance
              .collection('donation_requests')
              .where('donationId', isEqualTo: donationId)
              .where('recipientId', isEqualTo: myUid)
              .limit(1);

          final scheduledTime = asDate(d['pickupInfo']?['time']);

          final donorStream = donorId.isEmpty
              ? null
              : FirebaseFirestore.instance.collection('users').doc(donorId).snapshots();

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: myReqQuery.snapshots(),
            builder: (context, rSnap) {
              final rawPersonalStatus =
                  (rSnap.data?.docs.isNotEmpty ?? false)
                      ? (rSnap.data!.docs.first.data()['status'] as String? ?? '')
                      : '';
              final effectivePersonalStatus =
                  (rawPersonalStatus.isEmpty) ? (isRecipient ? status : '') : rawPersonalStatus;

              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  _summaryCard(
                    title: title,
                    qty: qty,
                    expiry: expiry,
                    address: address,
                    status: status,
                    personalStatus: effectivePersonalStatus,
                  ),
                  const SizedBox(height: 12),

                  // Donor Contact (read-only)
                  if (donorStream != null)
                    StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      stream: donorStream,
                      builder: (context, uSnap) {
                        if (uSnap.hasError) {
                          return _contactCard(
                            orgName: null,
                            personName: null,
                            phone: null,
                            loading: false,
                            error: 'Unable to load donor contact at the moment.',
                          );
                        }
                        if (!uSnap.hasData || !uSnap.data!.exists) {
                          return _contactCard(
                            orgName: null,
                            personName: null,
                            phone: null,
                            loading: true,
                          );
                        }
                        final u = uSnap.data!.data()!;
                        final isOrg = u['isOrganization'] == true;

                        final orgName = isOrg
                            ? (u['organization']?['organization_name'] as String?) ??
                                (u['organization']?['name'] as String?) ??
                                ''
                            : null;
                        final personName = isOrg
                            ? (u['organization']?['contactPerson'] as String?) ??
                                (u['organization']?['contactName'] as String?) ??
                                ''
                            : (u['profile']?['name'] as String?) ??
                                (u['profile']?['displayName'] as String?) ??
                                '';
                        final phone =
                            isOrg ? (u['organization']?['phone'] as String?) ?? '' : (u['profile']?['phone'] as String?) ?? '';

                        return _contactCard(
                          orgName: orgName,
                          personName: personName,
                          phone: phone,
                        );
                      },
                    )
                  else
                    _contactCard(
                      orgName: null,
                      personName: null,
                      phone: null,
                      error: 'Donor contact unavailable for this donation.',
                    ),

                  const SizedBox(height: 8),

                  // --- Actions: Edit / Schedule / Confirm Pickup (when editable) ---
                  if (canEdit) ...[
                    if (scheduledTime != null)
                      Align(
                        alignment: Alignment.centerRight,
                        child: Wrap(
                          spacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            TextButton.icon(
                              onPressed: () {
                                Navigator.pushNamed(
                                  context,
                                  '/beneficiary_edit_pickup_details',
                                  arguments: donationId,
                                );
                              },
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              label: const Text(
                                'Edit pickup schedule',
                                style: TextStyle(
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFFE26A2C),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 6,
                                ),
                              ),
                            ),
                            ElevatedButton.icon(
                              onPressed: status == 'scheduled'
                                  ? () {
                                      Navigator.pushNamed(
                                        context,
                                        '/confirm_pickup',
                                        arguments: {
                                          'donationId': donationId,
                                          'readOnly': false,
                                        },
                                      );
                                    }
                                  : null,
                              icon: const Icon(Icons.check_circle_outline),
                              label: const Text('Confirm Pickup'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2E7D32),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Align(
                        alignment: Alignment.centerRight,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pushNamed(
                              context,
                              '/beneficiary_create_pickup_details',
                              arguments: donationId,
                            );
                          },
                          icon: const Icon(Icons.event_available),
                          label: const Text('Schedule pickup'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0277BD),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                  ],

                  // --- View Proofs button for completed records (read-only) ---
                  if (status == 'completed') ...[
                    Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pushNamed(
                            context,
                            '/confirm_pickup',
                            arguments: {
                              'donationId': donationId,
                              'readOnly': true,
                            },
                          );
                        },
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('View Proofs'),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Scheduled info (read-only)
                  _formCard(
                    children: [
                      _fieldLabel('Pickup Date'),
                      _readOnlyField(
                        value: scheduledTime == null ? '-' : _formatDate(scheduledTime),
                        icon: Icons.event,
                      ),
                      const SizedBox(height: 14),
                      _fieldLabel('Pickup Time'),
                      _readOnlyField(
                        value: scheduledTime == null
                            ? '-'
                            : _formatTimeOfDay(TimeOfDay.fromDateTime(scheduledTime)),
                        icon: Icons.schedule,
                      ),
                      if (notes.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _fieldLabel('Additional Notes'),
                        _readOnlyMultiline(notes),
                      ],
                    ],
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  // ---------- small ui blocks reused ----------
  Widget _summaryCard({
    required String title,
    required String qty,
    required DateTime? expiry,
    required String address,
    required String status,
    String? personalStatus,
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
              if ((personalStatus ?? '').isNotEmpty) ...[
                const SizedBox(width: 6),
                _StatusChip(status: personalStatus!, personal: true),
              ],
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
          const Text(
            'Donor Contact',
            style: TextStyle(
              color: Color(0xFFE26A2C),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          if (loading) const LinearProgressIndicator(minHeight: 2),
          if (!loading && error != null) ...[
            Text(error, style: const TextStyle(color: Colors.black54)),
          ] else if (!loading) ...[
            if ((orgName ?? '').isNotEmpty) _kv('Organization Name:', orgName!),
            if ((personName ?? '').isNotEmpty) _kv('Contact Name:', personName!),
            if ((phone ?? '').isNotEmpty) _kv('Phone Number:', phone!),
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
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  Widget _readOnlyField({required String value, required IconData icon}) {
    return InputDecorator(
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      child: Row(
        children: [
          Expanded(child: Text(value, style: const TextStyle(color: Colors.black87))),
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

  Widget _center(String t) => Center(child: Padding(padding: const EdgeInsets.all(16), child: Text(t)));
}

class _StatusChip extends StatelessWidget {
  final String status;
  final bool personal;
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
    } else if (s == 'rejected' || s == 'cancelled' || s == 'declined') {
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
