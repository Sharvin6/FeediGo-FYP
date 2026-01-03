// ==============================
// Edit Profile Screen (Feedigo)
// ==============================

// Firestore → used to read & update user profile data
import 'package:cloud_firestore/cloud_firestore.dart';

// Firebase Auth → used to get the currently logged-in user
import 'package:firebase_auth/firebase_auth.dart';

// Flutter UI framework
import 'package:flutter/material.dart';

/// EditProfileScreen
/// -----------------
/// This screen allows a user to edit their profile details.
/// The screen supports TWO user types:
/// 1. Individual users (beneficiaries)
/// 2. Organization users (food banks / NGOs)
///
/// Data is loaded from Firestore and updated back securely
/// using the authenticated user's UID.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  // GlobalKey to validate and manage the form state
  final _formKey = GlobalKey<FormState>();

  // TextEditingControllers
  // These controllers hold and manage text input values
  // for each form field
  final _orgNameCtrl = TextEditingController();
  final _contactNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();

  // Controls loading state (used to show a progress indicator)
  bool _loading = false;

  // Determines whether the logged-in user is an organization
  // This affects which fields are displayed and updated
  bool _isOrganization = false;

  @override
  void initState() {
    super.initState();

    // Load user data as soon as the screen is created
    _loadUserData();
  }

  /// Loads user profile data from Firestore
  ///
  /// Steps:
  /// 1. Get the currently logged-in user's UID
  /// 2. Fetch the corresponding document from "users" collection
  /// 3. Populate form fields based on user type
  Future<void> _loadUserData() async {
    setState(() => _loading = true);

    // Get the current authenticated user's UID
    final uid = FirebaseAuth.instance.currentUser!.uid;

    // Fetch user document from Firestore
    final doc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();

    if (doc.exists) {
      final data = doc.data()!;

      // Determine if user is an organization
      _isOrganization = data['isOrganization'] == true;

      // Email is common for both user types
      _emailCtrl.text = data['email'] ?? '';

      if (_isOrganization) {
        // Organization user data
        final orgData = data['organization'] ?? {};

        _orgNameCtrl.text = orgData['organization_name'] ?? '';
        _contactNameCtrl.text = orgData['contactName'] ?? '';
        _phoneCtrl.text = orgData['phone'] ?? '';
        _addressCtrl.text = orgData['address'] ?? '';
      } else {
        // Individual user (beneficiary) data
        final profileData = data['profile'] ?? {};

        _contactNameCtrl.text = profileData['name'] ?? '';
        _phoneCtrl.text = profileData['phone'] ?? '';
        _addressCtrl.text = profileData['address'] ?? '';
      }
    }

    setState(() => _loading = false);
  }

  /// Saves updated profile information back to Firestore
  ///
  /// Uses form validation to ensure all required fields
  /// are filled correctly before updating.
  ///
  /// The update path differs depending on user type:
  /// - Organization → organization.*
  /// - Individual → profile.*
  Future<void> _saveProfile() async {
    // Validate form fields
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    // Get current user's UID
    final uid = FirebaseAuth.instance.currentUser!.uid;

    if (_isOrganization) {
      // Update organization profile fields
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        "email": _emailCtrl.text.trim(),
        "organization.organization_name": _orgNameCtrl.text.trim(),
        "organization.contactName": _contactNameCtrl.text.trim(),
        "organization.phone": _phoneCtrl.text.trim(),
        "organization.address": _addressCtrl.text.trim(),
      });
    } else {
      // Update individual user profile fields
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        "email": _emailCtrl.text.trim(),
        "profile.name": _contactNameCtrl.text.trim(),
        "profile.phone": _phoneCtrl.text.trim(),
        "profile.address": _addressCtrl.text.trim(),
      });
    }

    setState(() => _loading = false);

    // Show success message and return to previous screen
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully')),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Primary theme color for Feedigo
    const orange = Color.fromARGB(255, 255, 109, 36);

    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F7),
      appBar: AppBar(
        backgroundColor: orange,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        title: const Text(
          'Edit Profile',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),

      // Show loading indicator while data is loading/saving
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : Padding(
                padding: const EdgeInsets.all(16),

                // Form widget to group input fields
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      // Organization Name field
                      // Displayed ONLY if the user is an organization
                      if (_isOrganization)
                        Column(
                          children: [
                            TextFormField(
                              controller: _orgNameCtrl,
                              decoration: const InputDecoration(
                                labelText: "Organization Name",
                                prefixIcon: Icon(Icons.apartment),
                                border: OutlineInputBorder(),
                              ),
                              validator:
                                  (value) =>
                                      value!.isEmpty
                                          ? "Please enter organization name"
                                          : null,
                            ),
                            const SizedBox(height: 16),
                          ],
                        ),

                      // Name or Contact Name field
                      TextFormField(
                        controller: _contactNameCtrl,
                        decoration: InputDecoration(
                          labelText: _isOrganization ? "Contact Name" : "Name",
                          prefixIcon: const Icon(Icons.person),
                          border: const OutlineInputBorder(),
                        ),
                        validator:
                            (value) =>
                                value!.isEmpty ? "Please enter a name" : null,
                      ),
                      const SizedBox(height: 16),

                      // Email field
                      TextFormField(
                        controller: _emailCtrl,
                        decoration: const InputDecoration(
                          labelText: "Email",
                          prefixIcon: Icon(Icons.email),
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return "Please enter an email";
                          }
                          if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value)) {
                            return "Enter a valid email";
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Phone number field
                      TextFormField(
                        controller: _phoneCtrl,
                        decoration: const InputDecoration(
                          labelText: "Phone",
                          prefixIcon: Icon(Icons.phone),
                          border: OutlineInputBorder(),
                        ),
                        validator:
                            (value) =>
                                value!.isEmpty
                                    ? "Please enter a phone number"
                                    : null,
                      ),
                      const SizedBox(height: 16),

                      // Address field
                      TextFormField(
                        controller: _addressCtrl,
                        decoration: const InputDecoration(
                          labelText: "Address",
                          prefixIcon: Icon(Icons.location_city),
                          border: OutlineInputBorder(),
                        ),
                        validator:
                            (value) =>
                                value!.isEmpty
                                    ? "Please enter an address"
                                    : null,
                      ),
                      const SizedBox(height: 24),

                      // Save button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _saveProfile,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: orange,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text(
                            "Save",
                            style: TextStyle(fontSize: 16, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
    );
  }
}
