import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'signup_page.dart';
import 'student_home_page.dart';
import 'doctor_dashboard.dart';
import 'admin_dashboard.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController userIdController =
      TextEditingController();

  final TextEditingController passwordController =
      TextEditingController();

  bool obscurePassword = true;
  bool rememberMe = true;
  bool isLoading = false;

  static const String _studentEmailDomain =
      '@student.cuet.ac.bd';

  static const String _adminEmail =
      'admin@gmail.com';

  @override
  void dispose() {
    userIdController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  String _resolveEmail(String rawInput) {
    final input = rawInput.trim();

    if (input.contains('@')) {
      return input;
    }

    return 'u$input$_studentEmailDomain';
  }

  Future<void> handleLogin() async {
    if (isLoading) return;

    final rawInput = userIdController.text.trim();
    final password = passwordController.text.trim();

    if (rawInput.isEmpty) {
      _showMessage(
        'Please enter your Email or Student ID.',
      );
      return;
    }

    if (password.isEmpty) {
      _showMessage(
        'Please enter your password.',
      );
      return;
    }

    final email = _resolveEmail(rawInput);

    setState(() {
      isLoading = true;
    });

    try {
      if (email.toLowerCase() == _adminEmail) {
        await _loginAdmin(password);
        return;
      }

      final userCredential =
          await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = userCredential.user;

      if (user == null) {
        _showMessage(
          'Login failed. Please try again.',
        );
        return;
      }

      final uid = user.uid;

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();

      if (!userDoc.exists) {
        await FirebaseAuth.instance.signOut();

        if (!mounted) return;

        _showMessage(
          'No profile found for this account.',
        );

        return;
      }

      final data = userDoc.data()!;

      final role = data['role'] as String?;

      final status =
          data['status'] as String? ?? 'approved';

      if (role == 'doctor' && status != 'approved') {
        await FirebaseAuth.instance.signOut();

        if (!mounted) return;

        _showMessage(
          status == 'pending'
              ? 'Your doctor account is still awaiting admin approval.'
              : 'Your doctor account was not approved. Please contact support.',
        );

        return;
      }

      if (!mounted) return;

      if (role == 'student') {
        _openStudentDashboard();
      } else if (role == 'doctor') {
        _openDoctorDashboard();
      } else if (role == 'admin') {
        _openAdminDashboard();
      } else {
        await FirebaseAuth.instance.signOut();

        if (!mounted) return;

        _showMessage(
          'Unknown account role. Please contact support.',
        );
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      String message;

      switch (e.code) {
        case 'user-not-found':
          message =
              'No account found for that email or Student ID.';
          break;

        case 'wrong-password':
        case 'invalid-credential':
          message =
              'Incorrect email/Student ID or password.';
          break;

        case 'invalid-email':
          message =
              'That email or Student ID looks invalid.';
          break;

        case 'user-disabled':
          message =
              'This account has been disabled.';
          break;

        case 'too-many-requests':
          message =
              'Too many login attempts. Please try again later.';
          break;

        default:
          message =
              'Login failed. Please try again.';
      }

      _showMessage(message);
    } catch (e) {
      if (!mounted) return;

      _showMessage(
        'Something went wrong. Please try again.',
      );
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> _loginAdmin(String password) async {
    try {
      final credential =
          await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _adminEmail,
        password: password,
      );

      final user = credential.user;

      if (user == null) {
        if (!mounted) return;

        _showMessage(
          'Admin login failed.',
        );

        return;
      }

      if (!mounted) return;

      _openAdminDashboard();
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      String message;

      switch (e.code) {
        case 'user-not-found':
          message =
              'Admin account does not exist in Firebase Authentication.';
          break;

        case 'wrong-password':
        case 'invalid-credential':
          message =
              'Incorrect admin email or password.';
          break;

        case 'invalid-email':
          message =
              'Invalid admin email.';
          break;

        case 'user-disabled':
          message =
              'The admin account has been disabled.';
          break;

        case 'too-many-requests':
          message =
              'Too many login attempts. Please try again later.';
          break;

        default:
          message =
              'Admin login failed. Please try again.';
      }

      _showMessage(message);
    } catch (e) {
      if (!mounted) return;

      _showMessage(
        'Something went wrong. Please try again.',
      );
    }
  }

  void _openStudentDashboard() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const StudentHome(),
      ),
      (route) => false,
    );
  }

  // FIXED: DoctorDashboard now requires the logged-in doctor's uid so it
  // knows whose profile/appointments to stream from Firestore. We pass
  // FirebaseAuth.instance.currentUser!.uid, which is safe here because
  // this is only ever called right after a successful sign-in above.
  void _openDoctorDashboard() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => DoctorDashboard(
          doctorId: FirebaseAuth.instance.currentUser!.uid,
        ),
      ),
      (route) => false,
    );
  }

  void _openAdminDashboard() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const AdminDashboardPage(),
      ),
      (route) => false,
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> forgotPassword() async {
    final rawInput = userIdController.text.trim();

    if (rawInput.isEmpty) {
      _showMessage(
        'Enter your email or Student ID first.',
      );
      return;
    }

    final email = _resolveEmail(rawInput);

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: email,
      );

      if (!mounted) return;

      _showMessage(
        'Password reset email sent to $email.',
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      _showMessage(
        'Could not send reset email.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        backgroundColor: const Color(0xFF003D9B),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Login',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(
                    color: const Color(0xFFC3C6D6),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 18,
                      offset: const Offset(0, 7),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(
                        24,
                        30,
                        24,
                        25,
                      ),
                      color: const Color(0xFFF0F3FF),
                      child: Column(
                        children: [
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              color: const Color(0xFF003D9B),
                              borderRadius:
                                  BorderRadius.circular(20),
                            ),
                            child: const Icon(
                              Icons.favorite_rounded,
                              color: Color(0xFF6AE1FF),
                              size: 40,
                            ),
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            'CUET SmartCare',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 25,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF003D9B),
                            ),
                          ),
                          const SizedBox(height: 5),
                          const Text(
                            'Secure digital access to your campus '
                            'medical records & appointments',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF434654),
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'CUET Email / Student ID',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF111C2D),
                              ),
                            ),
                          ),
                          const SizedBox(height: 7),
                          TextField(
                            controller: userIdController,
                            keyboardType:
                                TextInputType.emailAddress,
                            textInputAction:
                                TextInputAction.next,
                            decoration: _inputDecoration(
                              hint:
                                  'Student: 2204030   Doctor/Admin: full email',
                              icon: Icons.person_outline,
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.only(top: 6),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Students: enter just your Student ID. '
                                'Doctors/Admins: enter your full email.',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Color(0xFF737685),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Password',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF111C2D),
                                ),
                              ),
                              TextButton(
                                onPressed: isLoading
                                    ? null
                                    : forgotPassword,
                                child: const Text(
                                  'Forgot Password?',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF003D9B),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          TextField(
                            controller: passwordController,
                            obscureText: obscurePassword,
                            textInputAction:
                                TextInputAction.done,
                            onSubmitted: (_) =>
                                handleLogin(),
                            decoration:
                                _inputDecoration(
                              hint: 'Enter your password',
                              icon: Icons.lock_outline,
                            ).copyWith(
                              suffixIcon: IconButton(
                                onPressed: isLoading
                                    ? null
                                    : () {
                                        setState(() {
                                          obscurePassword =
                                              !obscurePassword;
                                        });
                                      },
                                icon: Icon(
                                  obscurePassword
                                      ? Icons
                                          .visibility_outlined
                                      : Icons
                                          .visibility_off_outlined,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Checkbox(
                                value: rememberMe,
                                activeColor:
                                    const Color(0xFF003D9B),
                                onChanged: isLoading
                                    ? null
                                    : (value) {
                                        setState(() {
                                          rememberMe =
                                              value ?? false;
                                        });
                                      },
                              ),
                              const Expanded(
                                child: Text(
                                  'Remember this device on campus network',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF434654),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: isLoading
                                  ? null
                                  : handleLogin,
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    const Color(0xFF003D9B),
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                shape:
                                    RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(13),
                                ),
                                elevation: 0,
                              ),
                              child: isLoading
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child:
                                          CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          'Sign In to SmartCare',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight:
                                                FontWeight.bold,
                                          ),
                                        ),
                                        SizedBox(width: 8),
                                        Icon(
                                          Icons.login_rounded,
                                          size: 19,
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.center,
                            children: [
                              const Text(
                                "Don't have an account? ",
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF434654),
                                ),
                              ),
                              GestureDetector(
                                onTap: isLoading
                                    ? null
                                    : () {
                                        Navigator.of(context)
                                            .push(
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const SignUpPage(),
                                          ),
                                        );
                                      },
                                child: const Text(
                                  'Student Registration',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight:
                                        FontWeight.bold,
                                    color:
                                        Color(0xFF003D9B),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        vertical: 13,
                      ),
                      color: const Color(0xFFF0F3FF),
                      child: const Row(
                        mainAxisAlignment:
                            MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons
                                .admin_panel_settings_outlined,
                            color: Color(0xFF00687A),
                            size: 17,
                          ),
                          SizedBox(width: 7),
                          Text(
                            'CUET Central IT & Medical Services Network',
                            style: TextStyle(
                              fontSize: 10,
                              color: Color(0xFF737685),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              TextButton.icon(
                onPressed: isLoading
                    ? null
                    : () {
                        Navigator.of(context).pop();
                      },
                icon: const Icon(
                  Icons.arrow_back,
                  size: 18,
                ),
                label: const Text(
                  'Back to Home',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(
        icon,
        size: 20,
      ),
      filled: true,
      fillColor: const Color(0xFFF9F9FF),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(
          color: Color(0xFFC3C6D6),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(
          color: Color(0xFFC3C6D6),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(
          color: Color(0xFF003D9B),
          width: 1.5,
        ),
      ),
    );
  }
}