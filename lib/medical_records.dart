import 'package:flutter/material.dart'; // Flutter UI widgets

// NOTE: StatefulWidget because the screen changes when the user types in the
// search box (searchQuery changes -> list must refresh).
class MedicalRecordsPage extends StatefulWidget {
  const MedicalRecordsPage({super.key});

  @override
  State<MedicalRecordsPage> createState() => _MedicalRecordsPageState();
}

class _MedicalRecordsPageState extends State<MedicalRecordsPage> {
  // ==============================================================
  // DEMO CURRENT STUDENT
  // NOTE: Fixed demo student. In a real app this comes from login
  // (Firebase Auth / user profile).
  // ==============================================================

  final String currentStudentName = 'Rahim Ahmed';
  final String currentStudentId = 'CSE-21001';
  final String currentStudentDepartment = 'CSE';

  // ==============================================================
  // SEARCH
  // NOTE: Stores the text typed in the search box.
  // ==============================================================

  String searchQuery = '';

  // ==============================================================
  // DEMO MEDICAL RECORDS
  // Later these can come from Firebase / backend.
  // NOTE: Hard-coded sample data (3 visits) so the UI can be tested
  // without a database.
  // ==============================================================

  final List<MedicalRecord> medicalRecords = [
    // ---- Record 1: Flu & Fever ----
    MedicalRecord(
      id: 'REC-2023-001',
      studentId: 'CSE-21001',
      studentName: 'Rahim Ahmed',
      date: 'Oct 12, 2023',
      time: '10:30 AM',
      diagnosis: 'Seasonal Flu & Fever',
      doctorName: 'Dr. Anisur Rahman',
      doctorDept: 'General Medicine',
      chiefComplaint: 'Fever, headache and body weakness',
      symptoms: 'Fever, headache, mild cough',
      // Vitals = body measurements taken at the visit
      vitals: Vitals(
        bloodPressure: '120/80 mmHg',
        temperature: '101.2°F',
        pulseRate: '88 bpm',
        spO2: '98%', // Oxygen saturation
      ),
      // List of medicines given by the doctor
      prescriptions: [
        Prescription(
          medicineName: 'Paracetamol 500mg',
          dosage: '1 tablet',
          frequency: '3 times/day',
          duration: '5 days',
          timing: 'After meals',
          instructions: 'Take with sufficient water.',
        ),
        Prescription(
          medicineName: 'Cetirizine 10mg',
          dosage: '1 tablet',
          frequency: 'Once/day',
          duration: '5 days',
          timing: 'At night',
          instructions: 'May cause drowsiness.',
        ),
      ],
      testsRecommended: [
        'CBC',
        'Temperature monitoring',
      ],
      treatmentAdvice:
          'Rest adequately, drink sufficient fluids, and monitor your temperature. '
          'Return to the medical center if symptoms worsen or persist.',
      followUpDate: 'Oct 17, 2023',
    ),

    // ---- Record 2: Wrist strain ----
    MedicalRecord(
      id: 'REC-2023-002',
      studentId: 'CSE-21001',
      studentName: 'Rahim Ahmed',
      date: 'Sep 05, 2023',
      time: '02:15 PM',
      diagnosis: 'Wrist Strain - Left Hand',
      doctorName: 'Dr. Shafiqul Kabir',
      doctorDept: 'Orthopedics',
      chiefComplaint: 'Pain in left wrist after sports activity',
      symptoms: 'Wrist pain, mild swelling and reduced movement',
      vitals: Vitals(
        bloodPressure: '118/78 mmHg',
        temperature: '98.4°F',
        pulseRate: '76 bpm',
        spO2: '99%',
      ),
      prescriptions: [
        Prescription(
          medicineName: 'Ibuprofen 400mg',
          dosage: '1 tablet',
          frequency: '2 times/day',
          duration: '3 days',
          timing: 'After meals',
          instructions: 'Take only as directed.',
        ),
      ],
      testsRecommended: [
        'Left wrist X-Ray',
      ],
      treatmentAdvice:
          'Avoid strenuous activity involving the affected wrist. '
          'Apply a cold pack when necessary and allow adequate rest.',
      followUpDate: 'Sep 12, 2023',
    ),

    // ---- Record 3: Gastritis ----
    MedicalRecord(
      id: 'REC-2023-003',
      studentId: 'CSE-21001',
      studentName: 'Rahim Ahmed',
      date: 'Jul 21, 2023',
      time: '11:00 AM',
      diagnosis: 'Gastritis',
      doctorName: 'Dr. Nusrat Jahan',
      doctorDept: 'General Medicine',
      chiefComplaint: 'Stomach discomfort after meals',
      symptoms: 'Abdominal discomfort, acidity and nausea',
      vitals: Vitals(
        bloodPressure: '122/80 mmHg',
        temperature: '98.2°F',
        pulseRate: '80 bpm',
        spO2: '99%',
      ),
      prescriptions: [
        Prescription(
          medicineName: 'Omeprazole 20mg',
          dosage: '1 capsule',
          frequency: 'Once/day',
          duration: '14 days',
          timing: 'Before breakfast',
          instructions: 'Take before eating.',
        ),
      ],
      testsRecommended: [], // No tests -> "tests" section will be hidden
      treatmentAdvice:
          'Avoid spicy and oily food. Maintain regular meal times and '
          'drink adequate water throughout the day.',
      followUpDate: null, // No follow-up -> follow-up line will be hidden
    ),
  ];

  // ==============================================================
  // FILTER RECORDS
  // NOTE: A "getter" - returns the list that should be displayed.
  // Step 1: keep only records of the current student.
  // Step 2: if the user typed something, filter by that text.
  // ==============================================================

  List<MedicalRecord> get filteredRecords {
    // Step 1: only this student's records (match by ID or first name)
    final studentRecords = medicalRecords.where(
      (record) {
        return record.studentId == currentStudentId ||
            record.studentName.toLowerCase().contains(
                  currentStudentName.toLowerCase().split(' ').first,
                );
      },
    ).toList();

    // No search text -> show all of the student's records
    if (searchQuery.trim().isEmpty) {
      return studentRecords;
    }

    final query = searchQuery.toLowerCase(); // Ignore upper/lower case

    // Step 2: search in diagnosis, doctor name, date and complaint
    return studentRecords.where(
      (record) {
        return record.diagnosis.toLowerCase().contains(query) ||
            record.doctorName.toLowerCase().contains(query) ||
            record.date.toLowerCase().contains(query) ||
            record.chiefComplaint.toLowerCase().contains(query);
      },
    ).toList();
  }

  // ==============================================================
  // BUILD
  // NOTE: Main screen = AppBar + scrollable body (header + records list).
  // ==============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB), // Light page background

      // ============================================================
      // APP BAR
      // ============================================================

      appBar: AppBar(
        backgroundColor: const Color(0xFF003D9B), // Dark blue
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Medical Records',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),

      // ============================================================
      // BODY
      // NOTE: Center + ConstrainedBox(maxWidth 900) keeps content from
      // becoming too wide on big screens (tablet / web).
      // ============================================================

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 900,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(), // Title + search box

                  const SizedBox(height: 24),

                  _buildRecordsList(), // All record cards

                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ==============================================================
  // HEADER
  // NOTE: Page title, short description and the search box.
  // ==============================================================

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Medical History',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Color(0xFF111C2D),
          ),
        ),

        const SizedBox(height: 5),

        const Text(
          'Chronological record of your visits, prescriptions, and diagnoses.',
          style: TextStyle(
            fontSize: 13,
            color: Color(0xFF434654),
          ),
        ),

        const SizedBox(height: 16),

        // SEARCH BOX
        // NOTE: onChanged runs on every key press -> updates searchQuery
        // -> setState rebuilds the screen -> list is filtered live.
        TextField(
          onChanged: (value) {
            setState(() {
              searchQuery = value;
            });
          },
          decoration: InputDecoration(
            hintText: 'Search records or diagnoses...',
            hintStyle: const TextStyle(
              fontSize: 12,
              color: Color(0xFF737685),
            ),
            prefixIcon: const Icon(
              Icons.search,
              color: Color(0xFF737685),
            ),

            // Clear (X) button appears only when something is typed
            suffixIcon: searchQuery.isNotEmpty
                ? IconButton(
                    tooltip: 'Clear',
                    onPressed: () {
                      setState(() {
                        searchQuery = '';
                      });
                    },
                    icon: const Icon(
                      Icons.close,
                      size: 18,
                      color: Color(0xFF737685),
                    ),
                  )
                : null,

            filled: true,
            fillColor: Colors.white,

            // Border styles: normal, enabled, and focused (blue, thicker)
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: Color(0xFFC3C6D6),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: Color(0xFFC3C6D6),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: Color(0xFF003D9B),
                width: 1.5,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
          ),
        ),
      ],
    );
  }

  // ==============================================================
  // RECORDS LIST
  // NOTE: If no record matches -> show empty message.
  // Otherwise create one card for each record.
  // ==============================================================

  Widget _buildRecordsList() {
    final records = filteredRecords;

    if (records.isEmpty) {
      return _buildEmptyState();
    }

    return Column(
      children: records.map(
        (record) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _buildRecordCard(record),
          );
        },
      ).toList(),
    );
  }

  // ==============================================================
  // RECORD CARD
  // NOTE: Short summary card of one visit (date, diagnosis, doctor,
  // complaint) with a "View Full Report" button.
  // ==============================================================

  Widget _buildRecordCard(MedicalRecord record) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      // White rounded card with border and soft shadow
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFC3C6D6),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ========================================================
          // DATE + STATUS
          // NOTE: Date and time on the left, "Completed" badge on right.
          // ========================================================

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.date.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                        color: Color(0xFF737685),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      record.time,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF111C2D),
                      ),
                    ),
                  ],
                ),
              ),

              // "Completed" badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F3FF),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFFC3C6D6),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 13,
                      color: Color(0xFF003D9B),
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Completed',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF003D9B),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          const Divider(
            color: Color(0xFFE5E6ED),
          ),

          const SizedBox(height: 12),

          // ========================================================
          // DIAGNOSIS
          // NOTE: Main title of the card + doctor name and department
          // + chief complaint (max 2 lines, "..." if longer).
          // ========================================================

          Text(
            record.diagnosis,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: Color(0xFF111C2D),
            ),
          ),

          const SizedBox(height: 7),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.medical_services_outlined,
                size: 17,
                color: Color(0xFF00687A),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  '${record.doctorName}, ${record.doctorDept}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF434654),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 6),

          Text(
            'Complaint: ${record.chiefComplaint}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF737685),
            ),
          ),

          const SizedBox(height: 14),

          // ========================================================
          // VIEW REPORT BUTTON
          // NOTE: Opens a popup (dialog) with the full report.
          // ========================================================

          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                _showMedicalReport(record);
              },
              icon: const Icon(
                Icons.arrow_forward,
                size: 15,
              ),
              label: const Text(
                'View Full Report',
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF003D9B),
                side: const BorderSide(
                  color: Color(0xFF003D9B),
                ),
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==============================================================
  // EMPTY STATE
  // NOTE: Shown when there are no records (or search finds nothing).
  // ==============================================================

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFC3C6D6),
        ),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.description_outlined,
            size: 45,
            color: Color(0xFF737685),
          ),
          const SizedBox(height: 10),
          const Text(
            'No medical records found',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF111C2D),
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'Past consultations and prescriptions will be logged here automatically.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              color: Color(0xFF737685),
            ),
          ),
        ],
      ),
    );
  }

  // ==============================================================
  // SHOW FULL MEDICAL REPORT
  // NOTE: Opens a popup dialog. Structure of the popup:
  //   Header (blue)  -> Body (scrollable)  -> Footer (Print / Close)
  // barrierDismissible: true = tapping outside closes the popup.
  // ==============================================================

  void _showMedicalReport(MedicalRecord record) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(14),
          child: Container(
            constraints: const BoxConstraints(
              maxWidth: 700,
              maxHeight: 800,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
            ),
            clipBehavior: Clip.antiAlias, // Cuts content to rounded corners
            child: Column(
              children: [
                _buildReportHeader(record),

                // Expanded + SingleChildScrollView = body scrolls if long
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: _buildReportBody(record),
                  ),
                ),

                _buildReportFooter(),
              ],
            ),
          ),
        );
      },
    );
  }

  // ==============================================================
  // REPORT HEADER
  // NOTE: Blue top bar: center name, title, Ref ID + date, close (X).
  // ==============================================================

  Widget _buildReportHeader(MedicalRecord record) {
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
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                    color: Color(0xFF6AE1FF),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Official Digital Prescription Slip',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Ref ID: ${record.id} • Date: ${record.date}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),

          // Close button -> closes the popup
          IconButton(
            onPressed: () {
              Navigator.pop(context);
            },
            icon: const Icon(
              Icons.close,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  // ==============================================================
  // REPORT BODY
  // NOTE: All details in order: Doctor+Patient, Vitals, Complaint &
  // Diagnosis, Prescriptions, Tests, Advice, Follow-up.
  // ==============================================================

  Widget _buildReportBody(MedicalRecord record) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ==========================================================
        // DOCTOR + PATIENT
        // NOTE: LayoutBuilder checks available width.
        // Narrow screen (< 450) -> stack vertically.
        // Wide screen -> show side by side with a divider line.
        // ==========================================================

        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: const Color(0xFFF9F9FF),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFFC3C6D6),
            ),
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
                  Expanded(
                    child: _doctorMetadata(record),
                  ),
                  Container(
                    width: 1,
                    height: 80,
                    color: const Color(0xFFC3C6D6),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: _patientMetadata(record),
                  ),
                ],
              );
            },
          ),
        ),

        const SizedBox(height: 20),

        // ==========================================================
        // VITALS
        // NOTE: "if (...) ...[ ]" = show this block only when vitals exist.
        // ==========================================================

        if (record.vitals != null) ...[
          _reportSectionTitle(
            Icons.monitor_heart_outlined,
            'CLINICAL VITALS RECORDED',
          ),
          const SizedBox(height: 10),
          _buildVitals(record.vitals!), // "!" = we know it is not null here
          const SizedBox(height: 20),
        ],

        // ==========================================================
        // COMPLAINT + DIAGNOSIS
        // ==========================================================

        _buildComplaintAndDiagnosis(record),

        const SizedBox(height: 20),

        // ==========================================================
        // PRESCRIPTIONS
        // ==========================================================

        _reportSectionTitle(
          Icons.medication_outlined,
          'PRESCRIBED MEDICINES (Rx)',
        ),
        const SizedBox(height: 10),
        _buildPrescriptionList(record),
        const SizedBox(height: 20),

        // ==========================================================
        // TESTS
        // NOTE: Hidden if no tests were recommended.
        // ==========================================================

        if (record.testsRecommended.isNotEmpty) ...[
          _buildRecommendedTests(record),
          const SizedBox(height: 20),
        ],

        // ==========================================================
        // ADVICE
        // ==========================================================

        _buildAdvice(record),

        const SizedBox(height: 16),

        // ==========================================================
        // FOLLOW UP
        // NOTE: Hidden if followUpDate is null.
        // ==========================================================

        if (record.followUpDate != null)
          Row(
            children: [
              const Icon(
                Icons.access_time,
                size: 18,
                color: Color(0xFF00687A),
              ),
              const SizedBox(width: 7),
              Text(
                'Follow-up Review Date: ${record.followUpDate}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF00687A),
                ),
              ),
            ],
          ),
      ],
    );
  }

  // ==============================================================
  // DOCTOR METADATA
  // NOTE: Small block showing physician name and department.
  // ==============================================================

  Widget _doctorMetadata(MedicalRecord record) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'PHYSICIAN',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: Color(0xFF737685),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          record.doctorName,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Color(0xFF003D9B),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          record.doctorDept,
          style: const TextStyle(
            fontSize: 11,
            color: Color(0xFF434654),
          ),
        ),
      ],
    );
  }

  // ==============================================================
  // PATIENT METADATA
  // NOTE: Small block showing student name, ID and department.
  // ==============================================================

  Widget _patientMetadata(MedicalRecord record) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'STUDENT PATIENT',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: Color(0xFF737685),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          record.studentName,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Color(0xFF111C2D),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          'ID: ${record.studentId} • Dept: $currentStudentDepartment',
          style: const TextStyle(
            fontSize: 11,
            color: Color(0xFF434654),
          ),
        ),
      ],
    );
  }

  // ==============================================================
  // REPORT SECTION TITLE
  // NOTE: Reusable small heading (icon + text). Used by several sections
  // so we do not repeat the same code.
  // ==============================================================

  Widget _reportSectionTitle(
    IconData icon,
    String title,
  ) {
    return Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: const Color(0xFF00687A),
        ),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
            color: Color(0xFF737685),
          ),
        ),
      ],
    );
  }

  // ==============================================================
  // VITALS
  // NOTE: Builds a small tile for each vital that is not null, then
  // shows them in a grid (4 columns if 4 items, otherwise 2).
  // ==============================================================

  Widget _buildVitals(Vitals vitals) {
    final List<Widget> items = [];

    if (vitals.bloodPressure != null) {
      items.add(
        _vitalItem(
          'Blood Pressure',
          vitals.bloodPressure!,
        ),
      );
    }

    if (vitals.temperature != null) {
      items.add(
        _vitalItem(
          'Temperature',
          vitals.temperature!,
        ),
      );
    }

    if (vitals.pulseRate != null) {
      items.add(
        _vitalItem(
          'Pulse',
          vitals.pulseRate!,
        ),
      );
    }

    if (vitals.spO2 != null) {
      items.add(
        _vitalItem(
          'Oxygen SpO2',
          vitals.spO2!,
        ),
      );
    }

    return GridView.count(
      crossAxisCount: items.length >= 4 ? 4 : 2,
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      childAspectRatio: 1.5,
      shrinkWrap: true, // Grid takes only the space it needs
      physics: const NeverScrollableScrollPhysics(), // Parent already scrolls
      children: items,
    );
  }

  // NOTE: One small tile: title (e.g. "Pulse") and value (e.g. "88 bpm").
  Widget _vitalItem(
    String title,
    String value,
  ) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F3FF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 9,
              color: Color(0xFF737685),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Color(0xFF003D9B),
            ),
          ),
        ],
      ),
    );
  }

  // ==============================================================
  // COMPLAINT + DIAGNOSIS
  // NOTE: Two colored boxes: yellow = complaint & symptoms,
  // blue = clinical diagnosis.
  // ==============================================================

  Widget _buildComplaintAndDiagnosis(
    MedicalRecord record,
  ) {
    return Column(
      children: [
        // Yellow box: chief complaint + symptoms
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF8E8),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFFFFD88A),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Chief Complaint & Symptoms:',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF795500),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${record.chiefComplaint} (${record.symptoms})',
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF5F4700),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 10),

        // Blue box: diagnosis
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: const Color(0xFFE7EEFF),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFF003D9B).withOpacity(0.2),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Clinical Diagnosis:',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF003D9B),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                record.diagnosis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF111C2D),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ==============================================================
  // PRESCRIPTION LIST
  // NOTE: A table-like layout.
  // Row 1 = header (Medicine | Dosage | Duration).
  // Then one row for every medicine, with timing + instructions below.
  // If there are no medicines, a short italic message is shown.
  // ==============================================================

  Widget _buildPrescriptionList(
    MedicalRecord record,
  ) {
    if (record.prescriptions.isEmpty) {
      return const Text(
        'No oral medications prescribed.',
        style: TextStyle(
          fontSize: 11,
          fontStyle: FontStyle.italic,
          color: Color(0xFF737685),
        ),
      );
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFC3C6D6),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Header
          // NOTE: flex 2 / 2 / 1 = column width ratio.
          Container(
            padding: const EdgeInsets.all(10),
            color: const Color(0xFFF0F3FF),
            child: const Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    'Medicine',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF003D9B),
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Dosage',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF003D9B),
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Duration',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF003D9B),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // One row for each medicine ("rx" = prescription item)
          ...record.prescriptions.map(
            (rx) {
              return Container(
                padding: const EdgeInsets.all(10),
                // Thin line on top to separate rows
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: Color(0xFFE5E6ED),
                    ),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Medicine name
                        Expanded(
                          flex: 2,
                          child: Text(
                            rx.medicineName,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF111C2D),
                            ),
                          ),
                        ),

                        // Dosage + how many times a day
                        Expanded(
                          flex: 2,
                          child: Text(
                            '${rx.dosage} (${rx.frequency})',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF00687A),
                            ),
                          ),
                        ),

                        // For how many days
                        Expanded(
                          child: Text(
                            rx.duration,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xFF434654),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 6),

                    // When to take + special instructions
                    Text(
                      '${rx.timing} - ${rx.instructions}',
                      style: const TextStyle(
                        fontSize: 9,
                        color: Color(0xFF737685),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ==============================================================
  // RECOMMENDED TESTS
  // NOTE: Bullet list of tests suggested by the doctor.
  // ==============================================================

  Widget _buildRecommendedTests(
    MedicalRecord record,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Recommended Diagnostic Tests:',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Color(0xFF111C2D),
          ),
        ),
        const SizedBox(height: 6),

        // One bullet row for each test
        ...record.testsRecommended.map(
          (test) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '• ',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF003D9B),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      test,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF434654),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  // ==============================================================
  // ADVICE
  // NOTE: Doctor's written advice inside a light box.
  // ==============================================================

  Widget _buildAdvice(
    MedicalRecord record,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Doctor's Clinical Advice:",
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Color(0xFF111C2D),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: const Color(0xFFF9F9FF),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFFC3C6D6),
            ),
          ),
          child: Text(
            record.treatmentAdvice,
            style: const TextStyle(
              fontSize: 10,
              height: 1.5, // Line spacing for easy reading
              color: Color(0xFF434654),
            ),
          ),
        ),
      ],
    );
  }

  // ==============================================================
  // REPORT FOOTER
  // NOTE: Bottom bar of the popup: hospital text, Print button
  // (only shows a message for now), and Close button.
  // ==============================================================

  Widget _buildReportFooter() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: const BoxDecoration(
        color: Color(0xFFF5F5F7),
        border: Border(
          top: BorderSide(
            color: Color(0xFFC3C6D6),
          ),
        ),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'CUET Medical Center Electronic Health Record',
              style: TextStyle(
                fontSize: 9,
                color: Color(0xFF737685),
              ),
            ),
          ),

          // Print button (placeholder - real printing not connected yet)
          OutlinedButton.icon(
            onPressed: () {
              _showMessage(
                'Print feature can be connected to the printing package.',
              );
            },
            icon: const Icon(
              Icons.print_outlined,
              size: 15,
            ),
            label: const Text(
              'Print',
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF003D9B),
              side: const BorderSide(
                color: Color(0xFF003D9B),
              ),
              textStyle: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          const SizedBox(width: 7),

          // Close button -> closes the popup
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF003D9B),
              foregroundColor: Colors.white,
              textStyle: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Close',
            ),
          ),
        ],
      ),
    );
  }

  // ==============================================================
  // SNACKBAR
  // NOTE: Shows a small message at the bottom of the screen.
  // ==============================================================

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

// ====================================================================
// MEDICAL RECORD MODEL
// NOTE: Data class - holds all information of ONE medical visit.
// "final" = value cannot change after creation.
// "String?" = value can be null (optional).
// ====================================================================

class MedicalRecord {
  final String id; // Record reference number
  final String studentId;
  final String studentName;

  final String date;
  final String time;

  final String diagnosis;

  final String doctorName;
  final String doctorDept;

  final String chiefComplaint; // Main reason for visit
  final String symptoms;

  final Vitals? vitals; // Optional body measurements

  final List<Prescription> prescriptions; // Medicines given

  final List<String> testsRecommended; // Suggested lab tests

  final String treatmentAdvice;

  final String? followUpDate; // Optional next visit date

  const MedicalRecord({
    required this.id,
    required this.studentId,
    required this.studentName,
    required this.date,
    required this.time,
    required this.diagnosis,
    required this.doctorName,
    required this.doctorDept,
    required this.chiefComplaint,
    required this.symptoms,
    required this.vitals,
    required this.prescriptions,
    required this.testsRecommended,
    required this.treatmentAdvice,
    required this.followUpDate,
  });
}

// ====================================================================
// VITALS MODEL
// NOTE: Body measurements. All fields are optional (can be null),
// so the report shows only the values that exist.
// ====================================================================

class Vitals {
  final String? bloodPressure;
  final String? temperature;
  final String? pulseRate;
  final String? spO2; // Blood oxygen level

  const Vitals({
    this.bloodPressure,
    this.temperature,
    this.pulseRate,
    this.spO2,
  });
}

// ====================================================================
// PRESCRIPTION MODEL
// NOTE: One medicine entry: name, how much, how often, how long, when
// to take, and extra instructions.
// ====================================================================

class Prescription {
  final String medicineName;
  final String dosage;
  final String frequency;
  final String duration;
  final String timing;
  final String instructions;

  const Prescription({
    required this.medicineName,
    required this.dosage,
    required this.frequency,
    required this.duration,
    required this.timing,
    required this.instructions,
  });
}
