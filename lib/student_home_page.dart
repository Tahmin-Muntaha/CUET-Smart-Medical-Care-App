// ============================================================
// student_home.dart
//
// NOTE ON NEW DEPENDENCIES
// This file now generates downloadable prescription PDFs.
// Add these to pubspec.yaml if not already present:
//
//   dependencies:
//     pdf: ^3.10.7
//     printing: ^5.12.0
//
// Then run: flutter pub get
// ============================================================

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'book_appointment.dart';
import 'find_doctors.dart';
import 'chat_list_page.dart';
import 'symptom_check_page.dart';

class StudentHome extends StatefulWidget {
  const StudentHome({super.key});

  @override
  State<StudentHome> createState() => _StudentHomeState();
}

class _StudentHomeState extends State<StudentHome> {
  bool loadingProfile = true;
  bool loadingAppointment = true;
  bool loadingMedicalHistory = true;

  String studentName = '';
  String studentId = '';
  String session = '';
  String email = '';

  String department = 'Not set';
  String phone = 'Not set';
  String bloodGroup = 'Not set';
  String hall = 'Not set';

  List<Map<String, dynamic>> appointments = [];
  List<Map<String, dynamic>> medicalHistory = [];

  int healthTipIndex = 0;
  Timer? healthTipTimer;

  final List<Map<String, String>> healthTips = [
    {
      'title': 'Stay Hydrated',
      'tip':
          'Drink enough water throughout the day, especially during hot weather and long classes.',
    },
    {
      'title': 'Take Study Breaks',
      'tip':
          'Take short breaks during long study sessions to reduce eye strain and improve concentration.',
    },
    {
      'title': 'Get Enough Sleep',
      'tip':
          'Maintain a regular sleep schedule and get enough rest before classes and exams.',
    },
    {
      'title': 'Eat Healthy',
      'tip':
          'Choose balanced meals with vegetables, fruits, protein, and enough water during busy campus days.',
    },
    {
      'title': 'Stay Physically Active',
      'tip':
          'Walk around campus or do light exercise regularly to keep the body active and healthy.',
    },
    {
      'title': 'Keep Hands Clean',
      'tip':
          'Wash hands regularly, especially before eating and after using shared campus facilities.',
    },
    {
      'title': 'Protect Your Eyes',
      'tip':
          'Follow the 20-20-20 rule when using computers or phones for long periods.',
    },
    {
      'title': 'Manage Stress',
      'tip':
          'Take time to relax, talk with friends, and maintain a healthy balance between study and rest.',
    },
  ];

  @override
  void initState() {
    super.initState();

    _loadStudentProfile();
    _loadAppointments();
    _loadMedicalHistory();
    _startHealthTipRotation();
  }

  @override
  void dispose() {
    healthTipTimer?.cancel();
    healthTipTimer = null;
    super.dispose();
  }

  // ============================================================
  // HEALTH TIP TIMER
  // ============================================================

  void _startHealthTipRotation() {
    healthTipTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        healthTipIndex = (healthTipIndex + 1) % healthTips.length;
      });
    });
  }

  void changeHealthTip() {
    if (!mounted) return;

    setState(() {
      healthTipIndex = (healthTipIndex + 1) % healthTips.length;
    });
  }

  // ============================================================
  // LOAD STUDENT PROFILE
  // ============================================================

  Future<void> _loadStudentProfile() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      if (!mounted) return;

      setState(() {
        loadingProfile = false;
      });

      return;
    }

    try {
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(user.uid).get();

      if (!mounted) return;

      final data = doc.data();

      if (!doc.exists || data == null) {
        setState(() {
          studentName = '';
          studentId = '';
          session = '';
          email = user.email ?? '';

          department = 'Not set';
          phone = 'Not set';
          bloodGroup = 'Not set';
          hall = 'Not set';

          loadingProfile = false;
        });

        return;
      }

      setState(() {
        studentName =
            data['name']?.toString() ?? data['studentName']?.toString() ?? '';

        studentId = data['studentId']?.toString() ?? '';
        session = data['session']?.toString() ?? '';
        email = data['email']?.toString() ?? user.email ?? '';

        department = data['department']?.toString() ?? 'Not set';
        phone = data['phone']?.toString() ?? 'Not set';
        bloodGroup = data['bloodGroup']?.toString() ?? 'Not set';
        hall = data['hall']?.toString() ?? 'Not set';

        loadingProfile = false;
      });
    } catch (e) {
      debugPrint('Failed to load student profile: $e');

      if (!mounted) return;

      setState(() {
        loadingProfile = false;
      });
    }
  }

  // ============================================================
  // LOAD ALL BOOKED APPOINTMENTS
  // ============================================================

  Future<void> _loadAppointments() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      if (!mounted) return;

      setState(() {
        loadingAppointment = false;
        appointments = [];
      });

      return;
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('appointments')
          .where('studentUid', isEqualTo: user.uid)
          .where('status', isEqualTo: 'booked')
          .get();

      final List<Map<String, dynamic>> loaded = [];

      for (final doc in snapshot.docs) {
        loaded.add({'id': doc.id, ...doc.data()});
      }

      loaded.sort((a, b) {
        final dateA = _getAppointmentDateTime(a);
        final dateB = _getAppointmentDateTime(b);

        if (dateA == null && dateB == null) return 0;
        if (dateA == null) return 1;
        if (dateB == null) return -1;

        return dateA.compareTo(dateB);
      });

      if (!mounted) return;

      setState(() {
        appointments = loaded;
        loadingAppointment = false;
      });
    } on FirebaseException catch (e) {
      debugPrint('Failed to load appointments: ${e.code} - ${e.message}');

      if (!mounted) return;

      setState(() {
        appointments = [];
        loadingAppointment = false;
      });

      _showMessage('Could not load appointments: ${e.code}');
    } catch (e) {
      debugPrint('Failed to load appointments: $e');

      if (!mounted) return;

      setState(() {
        appointments = [];
        loadingAppointment = false;
      });

      _showMessage('Could not load appointments.');
    }
  }

  // ============================================================
  // LOAD COMPLETED APPOINTMENTS (MEDICAL HISTORY)
  // ============================================================

  Future<void> _loadMedicalHistory() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      if (!mounted) return;

      setState(() {
        medicalHistory = [];
        loadingMedicalHistory = false;
      });

      return;
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('appointments')
          .where('studentUid', isEqualTo: user.uid)
          .where('status', isEqualTo: 'completed')
          .get();

      final List<Map<String, dynamic>> loaded = [];

      for (final doc in snapshot.docs) {
        loaded.add({'id': doc.id, ...doc.data()});
      }

      // Newest first.
      loaded.sort((a, b) {
        final dateA = _getAppointmentDateTime(a);
        final dateB = _getAppointmentDateTime(b);

        if (dateA == null && dateB == null) return 0;
        if (dateA == null) return 1;
        if (dateB == null) return -1;

        return dateB.compareTo(dateA);
      });

      if (!mounted) return;

      setState(() {
        medicalHistory = loaded;
        loadingMedicalHistory = false;
      });
    } catch (e) {
      debugPrint('Failed to load medical history: $e');

      if (!mounted) return;

      setState(() {
        medicalHistory = [];
        loadingMedicalHistory = false;
      });
    }
  }

  // ============================================================
  // GET APPOINTMENT DATE/TIME
  // ============================================================

  DateTime? _getAppointmentDateTime(Map<String, dynamic> data) {
    try {
      final dateKey = data['dateKey']?.toString() ?? '';
      final time =
          data['time']?.toString() ?? data['timeSlot']?.toString() ?? '';

      if (dateKey.isNotEmpty) {
        final parts = dateKey.split('-');

        if (parts.length == 3) {
          final year = int.parse(parts[0]);
          final month = int.parse(parts[1]);
          final day = int.parse(parts[2]);

          final parsedTime = _parseTime(time);

          if (parsedTime != null) {
            return DateTime(year, month, day, parsedTime.hour, parsedTime.minute);
          }

          return DateTime(year, month, day);
        }
      }

      final timestamp = data['appointmentDate'];

      if (timestamp is Timestamp) {
        return timestamp.toDate();
      }

      return null;
    } catch (e) {
      debugPrint('Failed to parse appointment date: $e');
      return null;
    }
  }

  // ============================================================
  // PARSE TIME
  // Supports: 10:00 AM / 10.00 AM / 10:00AM / 10.00AM
  // ============================================================

  TimeOfDay? _parseTime(String value) {
    try {
      var cleaned = value.trim().replaceAll('.', ':');
      cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ');

      final match = RegExp(
        r'^(\d{1,2}):(\d{2})\s*(AM|PM)$',
        caseSensitive: false,
      ).firstMatch(cleaned);

      if (match == null) return null;

      int hour = int.parse(match.group(1)!);
      final minute = int.parse(match.group(2)!);
      final period = match.group(3)!.toUpperCase();

      if (period == 'PM' && hour != 12) hour += 12;
      if (period == 'AM' && hour == 12) hour = 0;

      if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;

      return TimeOfDay(hour: hour, minute: minute);
    } catch (_) {
      return null;
    }
  }

  // ============================================================
  // FORMAT DATE
  // ============================================================

  String _formatDate(String dateKey) {
    try {
      final parts = dateKey.split('-');
      if (parts.length != 3) return dateKey;
      return '${parts[2]}/${parts[1]}/${parts[0]}';
    } catch (_) {
      return dateKey;
    }
  }

  // ============================================================
  // BOOK APPOINTMENT
  // ============================================================

  Future<void> openBookAppointment() async {
    final result = await Navigator.push<AppointmentResult>(
      context,
      MaterialPageRoute(builder: (context) => const BookAppointmentPage()),
    );

    if (!mounted || result == null) return;

    await _loadAppointments();

    if (!mounted) return;

    _showMessage('Appointment booked successfully.');
  }

  // ============================================================
  // FIND DOCTORS
  // ============================================================

  void openFindDoctors() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const FindDoctors()),
    );
  }

  // ============================================================
  // MEDICAL HISTORY (FULL PAGE)
  // ============================================================

  void openMedicalRecords() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MedicalHistoryPage(
          studentName: studentName,
          studentId: studentId,
        ),
      ),
    );
  }

  // ============================================================
  // ANNOUNCEMENTS
  // ============================================================

  void openAnnouncements() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AnnouncementsPage()),
    );
  }

  // ============================================================
  // MESSAGES
  // ============================================================

  void openMessages() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ChatListPage()),
    );
  }

  // ============================================================
  // AI SYMPTOM CHECK (real Gemini chatbot)
  // ============================================================

  void openSymptomCheck() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SymptomCheckPage()),
    );
  }

  // ============================================================
  // DEMO PAGE
  // ============================================================

  void openDemoPage(String title, IconData icon) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DemoFeaturePage(title: title, icon: icon)),
    );
  }

  // ============================================================
  // DOWNLOAD PRESCRIPTION PDF (from dashboard preview)
  // ============================================================

  Future<void> _downloadPrescriptionPdf(Map<String, dynamic> record) async {
    await downloadPrescriptionPdf(
      context,
      record: record,
      studentName: studentName.isEmpty ? 'Student' : studentName,
      studentId: studentId.isEmpty ? 'Not set' : studentId,
    );
  }

  // ============================================================
  // CANCEL APPOINTMENT
  //
  // IMPORTANT:
  // ALL FIRESTORE TRANSACTION READS ARE DONE FIRST.
  // ONLY AFTER THAT DO WE PERFORM UPDATE/DELETE WRITES.
  // ============================================================

  Future<void> cancelAppointment(Map<String, dynamic> appointment) async {
    final appointmentId = appointment['id']?.toString() ?? '';

    if (appointmentId.isEmpty) {
      _showMessage('Invalid appointment.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Cancel Appointment?'),
          content: const Text('Are you sure you want to cancel this appointment?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('No'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Yes, Cancel'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      _showMessage('You are not logged in.');
      return;
    }

    if (mounted) {
      _showMessage('Cancelling appointment...');
    }

    try {
      final db = FirebaseFirestore.instance;
      final appointmentRef = db.collection('appointments').doc(appointmentId);

      await db.runTransaction((transaction) async {
        // READ #1: APPOINTMENT
        final appointmentSnapshot = await transaction.get(appointmentRef);

        if (!appointmentSnapshot.exists) {
          throw Exception('Appointment no longer exists.');
        }

        final data = appointmentSnapshot.data();

        if (data == null) {
          throw Exception('Appointment data is missing.');
        }

        final studentUid = data['studentUid']?.toString() ?? '';

        if (studentUid != user.uid) {
          throw Exception('You cannot cancel this appointment.');
        }

        final currentStatus = data['status']?.toString() ?? '';

        if (currentStatus != 'booked') {
          throw Exception('Only booked appointments can be cancelled.');
        }

        String? slotLockId = data['slotLockId']?.toString();

        if (slotLockId == null || slotLockId.trim().isEmpty) {
          final doctorUid =
              data['doctorUid']?.toString() ?? data['doctorId']?.toString() ?? '';
          final dateKey = data['dateKey']?.toString() ?? '';
          final time =
              data['time']?.toString() ?? data['timeSlot']?.toString() ?? '';

          if (doctorUid.isNotEmpty && dateKey.isNotEmpty && time.isNotEmpty) {
            slotLockId = _buildSlotLockId(
              doctorUid: doctorUid,
              dateKey: dateKey,
              time: time,
            );
          }
        }

        // READ #2: SLOT (must happen before any write)
        DocumentReference<Map<String, dynamic>>? slotRef;
        DocumentSnapshot<Map<String, dynamic>>? slotSnapshot;

        if (slotLockId != null && slotLockId.trim().isNotEmpty) {
          slotRef = db.collection('appointment_slots').doc(slotLockId);
          slotSnapshot = await transaction.get(slotRef);
        }

        // NOW START WRITES
        transaction.update(appointmentRef, {
          'status': 'cancelled',
          'cancelledAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'statusUpdatedAt': FieldValue.serverTimestamp(),
          'statusUpdatedBy': user.uid,
        });

        if (slotRef != null && slotSnapshot != null && slotSnapshot.exists) {
          final slotData = slotSnapshot.data();
          final slotAppointmentId = slotData?['appointmentId']?.toString();
          final slotStudentUid = slotData?['studentUid']?.toString();

          if (slotAppointmentId == appointmentId && slotStudentUid == user.uid) {
            transaction.delete(slotRef);
          }
        }
      });

      if (!mounted) return;

      await _loadAppointments();

      if (!mounted) return;

      _showMessage('Appointment cancelled successfully.');
    } on FirebaseException catch (e) {
      debugPrint('Firebase cancel error: code=${e.code}, message=${e.message}');

      if (!mounted) return;

      switch (e.code) {
        case 'permission-denied':
          _showMessage('Cancellation denied by Firestore rules.');
          break;
        case 'failed-precondition':
          _showMessage(
              'Cancellation failed because the appointment was changed. Please refresh and try again.');
          break;
        case 'not-found':
          _showMessage('Appointment or slot was not found.');
          break;
        case 'aborted':
          _showMessage('Cancellation was interrupted. Please try again.');
          break;
        default:
          _showMessage('Cancel failed: ${e.code}');
      }
    } catch (e) {
      debugPrint('Failed to cancel appointment: $e');

      if (!mounted) return;

      final message = e.toString();

      if (message.contains('Only booked appointments')) {
        _showMessage('This appointment can no longer be cancelled.');
      } else if (message.contains('cannot cancel')) {
        _showMessage('You cannot cancel this appointment.');
      } else if (message.contains('no longer exists')) {
        _showMessage('This appointment no longer exists.');
      } else {
        _showMessage('Failed to cancel appointment.');
      }
    }
  }

  // ============================================================
  // SLOT LOCK ID (MUST MATCH book_appointment.dart)
  // ============================================================

  static String _buildSlotLockId({
    required String doctorUid,
    required String dateKey,
    required String time,
  }) {
    final safeTime = time
        .trim()
        .toLowerCase()
        .replaceAll(' ', '_')
        .replaceAll(':', '_')
        .replaceAll('.', '_');

    return '${doctorUid}_${dateKey}_$safeTime';
  }

  // ============================================================
  // EMERGENCY INFORMATION
  // ============================================================

  Future<void> _openEmergencyDetails() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      _showMessage('User not logged in.');
      return;
    }

    final result = await showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return _EmergencyDetailsDialog(
          initialBloodGroup: bloodGroup == 'Not set' ? '' : bloodGroup,
          initialHall: hall == 'Not set' ? '' : hall,
          userId: user.uid,
        );
      },
    );

    if (result == null || !mounted) return;

    setState(() {
      bloodGroup = result['bloodGroup'] ?? 'Not set';
      hall = result['hall'] ?? 'Not set';
    });

    _showMessage('Emergency information saved successfully.');
  }

  // ============================================================
  // SNACKBAR
  // ============================================================

  void _showMessage(String message) {
    if (!mounted) return;

    final messenger = ScaffoldMessenger.maybeOf(context);

    if (messenger == null) return;

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  // ============================================================
  // LOGOUT
  // ============================================================

  Future<void> logout() async {
    try {
      await FirebaseAuth.instance.signOut();

      if (!mounted) return;

      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    } catch (e) {
      debugPrint('Logout failed: $e');

      if (!mounted) return;

      _showMessage('Logout failed. Please try again.');
    }
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    if (loadingProfile || loadingAppointment) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        backgroundColor: const Color(0xFF003D9B),
        foregroundColor: Colors.white,
        title: const Row(
          children: [
            Icon(Icons.favorite_rounded, color: Color(0xFF6AE1FF)),
            SizedBox(width: 8),
            Text('CUET SmartCare', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () {
              openDemoPage('Notifications', Icons.notifications_outlined);
            },
            icon: const Icon(Icons.notifications_none_rounded),
          ),
          IconButton(
            tooltip: 'Logout',
            onPressed: logout,
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildWelcomeBanner(),
              const SizedBox(height: 22),
              _sectionTitle('QUICK HEALTH ACTIONS'),
              const SizedBox(height: 10),
              _buildQuickActions(),
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth < 800) {
                    return Column(
                      children: [
                        _buildUpcomingAppointments(),
                        const SizedBox(height: 20),
                        _buildMedicalHistory(),
                        const SizedBox(height: 20),
                        _buildHealthTip(),
                        const SizedBox(height: 20),
                        _buildEmergencyCard(),
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: Column(
                          children: [
                            _buildUpcomingAppointments(),
                            const SizedBox(height: 20),
                            _buildMedicalHistory(),
                          ],
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          children: [
                            _buildHealthTip(),
                            const SizedBox(height: 20),
                            _buildEmergencyCard(),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // WELCOME BANNER
  // ============================================================

  Widget _buildWelcomeBanner() {
    final firstName =
        studentName.trim().isEmpty ? 'Student' : studentName.trim().split(' ').first;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFC3C6D6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            session.isEmpty ? 'CUET Student' : 'Session $session',
            style: const TextStyle(color: Color(0xFF00687A), fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Hello, $firstName',
            style: const TextStyle(
              fontSize: 27,
              fontWeight: FontWeight.bold,
              color: Color(0xFF003D9B),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'ID: ${studentId.isEmpty ? 'Not set' : studentId}',
            style: const TextStyle(color: Color(0xFF737685)),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: openSymptomCheck,
            icon: const Icon(Icons.smart_toy_outlined),
            label: const Text('Ask SmartCare AI'),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // QUICK ACTIONS
  // ============================================================

  Widget _buildQuickActions() {
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 1.55,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _quickAction(
          'Book Appointment',
          Icons.calendar_month_outlined,
          openBookAppointment,
        ),
        _quickAction(
          'Find Doctors',
          Icons.medical_services_outlined,
          openFindDoctors,
        ),
        _quickAction(
          'Announcements',
          Icons.campaign_outlined,
          openAnnouncements,
        ),
        _quickAction(
          'Messages',
          Icons.chat_bubble_outline,
          openMessages,
        ),
        _quickAction(
          'AI Symptom Check',
          Icons.smart_toy_outlined,
          openSymptomCheck,
        ),
      ],
    );
  }

  Widget _quickAction(String title, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFC3C6D6)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: const Color(0xFF003D9B), size: 27),
            const SizedBox(height: 8),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // UPCOMING APPOINTMENTS
  // ============================================================

  Widget _buildUpcomingAppointments() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _sectionTitle('UPCOMING APPOINTMENTS')),
            IconButton(
              tooltip: 'Refresh appointments',
              onPressed: _loadAppointments,
              icon: const Icon(Icons.refresh, size: 20),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (appointments.isEmpty)
          _emptySection(
            Icons.calendar_month_outlined,
            'No Upcoming Appointments',
            'Book an appointment when medical consultation is needed.',
            openBookAppointment,
            'Book Appointment',
          )
        else
          Column(
            children: appointments
                .map(
                  (appointment) => Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _buildAppointmentCard(appointment),
                  ),
                )
                .toList(),
          ),
      ],
    );
  }

  // ============================================================
  // APPOINTMENT CARD
  // ============================================================

  Widget _buildAppointmentCard(Map<String, dynamic> appointment) {
    final doctor = appointment['doctorName']?.toString() ?? 'Doctor';

    final doctorDepartment = appointment['doctorDepartment']?.toString() ??
        appointment['department']?.toString() ??
        '';

    final reason = appointment['problem']?.toString() ??
        appointment['reason']?.toString() ??
        'Medical Consultation';

    final symptoms = appointment['symptoms']?.toString() ?? '';

    final date =
        appointment['dateKey']?.toString() ?? appointment['date']?.toString() ?? '';

    final time =
        appointment['time']?.toString() ?? appointment['timeSlot']?.toString() ?? '';

    final room =
        appointment['doctorRoom']?.toString() ?? appointment['room']?.toString() ?? 'Not set';

    final token =
        appointment['token']?.toString() ?? appointment['queueNumber']?.toString() ?? '';

    final status = appointment['status']?.toString() ?? 'booked';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFC3C6D6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Appointment', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  status.toUpperCase(),
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF2E7D32)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F3FF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFD5DEFF)),
            ),
            child: Column(
              children: [
                const Text(
                  'YOUR QUEUE TOKEN',
                  style: TextStyle(fontSize: 10, color: Color(0xFF737685), fontWeight: FontWeight.bold, letterSpacing: 1),
                ),
                const SizedBox(height: 5),
                Text(
                  token.isEmpty ? 'Not assigned' : '#$token',
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF003D9B)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(reason, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 5),
          Text(doctor, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF003D9B))),
          if (doctorDepartment.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(doctorDepartment, style: const TextStyle(color: Color(0xFF00687A))),
          ],
          const SizedBox(height: 15),
          _appointmentInfoRow(Icons.calendar_today_outlined, 'Date', _formatDate(date)),
          const SizedBox(height: 8),
          _appointmentInfoRow(Icons.access_time_outlined, 'Time', time),
          const SizedBox(height: 8),
          _appointmentInfoRow(Icons.room_outlined, 'Room', room),
          if (symptoms.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            _appointmentInfoRow(Icons.notes_outlined, 'Symptoms', symptoms),
          ],
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
              onPressed: () => cancelAppointment(appointment),
              icon: const Icon(Icons.cancel_outlined, size: 18),
              label: const Text('Cancel Appointment'),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // APPOINTMENT INFO ROW
  // ============================================================

  Widget _appointmentInfoRow(IconData icon, String title, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: const Color(0xFF003D9B)),
        const SizedBox(width: 8),
        SizedBox(
          width: 65,
          child: Text(title, style: const TextStyle(color: Color(0xFF737685), fontSize: 11)),
        ),
        Expanded(
          child: Text(
            value.isEmpty ? 'Not set' : value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // MEDICAL HISTORY (dashboard preview card)
  // ============================================================

  Widget _buildMedicalHistory() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFC3C6D6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Medical History', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              ),
              TextButton(onPressed: openMedicalRecords, child: const Text('View All')),
            ],
          ),
          const SizedBox(height: 10),
          if (loadingMedicalHistory)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 30),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (medicalHistory.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Column(
                  children: [
                    Icon(Icons.description_outlined, size: 42, color: Color(0xFF003D9B)),
                    SizedBox(height: 8),
                    Text('No Medical Records', style: TextStyle(fontWeight: FontWeight.bold)),
                    SizedBox(height: 4),
                    Text(
                      'Completed appointments and prescriptions will appear here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF737685)),
                    ),
                  ],
                ),
              ),
            )
          else
            Column(
              children: medicalHistory
                  .take(3)
                  .map(
                    (record) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _medicalHistoryPreviewTile(record),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }

  Widget _medicalHistoryPreviewTile(Map<String, dynamic> record) {
    final diagnosis = record['diagnosis']?.toString() ??
        record['problem']?.toString() ??
        'Consultation';

    final doctor = record['doctorName']?.toString() ?? 'Doctor';
    final date = _formatDate(record['dateKey']?.toString() ?? '');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F9FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E6ED)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(diagnosis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 3),
                Text('$doctor • $date', style: const TextStyle(fontSize: 10, color: Color(0xFF737685))),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Download Prescription PDF',
            onPressed: () => _downloadPrescriptionPdf(record),
            icon: const Icon(Icons.picture_as_pdf_outlined, color: Color(0xFF003D9B)),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // HEALTH TIP
  // ============================================================

  Widget _buildHealthTip() {
    final tip = healthTips[healthTipIndex];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFC3C6D6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'CAMPUS HEALTH TIP',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00687A)),
                ),
              ),
              IconButton(onPressed: changeHealthTip, icon: const Icon(Icons.refresh)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.health_and_safety_outlined, color: Color(0xFF003D9B), size: 35),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tip['title']!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 6),
                    Text(tip['tip']!, style: const TextStyle(color: Color(0xFF555555))),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // EMERGENCY CARD
  // ============================================================

  Widget _buildEmergencyCard() {
    return InkWell(
      onTap: _openEmergencyDetails,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF003D9B),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.bloodtype_outlined, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Blood: $bloodGroup',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
                const Icon(Icons.edit_outlined, color: Colors.white70, size: 20),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              studentName.isEmpty ? 'Student' : studentName,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'ID: ${studentId.isEmpty ? 'Not set' : studentId} • $phone',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.home_work_outlined, color: Colors.white70, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('Hall: $hall', style: const TextStyle(color: Colors.white70)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Tap to add emergency information',
              style: TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // EMPTY SECTION
  // ============================================================

  Widget _emptySection(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onPressed,
    String buttonText,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFC3C6D6)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 45, color: const Color(0xFF003D9B)),
          const SizedBox(height: 10),
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 5),
          Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF737685))),
          const SizedBox(height: 15),
          ElevatedButton(onPressed: onPressed, child: Text(buttonText)),
        ],
      ),
    );
  }

  // ============================================================
  // SECTION TITLE
  // ============================================================

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1, color: Color(0xFF737685)),
    );
  }
}

// ============================================================
// EMERGENCY DETAILS DIALOG
// ============================================================

class _EmergencyDetailsDialog extends StatefulWidget {
  final String initialBloodGroup;
  final String initialHall;
  final String userId;

  const _EmergencyDetailsDialog({
    required this.initialBloodGroup,
    required this.initialHall,
    required this.userId,
  });

  @override
  State<_EmergencyDetailsDialog> createState() => _EmergencyDetailsDialogState();
}

class _EmergencyDetailsDialogState extends State<_EmergencyDetailsDialog> {
  late final TextEditingController bloodController;
  late final TextEditingController hallController;

  bool saving = false;

  @override
  void initState() {
    super.initState();

    bloodController = TextEditingController(text: widget.initialBloodGroup);
    hallController = TextEditingController(text: widget.initialHall);
  }

  @override
  void dispose() {
    bloodController.dispose();
    hallController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (saving) return;

    final blood = bloodController.text.trim();
    final hallName = hallController.text.trim();

    if (blood.isEmpty || hallName.isEmpty) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Please enter both blood group and hall.')),
      );
      return;
    }

    if (!mounted) return;

    setState(() {
      saving = true;
    });

    try {
      await FirebaseFirestore.instance.collection('users').doc(widget.userId).set(
        {
          'bloodGroup': blood,
          'hall': hallName,
        },
        SetOptions(merge: true),
      );

      if (!mounted) return;

      Navigator.of(context).pop({
        'bloodGroup': blood,
        'hall': hallName,
      });
    } on FirebaseException catch (e) {
      debugPrint('Failed to save emergency information: ${e.code} - ${e.message}');

      if (!mounted) return;

      setState(() {
        saving = false;
      });

      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('Failed to save: ${e.code}')),
      );
    } catch (e) {
      debugPrint('Failed to save emergency information: $e');

      if (!mounted) return;

      setState(() {
        saving = false;
      });

      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Failed to save information.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.medical_information_outlined, color: Color(0xFF003D9B)),
          SizedBox(width: 10),
          Expanded(child: Text('Emergency Information')),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: bloodController,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: 'Blood Group',
                hintText: 'Example: B+',
                prefixIcon: const Icon(Icons.bloodtype_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: hallController,
              decoration: InputDecoration(
                labelText: 'Hall',
                hintText: 'Example: Shahid Tareq Huda Hall',
                prefixIcon: const Icon(Icons.home_work_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: saving ? null : _save,
          child: saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}

// ============================================================
// PDF GENERATION HELPERS (shared across screens)
// ============================================================

Future<Uint8List> buildPrescriptionPdfBytes({
  required Map<String, dynamic> record,
  required String studentName,
  required String studentId,
}) async {
  final doc = pw.Document();

  final diagnosis =
      record['diagnosis']?.toString() ?? record['problem']?.toString() ?? 'Consultation';

  final doctorName = record['doctorName']?.toString() ?? 'Doctor';
  final doctorDept =
      record['doctorDepartment']?.toString() ?? record['department']?.toString() ?? '';

  final date = record['dateKey']?.toString() ?? '';
  final time = record['time']?.toString() ?? record['timeSlot']?.toString() ?? '';

  final chiefComplaint =
      record['problem']?.toString() ?? record['reason']?.toString() ?? '';
  final symptoms = record['symptoms']?.toString() ?? '';
  final treatmentAdvice = record['treatmentAdvice']?.toString() ?? '';
  final followUpDate = record['followUpDate']?.toString();

  final vitalsRaw = record['vitals'];
  final vitalsMap =
      vitalsRaw is Map ? vitalsRaw.map((k, v) => MapEntry(k.toString(), v)) : <String, dynamic>{};

  final testsRaw = record['testsRecommended'];
  final testsRecommended =
      testsRaw is List ? testsRaw.map((e) => e.toString()).toList() : <String>[];

  final prescriptionsRaw = record['prescriptions'];
  final prescriptions = prescriptionsRaw is List
      ? prescriptionsRaw
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
          .toList()
      : <Map<String, dynamic>>[];

  doc.addPage(
    pw.MultiPage(
      build: (context) => [
        pw.Text('CUET Medical Center', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        pw.Text('Official Digital Prescription Slip', style: const pw.TextStyle(fontSize: 12)),
        pw.SizedBox(height: 4),
        pw.Text('Ref ID: ${record['id'] ?? ''}   Date: $date   Time: $time', style: const pw.TextStyle(fontSize: 10)),
        pw.Divider(),
        pw.SizedBox(height: 10),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Physician', style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                  pw.Text(doctorName, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.Text(doctorDept, style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
            ),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Student Patient', style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                  pw.Text(studentName, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.Text('ID: $studentId', style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 14),
        if (vitalsMap.isNotEmpty) ...[
          pw.Text('Clinical Vitals', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
          pw.SizedBox(height: 4),
          pw.Wrap(
            spacing: 14,
            runSpacing: 4,
            children: vitalsMap.entries
                .where((e) => e.value != null && e.value.toString().trim().isNotEmpty)
                .map((e) => pw.Text('${e.key}: ${e.value}', style: const pw.TextStyle(fontSize: 10)))
                .toList(),
          ),
          pw.SizedBox(height: 14),
        ],
        if (chiefComplaint.isNotEmpty || symptoms.isNotEmpty) ...[
          pw.Text('Chief Complaint & Symptoms', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
          pw.SizedBox(height: 4),
          pw.Text(
            '$chiefComplaint${symptoms.isNotEmpty ? ' ($symptoms)' : ''}',
            style: const pw.TextStyle(fontSize: 10),
          ),
          pw.SizedBox(height: 14),
        ],
        pw.Text('Clinical Diagnosis', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
        pw.SizedBox(height: 4),
        pw.Text(diagnosis, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 14),
        pw.Text('Prescribed Medicines (Rx)', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
        pw.SizedBox(height: 6),
        if (prescriptions.isEmpty)
          pw.Text(
            'No oral medications prescribed.',
            style: const pw.TextStyle(fontSize: 10, fontStyle: pw.FontStyle.italic),
          )
        else
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
            columnWidths: const {
              0: pw.FlexColumnWidth(2),
              1: pw.FlexColumnWidth(2),
              2: pw.FlexColumnWidth(1),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.blue50),
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(5),
                    child: pw.Text('Medicine', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(5),
                    child: pw.Text('Dosage', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(5),
                    child: pw.Text('Duration', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                  ),
                ],
              ),
              ...prescriptions.map(
                (rx) => pw.TableRow(
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(5),
                      child: pw.Text('${rx['medicineName'] ?? ''}', style: const pw.TextStyle(fontSize: 9)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(5),
                      child: pw.Text(
                        '${rx['dosage'] ?? ''} (${rx['frequency'] ?? ''})',
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(5),
                      child: pw.Text('${rx['duration'] ?? ''}', style: const pw.TextStyle(fontSize: 9)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        pw.SizedBox(height: 14),
        if (testsRecommended.isNotEmpty) ...[
          pw.Text('Recommended Diagnostic Tests', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
          pw.SizedBox(height: 4),
          ...testsRecommended.map((t) => pw.Text('•  $t', style: const pw.TextStyle(fontSize: 10))),
          pw.SizedBox(height: 14),
        ],
        if (treatmentAdvice.isNotEmpty) ...[
          pw.Text("Doctor's Clinical Advice", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
          pw.SizedBox(height: 4),
          pw.Text(treatmentAdvice, style: const pw.TextStyle(fontSize: 10)),
          pw.SizedBox(height: 14),
        ],
        if (followUpDate != null && followUpDate.trim().isNotEmpty)
          pw.Text('Follow-up Review Date: $followUpDate', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
      ],
    ),
  );

  return doc.save();
}

Future<void> downloadPrescriptionPdf(
  BuildContext context, {
  required Map<String, dynamic> record,
  required String studentName,
  required String studentId,
}) async {
  try {
    final bytes = await buildPrescriptionPdfBytes(
      record: record,
      studentName: studentName,
      studentId: studentId,
    );

    final refId = record['id']?.toString() ?? 'prescription';

    await Printing.sharePdf(bytes: bytes, filename: 'prescription_$refId.pdf');
  } catch (e) {
    debugPrint('Failed to generate PDF: $e');

    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Failed to generate PDF. Please try again.')),
      );
    }
  }
}

// ============================================================
// MEDICAL HISTORY PAGE (full list, replaces old
// EmptyMedicalRecordsPage)
// ============================================================

class MedicalHistoryPage extends StatefulWidget {
  final String studentName;
  final String studentId;

  const MedicalHistoryPage({
    super.key,
    required this.studentName,
    required this.studentId,
  });

  @override
  State<MedicalHistoryPage> createState() => _MedicalHistoryPageState();
}

class _MedicalHistoryPageState extends State<MedicalHistoryPage> {
  bool loading = true;
  List<Map<String, dynamic>> records = [];
  String searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      if (!mounted) return;
      setState(() {
        records = [];
        loading = false;
      });
      return;
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('appointments')
          .where('studentUid', isEqualTo: user.uid)
          .where('status', isEqualTo: 'completed')
          .get();

      final loaded = snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();

      loaded.sort((a, b) {
        final dateKeyA = a['dateKey']?.toString() ?? '';
        final dateKeyB = b['dateKey']?.toString() ?? '';
        return dateKeyB.compareTo(dateKeyA);
      });

      if (!mounted) return;

      setState(() {
        records = loaded;
        loading = false;
      });
    } catch (e) {
      debugPrint('Failed to load medical history: $e');

      if (!mounted) return;

      setState(() {
        records = [];
        loading = false;
      });
    }
  }

  String _formatDate(String dateKey) {
    try {
      final parts = dateKey.split('-');
      if (parts.length != 3) return dateKey;
      return '${parts[2]}/${parts[1]}/${parts[0]}';
    } catch (_) {
      return dateKey;
    }
  }

  List<Map<String, dynamic>> get filteredRecords {
    if (searchQuery.trim().isEmpty) return records;

    final query = searchQuery.toLowerCase();

    return records.where((record) {
      final diagnosis = (record['diagnosis']?.toString() ?? record['problem']?.toString() ?? '').toLowerCase();
      final doctor = (record['doctorName']?.toString() ?? '').toLowerCase();
      final date = (record['dateKey']?.toString() ?? '').toLowerCase();
      final complaint = (record['problem']?.toString() ?? record['reason']?.toString() ?? '').toLowerCase();

      return diagnosis.contains(query) ||
          doctor.contains(query) ||
          date.contains(query) ||
          complaint.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        backgroundColor: const Color(0xFF003D9B),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Medical History', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadRecords,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 24),
                    if (loading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 60),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else
                      _buildRecordsList(),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Medical History',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF111C2D)),
        ),
        const SizedBox(height: 5),
        const Text(
          'All your completed appointments, diagnoses, and prescriptions.',
          style: TextStyle(fontSize: 13, color: Color(0xFF434654)),
        ),
        const SizedBox(height: 16),
        TextField(
          onChanged: (value) => setState(() => searchQuery = value),
          decoration: InputDecoration(
            hintText: 'Search records or diagnoses...',
            hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF737685)),
            prefixIcon: const Icon(Icons.search, color: Color(0xFF737685)),
            suffixIcon: searchQuery.isNotEmpty
                ? IconButton(
                    tooltip: 'Clear',
                    onPressed: () => setState(() => searchQuery = ''),
                    icon: const Icon(Icons.close, size: 18, color: Color(0xFF737685)),
                  )
                : null,
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFC3C6D6)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFC3C6D6)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF003D9B), width: 1.5),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildRecordsList() {
    final visible = filteredRecords;

    if (visible.isEmpty) {
      return _buildEmptyState();
    }

    return Column(
      children: visible
          .map((record) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _buildRecordCard(record),
              ))
          .toList(),
    );
  }

  Widget _buildRecordCard(Map<String, dynamic> record) {
    final diagnosis =
        record['diagnosis']?.toString() ?? record['problem']?.toString() ?? 'Consultation';
    final doctorName = record['doctorName']?.toString() ?? 'Doctor';
    final doctorDept =
        record['doctorDepartment']?.toString() ?? record['department']?.toString() ?? '';
    final chiefComplaint =
        record['problem']?.toString() ?? record['reason']?.toString() ?? '';
    final date = _formatDate(record['dateKey']?.toString() ?? '');
    final time = record['time']?.toString() ?? record['timeSlot']?.toString() ?? '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFC3C6D6)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      date.toUpperCase(),
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1, color: Color(0xFF737685)),
                    ),
                    const SizedBox(height: 3),
                    Text(time, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF111C2D))),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F3FF),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFC3C6D6)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_outline, size: 13, color: Color(0xFF003D9B)),
                    SizedBox(width: 4),
                    Text('Completed', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF003D9B))),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(color: Color(0xFFE5E6ED)),
          const SizedBox(height: 12),
          Text(diagnosis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF111C2D))),
          const SizedBox(height: 7),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.medical_services_outlined, size: 17, color: Color(0xFF00687A)),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  doctorDept.isEmpty ? doctorName : '$doctorName, $doctorDept',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF434654)),
                ),
              ),
            ],
          ),
          if (chiefComplaint.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Complaint: $chiefComplaint',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Color(0xFF737685)),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _showMedicalReport(record),
                  icon: const Icon(Icons.arrow_forward, size: 15),
                  label: const Text('View Full Report'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF003D9B),
                    side: const BorderSide(color: Color(0xFF003D9B)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: () => downloadPrescriptionPdf(
                  context,
                  record: record,
                  studentName: widget.studentName.isEmpty ? 'Student' : widget.studentName,
                  studentId: widget.studentId.isEmpty ? 'Not set' : widget.studentId,
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF00687A),
                  side: const BorderSide(color: Color(0xFF00687A)),
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Icon(Icons.picture_as_pdf_outlined, size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFC3C6D6)),
      ),
      child: Column(
        children: [
          const Icon(Icons.description_outlined, size: 45, color: Color(0xFF737685)),
          const SizedBox(height: 10),
          const Text('No medical records found', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF111C2D))),
          const SizedBox(height: 5),
          const Text(
            'Completed consultations and prescriptions will be logged here automatically.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: Color(0xFF737685)),
          ),
        ],
      ),
    );
  }

  void _showMedicalReport(Map<String, dynamic> record) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(14),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 700, maxHeight: 800),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _buildReportHeader(record),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: _buildReportBody(record),
                  ),
                ),
                _buildReportFooter(record),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildReportHeader(Map<String, dynamic> record) {
    final date = _formatDate(record['dateKey']?.toString() ?? '');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      color: const Color(0xFF003D9B),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'CUET MEDICAL CENTER',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 2, color: Color(0xFF6AE1FF)),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Official Digital Prescription Slip',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 5),
                Text(
                  'Ref ID: ${record['id'] ?? ''} • Date: $date',
                  style: const TextStyle(fontSize: 10, color: Colors.white70),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildReportBody(Map<String, dynamic> record) {
    final vitalsRaw = record['vitals'];
    final vitalsMap =
        vitalsRaw is Map ? vitalsRaw.map((k, v) => MapEntry(k.toString(), v?.toString())) : <String, String?>{};

    final testsRaw = record['testsRecommended'];
    final testsRecommended =
        testsRaw is List ? testsRaw.map((e) => e.toString()).toList() : <String>[];

    final prescriptionsRaw = record['prescriptions'];
    final prescriptions = prescriptionsRaw is List
        ? prescriptionsRaw.whereType<Map>().map((e) => e.map((k, v) => MapEntry(k.toString(), v))).toList()
        : <Map<String, dynamic>>[];

    final chiefComplaint = record['problem']?.toString() ?? record['reason']?.toString() ?? '';
    final symptoms = record['symptoms']?.toString() ?? '';
    final diagnosis = record['diagnosis']?.toString() ?? record['problem']?.toString() ?? 'Consultation';
    final treatmentAdvice = record['treatmentAdvice']?.toString() ?? '';
    final followUpDate = record['followUpDate']?.toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: const Color(0xFFF9F9FF),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFC3C6D6)),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 450) {
                return Column(
                  children: [
                    _doctorMetadata(record),
                    const SizedBox(height: 15),
                    _patientMetadata(record),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _doctorMetadata(record)),
                  Container(width: 1, height: 80, color: const Color(0xFFC3C6D6)),
                  const SizedBox(width: 18),
                  Expanded(child: _patientMetadata(record)),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 20),
        if (vitalsMap.isNotEmpty) ...[
          _reportSectionTitle(Icons.monitor_heart_outlined, 'CLINICAL VITALS RECORDED'),
          const SizedBox(height: 10),
          _buildVitals(vitalsMap),
          const SizedBox(height: 20),
        ],
        if (chiefComplaint.isNotEmpty || diagnosis.isNotEmpty) ...[
          _buildComplaintAndDiagnosis(chiefComplaint, symptoms, diagnosis),
          const SizedBox(height: 20),
        ],
        _reportSectionTitle(Icons.medication_outlined, 'PRESCRIBED MEDICINES (Rx)'),
        const SizedBox(height: 10),
        _buildPrescriptionList(prescriptions),
        const SizedBox(height: 20),
        if (testsRecommended.isNotEmpty) ...[
          _buildRecommendedTests(testsRecommended),
          const SizedBox(height: 20),
        ],
        if (treatmentAdvice.isNotEmpty) ...[
          _buildAdvice(treatmentAdvice),
          const SizedBox(height: 16),
        ],
        if (followUpDate != null && followUpDate.trim().isNotEmpty)
          Row(
            children: [
              const Icon(Icons.access_time, size: 18, color: Color(0xFF00687A)),
              const SizedBox(width: 7),
              Text(
                'Follow-up Review Date: $followUpDate',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF00687A)),
              ),
            ],
          ),
      ],
    );
  }

  Widget _doctorMetadata(Map<String, dynamic> record) {
    final doctorName = record['doctorName']?.toString() ?? 'Doctor';
    final doctorDept = record['doctorDepartment']?.toString() ?? record['department']?.toString() ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('PHYSICIAN', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF737685))),
        const SizedBox(height: 4),
        Text(doctorName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF003D9B))),
        const SizedBox(height: 3),
        Text(doctorDept, style: const TextStyle(fontSize: 11, color: Color(0xFF434654))),
      ],
    );
  }

  Widget _patientMetadata(Map<String, dynamic> record) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('STUDENT PATIENT', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF737685))),
        const SizedBox(height: 4),
        Text(
          widget.studentName.isEmpty ? 'Student' : widget.studentName,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF111C2D)),
        ),
        const SizedBox(height: 3),
        Text(
          'ID: ${widget.studentId.isEmpty ? 'Not set' : widget.studentId}',
          style: const TextStyle(fontSize: 11, color: Color(0xFF434654)),
        ),
      ],
    );
  }

  Widget _reportSectionTitle(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF00687A)),
        const SizedBox(width: 6),
        Text(title, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1, color: Color(0xFF737685))),
      ],
    );
  }

  Widget _buildVitals(Map<String, String?> vitals) {
    final entries = vitals.entries.where((e) => e.value != null && e.value!.trim().isNotEmpty).toList();

    if (entries.isEmpty) {
      return const Text('No vitals recorded.', style: TextStyle(fontSize: 11, color: Color(0xFF737685)));
    }

    return GridView.count(
      crossAxisCount: entries.length >= 4 ? 4 : 2,
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      childAspectRatio: 1.5,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: entries.map((e) => _vitalItem(e.key, e.value!)).toList(),
    );
  }

  Widget _vitalItem(String title, String value) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: const Color(0xFFF0F3FF), borderRadius: BorderRadius.circular(12)),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 9, color: Color(0xFF737685))),
          const SizedBox(height: 4),
          Text(value, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF003D9B))),
        ],
      ),
    );
  }

  Widget _buildComplaintAndDiagnosis(String chiefComplaint, String symptoms, String diagnosis) {
    return Column(
      children: [
        if (chiefComplaint.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E8),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFFD88A)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Chief Complaint & Symptoms:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF795500))),
                const SizedBox(height: 4),
                Text(
                  symptoms.isEmpty ? chiefComplaint : '$chiefComplaint ($symptoms)',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF5F4700)),
                ),
              ],
            ),
          ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: const Color(0xFFE7EEFF),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF003D9B).withOpacity(0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Clinical Diagnosis:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF003D9B))),
              const SizedBox(height: 4),
              Text(diagnosis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF111C2D))),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPrescriptionList(List<Map<String, dynamic>> prescriptions) {
    if (prescriptions.isEmpty) {
      return const Text(
        'No oral medications prescribed.',
        style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Color(0xFF737685)),
      );
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFC3C6D6))),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            color: const Color(0xFFF0F3FF),
            child: const Row(
              children: [
                Expanded(flex: 2, child: Text('Medicine', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF003D9B)))),
                Expanded(flex: 2, child: Text('Dosage', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF003D9B)))),
                Expanded(child: Text('Duration', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF003D9B)))),
              ],
            ),
          ),
          ...prescriptions.map((rx) {
            return Container(
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFE5E6ED)))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: Text('${rx['medicineName'] ?? ''}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF111C2D))),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text('${rx['dosage'] ?? ''} (${rx['frequency'] ?? ''})', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF00687A))),
                      ),
                      Expanded(child: Text('${rx['duration'] ?? ''}', style: const TextStyle(fontSize: 10, color: Color(0xFF434654)))),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text('${rx['timing'] ?? ''} - ${rx['instructions'] ?? ''}', style: const TextStyle(fontSize: 9, color: Color(0xFF737685))),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildRecommendedTests(List<String> tests) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Recommended Diagnostic Tests:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF111C2D))),
        const SizedBox(height: 6),
        ...tests.map((test) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('• ', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF003D9B))),
                Expanded(child: Text(test, style: const TextStyle(fontSize: 10, color: Color(0xFF434654)))),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildAdvice(String advice) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Doctor's Clinical Advice:", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF111C2D))),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: const Color(0xFFF9F9FF),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFC3C6D6)),
          ),
          child: Text(advice, style: const TextStyle(fontSize: 10, height: 1.5, color: Color(0xFF434654))),
        ),
      ],
    );
  }

  Widget _buildReportFooter(Map<String, dynamic> record) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: const BoxDecoration(color: Color(0xFFF5F5F7), border: Border(top: BorderSide(color: Color(0xFFC3C6D6)))),
      child: Row(
        children: [
          const Expanded(
            child: Text('CUET Medical Center Electronic Health Record', style: TextStyle(fontSize: 9, color: Color(0xFF737685))),
          ),
          OutlinedButton.icon(
            onPressed: () => downloadPrescriptionPdf(
              context,
              record: record,
              studentName: widget.studentName.isEmpty ? 'Student' : widget.studentName,
              studentId: widget.studentId.isEmpty ? 'Not set' : widget.studentId,
            ),
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 15),
            label: const Text('Download PDF'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF003D9B),
              side: const BorderSide(color: Color(0xFF003D9B)),
              textStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 7),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF003D9B),
              foregroundColor: Colors.white,
              textStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// ANNOUNCEMENTS PAGE (replaces the old "Campus Health
// Notices" dashboard section)
// ============================================================

class AnnouncementsPage extends StatefulWidget {
  const AnnouncementsPage({super.key});

  @override
  State<AnnouncementsPage> createState() => _AnnouncementsPageState();
}

class _AnnouncementsPageState extends State<AnnouncementsPage> {
  static const List<String> _visibleAudiences = ['All', 'Student'];

  bool loading = true;
  List<Map<String, dynamic>> announcements = [];

  @override
  void initState() {
    super.initState();
    _loadAnnouncements();
  }

  // ============================================================
  // LOAD ANNOUNCEMENTS
  //
  // Schema (as stored by the admin dashboard):
  //   audience:  "All" | "Student" | "Doctor" | ...
  //   content:   String
  //   priority:  "Urgent" | "Normal" | ...
  //   timestamp: Firestore Timestamp
  //   title:     String
  //
  // Shows only announcements meant for students ("All" or
  // "Student"), most recent first.
  // ============================================================

  Future<void> _loadAnnouncements() async {
    try {
      List<Map<String, dynamic>> loaded;

      try {
        // Preferred path: server-side filter + sort.
        // NOTE: Firestore may require a composite index for
        // `where('audience', whereIn: ...)` combined with
        // `orderBy('timestamp')`. If you see a "failed-precondition /
        // requires an index" error in the console it will include a
        // direct link to create it — click it once and this query
        // will work going forward.
        final snapshot = await FirebaseFirestore.instance
            .collection('announcements')
            .where('audience', whereIn: _visibleAudiences)
            .orderBy('timestamp', descending: true)
            .get();

        loaded = snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
      } catch (e) {
        // Fallback: fetch everything and filter/sort on the client
        // (works immediately, no index required).
        debugPrint('Falling back to client-side announcement filtering: $e');

        final snapshot = await FirebaseFirestore.instance.collection('announcements').get();

        loaded = snapshot.docs
            .map((doc) => {'id': doc.id, ...doc.data()})
            .where((item) {
              final audience = item['audience']?.toString() ?? 'All';
              return _visibleAudiences.contains(audience);
            })
            .toList();

        loaded.sort((a, b) {
          final dateA = _timestampToDate(a['timestamp']);
          final dateB = _timestampToDate(b['timestamp']);
          return dateB.compareTo(dateA);
        });
      }

      if (!mounted) return;

      setState(() {
        announcements = loaded;
        loading = false;
      });
    } catch (e) {
      debugPrint('Failed to load announcements: $e');

      if (!mounted) return;

      setState(() {
        announcements = [];
        loading = false;
      });
    }
  }

  DateTime _timestampToDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  String _formatTimestamp(dynamic value) {
    if (value is! Timestamp) return '';

    final date = value.toDate();

    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];

    final hour12 = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final period = date.hour >= 12 ? 'PM' : 'AM';
    final minute = date.minute.toString().padLeft(2, '0');

    return '${date.day} ${months[date.month - 1]} ${date.year}, $hour12:$minute $period';
  }

  Color _priorityColor(String priority) {
    switch (priority.toLowerCase()) {
      case 'urgent':
        return const Color(0xFFD32F2F);
      case 'high':
        return const Color(0xFFEF6C00);
      default:
        return const Color(0xFF00687A);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        backgroundColor: const Color(0xFF003D9B),
        foregroundColor: Colors.white,
        title: const Text('Announcements'),
      ),
      body: RefreshIndicator(
        onRefresh: _loadAnnouncements,
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : announcements.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 120),
                      Icon(Icons.campaign_outlined, size: 60, color: Color(0xFF003D9B)),
                      SizedBox(height: 16),
                      Center(
                        child: Text('No Announcements', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ),
                      SizedBox(height: 6),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 40),
                        child: Text(
                          'New campus health notices and announcements will appear here.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFF737685)),
                        ),
                      ),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: announcements.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final item = announcements[index];

                      final title = item['title']?.toString() ?? 'Announcement';
                      final content = item['content']?.toString() ??
                          item['body']?.toString() ??
                          item['message']?.toString() ??
                          '';
                      final priority = item['priority']?.toString() ?? '';
                      final audience = item['audience']?.toString() ?? 'All';
                      final timestampLabel = _formatTimestamp(item['timestamp']);

                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFC3C6D6)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.03),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    title,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF111C2D),
                                    ),
                                  ),
                                ),
                                if (priority.isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: _priorityColor(priority).withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      priority.toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.5,
                                        color: _priorityColor(priority),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            if (content.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                content,
                                style: const TextStyle(fontSize: 12, height: 1.4, color: Color(0xFF434654)),
                              ),
                            ],
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                const Icon(Icons.access_time, size: 12, color: Color(0xFF737685)),
                                const SizedBox(width: 4),
                                Text(
                                  timestampLabel.isEmpty ? 'Just now' : timestampLabel,
                                  style: const TextStyle(fontSize: 10, color: Color(0xFF737685)),
                                ),
                                const SizedBox(width: 12),
                                const Icon(Icons.groups_outlined, size: 12, color: Color(0xFF737685)),
                                const SizedBox(width: 4),
                                Text(
                                  audience,
                                  style: const TextStyle(fontSize: 10, color: Color(0xFF737685)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}

// ============================================================
// DEMO FEATURE PAGE
// ============================================================

class DemoFeaturePage extends StatelessWidget {
  final String title;
  final IconData icon;

  const DemoFeaturePage({super.key, required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF003D9B),
        foregroundColor: Colors.white,
        title: Text(title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 70, color: const Color(0xFF003D9B)),
            const SizedBox(height: 20),
            Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}