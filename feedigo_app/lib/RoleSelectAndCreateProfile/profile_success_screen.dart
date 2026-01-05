/*
This screen appears after the user successfully creates their profile. It shows a success message, 
plays confetti animations for visual feedback, and provides a button to navigate to the 
appropriate dashboard based on the user’s role (Donor, Food Bank, or Beneficiary).
    - Uses ConfettiController to show blast and rain animations.
    - Retrieves the user role from Firestore (or passed argument) to determine dashboard.
    - Provides feedback using a success icon and text.
    - Uses FutureBuilder to handle asynchronous role fetching gracefully.
*/

// Firebase Firestore and Authentication
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Confetti animation package
import 'package:confetti/confetti.dart';

// Flutter UI
import 'package:flutter/material.dart';

// Dart math library for pi
import 'dart:math';

/// ProfileSuccessScreen
/// --------------------------------------------------
/// Screen shown after the user successfully creates
/// a profile. Features:
/// - Confetti animations (blast + rain)
/// - Success message
/// - Button navigation to role-specific dashboard
class ProfileSuccessScreen extends StatefulWidget {
  const ProfileSuccessScreen({super.key});

  @override
  State<ProfileSuccessScreen> createState() => _ProfileSuccessScreenState();
}

class _ProfileSuccessScreenState extends State<ProfileSuccessScreen> {
  // ==========================
  // CONFETTI CONTROLLERS
  // ==========================
  late final ConfettiController _blast; // short burst confetti
  late final ConfettiController _rain; // long rain effect

  @override
  void initState() {
    super.initState();

    // Initialize confetti controllers with duration
    _blast = ConfettiController(duration: const Duration(seconds: 1));
    _rain = ConfettiController(duration: const Duration(seconds: 5));

    // Start confetti animations immediately
    _blast.play();
    _rain.play();
  }

  @override
  void dispose() {
    // Dispose controllers to prevent memory leaks
    _blast.dispose();
    _rain.dispose();
    super.dispose();
  }

  // ==========================
  // FETCH USER ROLE
  // ==========================

  /// Retrieves the user's role from Firestore
  /// If passedRole is provided, uses that instead
  Future<String> _getRole(String? passedRole) async {
    if (passedRole != null && passedRole.isNotEmpty) return passedRole;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return 'Beneficiary';

    final snap =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();

    return (snap.data()?['role'] as String?) ?? 'Beneficiary';
  }

  /// Maps role to specific dashboard route
  String _routeForRole(String role) {
    if (role == 'Donor') return '/donor_dashboard';
    if (role == 'Food Bank') return '/foodbank_dashboard';
    return '/beneficiary_dashboard';
  }

  // ==========================
  // UI BUILD
  // ==========================

  @override
  Widget build(BuildContext context) {
    const orange = Color.fromARGB(255, 255, 109, 36);

    // Arguments passed from previous screen (optional role)
    final args = ModalRoute.of(context)?.settings.arguments as String?;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F7),

      // ==========================
      // APP BAR
      // ==========================
      appBar: AppBar(
        backgroundColor: orange,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            // Navigate back if possible
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else {
              // Fallback: go to profile setup
              Navigator.pushReplacementNamed(context, '/profile_setup');
            }
          },
        ),
      ),

      // ==========================
      // BODY
      // ==========================
      body: SafeArea(
        child: FutureBuilder<String>(
          future: _getRole(args), // Get user role from Firestore
          builder: (context, snap) {
            final role = snap.data; // role value when ready

            return Stack(
              alignment: Alignment.topCenter,
              children: [
                // ==========================
                // MAIN SUCCESS MESSAGE
                // ==========================
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Circle icon indicating success
                        Container(
                          width: 110,
                          height: 110,
                          decoration: const BoxDecoration(
                            color: orange,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check,
                            color: Colors.white,
                            size: 56,
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Success text
                        const Text(
                          'You have successfully created your profile !!!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 24),

                        // ==========================
                        // NAVIGATION BUTTON
                        // ==========================
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed:
                                (snap.connectionState ==
                                        ConnectionState.waiting)
                                    ? null // disable if loading
                                    : () {
                                      final r = role ?? 'Beneficiary';
                                      Navigator.pushNamedAndRemoveUntil(
                                        context,
                                        _routeForRole(
                                          r,
                                        ), // go to role-specific dashboard
                                        (route) => false,
                                      );
                                    },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: orange,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 2,
                            ),
                            child:
                                (snap.connectionState ==
                                        ConnectionState.waiting)
                                    ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                    : const Text('Go to Homepage'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ==========================
                // CONFETTI EFFECTS
                // ==========================

                // Blast confetti (short, explosive)
                ConfettiWidget(
                  confettiController: _blast,
                  blastDirection: pi / 2, // upward
                  blastDirectionality: BlastDirectionality.explosive,
                  emissionFrequency: 0.8,
                  numberOfParticles: 30,
                  gravity: 0.9,
                  shouldLoop: false,
                  colors: const [
                    orange,
                    Colors.deepOrange,
                    Colors.amber,
                    Colors.pinkAccent,
                    Colors.white,
                  ],
                ),

                // Rain confetti (long, directional from top)
                Positioned(
                  top: 0,
                  child: ConfettiWidget(
                    confettiController: _rain,
                    blastDirection: pi / 2,
                    blastDirectionality: BlastDirectionality.directional,
                    emissionFrequency: 0.03,
                    numberOfParticles: 5,
                    maxBlastForce: 8,
                    minBlastForce: 2,
                    gravity: 0.2,
                    shouldLoop: false,
                    colors: const [
                      orange,
                      Colors.deepOrange,
                      Colors.amber,
                      Colors.pinkAccent,
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
