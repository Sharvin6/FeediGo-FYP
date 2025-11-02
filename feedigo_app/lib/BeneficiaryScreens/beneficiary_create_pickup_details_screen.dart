// lib/screens/beneficiary_create_pickup_details_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class BeneficiaryCreatePickupDetailsScreen extends StatefulWidget {
  const BeneficiaryCreatePickupDetailsScreen({super.key});

  @override
  State<BeneficiaryCreatePickupDetailsScreen> createState() =>
      _BeneficiaryCreatePickupDetailsScreenState();
}

class _BeneficiaryCreatePickupDetailsScreenState
    extends State<BeneficiaryCreatePickupDetailsScreen> {
  late final String donationId;

  final _notesCtrl = TextEditingController();
  DateTime? _pickedDate;
  TimeOfDay? _pickedStart;
  bool _saving = false;
  bool _gotArgs = false; // guard late-final

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_gotArgs) return;
    donationId = (ModalRoute.of(context)?.settings.arguments as String?) ?? '';
    _gotArgs = true;
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
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
          'Request Pickup',
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
          final recipientId = (d['recipientId'] ?? '').toString();
          final donorId = (d['donorId'] ?? '').toString();

          final myUid = FirebaseAuth.instance.currentUser?.uid;
          final isRecipient = myUid != null && recipientId == myUid;
          final isAccepted = status == 'accepted' || status == 'approved';

          // Personal request (Your: …)
          final myReqQuery = FirebaseFirestore.instance
              .collection('donation_requests')
              .where('donationId', isEqualTo: donationId)
              .where('recipientId', isEqualTo: myUid)
              .limit(1);

          // Donor contact stream (to render read-only)
          final donorStream =
              donorId.isEmpty
                  ? null
                  : FirebaseFirestore.instance
                      .collection('users')
                      .doc(donorId)
                      .snapshots();

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: myReqQuery.snapshots(),
            builder: (context, rSnap) {
              final personalStatus =
                  (rSnap.data?.docs.isNotEmpty ?? false)
                      ? (rSnap.data!.docs.first.data()['status'] as String? ??
                          '')
                      : null;

              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  if (!isRecipient)
                    _warn(
                      'You are not the accepted beneficiary for this donation. '
                      'Only the accepted beneficiary should schedule the pickup.',
                    ),
                  if (!isAccepted)
                    _warn(
                      'This donation has not been approved by the donor yet. '
                      'You can select a time, but you can only save after approval.',
                    ),

                  // Summary (shows both chips)
                  _summaryCard(
                    title: title,
                    qty: qty,
                    expiry: expiry,
                    address: address,
                    status: status,
                    personalStatus: personalStatus,
                  ),
                  const SizedBox(height: 12),

                  // Donor Contact (read-only, above pickup date/time)
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
                            error:
                                'Unable to load donor contact. You can still schedule.',
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
                                    ''
                                : (u['profile']?['name'] as String?) ??
                                    (u['profile']?['displayName'] as String?) ??
                                    '';
                        final phone =
                            isOrg
                                ? (u['organization']?['phone'] as String?) ?? ''
                                : (u['profile']?['phone'] as String?) ?? '';

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

                  const SizedBox(height: 12),

                  // Form
                  _formCard(
                    children: [
                      _fieldLabel('Pickup Date *'),
                      _PickerField(
                        hint: 'Select pickup date',
                        icon: Icons.event,
                        valueText:
                            _pickedDate == null
                                ? null
                                : _formatDate(_pickedDate!),
                        onTap: () => _pickDate(context, expiry),
                      ),
                      const SizedBox(height: 14),

                      _fieldLabel('Pickup Time *'),
                      _PickerField(
                        hint: 'Select time',
                        icon: Icons.schedule,
                        valueText:
                            _pickedStart == null
                                ? null
                                : _formatTime(_pickedStart!),
                        onTap: () => _pickStartTime(context),
                      ),

                      const SizedBox(height: 16),
                      _fieldLabel('Additional Notes'),
                      TextField(
                        controller: _notesCtrl,
                        maxLines: 3,
                        decoration: _inputDeco('Any special instructions...'),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.event_available),
                      label: const Text('Schedule Pickup'),
                      onPressed:
                          _saving
                              ? null
                              : () => _save(
                                donationRef: donationRef,
                                expiry: expiry,
                                isRecipient: isRecipient,
                                isAccepted: isAccepted,
                              ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: orange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  // ---------- pickers ----------

  Future<void> _pickDate(BuildContext context, DateTime? expiry) async {
    final now = DateTime.now();
    final first = DateTime(now.year, now.month, now.day);
    final last = expiry ?? now.add(const Duration(days: 60));

    final d = await showDatePicker(
      context: context,
      initialDate: _pickedDate ?? first,
      firstDate: first,
      lastDate: last,
    );
    if (d != null) setState(() => _pickedDate = d);
  }

  Future<void> _pickStartTime(BuildContext context) async {
    final t = await showTimePicker(
      context: context,
      initialTime: _pickedStart ?? const TimeOfDay(hour: 10, minute: 0),
    );
    if (t != null) setState(() => _pickedStart = t);
  }

  // ---------- save (updates donations AND donation_requests) ----------

  Future<void> _save({
    required DocumentReference<Map<String, dynamic>> donationRef,
    required DateTime? expiry,
    required bool isRecipient,
    required bool isAccepted,
  }) async {
    if (_pickedDate == null || _pickedStart == null) {
      _snack('Please select pickup date and time.');
      return;
    }

    if (!isAccepted) {
      _snack('Pickup can only be scheduled after the donor approves.');
      return;
    }
    if (!isRecipient) {
      _snack('Only the accepted beneficiary can schedule this pickup.');
      return;
    }

    final start = DateTime(
      _pickedDate!.year,
      _pickedDate!.month,
      _pickedDate!.day,
      _pickedStart!.hour,
      _pickedStart!.minute,
    );

    if (expiry != null && !start.isBefore(expiry)) {
      _snack('Pickup must be scheduled before the expiry date.');
      return;
    }

    setState(() => _saving = true);
    try {
      final db = FirebaseFirestore.instance;
      final batch = db.batch();

      // 1) Update the donation
      batch.update(donationRef, {
        'status': 'scheduled',
        'pickupInfo.time': Timestamp.fromDate(start),
        if (_notesCtrl.text.trim().isNotEmpty)
          'pickupInfo.notes': _notesCtrl.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // 2) Update the current user's donation_request for this donation
      final myUid = FirebaseAuth.instance.currentUser?.uid;
      if (myUid != null) {
        final reqSnap =
            await db
                .collection('donation_requests')
                .where('donationId', isEqualTo: donationId)
                .where('recipientId', isEqualTo: myUid)
                .limit(1)
                .get();

        if (reqSnap.docs.isNotEmpty) {
          batch.update(reqSnap.docs.first.reference, {
            'status': 'scheduled',
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }

      await batch.commit();

      if (!mounted) return;
      _snack('Pickup scheduled.');

      Navigator.pushReplacementNamed(
        context,
        '/beneficiary_pickup_schedule_details',
        arguments: donationId,
      );
    } catch (e) {
      _snack('Failed to schedule: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---------- small ui helpers ----------

  InputDecoration _inputDeco(String hint) => const InputDecoration(
    border: OutlineInputBorder(),
    isDense: true,
    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  ).copyWith(hintText: hint);

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

  Widget _PickerField({
    required String hint,
    required IconData icon,
    required VoidCallback? onTap,
    String? valueText,
  }) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                valueText ?? hint,
                style: TextStyle(
                  color: valueText == null ? Colors.black45 : Colors.black87,
                ),
              ),
            ),
            Icon(icon, color: Colors.orange),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard({
    required String title,
    required String qty,
    required DateTime? expiry,
    required String address,
    required String status,
    String? personalStatus, // NEW
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
          // header + both status chips
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
              if (personalStatus != null && personalStatus.isNotEmpty) ...[
                const SizedBox(width: 6),
                _StatusChip(status: personalStatus, personal: true),
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

  // Donor contact read-only card
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
            if ((personName ?? '').isNotEmpty)
              _kv('Conatct Name:', personName!),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

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

  String _formatTime(TimeOfDay t) {
    final hh = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final mm = t.minute.toString().padLeft(2, '0');
    final ap = t.hour >= 12 ? 'PM' : 'AM';
    return '$hh:$mm $ap';
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

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
}

/// Status chip (supports global and "Your:" labels)
class _StatusChip extends StatelessWidget {
  final String status;
  final bool personal;
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
