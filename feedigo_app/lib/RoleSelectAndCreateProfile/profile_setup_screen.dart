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
    _fetchRole();
  }

  // Dynamic label based on role
  String get _roleToggleText {
    switch (_role) {
      case 'Donor':
        return 'Are you donating as an organization?';
      case 'Beneficiary':
        return 'Are you representing an organization receiving donations?';
      default:
        return 'Are you donating as an organization?';
    }
  }

  Future<void> _fetchRole() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _error = 'Not signed in.');
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get()
          .timeout(const Duration(seconds: 10));

      if (!mounted) return;
      final data = doc.data() ?? const {};
      final fetchedRole = (data['role'] as String?) ?? 'Beneficiary';

      setState(() {
        _role = fetchedRole;
        // Food Bank always org
        _isOrg = fetchedRole == 'Food Bank';
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
    }
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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final users = FirebaseFirestore.instance.collection('users');
      final now = FieldValue.serverTimestamp();

      final role = (_role ?? 'Beneficiary').trim();

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

      await users.doc(uid).set(payload, SetOptions(merge: true));

      if (!mounted) return;
      await Navigator.pushNamed(
        context,
        '/profile_success',
        arguments: (_role ?? 'Beneficiary'),
      );
    } catch (e) {
      setState(() => _error = 'Failed to save profile. Please try again.');
      if (mounted) {
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
      Navigator.pushReplacementNamed(context, '/role_selection');
    }
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
            _role == null
                ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(color: Colors.white),
                        const SizedBox(height: 16),
                        Text(
                          _error ?? 'Loading your role…',
                          style: const TextStyle(color: Colors.white),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ElevatedButton(
                              onPressed: _fetchRole,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: orange,
                              ),
                              child: const Text('Try again'),
                            ),
                            const SizedBox(width: 12),
                            OutlinedButton(
                              onPressed: () {
                                setState(() {
                                  _role = 'Beneficiary';
                                  _isOrg = false;
                                  _error = null;
                                });
                              },
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Colors.white),
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('Continue anyway'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
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
                                    _roleToggleText,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Switch(
                                  value: _isOrg,
                                  activeColor: orange,
                                  onChanged: (v) => setState(() => _isOrg = v),
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

                        const SizedBox(height: 16),
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
                                    ? const CircularProgressIndicator(
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        orange,
                                      ),
                                    )
                                    : const Text('Save & Continue'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
      ),
    );
  }

  // ---- field groups ----
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

  // ---- single field builder ----
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
}
