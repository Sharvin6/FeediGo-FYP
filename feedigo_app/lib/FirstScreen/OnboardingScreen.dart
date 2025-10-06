import 'package:flutter/material.dart';

class OnboardingScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE26A2C), // FeediGo orange
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),

              // Title
              const Text(
                'Welcome to FeediGO',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),

              // Description
              const Text(
                'Together, let’s fight hunger and reduce food waste — one meal at a time.',
                style: TextStyle(fontSize: 16, color: Colors.white),
              ),

              const Spacer(),

              // Button
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFFE26A2C),
                ),
                onPressed: () {
                  Navigator.pushReplacementNamed(context, '/auth');
                },
                child: const Text("Let’s Get Started"),
              ),

              const SizedBox(height: 40), // bottom space
            ],
          ),
        ),
      ),
    );
  }
}
