
//
// QUICK FLOW OF THIS FILE:
//  Open page -> choose Student/Doctor (setState) -> fill form
//  -> tap button -> handleSignUp():
//     validate -> Firebase Auth creates account -> Firestore saves profile
//     -> student: go to Landing | doctor: sign out + wait for admin approval
// ============================================================

// >> NOTE: IMPORTS: material = UI widgets | firebase_auth = login/account creation | cloud_firestore = database | home_page = LandingPage to go back to.
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'home_page.dart'; // LandingPage is defined here

// >> NOTE: SCREEN: Sign Up page for BOTH student and doctor.
// >>       StatefulWidget because the screen changes (toggle, loading spinner, password show/hide) -> uses setState().
class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

// >> NOTE: STATE CLASS: all variables + functions of the sign-up screen live here.
class _SignUpPageState extends State<SignUpPage> {
  // >> NOTE: isStudent: true = Student form, false = Doctor form. The toggle button changes it.
  bool isStudent = true;
  // >> NOTE: isLoading: true while Firebase is working -> button is disabled and shows a spinner (prevents double click).
  bool isLoading = false;

  // >> NOTE: CONTROLLERS: one per text field. They read what the user typed (e.g. nameController.text).
  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final studentIdController = TextEditingController();
  final sessionController = TextEditingController();
  final licenseNumberController = TextEditingController();

  // >> NOTE: obscurePassword: true = password shown as dots. The eye icon flips it.
  bool obscurePassword = true;

  // >> NOTE: Fixed CUET student email domain. Student email = u + StudentID + this domain.
  static const String _studentEmailDomain = '@student.cuet.ac.bd';

  @override
  // >> NOTE: initState(): runs once when the screen opens.
  // >>       Here we attach a listener so the email updates automatically when the Student ID changes.
  void initState() {
    super.initState();
    // Keep the student's email in sync with their Student ID automatically.
    // >> NOTE: LISTENER: every time the user types in Student ID, _syncStudentEmail() runs.
    studentIdController.addListener(_syncStudentEmail);
  }

  // >> NOTE: AUTO EMAIL: for students the email is generated from the ID.
  // >>       Example: ID 2204030  ->  u2204030@student.cuet.ac.bd
  // >>       Doctors skip this (return) because they type their own email.
  void _syncStudentEmail() {
    if (!isStudent) return;
    final id = studentIdController.text.trim();
    setState(() {
      emailController.text = id.isEmpty ? '' : 'u$id$_studentEmailDomain';
    });
  }

  @override
  // >> NOTE: dispose(): cleanup when leaving the screen. Remove listener and free all controllers (avoids memory leak).
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

  // >> NOTE: MAIN BACKEND FUNCTION - runs when the user taps the button.
  // >>       FLOW: 1) validate inputs  2) show loading  3) create account in Firebase Auth  4) save profile in Firestore  5) navigate  6) handle errors  7) stop loading.
  // >>       async/await = wait for Firebase without freezing the app.
  Future<void> handleSignUp() async {
    // >> NOTE: STEP 1 - VALIDATION (common): name, email and password must not be empty. If empty -> show SnackBar message and STOP (return).
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

    // >> NOTE: Student-only validation: Student ID and Session are required.
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
      // >> NOTE: SAFETY CHECK: email must exactly match the auto-generated pattern, so nobody can use a fake student email.
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
      // >> NOTE: Doctor-only validation: Medical License Number is required.
      if (licenseNumberController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter your Medical License Number.'),
          ),
        );
        return;
      }
    }

    // >> NOTE: STEP 2 - START LOADING: button disabled + spinner appears.
    setState(() => isLoading = true);

    try {
      // >> NOTE: STEP 3 - FIREBASE AUTHENTICATION
      // >>       createUserWithEmailAndPassword() creates the login account (email + password only).
      // >>       It returns a userCredential that contains the unique user id (uid).
      // 1. Create the auth account
      final userCredential =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text,
      );

      // >> NOTE: uid = unique ID of the new user. We use it as the document ID in Firestore so Auth and Firestore are linked.
      final uid = userCredential.user!.uid;

      // >> NOTE: STEP 4 - FIRESTORE: save the profile in collection 'users', document = uid.
      // >>       role = student/doctor decides which dashboard opens at login.
      // >>       status: student = 'approved' now | doctor = 'pending' until admin approves.
      // 2. Save the extra profile info to Firestore.
      // Students are approved immediately; doctors need admin approval
      // before they can log in (checked at login time via `status`).
      try {
        // >> NOTE: set({...}) writes the document. The 'if (isStudent) key: value' lines add fields only for that role (collection-if).
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'name': nameController.text.trim(),
          'email': emailController.text.trim(),
          'role': isStudent ? 'student' : 'doctor',
          'status': isStudent ? 'approved' : 'pending',
          if (isStudent) 'studentId': studentIdController.text.trim(),
          if (isStudent) 'session': sessionController.text.trim(),
          if (!isStudent)
            'licenseNumber': licenseNumberController.text.trim(),
          // >> NOTE: serverTimestamp = time taken from Firebase server (more reliable than the phone clock).
          'createdAt': FieldValue.serverTimestamp(),
        });
      } catch (firestoreError) {
        // >> NOTE: If saving fails, print it for debugging and rethrow (send the error to the outer catch).
        debugPrint('FIRESTORE WRITE FAILED: $firestoreError');
        rethrow;
      }

      // >> NOTE: mounted check: if the user already left the screen, do nothing (avoids crash when using context after await).
      if (!mounted) return;

      if (isStudent) {
        ScaffoldMessenger.of(context).showSnackBar(
          // >> NOTE: STEP 5a - STUDENT SUCCESS: show message, then go back to LandingPage with pushReplacement (this page is replaced, so Back won't return here).
          const SnackBar(content: Text('Student account created successfully!')),
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => LandingPage()),
        );
      } else {
        // >> NOTE: STEP 5b - DOCTOR: account is saved but 'pending'. Sign out immediately so the doctor cannot enter the app.
        // >>       Show a message that admin approval is needed, then go to LandingPage.
        // Doctor accounts need approval — sign them out and send them back
        // to the landing/login screen with a clear message instead of
        // letting them straight into the app.
        // >> NOTE: signOut(): Firebase automatically logs in a new user, so we log the doctor out until the admin approves.
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
    // >> NOTE: STEP 6 - ERROR HANDLING: catches Firebase Auth errors and shows a friendly message by error code.
    } on FirebaseAuthException catch (e) {
      String message;
      switch (e.code) {
        // >> NOTE: Common errors: email already used | weak password (less than 6 characters) | invalid email.
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
    // >> NOTE: Catches any other unexpected error.
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Something went wrong: $e')),
      );
    // >> NOTE: STEP 7 - finally ALWAYS runs (success or error): stop the loading spinner.
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  // >> NOTE: BUILD (UI): draws the screen. Structure: Scaffold -> AppBar + scrollable Column with Header, Toggle, Form card, Back button.
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),

      appBar: AppBar(
        backgroundColor: const Color(0xFF003D9B),
        foregroundColor: Colors.white,
        elevation: 0,
        // >> NOTE: App bar title: 'Create Account'.
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
              // >> NOTE: UI SECTION 1 - HEADER: logo icon, title and short description (static widgets).
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
              // >> NOTE: UI SECTION 2 - TOGGLE: two custom buttons (_ToggleButton).
              // >>       Tap Student -> isStudent = true | Tap Doctor -> isStudent = false and clear email. setState() redraws the form.
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
                        // >> NOTE: Student toggle button. 'selected' decides the highlighted colour.
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
                        // >> NOTE: Doctor toggle button. Email is cleared because the doctor types their own email.
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
              // >> NOTE: UI SECTION 3 - FORM CARD: white rounded box containing all input fields.
              // >>       The form CHANGES depending on isStudent (ternary ? : and if-conditions).
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
                          // >> NOTE: Heading changes with isStudent: Student Registration / Doctor Registration.
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

                    // >> NOTE: Full Name field (common for both). Uses our reusable widget _InputField.
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

                    // >> NOTE: Student ID field - shown ONLY for students (if (isStudent) ...[ ]). Keyboard type = number.
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

                    // >> NOTE: EMAIL field: students -> readOnly + grey + auto-filled (cannot edit). Doctors -> editable.
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
                      // >> NOTE: readOnly = true for students so they cannot change the generated email.
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

                    // >> NOTE: PASSWORD field with show/hide eye icon.
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
                      // >> NOTE: obscureText hides the characters as dots.
                      obscureText: obscurePassword,
                      decoration: InputDecoration(
                        hintText: 'Create a password',
                        prefixIcon: const Icon(
                          Icons.lock_outline,
                          size: 20,
                        ),
                        // >> NOTE: Eye icon button: flips obscurePassword with setState -> password becomes visible/hidden.
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
                    // >> NOTE: Extra field for students: Session (e.g. 2021-22).
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
                    // >> NOTE: Extra field for doctors: Medical License Number. Admin uses it to verify the doctor.
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

                    // >> NOTE: Blue info box. Its text changes: student info or 'admin approval required' for doctors.
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

                    // >> NOTE: SUBMIT BUTTON: onPressed = null while loading (disabled), otherwise calls handleSignUp (the backend function above).
                    // >>       Child shows spinner when loading, otherwise text that depends on isStudent.
                    // CREATE ACCOUNT BUTTON
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        // >> NOTE: UI -> BACKEND CONNECTION: this line connects the button to handleSignUp().
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

              // >> NOTE: Back button: Navigator.pop() closes this screen and returns to the previous (landing) page.
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

// >> NOTE: REUSABLE WIDGET #1: Student/Doctor toggle button. StatelessWidget (no own state - parent controls 'selected').
class _ToggleButton extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool selected;
  // >> NOTE: Values are passed in through the constructor: title, icon, selected, onTap (function to run when tapped).
  final VoidCallback onTap;

  const _ToggleButton({
    required this.title,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // >> NOTE: GestureDetector detects the tap and calls onTap.
    return GestureDetector(
      onTap: onTap,
      // >> NOTE: AnimatedContainer smoothly changes colour in 200 ms: blue when selected, transparent when not.
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

// >> NOTE: REUSABLE WIDGET #2: labelled text field (label + TextField with icon and rounded border).
// >>       Written once, used for Name, Student ID, Session and License Number -> less repeated code.
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
    // >> NOTE: Optional parameter with a default value (normal text keyboard). Student ID passes TextInputType.number.
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
