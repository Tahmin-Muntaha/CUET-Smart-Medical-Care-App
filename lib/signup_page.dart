import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'home_page.dart'; // LandingPage is defined here

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  bool isStudent = true;
  bool isLoading = false;

  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final studentIdController = TextEditingController();
  final sessionController = TextEditingController();
  final licenseNumberController = TextEditingController();

  bool obscurePassword = true;

  static const String _studentEmailDomain = '@student.cuet.ac.bd';

  @override
  void initState() {
    super.initState();
    // Keep the student's email in sync with their Student ID automatically.
    studentIdController.addListener(_syncStudentEmail);
  }

  void _syncStudentEmail() {
    if (!isStudent) return;
    final id = studentIdController.text.trim();
    setState(() {
      emailController.text = id.isEmpty ? '' : 'u$id$_studentEmailDomain';
    });
  }

  @override
  void dispose() {
    studentIdController.removeListener(_syncStudentEmail);
    nameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    studentIdController.dispose();
    sessionController.dispose();
    licenseNumberController.dispose();
    super.dispose();
  }

  Future<void> handleSignUp() async {
    if (nameController.text.trim().isEmpty ||
        emailController.text.trim().isEmpty ||
        passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill in all required fields.'),
        ),
      );
      return;
    }

    if (isStudent) {
      if (studentIdController.text.trim().isEmpty ||
          sessionController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter your Student ID and Session.'),
          ),
        );
        return;
      }
      // Safety check: the email must match the auto-generated pattern.
      final expectedEmail =
          'u${studentIdController.text.trim()}$_studentEmailDomain';
      if (emailController.text.trim() != expectedEmail) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Student email must be $expectedEmail — '
              'please re-enter your Student ID.',
            ),
          ),
        );
        return;
      }
    } else {
      if (licenseNumberController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter your Medical License Number.'),
          ),
        );
        return;
      }
    }

    setState(() => isLoading = true);

    try {
      // 1. Create the auth account
      final userCredential =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text,
      );

      final uid = userCredential.user!.uid;

      // 2. Save the extra profile info to Firestore.
      // Students are approved immediately; doctors need admin approval
      // before they can log in (checked at login time via `status`).
      try {
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'name': nameController.text.trim(),
          'email': emailController.text.trim(),
          'role': isStudent ? 'student' : 'doctor',
          'status': isStudent ? 'approved' : 'pending',
          if (isStudent) 'studentId': studentIdController.text.trim(),
          if (isStudent) 'session': sessionController.text.trim(),
          if (!isStudent)
            'licenseNumber': licenseNumberController.text.trim(),
          'createdAt': FieldValue.serverTimestamp(),
        });
      } catch (firestoreError) {
        debugPrint('FIRESTORE WRITE FAILED: $firestoreError');
        rethrow;
      }

      if (!mounted) return;

      if (isStudent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Student account created successfully!')),
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => LandingPage()),
        );
      } else {
        // Doctor accounts need approval — sign them out and send them back
        // to the landing/login screen with a clear message instead of
        // letting them straight into the app.
        await FirebaseAuth.instance.signOut();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Doctor account submitted! An admin must approve your '
              'account before you can log in.',
            ),
            duration: Duration(seconds: 4),
          ),
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => LandingPage()),
        );
      }
    } on FirebaseAuthException catch (e) {
      String message;
      switch (e.code) {
        case 'email-already-in-use':
          message = 'An account already exists for that email.';
          break;
        case 'weak-password':
          message = 'Password should be at least 6 characters.';
          break;
        case 'invalid-email':
          message = 'That email address looks invalid.';
          break;
        default:
          message = 'Sign up failed: ${e.message}';
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Something went wrong: $e')),
      );
    } finally {
      if (mounted) setState(() => isLoading = false);
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
          'Create Account',
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
              // ==========================================================
              // HEADER
              // ==========================================================

              const SizedBox(height: 10),

              Container(
                width: 65,
                height: 65,
                decoration: BoxDecoration(
                  color: const Color(0xFFE7EEFF),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.local_hospital_rounded,
                  color: Color(0xFF003D9B),
                  size: 34,
                ),
              ),

              const SizedBox(height: 16),

              const Text(
                'Join CUET Medical Care',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF111C2D),
                ),
              ),

              const SizedBox(height: 7),

              const Text(
                'Create your account to access smart healthcare services.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF737685),
                  height: 1.5,
                ),
              ),

              const SizedBox(height: 25),

              // ==========================================================
              // STUDENT / DOCTOR TOGGLE
              // ==========================================================

              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFFC3C6D6),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _ToggleButton(
                        title: 'Student',
                        icon: Icons.school_outlined,
                        selected: isStudent,
                        onTap: () {
                          setState(() {
                            isStudent = true;
                            _syncStudentEmail();
                          });
                        },
                      ),
                    ),

                    const SizedBox(width: 5),

                    Expanded(
                      child: _ToggleButton(
                        title: 'Doctor',
                        icon: Icons.medical_services_outlined,
                        selected: !isStudent,
                        onTap: () {
                          setState(() {
                            isStudent = false;
                            emailController.clear();
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ==========================================================
              // FORM CARD
              // ==========================================================

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: const Color(0xFFC3C6D6),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isStudent
                          ? 'Student Registration'
                          : 'Doctor Registration',
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF111C2D),
                      ),
                    ),

                    const SizedBox(height: 5),

                    Text(
                      isStudent
                          ? 'Enter your CUET student information.'
                          : 'Enter your professional account information. '
                              'Your account will need admin approval before you can log in.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF737685),
                      ),
                    ),

                    const SizedBox(height: 22),

                    // NAME
                    _InputField(
                      controller: nameController,
                      label: 'Full Name',
                      hint: isStudent
                          ? 'e.g. Md. Rahim Ahmed'
                          : 'e.g. Dr. John Ahmed',
                      icon: Icons.person_outline,
                    ),

                    const SizedBox(height: 15),

                    // STUDENT ID must come before email since email is
                    // derived from it.
                    if (isStudent) ...[
                      _InputField(
                        controller: studentIdController,
                        label: 'CUET Student ID',
                        hint: 'e.g. 2204030',
                        icon: Icons.badge_outlined,
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 15),
                    ],

                    // EMAIL
                    Text(
                      'Email Address',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF111C2D),
                      ),
                    ),
                    const SizedBox(height: 7),
                    TextField(
                      controller: emailController,
                      readOnly: isStudent,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        hintText: isStudent
                            ? 'Auto-filled from your Student ID'
                            : 'example@email.com',
                        prefixIcon: const Icon(Icons.email_outlined, size: 20),
                        filled: true,
                        fillColor: isStudent
                            ? const Color(0xFFEDEFF5)
                            : const Color(0xFFF9F9FF),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(13),
                          borderSide:
                              const BorderSide(color: Color(0xFFC3C6D6)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(13),
                          borderSide:
                              const BorderSide(color: Color(0xFFC3C6D6)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(13),
                          borderSide: const BorderSide(
                            color: Color(0xFF003D9B),
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                    if (isStudent)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Generated as u<StudentID>@student.cuet.ac.bd',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Color(0xFF737685),
                          ),
                        ),
                      ),

                    const SizedBox(height: 15),

                    // PASSWORD
                    const Text(
                      'Password',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF111C2D),
                      ),
                    ),

                    const SizedBox(height: 7),

                    TextField(
                      controller: passwordController,
                      obscureText: obscurePassword,
                      decoration: InputDecoration(
                        hintText: 'Create a password',
                        prefixIcon: const Icon(
                          Icons.lock_outline,
                          size: 20,
                        ),
                        suffixIcon: IconButton(
                          onPressed: () {
                            setState(() {
                              obscurePassword = !obscurePassword;
                            });
                          },
                          icon: Icon(
                            obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
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
                      ),
                    ),

                    // =====================================================
                    // STUDENT ONLY FIELDS
                    // =====================================================

                    if (isStudent) ...[
                      const SizedBox(height: 15),

                      _InputField(
                        controller: sessionController,
                        label: 'Session',
                        hint: 'e.g. 2021-22',
                        icon: Icons.calendar_month_outlined,
                      ),
                    ],

                    // =====================================================
                    // DOCTOR ONLY FIELDS
                    // =====================================================

                    if (!isStudent) ...[
                      const SizedBox(height: 15),

                      _InputField(
                        controller: licenseNumberController,
                        label: 'Medical License Number',
                        hint: 'e.g. BMDC-A-123456',
                        icon: Icons.verified_outlined,
                      ),
                    ],

                    const SizedBox(height: 22),

                    // INFORMATION BOX
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE7F5FF),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.verified_user_outlined,
                            color: Color(0xFF003D9B),
                            size: 20,
                          ),

                          const SizedBox(width: 10),

                          Expanded(
                            child: Text(
                              isStudent
                                  ? 'Student accounts are intended for CUET students and will be used to access healthcare services.'
                                  : 'Doctor accounts are intended for authorized CUET medical professionals and require admin approval before login is enabled.',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF34506F),
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 22),

                    // CREATE ACCOUNT BUTTON
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: isLoading ? null : handleSignUp,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF003D9B),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            vertical: 16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                        child: isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                isStudent
                                    ? 'Create Student Account'
                                    : 'Submit Doctor Application',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // BACK BUTTON
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(context);
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

              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }
}

// =======================================================================
// TOGGLE BUTTON
// =======================================================================

class _ToggleButton extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ToggleButton({
    required this.title,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF003D9B)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 19,
              color: selected
                  ? Colors.white
                  : const Color(0xFF737685),
            ),

            const SizedBox(width: 7),

            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: selected
                    ? Colors.white
                    : const Color(0xFF737685),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =======================================================================
// INPUT FIELD
// =======================================================================

class _InputField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final TextInputType keyboardType;

  const _InputField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.keyboardType = TextInputType.text,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Color(0xFF111C2D),
          ),
        ),

        const SizedBox(height: 7),

        TextField(
          controller: controller,
          keyboardType: keyboardType,
          decoration: InputDecoration(
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
          ),
        ),
      ],
    );
  }
}