// ============================================================

//
// QUICK FLOW OF THIS FILE:
//  App opens -> LandingPage.build() draws 7 sections top to bottom
//  -> user taps Sign Up / Login -> Navigator.push opens that screen.
//  No backend / Firebase code in this file (StatelessWidget).
// ============================================================

// >> NOTE: IMPORTS: material = all UI widgets | signup_page and login_page = the two screens the buttons open.
import 'package:flutter/material.dart';
import 'signup_page.dart';
import 'login_page.dart';

// >> NOTE: SCREEN: Landing (first) page of the app.
// >>       StatelessWidget = screen never changes, so NO setState and NO backend here. It only shows info and navigates.
class LandingPage extends StatelessWidget {
  const LandingPage({super.key});

  @override
  // >> NOTE: build(): Flutter calls this to draw the screen.
  // >>       Structure: Scaffold -> SafeArea -> SingleChildScrollView -> Column of 7 sections (header, hero, intro, services, why us, emergency, footer).
  Widget build(BuildContext context) {
    // >> NOTE: Scaffold = basic page frame (background, body).
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),

      // >> NOTE: SafeArea keeps content away from the phone notch / status bar.
      body: SafeArea(
        // >> NOTE: Makes the whole page scrollable so it fits small phones.
        child: SingleChildScrollView(
          // >> NOTE: Column puts the 7 sections one below another (top to bottom).
          child: Column(
            children: [
              // =========================================================
              // >> NOTE: SECTION 1 - TOP HEADER: blue bar with logo, app name, tagline and an info button.
              // TOP HEADER
              // =========================================================
              Container(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                color: const Color(0xFF003D9B),
                // >> NOTE: Row places logo, title and info button side by side.
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.local_hospital_rounded,
                        color: Color(0xFF003D9B),
                        size: 26,
                      ),
                    ),

                    const SizedBox(width: 12),

                    // >> NOTE: Expanded: title block takes all remaining width.
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'CUET Medical Care',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Smart healthcare for CUET',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),

                    IconButton(
                      // >> NOTE: INFO BUTTON: tapping it opens the built-in About dialog (app name + version 1.0.0).
                      onPressed: () {
                        // >> NOTE: showAboutDialog = ready-made Flutter popup with app details.
                        showAboutDialog(
                          context: context,
                          applicationName: 'CUET Medical Care',
                          applicationVersion: '1.0.0',
                          applicationIcon: const Icon(
                            Icons.local_hospital_rounded,
                            color: Color(0xFF003D9B),
                          ),
                          children: const [
                            Text(
                              'Smart healthcare platform for the CUET community.',
                            ),
                          ],
                        );
                      },
                      icon: const Icon(
                        Icons.info_outline,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),

              // =========================================================
              // >> NOTE: SECTION 2 - HERO BANNER: main eye-catching box with slogan, description and Sign Up / Login buttons.
              // HERO SECTION
              // =========================================================
              Padding(
                padding: const EdgeInsets.all(20),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    // >> NOTE: BoxDecoration styling: blue gradient background, rounded corners (26) and a soft shadow.
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF003D9B),
                        Color(0xFF0052CC),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(26),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF003D9B).withOpacity(0.20),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Health icon
                      Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.14),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const Icon(
                          Icons.health_and_safety_rounded,
                          color: Color(0xFF6AE1FF),
                          size: 32,
                        ),
                      ),

                      const SizedBox(height: 22),

                      const Text(
                        // >> NOTE: Main slogan (big white text). \n makes a new line.
                        'Your Health.\nOur Priority.',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          height: 1.12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 14),

                      const Text(
                        'CUET Medical Care brings doctors, medicines, '
                        'appointments and smart health guidance together '
                        'in one convenient platform for the CUET community.',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                          height: 1.6,
                        ),
                      ),

                      const SizedBox(height: 24),

                      // =================================================
                      // >> NOTE: HERO BUTTONS: the ONLY functional part of this page. Two buttons share the width equally (Expanded).
                      // HERO BUTTONS
                      // =================================================
                      Row(
                        children: [
                          // >> NOTE: SIGN UP BUTTON (ElevatedButton = filled white = main action).
                          // SIGN UP
                          Expanded(
                            child: ElevatedButton(
                              // >> NOTE: onPressed runs when the user taps.
                              onPressed: () {
                                // >> NOTE: NAVIGATION: Navigator.push opens a NEW screen on top of this one (Back button returns here).
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        // >> NOTE: The screen to open: SignUpPage (imported from signup_page.dart). Firebase work starts there.
                                        const SignUpPage(),
                                  ),
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor:
                                    const Color(0xFF003D9B),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 15,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(14),
                                ),
                                elevation: 0,
                              ),
                              child: const Text(
                                'Sign Up',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(width: 12),

                          // >> NOTE: LOGIN BUTTON (OutlinedButton = border only = secondary action).
                          // LOGIN
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        // >> NOTE: Opens LoginPage (imported from login_page.dart).
                                        const LoginPage(),
                                  ),
                                );
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(
                                  color: Colors.white70,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 15,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(14),
                                ),
                              ),
                              child: const Text(
                                'Login',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // =========================================================
              // >> NOTE: SECTION 3 - INTRODUCTION: heading 'Healthcare made simple' + one grey line of text (static).
              // INTRODUCTION
              // =========================================================
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Healthcare made simple',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF111C2D),
                      ),
                    ),

                    SizedBox(height: 7),

                    Text(
                      'Everything you need for your healthcare journey at CUET.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Color(0xFF737685),
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // =========================================================
              // >> NOTE: SECTION 4 - SERVICES GRID (2 x 2): four cards built with our reusable widget _ServiceCard (defined at the bottom of this file).
              // >>       Each card gets its own icon, title, description and colours through the constructor.
              // SERVICES
              // =========================================================
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    // >> NOTE: First row: AI Assistant + Appointments.
                    // FIRST ROW
                    Row(
                      children: [
                        Expanded(
                          // >> NOTE: Using the reusable widget. We pass icon, title, description, iconColor and backgroundColor.
                          child: _ServiceCard(
                            icon: Icons.smart_toy_outlined,
                            title: 'AI Assistant',
                            description:
                                'Get smart symptom guidance.',
                            iconColor: const Color(0xFF00687A),
                            backgroundColor:
                                const Color(0xFFE6F8FC),
                          ),
                        ),

                        const SizedBox(width: 12),

                        Expanded(
                          child: _ServiceCard(
                            icon: Icons.calendar_month_outlined,
                            title: 'Appointments',
                            description:
                                'Book visits with doctors.',
                            iconColor: const Color(0xFF003D9B),
                            backgroundColor:
                                const Color(0xFFE7EEFF),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // >> NOTE: Second row: Medical Store + Doctors.
                    // >>       Note: 'Medical Store' is only a description card here - no ordering screen is linked, so call it a planned feature if asked.
                    // SECOND ROW
                    Row(
                      children: [
                        Expanded(
                          child: _ServiceCard(
                            icon: Icons.medication_outlined,
                            title: 'Medical Store',
                            description:
                                'Find and order medicines.',
                            iconColor: const Color(0xFF2E7D32),
                            backgroundColor:
                                const Color(0xFFEAF7EA),
                          ),
                        ),

                        const SizedBox(width: 12),

                        Expanded(
                          child: _ServiceCard(
                            icon: Icons.person_search_outlined,
                            title: 'Doctors',
                            description:
                                'Find available doctors.',
                            iconColor: const Color(0xFF7B3FA1),
                            backgroundColor:
                                const Color(0xFFF5EAFB),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 30),

              // =========================================================
              // >> NOTE: SECTION 5 - 'WHY CUET MEDICAL CARE?': white card with 3 feature rows.
              // WHY CUET MEDICAL CARE
              // =========================================================
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFFC3C6D6),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Why CUET Medical Care?',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF111C2D),
                        ),
                      ),

                      const SizedBox(height: 18),

                      // >> NOTE: _FeatureRow = second reusable widget (icon on the left, title + description on the right). 'const' = created once, better performance.
                      const _FeatureRow(
                        icon: Icons.verified_user_outlined,
                        title: 'Trusted healthcare',
                        description:
                            'Designed for the CUET community.',
                      ),

                      const SizedBox(height: 15),

                      const _FeatureRow(
                        icon: Icons.access_time_outlined,
                        title: 'Easy access',
                        description:
                            'Access healthcare services whenever you need them.',
                      ),

                      const SizedBox(height: 15),

                      const _FeatureRow(
                        icon: Icons.devices_outlined,
                        title: 'One convenient platform',
                        description:
                            'Doctors, medicines and appointments in one place.',
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // =========================================================
              // >> NOTE: SECTION 6 - EMERGENCY BOX: light red card to catch attention.
              // EMERGENCY SECTION
              // =========================================================
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    // >> NOTE: Light red background = warning style.
                    color: const Color(0xFFFFF2F2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.red.withOpacity(0.18),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.10),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.emergency_rounded,
                          color: Colors.red,
                          size: 27,
                        ),
                      ),

                      const SizedBox(width: 14),

                      const Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Emergency Assistance',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF111C2D),
                              ),
                            ),

                            SizedBox(height: 5),

                            Text(
                              'For serious emergencies, contact CUET emergency services immediately.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF737685),
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),

                      IconButton(
                        // >> NOTE: PHONE BUTTON: shows a SnackBar (small message at the bottom).
                        // >>       It only shows a reminder text - it does not dial a number.
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Please contact the appropriate CUET emergency service.',
                              ),
                            ),
                          );
                        },
                        icon: const Icon(
                          Icons.phone_rounded,
                          color: Colors.red,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 30),

              // =========================================================
              // >> NOTE: SECTION 7 - FOOTER: app name and tagline (static text).
              // FOOTER
              // =========================================================
              const Padding(
                padding: EdgeInsets.only(bottom: 25),
                child: Column(
                  children: [
                    Text(
                      'CUET Medical Care',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF003D9B),
                      ),
                    ),

                    SizedBox(height: 5),

                    Text(
                      'Smart healthcare for the CUET community',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF9A9CA8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


// =======================================================================
// >> NOTE: REUSABLE WIDGET #1 (below): _ServiceCard
// SERVICE CARD
// =======================================================================

// >> NOTE: _ServiceCard: one card design used 4 times with different data. '_' means private to this file.
class _ServiceCard extends StatelessWidget {
  // >> NOTE: FIELDS: the data this card needs. They are 'final' (cannot change after creation).
  final IconData icon;
  final String title;
  final String description;
  final Color iconColor;
  final Color backgroundColor;

  // >> NOTE: CONSTRUCTOR: receives the values. 'required' = must be given when the widget is used.
  const _ServiceCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.iconColor,
    required this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    // >> NOTE: Card UI: white rounded box with border -> Column of [coloured icon box, title, description].
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFC3C6D6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 45,
            height: 45,
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              icon,
              color: iconColor,
              size: 24,
            ),
          ),

          const SizedBox(height: 12),

          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Color(0xFF111C2D),
            ),
          ),

          const SizedBox(height: 5),

          Text(
            description,
            style: const TextStyle(
              fontSize: 11,
              height: 1.4,
              color: Color(0xFF737685),
            ),
          ),
        ],
      ),
    );
  }
}


// =======================================================================
// >> NOTE: REUSABLE WIDGET #2 (below): _FeatureRow
// FEATURE ROW
// =======================================================================

// >> NOTE: _FeatureRow: icon + title + description in one row. Used 3 times in the 'Why CUET Medical Care?' card.
class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    // >> NOTE: Row: icon box on the left, Expanded text column on the right.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFFE7EEFF),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            color: const Color(0xFF003D9B),
            size: 22,
          ),
        ),

        const SizedBox(width: 12),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF111C2D),
                ),
              ),

              const SizedBox(height: 3),

              Text(
                description,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF737685),
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
