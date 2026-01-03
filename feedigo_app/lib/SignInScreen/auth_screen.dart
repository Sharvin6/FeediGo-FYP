import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool isSignIn = true;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;
  String _errorMessage = '';

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> handleAuth() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

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
        // SIGN IN
        final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
        await _routeByRole(cred.user);
      } else {
        // SIGN UP
        final userCredential = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(email: email, password: password);

        if (userCredential.additionalUserInfo?.isNewUser == true) {
          // New users pick a role first
          if (!mounted) return;
          Navigator.pushReplacementNamed(context, '/role_selection');
        } else {
          await _routeByRole(userCredential.user);
        }
      }
    } on FirebaseAuthException catch (e) {
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
          case 'weak-password':
            _errorMessage = 'Password should be at least 6 characters.';
            break;
          case 'invalid-email':
            _errorMessage = 'Please enter a valid email address.';
            break;
          default:
            _errorMessage = 'Authentication error: ${e.message}';
        }
      });
    } catch (e) {
      setState(() => _errorMessage = 'Something went wrong. Try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _routeByRole(User? user) async {
    if (user == null) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Could not get current user.');
      return;
    }

    try {
      final snap =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();

      final role = (snap.data()?['role'] as String?)?.trim();

      // If there’s no role yet, send them to the role selection
      if (role == null || role.isEmpty) {
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/role_selection');
        return;
      }

      String route;
      switch (role) {
        case 'Donor':
          route = '/donor_dashboard';
          break;
        case 'Food Bank':
          route = '/foodbank_dashboard';
          break;
        case 'Beneficiary':
        default:
          route = '/beneficiary_dashboard';
          break;
      }

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, route);
    } catch (e) {
      // If Firestore fails, fall back to a safe screen
      if (!mounted) return;
      setState(
        () =>
            _errorMessage =
                'Failed to fetch role. Taking you to role selection.',
      );
      Navigator.pushReplacementNamed(context, '/role_selection');
    }
  }

  // --------------------------
  // Forgot password flow
  // --------------------------
  void _showForgotPasswordDialog() {
    final ctrl = TextEditingController(text: _emailController.text.trim());
    showDialog<void>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Reset password'),
            content: TextField(
              controller: ctrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(hintText: 'Enter your email'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color.fromARGB(
                    255,
                    255,
                    109,
                    36,
                  ), // FeediGo orange
                ),
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _sendPasswordReset(ctrl.text.trim());
                },
                child: const Text('Send reset link'),
              ),
            ],
          ),
    );
  }

  Future<void> _sendPasswordReset(String email) async {
    if (email.isEmpty) {
      _showSnack('Please enter an email address.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);

      // Neutral message to avoid account enumeration
      _showSnack(
        'If an account exists for that email, a reset link has been sent.',
      );
    } on FirebaseAuthException catch (e) {
      setState(() {
        switch (e.code) {
          case 'invalid-email':
            _errorMessage = 'Please enter a valid email.';
            break;
          case 'user-not-found':
            // Keep neutral UX but optionally show a hint
            _errorMessage =
                'If an account exists for that email, a reset link has been sent.';
            break;
          case 'too-many-requests':
            _errorMessage = 'Too many attempts. Try again later.';
            break;
          default:
            _errorMessage = 'Could not send reset email: ${e.message}';
        }
      });
    } catch (_) {
      setState(() => _errorMessage = 'Something went wrong. Try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --------------------------
  // Find account (by phone) flow
  // --------------------------
  void _showFindAccountDialog() {
    final ctrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Find account'),
            content: TextField(
              controller: ctrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                hintText: 'Enter phone number (with country code)',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color.fromARGB(
                    255,
                    255,
                    109,
                    36,
                  ), // FeediGo orange
                ),
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _lookupEmailByPhone(ctrl.text.trim());
                },
                child: const Text('Find'),
              ),
            ],
          ),
    );
  }

  Future<void> _lookupEmailByPhone(String phone) async {
    if (phone.isEmpty) {
      _showSnack('Please enter a phone number.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      // Try profile.phone
      final q1 =
          await FirebaseFirestore.instance
              .collection('users')
              .where('profile.phone', isEqualTo: phone)
              .limit(1)
              .get();

      String? email;
      if (q1.docs.isNotEmpty) {
        email = q1.docs.first.data()['email'] as String?;
      } else {
        // Try organization.phone
        final q2 =
            await FirebaseFirestore.instance
                .collection('users')
                .where('organization.phone', isEqualTo: phone)
                .limit(1)
                .get();
        if (q2.docs.isNotEmpty) {
          email = q2.docs.first.data()['email'] as String?;
        }
      }

      if (email == null || email.isEmpty) {
        // Neutral response to avoid leaking info
        _showSnack(
          'If an account is linked to that phone number, we found nothing public.',
        );
      } else {
        final masked = _maskEmail(email);
        _showSnack('Found account: $masked');
      }
    } catch (e) {
      _showSnack('Lookup failed. Try again later.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _maskEmail(String? email) {
    if (email == null || !email.contains('@')) return '—';
    final parts = email.split('@');
    final local = parts[0];
    final domain = parts[1];
    final maskedLocal =
        local.length <= 2
            ? '*' * local.length
            : '${local[0]}${'*' * (local.length - 2)}${local[local.length - 1]}';
    final domainParts = domain.split('.');
    final domainName = domainParts[0];
    final tld = domainParts.skip(1).join('.');
    final maskedDomain =
        domainName.length <= 2
            ? '*' * domainName.length
            : '${domainName[0]}${'*' * (domainName.length - 2)}${domainName[domainName.length - 1]}';
    return '$maskedLocal@$maskedDomain${tld.isNotEmpty ? '.$tld' : ''}';
  }

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  // --------------------------
  // Build UI
  // --------------------------
  @override
  Widget build(BuildContext context) {
    const orange = Color.fromARGB(255, 255, 109, 36);
    return Scaffold(
      backgroundColor: orange,
      appBar: AppBar(
        backgroundColor: orange,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else {
              Navigator.pushReplacementNamed(context, '/');
            }
          },
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 8),
              const Text(
                "FEEDIGO",
                style: TextStyle(
                  fontSize: 24,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Text(
                "HUNGRY? FEEDIGO’S GOT YOU.",
                style: TextStyle(fontSize: 14, color: Colors.white),
              ),
              const SizedBox(height: 32),

              // Tabs
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap:
                        () => setState(() {
                          isSignIn = true;
                          _errorMessage = '';
                        }),
                    child: Column(
                      children: [
                        Text(
                          "Sign In",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight:
                                isSignIn ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        if (isSignIn)
                          Container(
                            height: 2,
                            width: 50,
                            color: Colors.white,
                            margin: const EdgeInsets.only(top: 4),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 24),
                  GestureDetector(
                    onTap:
                        () => setState(() {
                          isSignIn = false;
                          _errorMessage = '';
                        }),
                    child: Column(
                      children: [
                        Text(
                          "Sign Up",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight:
                                !isSignIn ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        if (!isSignIn)
                          Container(
                            height: 2,
                            width: 50,
                            color: Colors.white,
                            margin: const EdgeInsets.only(top: 4),
                          ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Email Field
              TextField(
                controller: _emailController,
                decoration: InputDecoration(
                  hintText: "Email Address",
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Password Field
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  hintText: "Password",
                  filled: true,
                  fillColor: Colors.white,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                    ),
                    onPressed:
                        () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),

              // Forgot password & find account (visible in Sign In)
              if (isSignIn) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: _isLoading ? null : _showForgotPasswordDialog,
                      child: const Text(
                        'Forgot password?',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                    TextButton(
                      onPressed: _isLoading ? null : _showFindAccountDialog,
                      child: const Text(
                        'Find account',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  ],
                ),
              ],

              // Confirm Password (Sign Up only)
              if (!isSignIn) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _confirmPasswordController,
                  obscureText: _obscureConfirmPassword,
                  decoration: InputDecoration(
                    hintText: "Confirm Password",
                    filled: true,
                    fillColor: Colors.white,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirmPassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed:
                          () => setState(
                            () =>
                                _obscureConfirmPassword =
                                    !_obscureConfirmPassword,
                          ),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 20),

              if (_errorMessage.isNotEmpty)
                Text(
                  _errorMessage,
                  style: const TextStyle(
                    color: Colors.yellowAccent,
                    fontSize: 12,
                  ),
                ),

              const SizedBox(height: 10),

              ElevatedButton(
                onPressed: _isLoading ? null : handleAuth,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: orange,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 60,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child:
                    _isLoading
                        ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(orange),
                            strokeWidth: 2,
                          ),
                        )
                        : Text(isSignIn ? "Sign In" : "Create Account"),
              ),

              const Spacer(),
              const Text(
                "Empowering communities with 🤍",
                style: TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
