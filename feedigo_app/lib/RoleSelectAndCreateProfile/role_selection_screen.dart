/*
  This screen implements a role selection interface using PageView, providing an intuitive and modern onboarding experience.
  Key technical points:
    - Uses PageController to manage horizontal swipe navigation
    - Role selection logic is decoupled from database operations
    - Uses route arguments to support role switching
    - Reusable UI components improve maintainability and scalability
    - Animated indicators enhance UX feedback
  This design follows clean architecture principles, keeping UI and data persistence responsibilities separate.
*/

import 'package:flutter/material.dart';

// ===============================
// ROLE SELECTION SCREEN
// ===============================
//
// Allows new users to select how they want to participate in FeediGo.
//  Roles available: Donor, Food Bank, Beneficiary.
//
//  Uses a PageView-based UI to present role information
//  Role is passed to the profile setup screen

class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  final PageController _pageController =
      PageController(); // Controller to manage horizontal page swiping
  int _currentPage = 0; // Tracks the currently visible role page

  // --------------------------
  // ROLE SELECTION HANDLER
  // --------------------------
  //  Navigates user to profile setup with selected role
  //  Keeps role selection UI separate from database logic
  void _onRoleSelected(String role) {
    final args = ModalRoute.of(context)?.settings.arguments;

    // Used when user is switching roles from settings
    final fromSwitch = args is Map && args['fromSwitch'] == true;

    Navigator.pushReplacementNamed(
      context,
      '/profile_setup',
      arguments: {'fromSwitch': fromSwitch, 'targetRole': role},
    );
  }

  // --------------------------
  // PAGE INDICATOR DOTS
  // --------------------------
  //  Shows which role page is currently active
  //  Uses AnimatedContainer for smooth UI feedback
  Widget _buildIndicator(int index) {
    final bool isActive = index == _currentPage;

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

  // --------------------------
  // UI BUILD
  // --------------------------
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

            // Screen title
            const Text(
              "Choose Your Role",
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),

            const SizedBox(height: 8),

            // Subtitle
            const Text(
              "Select how you want to participate in\nFeediGo",
              style: TextStyle(fontSize: 13, color: Colors.white70),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 14),

            // --------------------------
            // ROLE PAGES
            // --------------------------
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
                    onPressed: () => _onRoleSelected('Donor'),
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
                    onPressed: () => _onRoleSelected('Food Bank'),
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
                    onPressed: () => _onRoleSelected('Beneficiary'),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Page indicator dots
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

  // --------------------------
  // ROLE CARD COMPONENT
  // --------------------------
  //  Reusable UI widget to display each role
  //  Improves modularity and reduces duplicated code
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
                style: const TextStyle(fontSize: 12, color: Colors.black54),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 14),

              // Role feature points
              ...points.map(
                (point) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.circle,
                        size: 6,
                        color: Color(0xFFE26A2C),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          point,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Continue button
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE26A2C),
                  foregroundColor: Colors.white,
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
