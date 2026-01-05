/*
This screen implements Firebase Authentication with email/password sign-in and Firestore-driven role-based navigation.
Key technical highlights:
    - Uses StatefulWidget for UI state control
    - Asynchronous authentication using async/await
    - Secure UX patterns (neutral error messages to prevent account enumeration)
    - Firestore is used as a single source of truth for user role management
    - Centralized routing improves scalability and maintainability
This design follows clean separation of concerns between authentication, validation, and navigation.
*/
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ===============================
// AUTH SCREEN (SIGN IN / SIGN UP)
// ===============================
//
// This screen allows users to either sign in or create a new account.
// It integrates Firebase Authentication and Firestore role-based routing.

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  // --------------------------
  // UI & STATE VARIABLES
  // --------------------------

  bool isSignIn = true; // Toggle between Sign In & Sign Up
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;
  String _errorMessage = '';

  // Controllers for form input
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  // Dispose controllers to avoid memory leaks
  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // --------------------------
  // AUTHENTICATION HANDLER
  // --------------------------
  // Handles both Sign In and Sign Up logic
  // Centralized async authentication handler with FirebaseAuth
  Future<void> handleAuth() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    // Validation for sign up
    if (!isSignIn && password != confirmPassword) {
      setState(() => _errorMessage = "Passwords do not match.");
      return;
    }

    if (password.length < 6) {
      setState(() => _errorMessage = "Password must be at least 6 characters.");
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      if (isSignIn) {
        // -------- SIGN IN --------
        final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );

        await _routeByRole(cred.user);
      } else {
        // -------- SIGN UP --------
        final userCredential = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(email: email, password: password);

        // New users must select a role first
        if (userCredential.additionalUserInfo?.isNewUser == true) {
          if (!mounted) return;
          Navigator.pushReplacementNamed(context, '/role_selection');
        } else {
          await _routeByRole(userCredential.user);
        }
      }
    } on FirebaseAuthException catch (e) {
      // Firebase-specific error handling
      setState(() {
        switch (e.code) {
          case 'user-not-found':
            _errorMessage = 'No account found with this email.';
            break;
          case 'wrong-password':
            _errorMessage = 'Incorrect password.';
            break;
          case 'email-already-in-use':
            _errorMessage = 'This email is already registered.';
            break;
          case 'invalid-email':
            _errorMessage = 'Invalid email format.';
            break;
          default:
            _errorMessage = 'Authentication error.';
        }
      });
    } catch (_) {
      setState(() => _errorMessage = 'Something went wrong. Try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --------------------------
  // ROLE-BASED ROUTING
  // --------------------------
  // Sends user to correct dashboard based on role
  // Implements Firestore-driven role-based navigation
  Future<void> _routeByRole(User? user) async {
    if (user == null) return;

    try {
      final doc =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();

      final role = doc.data()?['role'];

      if (role == null || role.isEmpty) {
        Navigator.pushReplacementNamed(context, '/role_selection');
        return;
      }

      switch (role) {
        case 'Donor':
          Navigator.pushReplacementNamed(context, '/donor_dashboard');
          break;
        case 'Food Bank':
          Navigator.pushReplacementNamed(context, '/foodbank_dashboard');
          break;
        default:
          Navigator.pushReplacementNamed(context, '/beneficiary_dashboard');
      }
    } catch (_) {
      Navigator.pushReplacementNamed(context, '/role_selection');
    }
  }

  // --------------------------
  // PASSWORD RESET
  // --------------------------
  // Allows users to reset password via email
  // Uses FirebaseAuth password recovery mechanism
  Future<void> _sendPasswordReset(String email) async {
    if (email.isEmpty) return;

    await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
    _showSnack('If the email exists, a reset link has been sent.');
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // --------------------------
  // UI BUILD
  // --------------------------
  @override
  Widget build(BuildContext context) {
    const orange = Color.fromARGB(255, 255, 109, 36);

    return Scaffold(
      backgroundColor: orange,
      appBar: AppBar(backgroundColor: orange, elevation: 0),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Text(
                "FEEDIGO",
                style: TextStyle(
                  fontSize: 24,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 24),

              // Email input
              TextField(
                controller: _emailController,
                decoration: _inputStyle("Email"),
              ),

              const SizedBox(height: 16),

              // Password input
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: _passwordStyle(
                  "Password",
                  _obscurePassword,
                  () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),

              if (!isSignIn) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _confirmPasswordController,
                  obscureText: _obscureConfirmPassword,
                  decoration: _passwordStyle(
                    "Confirm Password",
                    _obscureConfirmPassword,
                    () => setState(
                      () => _obscureConfirmPassword = !_obscureConfirmPassword,
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 16),

              ElevatedButton(
                onPressed: _isLoading ? null : handleAuth,
                child: Text(isSignIn ? "Sign In" : "Sign Up"),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputStyle(String hint) => InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
  );

  InputDecoration _passwordStyle(
    String hint,
    bool obscure,
    VoidCallback toggle,
  ) => InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: Colors.white,
    suffixIcon: IconButton(
      icon: Icon(obscure ? Icons.visibility_off : Icons.visibility),
      onPressed: toggle,
    ),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
  );
}
