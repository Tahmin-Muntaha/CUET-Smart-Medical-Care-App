import 'package:cloud_firestore/cloud_firestore.dart'; // Firestore database (read/write data)
import 'package:firebase_auth/firebase_auth.dart'; // Firebase login system (to get current user)
import 'package:flutter/material.dart'; // Flutter UI widgets

// ============================================================================
// APPOINTMENT RESULT
// NOTE: This is a simple data class. After booking succeeds, we create one
// object of this class and send it back to the previous page
// (via Navigator.pop) so that page can show the booking summary.
// ============================================================================

class AppointmentResult {
  final String appointmentId; // Firestore document id of the appointment
  final String doctorId; // Doctor's user id
  final String doctorName;
  final String department; // Doctor's specialization
  final String reason; // Why the student is visiting
  final String symptoms;
  final String date; // Display date (dd/mm/yyyy)
  final String time; // Time slot, e.g. "10:00 AM - 11:00 AM"
  final String room; // Doctor's chamber/room
  final String queueNumber; // Token number given to the student

  const AppointmentResult({
    required this.appointmentId,
    required this.doctorId,
    required this.doctorName,
    required this.department,
    required this.reason,
    required this.symptoms,
    required this.date,
    required this.time,
    required this.room,
    required this.queueNumber,
  });
}

// ============================================================================
// DOCTOR MODEL
// NOTE: Represents one doctor shown in the booking page.
// ============================================================================

class BookingDoctor {
  final String id;
  final String name;
  final String department;
  final String degrees;
  final String room;
  final String shift; // Working hours text, e.g. "10.00AM - 2.00PM"
  final bool isActive; // Only active doctors are shown to students

  const BookingDoctor({
    required this.id,
    required this.name,
    required this.department,
    required this.degrees,
    required this.room,
    required this.shift,
    required this.isActive,
  });

  // NOTE: Converts a Firestore document into a BookingDoctor object.
  // Different documents may use different field names, so for every value
  // we try several possible keys (see _getString below).
  factory BookingDoctor.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {}; // If document is empty, use empty map

    return BookingDoctor(
      id: doc.id, // Document id = doctor's uid

      // Try these keys one by one; fallback is 'Doctor'
      name: _getString(
        data,
        ['fullName', 'name', 'doctorName', 'displayName'],
        'Doctor',
      ),

      // Department may be saved as specialization / speciality / etc.
      department: _getString(
        data,
        ['specialization', 'speciality', 'specialty', 'department'],
        'General Medicine',
      ),

      degrees: _getString(
        data,
        ['degrees', 'degree', 'qualification', 'qualifications'],
        '',
      ),

      room: _getString(
        data,
        ['chamber', 'room', 'roomNumber', 'chamberNumber'],
        'Not assigned',
      ),

      shift: _getString(
        data,
        ['shift', 'workingShift', 'dutyShift'],
        '',
      ),

      isActive: _getActiveStatus(data), // true/false based on data
    );
  }
}

// ============================================================================
// HELPER - GET STRING
// NOTE: Takes a list of possible keys and returns the first one that has a
// non-empty value. If none found, returns the fallback value.
// ============================================================================

String _getString(
  Map<String, dynamic> data,
  List<String> keys,
  String fallback,
) {
  for (final key in keys) {
    final value = data[key];

    if (value != null && value.toString().trim().isNotEmpty) {
      return value.toString().trim();
    }
  }

  return fallback;
}

// ============================================================================
// HELPER - ACTIVE STATUS
// NOTE: Decides whether a doctor is active. Checks several possible fields.
// If nothing says "inactive", the doctor is treated as active (default true).
// ============================================================================

bool _getActiveStatus(
  Map<String, dynamic> data,
) {
  if (data['isActive'] != null) {
    return data['isActive'] == true;
  }

  if (data['active'] != null) {
    return data['active'] == true;
  }

  if (data['available'] != null) {
    return data['available'] == true;
  }

  // 'status' is text, so we check for words meaning "not active"
  if (data['status'] != null) {
    final status = data['status'].toString().toLowerCase().trim();

    if (status == 'inactive' ||
        status == 'disabled' ||
        status == 'suspended') {
      return false;
    }
  }

  return true;
}

// ============================================================================
// BOOK APPOINTMENT PAGE
// NOTE: StatefulWidget because the screen changes (steps, slots, loading).
// initialDoctor is optional: if another page sends a doctor, it is
// pre-selected automatically.
// ============================================================================

class BookAppointmentPage extends StatefulWidget {
  final BookingDoctor? initialDoctor;

  const BookAppointmentPage({
    super.key,
    this.initialDoctor,
  });

  @override
  State<BookAppointmentPage> createState() => _BookAppointmentPageState();
}

// ============================================================================
// STATE
// NOTE: All variables and logic of the page live here.
// ============================================================================

class _BookAppointmentPageState extends State<BookAppointmentPage> {
  final FirebaseFirestore firestore = FirebaseFirestore.instance; // Database
  final FirebaseAuth auth = FirebaseAuth.instance; // Logged-in user info

  // --------------------------------------------------------------------------
  // STEP
  // NOTE: 0 = Doctor, 1 = Date & Time, 2 = Details, 3 = Confirm
  // --------------------------------------------------------------------------

  int currentStep = 0;

  // --------------------------------------------------------------------------
  // DOCTORS
  // --------------------------------------------------------------------------

  List<BookingDoctor> doctors = []; // All active doctors loaded from Firestore

  BookingDoctor? selectedDoctor; // Doctor chosen by student (null = none)

  // --------------------------------------------------------------------------
  // DATE
  // NOTE: Default date is tomorrow (today + 1 day).
  // --------------------------------------------------------------------------

  DateTime selectedDate = DateTime.now().add(
    const Duration(days: 1),
  );

  // --------------------------------------------------------------------------
  // TIME
  // --------------------------------------------------------------------------

  List<String> timeSlots = []; // All 1-hour slots for the doctor's shift

  Set<String> bookedSlots = {}; // Slots already taken by other students

  String? selectedTimeSlot; // Slot chosen by the student

  // --------------------------------------------------------------------------
  // LOADING FLAGS
  // NOTE: Used to show spinners / disable buttons.
  // --------------------------------------------------------------------------

  bool loadingDoctors = true;

  bool loadingSlots = false;

  bool booking = false;

  String? errorMessage; // Shown in a red box at the top when something fails

  // --------------------------------------------------------------------------
  // TEXT FIELDS
  // NOTE: Controllers read what the student types.
  // --------------------------------------------------------------------------

  final TextEditingController reasonController = TextEditingController();

  final TextEditingController symptomsController = TextEditingController();

  // ==========================================================================
  // INIT
  // NOTE: Runs once when the page opens. We start loading doctors here.
  // ==========================================================================

  @override
  void initState() {
    super.initState();

    _loadDoctors();
  }

  // ==========================================================================
  // DISPOSE
  // NOTE: Runs when the page closes. Controllers must be disposed to free
  // memory.
  // ==========================================================================

  @override
  void dispose() {
    reasonController.dispose();
    symptomsController.dispose();

    super.dispose();
  }

  // ==========================================================================
  // LOAD DOCTORS
  //
  // IMPORTANT:
  //
  // Doctors are NOT stored in "doctors".
  //
  // Doctors are users where:
  //
  // role == doctor
  // ==========================================================================

  Future<void> _loadDoctors() async {
    if (!mounted) return; // If page is already closed, do nothing

    setState(() {
      loadingDoctors = true; // Show spinner
      errorMessage = null; // Clear old error
    });

    try {
      // Get all users whose role is "doctor"
      final snapshot = await firestore
          .collection('users')
          .where(
            'role',
            isEqualTo: 'doctor',
          )
          .get();

      // Convert each document to BookingDoctor, then keep only active ones
      final loadedDoctors = snapshot.docs
          .map(
            (doc) => BookingDoctor.fromFirestore(doc),
          )
          .where(
            (doctor) => doctor.isActive,
          )
          .toList();

      // Sort doctors by name (A to Z, ignoring upper/lower case).
      loadedDoctors.sort(
        (a, b) => a.name.toLowerCase().compareTo(
              b.name.toLowerCase(),
            ),
      );

      if (!mounted) return;

      setState(() {
        doctors = loadedDoctors;
        loadingDoctors = false; // Hide spinner
      });

      // If a doctor was passed from another page,
      // automatically select that doctor.
      if (widget.initialDoctor != null) {
        final matchingDoctors = loadedDoctors.where(
          (doctor) => doctor.id == widget.initialDoctor!.id,
        );

        if (matchingDoctors.isNotEmpty) {
          selectedDoctor = matchingDoctors.first;

          await _loadAvailableSlots(); // Load slots for that doctor
        }
      }
    } catch (e) {
      debugPrint(
        'Error loading doctors: $e',
      );

      if (!mounted) return;

      setState(() {
        loadingDoctors = false;

        errorMessage = 'Could not load doctors.\n$e';
      });
    }
  }

  // ==========================================================================
  // DATE KEY
  // NOTE: Converts a date to "yyyy-MM-dd" (e.g. 2026-11-20).
  // This format is used as an ID/key in the database.
  // ==========================================================================

  String _dateKey(
    DateTime date,
  ) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  // ==========================================================================
  // DISPLAY DATE
  // NOTE: Converts a date to "dd/MM/yyyy" for showing to the user.
  // ==========================================================================

  String _displayDate(
    DateTime date,
  ) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  // ==========================================================================
  // PARSE TIME
  //
  // Supports:
  //
  // 10.00AM
  // 10.00 AM
  // 10:00AM
  // 10:00 AM
  // 10AM
  // 2.00PM
  // 2:00 PM
  // 2PM
  //
  // NOTE: Converts a time text into "minutes since midnight".
  // Example: 2:00 PM -> 14*60 = 840. Easier to do math with numbers.
  // Returns null if the text is not a valid time.
  // ==========================================================================

  int? _parseTime(
    String value,
  ) {
    try {
      String text = value.trim().toUpperCase();

      // Remove all spaces.
      text = text.replaceAll(
        RegExp(r'\s+'),
        '',
      );

      // Convert "." to ":".
      text = text.replaceAll(
        '.',
        ':',
      );

      // Regex: hour, optional :minute, then AM or PM
      final match = RegExp(
        r'^(\d{1,2})(?::(\d{1,2}))?(AM|PM)$',
      ).firstMatch(text);

      if (match == null) {
        return null; // Format not recognized
      }

      int hour = int.parse(
        match.group(1)!,
      );

      // If minute is not written (like "10AM"), use 0
      final minute =
          match.group(2) == null ? 0 : int.parse(match.group(2)!);

      final period = match.group(3)!; // AM or PM

      // Validate hour (1-12) and minute (0-59)
      if (hour < 1 || hour > 12) {
        return null;
      }

      if (minute < 0 || minute > 59) {
        return null;
      }

      // Convert to 24-hour format
      if (period == 'AM') {
        if (hour == 12) {
          hour = 0; // 12 AM = midnight = 0
        }
      } else {
        if (hour != 12) {
          hour += 12; // 1 PM = 13, 2 PM = 14 ...
        }
      }

      return hour * 60 + minute; // Total minutes
    } catch (_) {
      return null;
    }
  }

  // ==========================================================================
  // FORMAT TIME
  // NOTE: Opposite of _parseTime. Converts minutes back to "h:mm AM/PM".
  // Example: 840 -> "2:00 PM"
  // ==========================================================================

  String _formatTime(
    int totalMinutes,
  ) {
    int hour = totalMinutes ~/ 60; // ~/ = integer division

    final minute = totalMinutes % 60;

    final period = hour >= 12 ? 'PM' : 'AM';

    // Convert 24-hour to 12-hour format
    if (hour == 0) {
      hour = 12;
    } else if (hour > 12) {
      hour -= 12;
    }

    return '$hour:'
        '${minute.toString().padLeft(2, '0')} '
        '$period';
  }

  // ==========================================================================
  // CREATE ONE HOUR SLOTS
  //
  // Example:
  //
  // 10.00AM - 2.00PM
  //
  // becomes:
  //
  // 10:00 AM - 11:00 AM
  // 11:00 AM - 12:00 PM
  // 12:00 PM - 1:00 PM
  // 1:00 PM - 2:00 PM
  //
  // NOTE: Reads the doctor's shift text, finds start and end time,
  // then splits it into 1-hour appointment slots.
  // ==========================================================================

  List<String> _createOneHourSlots(
    String shift,
  ) {
    try {
      String text = shift.trim();

      // Replace fancy dashes with a normal "-"
      text = text.replaceAll(
        '–',
        '-',
      );

      text = text.replaceAll(
        '—',
        '-',
      );

      // Convert "to" into "-".
      text = text.replaceAll(
        RegExp(
          r'\s+TO\s+',
          caseSensitive: false,
        ),
        '-',
      );

      // Find the two time values (start and end).
      final matches = RegExp(
        r'(\d{1,2}(?:[.:]\d{1,2})?\s*(?:AM|PM))',
        caseSensitive: false,
      ).allMatches(text);

      // Need at least 2 times (start and end)
      if (matches.length < 2) {
        debugPrint(
          'Could not parse shift: $shift',
        );

        return [];
      }

      final startText = matches.elementAt(0).group(1)!;

      final endText = matches.elementAt(1).group(1)!;

      final startMinutes = _parseTime(
        startText,
      );

      final endMinutes = _parseTime(
        endText,
      );

      if (startMinutes == null || endMinutes == null) {
        return [];
      }

      // End must be after start
      if (endMinutes <= startMinutes) {
        return [];
      }

      final slots = <String>[];

      // One-hour slots.
      // Loop continues while a full 60-minute slot fits before the end time.
      for (
        int current = startMinutes;
        current + 60 <= endMinutes;
        current += 60
      ) {
        final start = _formatTime(
          current,
        );

        final end = _formatTime(
          current + 60,
        );

        slots.add(
          '$start - $end',
        );
      }

      return slots;
    } catch (e) {
      debugPrint(
        'Slot creation error: $e',
      );

      return [];
    }
  }

  // ==========================================================================
  // LOAD AVAILABLE SLOTS
  //
  // We DO NOT query "appointments".
  //
  // We query appointment_slots.
  //
  // This allows a student to see whether a doctor/time is already occupied
  // without reading other students' private appointment documents.
  // ==========================================================================

  Future<void> _loadAvailableSlots() async {
    final doctor = selectedDoctor;

    if (doctor == null) {
      return; // No doctor selected yet
    }

    if (!mounted) return;

    // Reset old slot data before loading new
    setState(() {
      loadingSlots = true;

      selectedTimeSlot = null;

      timeSlots = [];

      bookedSlots = {};

      errorMessage = null;
    });

    try {
      // --------------------------------------------------------------
      // CREATE 1 HOUR SLOTS FROM SHIFT
      // --------------------------------------------------------------

      final generatedSlots = _createOneHourSlots(
        doctor.shift,
      );

      if (generatedSlots.isEmpty) {
        if (!mounted) return;

        setState(() {
          loadingSlots = false;

          errorMessage = 'Could not create time slots from shift:\n'
              '${doctor.shift}';
        });

        return;
      }

      // --------------------------------------------------------------
      // DATE
      // --------------------------------------------------------------

      final dateKey = _dateKey(
        selectedDate,
      );

      // --------------------------------------------------------------
      // READ SLOT LOCKS
      //
      // IMPORTANT:
      //
      // We only query doctorUid.
      //
      // We filter dateKey in Dart.
      //
      // This avoids requiring a Firestore composite index.
      // --------------------------------------------------------------

      final snapshot = await firestore
          .collection(
            'appointment_slots',
          )
          .where(
            'doctorUid',
            isEqualTo: doctor.id,
          )
          .get();

      final blocked = <String>{}; // Will hold the booked time slots

      // --------------------------------------------------------------
      // FIND BOOKED SLOTS
      // --------------------------------------------------------------

      for (final doc in snapshot.docs) {
        final data = doc.data();

        final slotDate = data['dateKey']?.toString();

        // Different date -> ignore.
        if (slotDate != dateKey) {
          continue;
        }

        final status =
            data['status']?.toString().toLowerCase().trim() ?? '';

        // Cancelled = available again.
        if (status == 'cancelled') {
          continue;
        }

        // These statuses block the slot.
        if (status == 'booked' ||
            status == 'confirmed' ||
            status == 'waiting' ||
            status == 'checked_in' ||
            status == 'checkedin') {
          final time = data['time']?.toString();

          if (time != null && time.isNotEmpty) {
            blocked.add(
              time,
            );
          }
        }
      }

      if (!mounted) return;

      setState(() {
        timeSlots = generatedSlots; // All possible slots

        bookedSlots = blocked; // Slots that are taken

        loadingSlots = false;
      });
    } catch (e) {
      debugPrint(
        'Error loading slots: $e',
      );

      if (!mounted) return;

      setState(() {
        loadingSlots = false;

        errorMessage = 'Could not load available slots.\n$e';
      });
    }
  }

  // ==========================================================================
  // SELECT DATE
  // NOTE: Opens Flutter's date picker. Student can choose from today up to
  // 30 days ahead. After choosing, slots are reloaded for the new date.
  // ==========================================================================

  Future<void> _selectDate() async {
    final today = DateTime.now();

    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: today,
      lastDate: today.add(
        const Duration(
          days: 30,
        ),
      ),
    );

    if (picked == null) {
      return; // User cancelled the picker
    }

    setState(() {
      // Keep only year-month-day (remove time part)
      selectedDate = DateTime(
        picked.year,
        picked.month,
        picked.day,
      );
    });

    await _loadAvailableSlots();
  }

  // ==========================================================================
  // NEXT
  // NOTE: Called when "Next" / "Confirm" button is pressed.
  // It validates the current step, then moves to the next step.
  // ==========================================================================

  Future<void> _nextStep() async {
    // ========================================================================
    // DOCTOR
    // ========================================================================

    if (currentStep == 0) {
      if (selectedDoctor == null) {
        _showMessage(
          'Please select a doctor.',
        );

        return;
      }

      setState(() {
        currentStep = 1;
      });

      await _loadAvailableSlots();

      return;
    }

    // ========================================================================
    // DATE + TIME
    // ========================================================================

    if (currentStep == 1) {
      if (selectedTimeSlot == null) {
        _showMessage(
          'Please select an available time slot.',
        );

        return;
      }

      // Safety check: slot may have been booked while student was choosing
      if (bookedSlots.contains(
        selectedTimeSlot,
      )) {
        _showMessage(
          'This slot is already booked.',
        );

        await _loadAvailableSlots();

        return;
      }

      setState(() {
        currentStep = 2;
      });

      return;
    }

    // ========================================================================
    // DETAILS
    // ========================================================================

    if (currentStep == 2) {
      // Reason is required, symptoms are optional
      if (reasonController.text.trim().isEmpty) {
        _showMessage(
          'Please enter the reason for your appointment.',
        );

        return;
      }

      setState(() {
        currentStep = 3;
      });

      return;
    }

    // ========================================================================
    // CONFIRM
    // ========================================================================

    if (currentStep == 3) {
      await _bookAppointment(); // Final step: save to database
    }
  }

  // ==========================================================================
  // BACK
  // NOTE: Goes one step back (not allowed on step 0).
  // ==========================================================================

  void _previousStep() {
    if (currentStep > 0) {
      setState(() {
        currentStep--;
      });
    }
  }

  // ==========================================================================
  // BOOK APPOINTMENT
  // NOTE: The most important function. It saves the appointment safely using
  // a Firestore TRANSACTION so two students cannot book the same slot.
  // ==========================================================================

  Future<void> _bookAppointment() async {
    final user = auth.currentUser; // Currently logged-in student

    if (user == null) {
      _showMessage(
        'Please login first.',
      );

      return;
    }

    final doctor = selectedDoctor;

    if (doctor == null) {
      _showMessage(
        'Please select a doctor.',
      );

      return;
    }

    final selectedSlot = selectedTimeSlot;

    if (selectedSlot == null) {
      _showMessage(
        'Please select a time slot.',
      );

      return;
    }

    if (reasonController.text.trim().isEmpty) {
      _showMessage(
        'Please enter the reason for your appointment.',
      );

      return;
    }

    if (!mounted) return;

    setState(() {
      booking = true; // Disable buttons, show spinner
      errorMessage = null;
    });

    try {
      // ======================================================================
      // STUDENT DATA
      // NOTE: Read student's profile to store name, department, etc.
      // inside the appointment.
      // ======================================================================

      final studentSnapshot =
          await firestore.collection('users').doc(user.uid).get();

      final studentData = studentSnapshot.data() ?? {};

      // ======================================================================
      // DATE
      // ======================================================================

      final dateKey = _dateKey(
        selectedDate,
      );

      // ======================================================================
      // CHECK SHIFT AGAIN
      // NOTE: Extra security check - the chosen slot must really belong to
      // the doctor's shift.
      // ======================================================================

      final validSlots = _createOneHourSlots(
        doctor.shift,
      );

      if (!validSlots.contains(
        selectedSlot,
      )) {
        throw Exception(
          'Selected time is outside the doctor shift.',
        );
      }

      // ======================================================================
      // SLOT ID
      // NOTE: A unique id for this doctor + date + time. Because the id is
      // fixed, a slot can have only ONE lock document (prevents double
      // booking). Special characters are replaced with "_".
      // ======================================================================

      final safeTime = selectedSlot
          .replaceAll(
            ':',
            '_',
          )
          .replaceAll(
            ' ',
            '_',
          )
          .replaceAll(
            '-',
            '_',
          );

      final slotId = '${doctor.id}_'
          '${dateKey}_'
          '$safeTime';

      final slotRef = firestore
          .collection(
            'appointment_slots',
          )
          .doc(
            slotId,
          );

      // ======================================================================
      // APPOINTMENT ID
      // NOTE: .doc() with no id = Firestore creates a new random id.
      // ======================================================================

      final appointmentRef = firestore
          .collection(
            'appointments',
          )
          .doc();

      // ======================================================================
      // TOKEN COUNTER
      // NOTE: One counter per doctor per day. It remembers the last token
      // number given so the next student gets last + 1.
      // ======================================================================

      final counterRef = firestore
          .collection(
            'appointment_counters',
          )
          .doc(
            '${doctor.id}_$dateKey',
          );

      // ======================================================================
      // TRANSACTION
      // NOTE: A transaction runs "all or nothing" and re-checks data if
      // another student changes it at the same time.
      // ======================================================================

      final token = await firestore.runTransaction<String>(
        (transaction) async {
          // --------------------------------------------------------------
          // READ SLOT
          // NOTE: Check if someone already booked this slot.
          // --------------------------------------------------------------

          final existingSlot = await transaction.get(
            slotRef,
          );

          if (existingSlot.exists) {
            final slotData = existingSlot.data();

            final status =
                slotData?['status']?.toString().toLowerCase().trim() ?? '';

            // Existing non-cancelled slot = occupied.
            if (status != 'cancelled') {
              throw Exception(
                'This slot was just booked by another student. '
                'Please choose another slot.',
              );
            }
          }

          // --------------------------------------------------------------
          // READ COUNTER
          // NOTE: Get the last token number used today for this doctor.
          // --------------------------------------------------------------

          final counterSnapshot = await transaction.get(
            counterRef,
          );

          int lastToken = 0; // If no counter yet, start from 0

          if (counterSnapshot.exists) {
            final counterData = counterSnapshot.data();

            final value = counterData?['lastToken'];

            if (value is int) {
              lastToken = value;
            } else if (value is num) {
              lastToken = value.toInt();
            }
          }

          final nextToken = lastToken + 1; // New student's token

          final tokenString = nextToken.toString();

          // --------------------------------------------------------------
          // SLOT LOCK
          // NOTE: Creates a small public document that marks this slot as
          // booked. Other students read THIS (not private appointments).
          // --------------------------------------------------------------

          transaction.set(
            slotRef,
            {
              'doctorUid': doctor.id,
              'doctorName': doctor.name,
              'studentUid': user.uid,
              'appointmentId': appointmentRef.id,
              'dateKey': dateKey,
              'time': selectedSlot,
              'status': 'booked',
              'createdAt': FieldValue.serverTimestamp(), // Server time
              'updatedAt': FieldValue.serverTimestamp(),
            },
          );

          // --------------------------------------------------------------
          // COUNTER
          // NOTE: Save the new last token number (merge keeps other fields).
          // --------------------------------------------------------------

          transaction.set(
            counterRef,
            {
              'doctorUid': doctor.id,
              'dateKey': dateKey,
              'lastToken': nextToken,
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(
              merge: true,
            ),
          );

          // --------------------------------------------------------------
          // APPOINTMENT DOCUMENT
          // NOTE: The full appointment record (student + doctor + time).
          // --------------------------------------------------------------

          transaction.set(
            appointmentRef,
            {
              // ============================================================
              // APPOINTMENT
              // ============================================================

              'appointmentId': appointmentRef.id,

              'status': 'booked',

              // ============================================================
              // STUDENT
              // NOTE: Student info copied from the profile, with fallbacks.
              // ============================================================

              'studentUid': user.uid,

              'studentId': _studentValue(
                studentData,
                [
                  'studentId',
                  'studentID',
                ],
                user.uid,
              ),

              'studentName': _studentValue(
                studentData,
                [
                  'fullName',
                  'name',
                  'displayName',
                ],
                user.displayName ?? '',
              ),

              'studentEmail': studentData['email'] ?? user.email ?? '',

              'studentDepartment':
                  studentData['department'] ?? studentData['program'] ?? '',

              'studentSession': studentData['session'] ?? '',

              'studentPhone':
                  studentData['phone'] ?? studentData['phoneNumber'] ?? '',

              'studentBloodGroup': studentData['bloodGroup'] ?? '',

              'studentHall':
                  studentData['hall'] ?? studentData['hallName'] ?? '',

              // ============================================================
              // DOCTOR
              // ============================================================

              'doctorUid': doctor.id,

              'doctorId': doctor.id,

              'doctorName': doctor.name,

              'doctorDepartment': doctor.department,

              'doctorDegrees': doctor.degrees,

              'doctorRoom': doctor.room,

              'doctorShift': doctor.shift,

              // ============================================================
              // DATE
              // ============================================================

              'date': _displayDate(
                selectedDate,
              ), // For display

              'dateKey': dateKey, // For searching/filtering

              'appointmentDate': Timestamp.fromDate(
                DateTime(
                  selectedDate.year,
                  selectedDate.month,
                  selectedDate.day,
                ),
              ), // Real date type, useful for sorting

              // ============================================================
              // TIME
              // ============================================================

              'time': selectedSlot,

              'timeKey': safeTime,

              // Start time in minutes (e.g. "10:00 AM - 11:00 AM" -> 600)
              'timeMinutes': _parseTime(
                selectedSlot.split(' - ').first,
              ),

              // ============================================================
              // PROBLEM
              // ============================================================

              'problem': reasonController.text.trim(),

              'reason': reasonController.text.trim(),

              'symptoms': symptomsController.text.trim(),

              // ============================================================
              // TOKEN
              // ============================================================

              'token': tokenString,

              'queueNumber': tokenString,

              // ============================================================
              // SLOT
              // NOTE: Link back to the slot lock document.
              // ============================================================

              'slotLockId': slotId,

              // ============================================================
              // SOURCE
              // ============================================================

              'bookingSource': 'student_app',

              // ============================================================
              // TIMESTAMP
              // ============================================================

              'createdAt': FieldValue.serverTimestamp(),

              'updatedAt': FieldValue.serverTimestamp(),
            },
          );

          return tokenString; // Transaction returns the token number
        },
      );

      // ======================================================================
      // RESULT
      // NOTE: Build the result object to send back to the previous page.
      // ======================================================================

      final result = AppointmentResult(
        appointmentId: appointmentRef.id,
        doctorId: doctor.id,
        doctorName: doctor.name,
        department: doctor.department,
        reason: reasonController.text.trim(),
        symptoms: symptomsController.text.trim(),
        date: _displayDate(
          selectedDate,
        ),
        time: selectedSlot,
        room: doctor.room,
        queueNumber: token,
      );

      // ======================================================================
      // SUCCESS
      // ======================================================================

      if (!mounted) return;

      setState(() {
        booking = false;
      });

      Navigator.pop(
        context,
        result,
      ); // Close this page and return the result
    } catch (e) {
      // Any error (including "slot just booked") ends up here
      debugPrint(
        'Booking error: $e',
      );

      if (!mounted) return;

      setState(() {
        booking = false;
      });

      _showMessage(
        e.toString().replaceFirst(
              'Exception: ',
              '',
            ), // Remove the technical "Exception: " prefix
      );
    }
  }

  // ==========================================================================
  // STUDENT VALUE
  // NOTE: Same idea as _getString, but for student data.
  // Returns first non-empty value from the given keys, else fallback.
  // ==========================================================================

  String _studentValue(
    Map<String, dynamic> data,
    List<String> keys,
    String fallback,
  ) {
    for (final key in keys) {
      final value = data[key];

      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString().trim();
      }
    }

    return fallback;
  }

  // ==========================================================================
  // MESSAGE
  // NOTE: Shows a small message (SnackBar) at the bottom of the screen.
  // ==========================================================================

  void _showMessage(
    String message,
  ) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ==========================================================================
  // BUILD
  // NOTE: Builds the main screen UI.
  // Logic: loading -> spinner, no doctors -> message, else -> step UI.
  // ==========================================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Book Appointment',
        ),
        centerTitle: true,
      ),
      body:

          // ================================================================
          // LOADING DOCTORS
          // ================================================================

          loadingDoctors
              ? const Center(
                  child: CircularProgressIndicator(),
                )

              // ================================================================
              // NO DOCTORS
              // ================================================================

              : doctors.isEmpty
                  ? _buildNoDoctors()

                  // ============================================================
                  // MAIN
                  // ============================================================

                  : Column(
                      children: [
                        _buildStepIndicator(), // 1-2-3-4 circles at top

                        // Red error box (only if there is an error)
                        if (errorMessage != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                            ),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(
                                  10,
                                ),
                                color: Colors.red.withOpacity(
                                  0.08,
                                ),
                              ),
                              child: Text(
                                errorMessage!,
                                style: const TextStyle(
                                  color: Colors.red,
                                ),
                              ),
                            ),
                          ),

                        // Current step content (scrollable)
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(20),
                            child: _buildCurrentStep(),
                          ),
                        ),

                        _buildBottomButtons(), // Back / Next buttons
                      ],
                    ),
    );
  }

  // ==========================================================================
  // NO DOCTORS
  // NOTE: Shown when no active doctor exists. Has a "Try Again" button.
  // ==========================================================================

  Widget _buildNoDoctors() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.medical_services_outlined,
              size: 65,
            ),
            const SizedBox(
              height: 20,
            ),
            const Text(
              'No doctor available',
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(
              height: 10,
            ),
            const Text(
              'No active doctor was found in the users collection.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(
              height: 20,
            ),
            ElevatedButton(
              onPressed: _loadDoctors, // Reload doctors
              child: const Text(
                'Try Again',
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================================
  // STEP INDICATOR
  // NOTE: Shows 4 numbered circles with labels. Labels of the current and
  // past steps are bold.
  // ==========================================================================

  Widget _buildStepIndicator() {
    const labels = [
      'Doctor',
      'Date & Time',
      'Details',
      'Confirm',
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        12,
        16,
        12,
        10,
      ),
      child: Row(
        children: List.generate(
          labels.length,
          (index) {
            final active = index <= currentStep; // Reached this step?

            return Expanded(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 16,
                    child: Text(
                      '${index + 1}',
                    ),
                  ),
                  const SizedBox(
                    height: 5,
                  ),
                  Text(
                    labels[index],
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight:
                          active ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ==========================================================================
  // CURRENT STEP
  // NOTE: Chooses which step screen to display based on currentStep.
  // ==========================================================================

  Widget _buildCurrentStep() {
    switch (currentStep) {
      case 0:
        return _buildDoctorStep();

      case 1:
        return _buildDateTimeStep();

      case 2:
        return _buildDetailsStep();

      case 3:
        return _buildConfirmationStep();

      default:
        return const SizedBox();
    }
  }

  // ==========================================================================
  // DOCTOR STEP
  // NOTE: Step 1 - shows a card for every doctor. Tapping a card selects the
  // doctor and loads that doctor's slots.
  // ==========================================================================

  Widget _buildDoctorStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Select Doctor',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(
          height: 8,
        ),
        const Text(
          'Select a doctor from the available doctors.',
        ),
        const SizedBox(
          height: 20,
        ),

        // One card per doctor
        ...doctors.map(
          (doctor) {
            final selected = selectedDoctor?.id == doctor.id;

            return Container(
              margin: const EdgeInsets.only(
                bottom: 12,
              ),
              // Border is thicker and colored if this doctor is selected
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(
                  12,
                ),
                border: Border.all(
                  color: selected
                      ? Theme.of(
                          context,
                        ).colorScheme.primary
                      : Colors.grey.withOpacity(
                          0.3,
                        ),
                  width: selected ? 2 : 1,
                ),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(
                  12,
                ),
                onTap: () async {
                  setState(() {
                    selectedDoctor = doctor;

                    selectedTimeSlot = null; // Reset time for new doctor
                  });

                  await _loadAvailableSlots();
                },
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      // Circle with the doctor's first letter
                      CircleAvatar(
                        radius: 28,
                        child: Text(
                          _doctorInitial(
                            doctor.name,
                          ),
                        ),
                      ),
                      const SizedBox(
                        width: 14,
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              doctor.name,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(
                              height: 5,
                            ),
                            Text(
                              doctor.department,
                            ),

                            // Show degrees only if available
                            if (doctor.degrees.isNotEmpty)
                              Text(
                                doctor.degrees,
                                style: const TextStyle(
                                  fontSize: 12,
                                ),
                              ),
                            const SizedBox(
                              height: 5,
                            ),
                            Text(
                              'Room: ${doctor.room}',
                              style: const TextStyle(
                                fontSize: 12,
                              ),
                            ),

                            // Show shift only if available
                            if (doctor.shift.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: 5,
                                ),
                                child: Text(
                                  'Shift: ${doctor.shift}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),

                      // Radio button on the right side
                      Radio<String>(
                        value: doctor.id,
                        groupValue: selectedDoctor?.id,
                        onChanged: (_) async {
                          setState(() {
                            selectedDoctor = doctor;
                          });

                          await _loadAvailableSlots();
                        },
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  // ==========================================================================
  // INITIAL
  // NOTE: Returns the first letter of the doctor's name (after removing
  // "Dr."), used inside the avatar circle.
  // ==========================================================================

  String _doctorInitial(
    String name,
  ) {
    String clean = name
        .replaceAll(
          'Dr.',
          '',
        )
        .trim();

    if (clean.isEmpty) {
      return 'D';
    }

    return clean[0].toUpperCase();
  }

  // ==========================================================================
  // DATE + TIME
  // NOTE: Step 2 - student picks a date and then a time slot.
  // ==========================================================================

  Widget _buildDateTimeStep() {
    final doctor = selectedDoctor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Select Date & Time',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(
          height: 20,
        ),

        // ====================================================================
        // DATE
        // NOTE: Tap this card to open the date picker.
        // ====================================================================

        Card(
          child: ListTile(
            leading: const Icon(
              Icons.calendar_month,
            ),
            title: const Text(
              'Appointment Date',
            ),
            subtitle: Text(
              _displayDate(
                selectedDate,
              ),
            ),
            trailing: const Icon(
              Icons.arrow_forward_ios,
              size: 16,
            ),
            onTap: _selectDate,
          ),
        ),
        const SizedBox(
          height: 14,
        ),

        // ====================================================================
        // SHIFT
        // NOTE: Shows the doctor's working hours.
        // ====================================================================

        if (doctor != null && doctor.shift.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(
                14,
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.access_time,
                  ),
                  const SizedBox(
                    width: 10,
                  ),
                  Expanded(
                    child: Text(
                      'Doctor Shift: ${doctor.shift}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(
          height: 15,
        ),

        // ====================================================================
        // LOADING
        // ====================================================================

        if (loadingSlots)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(30),
              child: CircularProgressIndicator(),
            ),
          )

        // ====================================================================
        // NO SLOTS
        // ====================================================================

        else if (timeSlots.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(
                16,
              ),
              child: Text(
                doctor == null || doctor.shift.isEmpty
                    ? 'No shift is configured for this doctor.'
                    : errorMessage ??
                        'No time slots available for this date.',
              ),
            ),
          )

        // ====================================================================
        // SLOTS
        // ====================================================================

        else
          _buildTimeSlots(),
      ],
    );
  }

  // ==========================================================================
  // TIME SLOTS
  // NOTE: Shows every 1-hour slot.
  // Red = already booked (cannot tap), highlighted = selected,
  // white = available.
  // ==========================================================================

  Widget _buildTimeSlots() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Select Time Slot',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(
          height: 5,
        ),
        const Text(
          'Each appointment is 1 hour.',
        ),
        const SizedBox(
          height: 15,
        ),
        ...timeSlots.map(
          (slot) {
            final isBooked = bookedSlots.contains(
              slot,
            );

            final isSelected = selectedTimeSlot == slot;

            return GestureDetector(
              // onTap = null means the slot is not clickable (booked)
              onTap: isBooked
                  ? null
                  : () {
                      setState(() {
                        selectedTimeSlot = slot;
                      });
                    },
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.only(
                  bottom: 12,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 15,
                ),
                decoration: BoxDecoration(
                  color:

                      // BOOKED = RED
                      isBooked
                          ? Colors.red.withOpacity(
                              0.10,
                            )

                          // SELECTED
                          : isSelected
                              ? Theme.of(
                                  context,
                                ).colorScheme.primary.withOpacity(
                                    0.10,
                                  )

                              // AVAILABLE
                              : Colors.white,
                  borderRadius: BorderRadius.circular(
                    12,
                  ),
                  border: Border.all(
                    color: isBooked
                        ? Colors.red
                        : isSelected
                            ? Theme.of(
                                context,
                              ).colorScheme.primary
                            : Colors.grey.withOpacity(
                                0.4,
                              ),
                    width: isBooked || isSelected ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isBooked ? Icons.event_busy : Icons.access_time,
                      color: isBooked
                          ? Colors.red
                          : Theme.of(
                              context,
                            ).colorScheme.primary,
                    ),
                    const SizedBox(
                      width: 14,
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            slot,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: isBooked ? Colors.red : null,
                            ),
                          ),
                          const SizedBox(
                            height: 4,
                          ),
                          Text(
                            isBooked ? 'Already booked' : 'Available',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: isBooked ? Colors.red : Colors.green,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Lock icon if booked, otherwise a radio button
                    if (isBooked)
                      const Icon(
                        Icons.lock_outline,
                        color: Colors.red,
                      )
                    else
                      Radio<String>(
                        value: slot,
                        groupValue: selectedTimeSlot,
                        onChanged: (_) {
                          setState(() {
                            selectedTimeSlot = slot;
                          });
                        },
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  // ==========================================================================
  // DETAILS
  // NOTE: Step 3 - student writes the reason (required) and symptoms
  // (optional).
  // ==========================================================================

  Widget _buildDetailsStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Appointment Details',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(
          height: 20,
        ),
        const Text(
          'Reason for Visit',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(
          height: 10,
        ),
        TextField(
          controller: reasonController,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Reason for appointment',
            hintText: 'Describe your problem...',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(
          height: 20,
        ),
        const Text(
          'Symptoms',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(
          height: 10,
        ),
        TextField(
          controller: symptomsController,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'Symptoms',
            hintText: 'Describe your symptoms...',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  // ==========================================================================
  // CONFIRMATION
  // NOTE: Step 4 - shows a summary of everything so the student can review
  // before pressing "Confirm Appointment".
  // ==========================================================================

  Widget _buildConfirmationStep() {
    final doctor = selectedDoctor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Confirm Appointment',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(
          height: 20,
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(
              18,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _summaryRow(
                  'Doctor',
                  doctor?.name ?? '',
                ),
                _summaryRow(
                  'Department',
                  doctor?.department ?? '',
                ),
                _summaryRow(
                  'Room',
                  doctor?.room ?? '',
                ),
                _summaryRow(
                  'Shift',
                  doctor?.shift ?? '',
                ),
                _summaryRow(
                  'Date',
                  _displayDate(
                    selectedDate,
                  ),
                ),
                _summaryRow(
                  'Time',
                  selectedTimeSlot ?? '',
                ),
                _summaryRow(
                  'Reason',
                  reasonController.text.trim(),
                ),
                _summaryRow(
                  'Symptoms',
                  symptomsController.text.trim().isEmpty
                      ? 'Not provided'
                      : symptomsController.text.trim(),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(
          height: 15,
        ),
        Card(
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'A queue token will be generated automatically after confirmation.',
            ),
          ),
        ),
      ],
    );
  }

  // ==========================================================================
  // SUMMARY ROW
  // NOTE: One line in the summary: bold title on the left, value on the right.
  // ==========================================================================

  Widget _summaryRow(
    String title,
    String value,
  ) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: 14,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // BOTTOM BUTTONS
  // NOTE: "Back" button (from step 1 onward) and "Next" / "Confirm" button.
  // While booking is in progress, buttons are disabled and a spinner shows.
  // ==========================================================================

  Widget _buildBottomButtons() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(
          16,
        ),
        child: Row(
          children: [
            // Back button hidden on the first step
            if (currentStep > 0)
              Expanded(
                child: OutlinedButton(
                  onPressed: booking ? null : _previousStep,
                  child: const Text(
                    'Back',
                  ),
                ),
              ),

            if (currentStep > 0)
              const SizedBox(
                width: 12,
              ),

            Expanded(
              child: ElevatedButton(
                onPressed: booking ? null : _nextStep,
                child: booking
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        currentStep == 3 ? 'Confirm Appointment' : 'Next',
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
