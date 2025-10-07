import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();

  // shared
  bool _isOrg = false;
  bool _loading = false;
  String? _role; // Donor / Food Bank / Beneficiary
  String? _error;

  // route args
  bool _fromSwitch = false;
  String? _targetRole;

  // remove old role data?
  bool _removeOldData = false;

  // individual fields
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addrCtrl = TextEditingController();

  // organization fields
  final _orgNameCtrl = TextEditingController();
  final _contactNameCtrl = TextEditingController();
  final _orgPhoneCtrl = TextEditingController();
  final _pickupAddrCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    // route args may not be available immediately, fetch after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map) {
        _fromSwitch = args['fromSwitch'] == true;
        _targetRole = args['targetRole'] as String?; // optional
      }
      _fetchRoleAndPrefill();
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addrCtrl.dispose();
    _orgNameCtrl.dispose();
    _contactNameCtrl.dispose();
    _orgPhoneCtrl.dispose();
    _pickupAddrCtrl.dispose();
    super.dispose();
  }

  String? _req(String? v, {int min = 1}) =>
      (v == null || v.trim().length < min) ? 'This field is required' : null;

  Future<void> _fetchRoleAndPrefill() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _error = 'Not signed in.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get()
          .timeout(const Duration(seconds: 10));

      if (!mounted) return;
      final data = doc.data() ?? <String, dynamic>{};

      // prefer targetRole (if provided via args), else existing role in DB, else Beneficiary
      final fetchedRole =
          (_targetRole?.trim().isNotEmpty == true)
              ? _targetRole
              : (data['role'] as String?) ?? 'Beneficiary';

      setState(() {
        _role = fetchedRole;
        // if role exists and is Food Bank, always treat as org
        _isOrg =
            (fetchedRole == 'Food Bank') || (data['isOrganization'] == true);
      });

      // Prefill profile or organization fields if present
      final profile = data['profile'] as Map<String, dynamic>?;
      final org = data['organization'] as Map<String, dynamic>?;

      if (profile != null) {
        _nameCtrl.text = (profile['name'] as String?) ?? '';
        _phoneCtrl.text = (profile['phone'] as String?) ?? '';
        _addrCtrl.text = (profile['address'] as String?) ?? '';
      }

      if (org != null) {
        _orgNameCtrl.text = (org['organization_name'] as String?) ?? '';
        _contactNameCtrl.text = (org['contactName'] as String?) ?? '';
        _orgPhoneCtrl.text = (org['phone'] as String?) ?? '';
        _pickupAddrCtrl.text = (org['address'] as String?) ?? '';
      }

      setState(() {
        _error = null;
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _error = 'Network timeout. Please check your internet and try again.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load your role: $e';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Show a confirmation dialog when the user has requested destructive deletion.
  Future<bool> _confirmRemoveOldData() async {
    if (!_fromSwitch || !_removeOldData) return true;
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Remove old role data?'),
          content: const Text(
            'You chose to remove your previous role data. This will delete the old '
            'profile or organization fields from your account (this is reversible only by admin). '
            'Are you sure you want to continue?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE26A2C),
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Yes, remove'),
            ),
          ],
        );
      },
    );
    return r == true;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    // If remove old data selected, ask for confirmation
    if (_fromSwitch && _removeOldData) {
      final ok = await _confirmRemoveOldData();
      if (!ok) return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final users = FirebaseFirestore.instance.collection('users');
      final now = FieldValue.serverTimestamp();
      final role = (_role ?? 'Beneficiary').trim();

      // Build payload using merge-safe approach
      final Map<String, dynamic> payload = {
        'role': role,
        'isOrganization': _isOrg,
        'updated_at': now,
        'email': FirebaseAuth.instance.currentUser?.email,
      };

      if (_isOrg) {
        payload['organization'] = {
          'organization_name': _orgNameCtrl.text.trim(),
          'contactName': _contactNameCtrl.text.trim(),
          'phone': _orgPhoneCtrl.text.trim(),
          'address': _pickupAddrCtrl.text.trim(),
        };
      } else {
        payload['profile'] = {
          'name': _nameCtrl.text.trim(),
          'phone': _phoneCtrl.text.trim(),
          'address': _addrCtrl.text.trim(),
        };
      }

      // If user chose to remove old role data, prepare deletes:
      final Map<String, dynamic> deletePayload = {};
      if (_fromSwitch && _removeOldData) {
        // If switching to organization role, remove 'profile'; otherwise remove 'organization'
        if (_isOrg) {
          deletePayload['profile'] = FieldValue.delete();
        } else {
          deletePayload['organization'] = FieldValue.delete();
        }
      }

      // 1) Write merged fields
      await users.doc(uid).set(payload, SetOptions(merge: true));

      // 2) Apply deletes if requested (single merge call that includes deletes)
      if (deletePayload.isNotEmpty) {
        await users.doc(uid).set(deletePayload, SetOptions(merge: true));
      }

      // 3) Audit entry when switching
      if (_fromSwitch) {
        await users.doc(uid).collection('roleChangeHistory').add({
          'newRole': role,
          'timestamp': now,
          'triggeredBy': uid,
          'removedOldData': _removeOldData,
        });
      }

      // Redirect: choose dashboard route based on the role
      String dest = '/dashboard'; // fallback
      if (role == 'Donor') {
        dest = '/donor_dashboard';
      } else if (role == 'Food Bank') {
        dest = '/foodbank_dashboard';
      } else if (role == 'Beneficiary') {
        dest = '/beneficiary_dashboard';
      }

      if (!mounted) return;
      // Clear stack and go to dashboard
      Navigator.pushNamedAndRemoveUntil(context, dest, (route) => false);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Failed to save profile. Please try again.');
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Save error: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _handleBack() {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      Navigator.pushReplacementNamed(
        context,
        '/role_selection',
        arguments: {'fromSwitch': true},
      );
    }
  }

  // UI builders
  List<Widget> _individualFields() => [
    _field(
      'Full Name',
      _nameCtrl,
      validator: _req,
      action: TextInputAction.next,
    ),
    const SizedBox(height: 12),
    _field(
      'Phone Number',
      _phoneCtrl,
      keyboard: TextInputType.phone,
      validator: _req,
      action: TextInputAction.next,
    ),
    const SizedBox(height: 12),
    _field(
      'Address',
      _addrCtrl,
      validator: _req,
      maxLines: 2,
      action: TextInputAction.done,
    ),
  ];

  List<Widget> _orgFields() => [
    _field(
      'Organization Name',
      _orgNameCtrl,
      validator: _req,
      action: TextInputAction.next,
    ),
    const SizedBox(height: 12),
    _field(
      'Contact Person Name',
      _contactNameCtrl,
      validator: _req,
      action: TextInputAction.next,
    ),
    const SizedBox(height: 12),
    _field(
      'Phone Number',
      _orgPhoneCtrl,
      keyboard: TextInputType.phone,
      validator: _req,
      action: TextInputAction.next,
    ),
    const SizedBox(height: 12),
    _field(
      'Pickup Address',
      _pickupAddrCtrl,
      validator: _req,
      maxLines: 2,
      action: TextInputAction.done,
    ),
  ];

  Widget _field(
    String label,
    TextEditingController ctrl, {
    TextInputType keyboard = TextInputType.text,
    TextInputAction action = TextInputAction.next,
    String? Function(String?)? validator,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: ctrl,
      validator: validator,
      keyboardType: keyboard,
      textInputAction: action,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onFieldSubmitted: (_) {
        if (action == TextInputAction.done) {
          FocusScope.of(context).unfocus();
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFE26A2C);
    final titleStyle = Theme.of(context).textTheme.headlineSmall?.copyWith(
      color: Colors.white,
      fontWeight: FontWeight.bold,
    );

    return Scaffold(
      backgroundColor: orange,
      appBar: AppBar(
        backgroundColor: orange,
        elevation: 0,
        title: const Text(
          'Create Profile',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: _handleBack,
        ),
      ),
      body: SafeArea(
        child:
            _loading && _role == null
                ? const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                )
                : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Complete Your Profile', style: titleStyle),
                        const SizedBox(height: 6),
                        const Text(
                          'Tell us a bit more about you.',
                          style: TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 16),

                        // role toggle and fields
                        if (_role == null)
                          const SizedBox.shrink()
                        else ...[
                          // Only show toggle for Donor/Beneficiary
                          if (_role == 'Donor' || _role == 'Beneficiary') ...[
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _role == 'Donor'
                                          ? 'Are you donating as an organization?'
                                          : 'Are you representing an organization receiving donations?',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Switch(
                                    value: _isOrg,
                                    activeColor: orange,
                                    onChanged:
                                        (v) => setState(() => _isOrg = v),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            if (_isOrg)
                              ..._orgFields()
                            else
                              ..._individualFields(),
                          ] else if (_role == 'Food Bank') ...[
                            ..._orgFields(), // always org
                          ],
                        ],

                        const SizedBox(height: 12),

                        // If switching role, show remove-old-data option
                        if (_fromSwitch) ...[
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            child: Row(
                              children: [
                                Checkbox(
                                  value: _removeOldData,
                                  onChanged:
                                      (v) => setState(
                                        () => _removeOldData = v ?? false,
                                      ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Remove previous role data (delete old profile/organization fields).',
                                    style: const TextStyle(
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],

                        if (_error != null)
                          Text(
                            _error!,
                            style: const TextStyle(color: Colors.yellowAccent),
                          ),

                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _loading ? null : _save,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: orange,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child:
                                _loading
                                    ? const SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                    : const Text('Save & Continue'),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
      ),
    );
  }
}
