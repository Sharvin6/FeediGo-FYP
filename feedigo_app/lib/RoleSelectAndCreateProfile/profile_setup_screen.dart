import 'dart:async'; // Used for handling async operations such as timeout
import 'package:cloud_firestore/cloud_firestore.dart'; // Firebase Firestore database
import 'package:firebase_auth/firebase_auth.dart'; // Firebase Authentication
import 'package:flutter/material.dart'; // Flutter UI framework
import 'package:flutter/services.dart'; // Used for input formatting (e.g., phone number)

/// ProfileSetupScreen
/// --------------------------------------------------
/// This screen allows users to create or update
/// their profile after selecting a role.
/// It supports:
/// - Individual users
/// - Organization users
/// - Role switching with optional data removal
class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  // Key to validate the form
  final _formKey = GlobalKey<FormState>();

  // ==========================
  // STATE VARIABLES
  // ==========================

  bool _isOrg = false; // Determines whether user represents an organization
  bool _loading = false; // Controls loading indicator & button state
  String? _role; // Current user role (Donor / Food Bank / Beneficiary)
  String? _error; // Error message to display on UI

  // ==========================
  // ROUTE ARGUMENTS
  // ==========================

  bool _fromSwitch = false; // Indicates whether user is switching roles
  String? _targetRole; // Role passed from RoleSelectionScreen
  bool _removeOldData =
      false; // Determines whether old role data should be removed

  // ==========================
  // TEXT CONTROLLERS
  // ==========================

  // Individual profile fields
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addrCtrl = TextEditingController();

  // Organization profile fields
  final _orgNameCtrl = TextEditingController();
  final _contactNameCtrl = TextEditingController();
  final _orgPhoneCtrl = TextEditingController();
  final _pickupAddrCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();

    // Runs after first frame is rendered
    // This ensures context is available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args = ModalRoute.of(context)?.settings.arguments;

      // Read role passed from previous screen
      if (args is Map) {
        _targetRole = args['targetRole'] as String?;
      }

      // Fetch role and existing profile data from Firestore
      _fetchRoleAndPrefill();
    });
  }

  @override
  void dispose() {
    // Dispose controllers to prevent memory leaks
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addrCtrl.dispose();
    _orgNameCtrl.dispose();
    _contactNameCtrl.dispose();
    _orgPhoneCtrl.dispose();
    _pickupAddrCtrl.dispose();
    super.dispose();
  }

  // ==========================
  // VALIDATORS
  // ==========================

  /// Generic required field validator
  String? _req(String? v, {int min = 1}) =>
      (v == null || v.trim().length < min) ? 'This field is required' : null;

  /// Phone number validator using regex
  String? _phoneValidator(String? v) {
    if (v == null || v.trim().isEmpty) {
      return 'Phone number is required';
    }

    // Allows optional +, digits, spaces and dashes
    final phoneRegex = RegExp(r'^\+?[0-9\-\s]{8,15}$');
    if (!phoneRegex.hasMatch(v.trim())) {
      return 'Enter a valid phone number (e.g. 0123456789)';
    }
    return null;
  }

  // ==========================
  // FETCH & PREFILL DATA
  // ==========================

  /// Fetches existing user role and profile data
  /// from Firestore and pre-fills the form
  Future<void> _fetchRoleAndPrefill() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    // User must be logged in
    if (uid == null) {
      setState(() => _error = 'Not signed in.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Fetch user document with timeout
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get()
          .timeout(const Duration(seconds: 10));

      if (!mounted) return;

      final data = doc.data() ?? {};
      final bool hasExistingRole = data.containsKey('role');

      // Role priority:
      // 1. Role from previous screen
      // 2. Role from database
      // 3. Default to Beneficiary
      final fetchedRole =
          (_targetRole?.trim().isNotEmpty == true)
              ? _targetRole
              : (data['role'] as String?) ?? 'Beneficiary';

      setState(() {
        _fromSwitch = hasExistingRole;
        _role = fetchedRole;
        _isOrg = fetchedRole == 'Food Bank' || data['isOrganization'] == true;
      });

      // Prefill individual profile data
      final profile = data['profile'] as Map<String, dynamic>?;
      if (profile != null) {
        _nameCtrl.text = profile['name'] ?? '';
        _phoneCtrl.text = profile['phone'] ?? '';
        _addrCtrl.text = profile['address'] ?? '';
      }

      // Prefill organization profile data
      final org = data['organization'] as Map<String, dynamic>?;
      if (org != null) {
        _orgNameCtrl.text = org['organization_name'] ?? '';
        _contactNameCtrl.text = org['contactName'] ?? '';
        _orgPhoneCtrl.text = org['phone'] ?? '';
        _pickupAddrCtrl.text = org['address'] ?? '';
      }
    } on TimeoutException {
      setState(() => _error = 'Network timeout. Please check your connection.');
    } catch (e) {
      setState(() => _error = 'Failed to load profile.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ==========================
  // CONFIRM DATA REMOVAL
  // ==========================

  /// Shows confirmation dialog before removing old role data
  Future<bool> _confirmRemoveOldData() async {
    if (!_fromSwitch || !_removeOldData) return true;

    final result = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Remove old role data?'),
            content: const Text(
              'This will permanently delete your previous profile data.',
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
          ),
    );

    return result == true;
  }

  // ==========================
  // SAVE PROFILE
  // ==========================

  /// Saves user profile and role data to Firestore
  Future<void> _save() async {
    // Validate form before saving
    if (!_formKey.currentState!.validate()) return;

    // Confirm data removal if switching roles
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
      final usersRef = FirebaseFirestore.instance.collection('users').doc(uid);

      final now = FieldValue.serverTimestamp();
      final role = (_role ?? 'Beneficiary').trim();

      // Base payload
      final payload = {
        'userId': uid,
        'role': role,
        'isOrganization': _isOrg,
        'email': FirebaseAuth.instance.currentUser?.email,
      };

      // Add created timestamp for new users
      if (!_fromSwitch) {
        payload['created_at'] = now;
      }

      // Save organization or individual data
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

      // Remove old role data if requested
      if (_fromSwitch && _removeOldData) {
        payload[_isOrg ? 'profile' : 'organization'] = FieldValue.delete();
      }

      // Save data to Firestore
      await usersRef.set(payload, SetOptions(merge: true));

      // Log role change history
      if (_fromSwitch) {
        await usersRef.collection('roleChangeHistory').add({
          'newRole': role,
          'timestamp': now,
          'triggeredBy': uid,
        });
      }

      if (!mounted) return;

      // Navigate to success screen
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/profile_success',
        (route) => false,
      );
    } catch (e) {
      setState(() => _error = 'Failed to save profile.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ==========================
  // NAVIGATION
  // ==========================

  /// Returns user back to Role Selection screen
  void _handleBack() {
    Navigator.pushReplacementNamed(
      context,
      '/role_selection',
      arguments: {'fromSwitch': _fromSwitch},
    );
  }

  // ==========================
  // UI HELPERS
  // ==========================

  /// Reusable form field widget
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
      inputFormatters:
          keyboard == TextInputType.phone
              ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-\s]'))]
              : null,
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
    );
  }

  // ==========================
  // UI BUILD
  // ==========================

  @override
  Widget build(BuildContext context) {
    const orange = Color.fromARGB(255, 255, 109, 36);

    return Scaffold(
      backgroundColor: orange,
      appBar: AppBar(
        backgroundColor: orange,
        elevation: 0,
        title: const Text(
          'Create Profile',
          style: TextStyle(color: Colors.white),
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
                  padding: const EdgeInsets.all(20),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Complete Your Profile',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Role-based form rendering
                        if (_role != null) ...[
                          if (_role == 'Donor' || _role == 'Beneficiary') ...[
                            _buildOrgSwitch(orange),
                            const SizedBox(height: 16),
                            if (_isOrg)
                              ..._orgFields()
                            else
                              ..._individualFields(),
                          ] else if (_role == 'Food Bank')
                            ..._orgFields(),
                        ],

                        if (_fromSwitch) _buildRemoveDataCheckbox(),
                        if (_error != null) _buildErrorText(),
                        const SizedBox(height: 20),
                        _buildSaveButton(orange),
                      ],
                    ),
                  ),
                ),
      ),
    );
  }

  // ==========================
  // SMALL UI COMPONENTS
  // ==========================

  Widget _buildOrgSwitch(Color orange) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _role == 'Donor'
                  ? 'Donating as an organization?'
                  : 'Representing an organization?',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Switch(
            value: _isOrg,
            activeColor: orange,
            onChanged: (v) => setState(() => _isOrg = v),
          ),
        ],
      ),
    );
  }

  Widget _buildRemoveDataCheckbox() {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Checkbox(
            value: _removeOldData,
            onChanged: (v) => setState(() => _removeOldData = v ?? false),
          ),
          const Expanded(child: Text('Remove previous role data')),
        ],
      ),
    );
  }

  Widget _buildErrorText() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(_error!, style: const TextStyle(color: Colors.yellowAccent)),
    );
  }

  Widget _buildSaveButton(Color orange) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _loading ? null : _save,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: orange,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child:
            _loading
                ? const CircularProgressIndicator(strokeWidth: 2)
                : const Text('Save & Continue'),
      ),
    );
  }

  List<Widget> _individualFields() => [
    _field('Full Name', _nameCtrl, validator: _req),
    const SizedBox(height: 12),
    _field(
      'Phone Number',
      _phoneCtrl,
      keyboard: TextInputType.phone,
      validator: _phoneValidator,
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
    _field('Organization Name', _orgNameCtrl, validator: _req),
    const SizedBox(height: 12),
    _field('Contact Person Name', _contactNameCtrl, validator: _req),
    const SizedBox(height: 12),
    _field(
      'Phone Number',
      _orgPhoneCtrl,
      keyboard: TextInputType.phone,
      validator: _phoneValidator,
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
}
