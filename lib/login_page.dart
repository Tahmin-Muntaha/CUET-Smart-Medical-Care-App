// ============================================================

//
// QUICK FLOW OF THIS FILE:
//  Enter Student ID/email + password -> tap Sign In -> handleLogin():
//   validate -> Firebase Auth checks password -> Firestore gives 'role'
//   -> doctor not approved? blocked | otherwise open matching dashboard
//   (student / doctor / admin). Errors shown as SnackBar.
// ============================================================

// >> NOTE: IMPORTS: material = UI | firebase_auth = login | cloud_firestore = read user role | the 3 dashboards = where we go after login | signup_page = register link.
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'signup_page.dart';
import 'student_home_page.dart';
import 'doctor_dashboard.dart';
import 'admin_dashboard.dart';

// >> NOTE: SCREEN: Login page for ALL 3 users (student, doctor, admin).
// >>       StatefulWidget because the screen changes (loading spinner, show/hide password, checkbox) -> setState().
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

// >> NOTE: STATE CLASS: variables + login logic + UI of this screen.
class _LoginPageState extends State<LoginPage> {
  // >> NOTE: CONTROLLERS: read what the user typed. userIdController = Email OR Student ID, passwordController = password.
  final TextEditingController userIdController =
      TextEditingController();

  final TextEditingController passwordController =
      TextEditingController();

  // >> NOTE: obscurePassword: password hidden as dots (eye icon flips it).
  bool obscurePassword = true;
  // >> NOTE: rememberMe: checkbox value (UI only - it is not used in the login logic).
  bool rememberMe = true;
  // >> NOTE: isLoading: true while Firebase is checking -> buttons disabled + spinner.
  bool isLoading = false;

  // >> NOTE: Constants: CUET student email domain and the fixed admin email.
  static const String _studentEmailDomain =
      '@student.cuet.ac.bd';

  // >> NOTE: Admin is recognised by this fixed email (admin@gmail.com).
  static const String _adminEmail =
      'admin@gmail.com';

  @override
  // >> NOTE: dispose(): free the controllers when leaving the screen.
  void dispose() {
    userIdController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  // >> NOTE: SMART INPUT: user can type Student ID OR full email.
  // >>       If it contains '@' -> use as it is (doctor/admin).
  // >>       Otherwise -> build student email: 2204030 -> u2204030@student.cuet.ac.bd
  String _resolveEmail(String rawInput) {
    final input = rawInput.trim();

    if (input.contains('@')) {
      return input;
    }

    return 'u$input$_studentEmailDomain';
  }

  // >> NOTE: MAIN BACKEND FUNCTION - runs when 'Sign In' is tapped (or Enter on keyboard).
  // >>       FLOW: validate -> resolve email -> loading -> (admin? special path) -> Firebase sign in -> read role from Firestore -> check approval -> open correct dashboard -> handle errors -> stop loading.
  Future<void> handleLogin() async {
    // >> NOTE: Guard: if already logging in, ignore extra taps (prevents double login).
    if (isLoading) return;

    final rawInput = userIdController.text.trim();
    final password = passwordController.text.trim();

    // >> NOTE: STEP 1 - VALIDATION: both fields must be filled, otherwise show a message and stop (return).
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

    // >> NOTE: STEP 2 - convert the input to a real email.
    final email = _resolveEmail(rawInput);

    // >> NOTE: STEP 3 - START LOADING: spinner appears and buttons are disabled.
    setState(() {
      isLoading = true;
    });

    try {
      // >> NOTE: ADMIN PATH: if the email is the admin email, use the separate _loginAdmin() function and stop here.
      if (email.toLowerCase() == _adminEmail) {
        await _loginAdmin(password);
        return;
      }

      final userCredential =
          // >> NOTE: STEP 4 - FIREBASE AUTH: checks email + password. Wrong data throws FirebaseAuthException (handled below).
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

      // >> NOTE: uid = unique ID of the logged-in user. It is the document ID in the 'users' collection.
      final uid = user.uid;

      // >> NOTE: STEP 5 - FIRESTORE: read users/{uid} to get the profile (role and status that were saved at sign up).
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();

      // >> NOTE: Account exists in Auth but has no profile in Firestore -> sign out and show a message.
      if (!userDoc.exists) {
        await FirebaseAuth.instance.signOut();

        if (!mounted) return;

        _showMessage(
          'No profile found for this account.',
        );

        return;
      }

      final data = userDoc.data()!;

      // >> NOTE: role = 'student' / 'doctor' / 'admin'. It decides which dashboard opens (ROLE-BASED ACCESS).
      final role = data['role'] as String?;

      // >> NOTE: status = 'approved' / 'pending' / rejected. Default 'approved' for students who have no status.
      final status =
          data['status'] as String? ?? 'approved';

      // >> NOTE: STEP 6 - DOCTOR APPROVAL CHECK: doctor is blocked until admin approves.
      // >>       Sign out immediately and show 'awaiting approval' (pending) or 'not approved' message.
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

      // >> NOTE: STEP 7 - ROUTING by role: student -> StudentHome | doctor -> DoctorDashboard | admin -> AdminDashboardPage | anything else -> sign out.
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
    // >> NOTE: STEP 8 - ERROR HANDLING: catches login errors and shows a friendly message based on e.code.
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      String message;

      switch (e.code) {
        // >> NOTE: Common errors: user-not-found | wrong-password / invalid-credential | invalid-email | user-disabled | too-many-requests.
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
    // >> NOTE: Catches any other unexpected error.
    } catch (e) {
      if (!mounted) return;

      _showMessage(
        'Something went wrong. Please try again.',
      );
    // >> NOTE: STEP 9 - finally ALWAYS runs: stop the loading spinner (if the screen still exists).
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  // >> NOTE: ADMIN LOGIN: only Firebase Auth is used here (no Firestore role check).
  // >>       Sign in with the fixed admin email + typed password -> open admin dashboard. Errors handled the same way.
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

  // >> NOTE: NAVIGATION: pushAndRemoveUntil opens the dashboard and REMOVES all previous screens.
  // >>       (route) => false means the Back button cannot return to login after login.
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
  // >> NOTE: Doctor dashboard needs the doctor's uid so it can load only this doctor's profile and appointments.
  void _openDoctorDashboard() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => DoctorDashboard(
          // >> NOTE: currentUser!.uid = id of the currently logged-in user (safe here because login just succeeded).
          doctorId: FirebaseAuth.instance.currentUser!.uid,
        ),
      ),
      (route) => false,
    );
  }

  // >> NOTE: Opens the admin dashboard.
  void _openAdminDashboard() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const AdminDashboardPage(),
      ),
      (route) => false,
    );
  }

  // >> NOTE: HELPER: shows a floating SnackBar message. Hides the old one first. 'mounted' check avoids errors if screen is closed.
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

  // >> NOTE: FORGOT PASSWORD: needs the email/ID typed first -> Firebase sends a reset link to that email with sendPasswordResetEmail().
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
  // >> NOTE: BUILD (UI): Scaffold -> AppBar + scrollable Column with ONE big white card (header, form, footer) + Back button.
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
                // >> NOTE: Clip: keeps the inner coloured sections inside the card's rounded corners.
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
                            // >> NOTE: CARD TOP (header section): logo, app name, short description - static widgets.
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
                              // >> NOTE: CARD MIDDLE (form) - FIELD 1: one box for Student ID or email. Hint tells the user how to enter it.
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
                            // >> NOTE: Text field connected to userIdController. keyboardType emailAddress shows the @ keyboard; 'next' moves to the password field.
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
                                // >> NOTE: FIELD 2: password + 'Forgot Password?' button (calls forgotPassword, disabled while loading).
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
                            // >> NOTE: Hides password characters. textInputAction.done + onSubmitted -> pressing Enter on the keyboard also calls handleLogin().
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
                              // >> NOTE: Eye icon: flips obscurePassword with setState -> show/hide password.
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
                              // >> NOTE: Remember-me checkbox: changes rememberMe with setState (display only).
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
                                  // >> NOTE: UI -> BACKEND CONNECTION: the 'Sign In to SmartCare' button calls handleLogin(). onPressed is null (disabled) while isLoading is true.
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
                                          // >> NOTE: Button content: spinner while loading, otherwise text + icon.
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
                                // >> NOTE: SIGN UP LINK: Navigator.push opens SignUpPage on top of login (Back returns here).
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
                            // >> NOTE: CARD BOTTOM (footer): static info strip.
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
                  // >> NOTE: Back button: Navigator.pop() closes login and returns to the landing page.
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

  // >> NOTE: REUSABLE STYLE FUNCTION: returns the same rounded input design (grey fill, border, blue focus border).
  // >>       Used by both text fields -> avoids repeating code. .copyWith() adds the eye icon for the password field.
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
