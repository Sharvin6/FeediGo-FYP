import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'dart:math';

class ProfileSuccessScreen extends StatefulWidget {
  const ProfileSuccessScreen({super.key});

  @override
  State<ProfileSuccessScreen> createState() => _ProfileSuccessScreenState();
}

class _ProfileSuccessScreenState extends State<ProfileSuccessScreen> {
  late final ConfettiController _blast;
  late final ConfettiController _rain;

  @override
  void initState() {
    super.initState();
    _blast = ConfettiController(duration: const Duration(seconds: 1));
    _rain = ConfettiController(duration: const Duration(seconds: 5));
    _blast.play();
    _rain.play();
  }

  @override
  void dispose() {
    _blast.dispose();
    _rain.dispose();
    super.dispose();
  }

  Future<String> _getRole(String? passedRole) async {
    if (passedRole != null && passedRole.isNotEmpty) return passedRole;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return 'Beneficiary';
    final snap =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    return (snap.data()?['role'] as String?) ?? 'Beneficiary';
  }

  String _routeForRole(String role) {
    if (role == 'Donor') return '/donor_dashboard';
    if (role == 'Food Bank') return '/foodbank_dashboard';
    return '/beneficiary_dashboard';
  }

  @override
  Widget build(BuildContext context) {
    const orange = Color.fromARGB(255, 255, 109, 36);
    final args = ModalRoute.of(context)?.settings.arguments as String?;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F7),
      appBar: AppBar(
        backgroundColor: orange,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else {
              Navigator.pushReplacementNamed(context, '/profile_setup');
            }
          }, // Back to previous screen
        ),
      ),
      body: SafeArea(
        child: FutureBuilder<String>(
          future: _getRole(args),
          builder: (context, snap) {
            final role = snap.data;

            return Stack(
              alignment: Alignment.topCenter,
              children: [
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
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
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed:
                                (snap.connectionState ==
                                        ConnectionState.waiting)
                                    ? null
                                    : () {
                                      final r = role ?? 'Beneficiary';
                                      Navigator.pushNamedAndRemoveUntil(
                                        context,
                                        _routeForRole(r),
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
                ConfettiWidget(
                  confettiController: _blast,
                  blastDirection: pi / 2,
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
