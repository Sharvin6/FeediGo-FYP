import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  final _orgNameCtrl = TextEditingController();
  final _contactNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  bool _loading = false;
  bool _isOrganization = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    setState(() => _loading = true);

    final uid = FirebaseAuth.instance.currentUser!.uid;
    final doc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();

    if (doc.exists) {
      final data = doc.data()!;
      _isOrganization = data['isOrganization'] == true;
      _emailCtrl.text = data['email'] ?? '';

      if (_isOrganization) {
        final orgData = data['organization'] ?? {};
        _orgNameCtrl.text = orgData['organization_name'] ?? '';
        _contactNameCtrl.text = orgData['contactName'] ?? '';
        _phoneCtrl.text = orgData['phone'] ?? '';
      } else {
        final profileData = data['profile'] ?? {};
        _contactNameCtrl.text = profileData['name'] ?? '';
        _phoneCtrl.text = profileData['phone'] ?? '';
      }
    }

    setState(() => _loading = false);
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    final uid = FirebaseAuth.instance.currentUser!.uid;

    if (_isOrganization) {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        "email": _emailCtrl.text.trim(),
        "organization.organization_name": _orgNameCtrl.text.trim(),
        "organization.contactName": _contactNameCtrl.text.trim(),
        "organization.phone": _phoneCtrl.text.trim(),
      });
    } else {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        "email": _emailCtrl.text.trim(),
        "profile.name": _contactNameCtrl.text.trim(),
        "profile.phone": _phoneCtrl.text.trim(),
      });
    }

    setState(() => _loading = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully')),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFE26A2C);

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
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : Padding(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      // Organization Name (only for organizations)
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

                      // Name or Contact Name
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

                      // Email
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

                      // Phone
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
                      const SizedBox(height: 24),

                      // Save Button
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
