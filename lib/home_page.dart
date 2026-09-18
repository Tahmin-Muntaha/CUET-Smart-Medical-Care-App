import 'package:flutter/material.dart';
import 'signup_page.dart';
import 'login_page.dart';

class LandingPage extends StatelessWidget {
  const LandingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),

      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // =========================================================
              // TOP HEADER
              // =========================================================
              Container(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                color: const Color(0xFF003D9B),
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
                      onPressed: () {
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
              // HERO SECTION
              // =========================================================
              Padding(
                padding: const EdgeInsets.all(20),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
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
                      // HERO BUTTONS
                      // =================================================
                      Row(
                        children: [
                          // SIGN UP
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
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

                          // LOGIN
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
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
              // SERVICES
              // =========================================================
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    // FIRST ROW
                    Row(
                      children: [
                        Expanded(
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
              // EMERGENCY SECTION
              // =========================================================
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
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
// SERVICE CARD
// =======================================================================

class _ServiceCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final Color iconColor;
  final Color backgroundColor;

  const _ServiceCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.iconColor,
    required this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
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
// FEATURE ROW
// =======================================================================

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