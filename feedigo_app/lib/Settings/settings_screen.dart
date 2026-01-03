import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const orange = Color.fromARGB(255, 255, 109, 36);
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      return const Scaffold(body: Center(child: Text('Not signed in')));
    }

    final uid = currentUser.uid;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F7),
      appBar: AppBar(
        backgroundColor: orange,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        title: const Text(
          'Settings',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream:
            FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text('User data not found'));
          }

          final userData = snapshot.data!.data()!;
          final isOrganization = userData['isOrganization'] == true;
          final email = userData['email'] ?? '';

          List<Widget> accountInfoWidgets = [];

          if (isOrganization) {
            final orgData = userData['organization'] ?? {};
            final orgName = orgData['organization_name'] ?? '';
            final contactName = orgData['contactName'] ?? '';
            final phone = orgData['phone'] ?? '';
            final address = orgData['address'] ?? '';

            accountInfoWidgets = [
              _infoRow(Icons.apartment, 'Organization Name', orgName),
              _infoRow(Icons.person, 'Contact Name', contactName),
              _infoRow(Icons.email, 'Email', email),
              _infoRow(Icons.phone, 'Phone', phone),
              _infoRow(Icons.location_city, 'Address', address),
            ];
          } else {
            final profileData = userData['profile'] ?? {};
            final name = profileData['name'] ?? '';
            final phone = profileData['phone'] ?? '';
            final address = profileData['address'] ?? '';

            accountInfoWidgets = [
              _infoRow(Icons.person, 'Name', name),
              _infoRow(Icons.email, 'Email', email),
              _infoRow(Icons.phone, 'Phone', phone),
              _infoRow(Icons.location_city, 'Address', address),
            ];
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Account Info Card
                _sectionCard(
                  children: [
                    ...accountInfoWidgets,
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        icon: const Icon(Icons.edit, color: orange),
                        onPressed: () {
                          Navigator.pushNamed(context, '/edit_profile');
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Security Section
                _sectionCard(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.lock, color: Colors.orange),
                      title: const Text('Change Password'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.pushNamed(context, '/change_password');
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.logout, color: Colors.red),
                      title: const Text(
                        'Log Out',
                        style: TextStyle(color: Colors.red),
                      ),
                      onTap: () async {
                        await FirebaseAuth.instance.signOut();
                        Navigator.pushNamedAndRemoveUntil(
                          context,
                          '/auth',
                          (route) => false,
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Role Management
                _sectionCard(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.badge, color: Colors.orange),
                      title: const Text('Current Role'),
                      subtitle: Text(userData['role'] ?? 'Not set'),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: orange,
                          minimumSize: const Size.fromHeight(45),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon: const Icon(Icons.swap_horiz, color: Colors.white),
                        label: const Text(
                          'Switch Role',
                          style: TextStyle(color: Colors.white),
                        ),
                        onPressed: () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder:
                                (ctx) => AlertDialog(
                                  title: const Text('Switch Role'),
                                  content: const Text(
                                    'Are you sure you want to switch your role? You will be guided to choose a new role and set up its profile.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed:
                                          () => Navigator.pop(ctx, false),
                                      child: const Text('Cancel'),
                                    ),
                                    ElevatedButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text('Yes'),
                                    ),
                                  ],
                                ),
                          );

                          if (confirmed == true) {
                            // navigate to role selection. pass a flag so RoleSelectionScreen knows it was triggered from settings
                            Navigator.pushNamed(
                              context,
                              '/role_selection',
                              arguments: {'fromSwitch': true},
                            );
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          );
        },
      ),
    );
  }

  static Widget _sectionCard({required List<Widget> children}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(children: children),
    );
  }

  static Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      child: Row(
        children: [
          Icon(icon, color: Colors.orange),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.black,
                    //fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
