import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  void _saveUserRole(String role) async {
    final args = ModalRoute.of(context)?.settings.arguments;
    final fromSwitch = args is Map && args['fromSwitch'] == true;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    final email = FirebaseAuth.instance.currentUser?.email;

    if (uid != null) {
      final userRef = FirebaseFirestore.instance.collection('users').doc(uid);

      final baseUpdate = <String, dynamic>{
        'role': role,
        'email': email,
        'updated_at': FieldValue.serverTimestamp(),
      };

      if (!fromSwitch) {
        baseUpdate['created_at'] = FieldValue.serverTimestamp();
      }

      await userRef.set(baseUpdate, SetOptions(merge: true));

      if (fromSwitch) {
        await userRef.collection('roleChangeHistory').add({
          'newRole': role,
          'timestamp': FieldValue.serverTimestamp(),
          'triggeredBy': uid,
        });
      }

      // forward args so profile setup knows this is a switch
      Navigator.pushReplacementNamed(
        context,
        '/profile_setup',
        arguments: {'fromSwitch': fromSwitch, 'targetRole': role},
      );
    }
  }

  Widget _buildIndicator(int index) {
    bool isActive = index == _currentPage;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.symmetric(horizontal: 4),
      height: 6,
      width: isActive ? 20 : 8,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const Color orange = Color(0xFFE26A2C);

    return Scaffold(
      backgroundColor: orange,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 70),
            const Text(
              "Choose Your Role",
              style: TextStyle(
                fontSize: 50,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              "Select how you want to participate in\nFeediGo",
              style: TextStyle(fontSize: 15, color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (index) => setState(() => _currentPage = index),
                children: [
                  _buildRoleCard(
                    icon: Icons.card_giftcard,
                    title: 'Food Donor',
                    description:
                        'Share surplus food to reduce waste and help the hungry.',
                    points: [
                      'Create and manage food donations',
                      'Track donation progress and pickup',
                      'Connect with food banks and recipients',
                    ],
                    buttonText: 'Continue as Donor',
                    onPressed: () => _saveUserRole('Donor'),
                  ),
                  _buildRoleCard(
                    icon: Icons.apartment,
                    title: 'Food Bank',
                    description:
                        'Access and collect food in bulk to serve your community.',
                    points: [
                      'Browse available donations',
                      'Accept and schedule pickups',
                      'Track pickup history',
                    ],
                    buttonText: 'Continue as Food Bank',
                    onPressed: () => _saveUserRole('Food Bank'),
                  ),
                  _buildRoleCard(
                    icon: Icons.groups,
                    title: 'Beneficiary',
                    description:
                        'Receive food assistance by requesting available donations.',
                    points: [
                      'View and request available food',
                      'Schedule your preferred pickup',
                      'Track donation request status',
                    ],
                    buttonText: 'Continue as Beneficiary',
                    onPressed: () => _saveUserRole('Beneficiary'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(3, _buildIndicator),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleCard({
    required IconData icon,
    required String title,
    required String description,
    required List<String> points,
    required String buttonText,
    required VoidCallback onPressed,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(icon, size: 48, color: const Color(0xFFE26A2C)),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                description,
                style: const TextStyle(fontSize: 13, color: Colors.black54),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children:
                    points
                        .map(
                          (point) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(top: 5),
                                  child: Icon(
                                    Icons.circle,
                                    size: 6,
                                    color: Color(0xFFE26A2C),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    point,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE26A2C),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: onPressed,
                child: Text(buttonText),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
