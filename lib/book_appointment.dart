import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';


// ============================================================================
// APPOINTMENT RESULT
// ============================================================================

class AppointmentResult {
  final String appointmentId;
  final String doctorId;
  final String doctorName;
  final String department;
  final String reason;
  final String symptoms;
  final String date;
  final String time;
  final String room;
  final String queueNumber;

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
// ============================================================================

class BookingDoctor {
  final String id;
  final String name;
  final String department;
  final String degrees;
  final String room;
  final String shift;
  final bool isActive;

  const BookingDoctor({
    required this.id,
    required this.name,
    required this.department,
    required this.degrees,
    required this.room,
    required this.shift,
    required this.isActive,
  });

  factory BookingDoctor.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};

    return BookingDoctor(
      id: doc.id,

      name: _getString(
        data,
        [
          'fullName',
          'name',
          'doctorName',
          'displayName',
        ],
        'Doctor',
      ),

      department: _getString(
        data,
        [
          'specialization',
          'speciality',
          'specialty',
          'department',
        ],
        'General Medicine',
      ),

      degrees: _getString(
        data,
        [
          'degrees',
          'degree',
          'qualification',
          'qualifications',
        ],
        '',
      ),

      room: _getString(
        data,
        [
          'chamber',
          'room',
          'roomNumber',
          'chamberNumber',
        ],
        'Not assigned',
      ),

      shift: _getString(
        data,
        [
          'shift',
          'workingShift',
          'dutyShift',
        ],
        '',
      ),

      isActive: _getActiveStatus(data),
    );
  }
}


// ============================================================================
// HELPER - GET STRING
// ============================================================================

String _getString(
  Map<String, dynamic> data,
  List<String> keys,
  String fallback,
) {
  for (final key in keys) {
    final value = data[key];

    if (value != null &&
        value.toString().trim().isNotEmpty) {
      return value.toString().trim();
    }
  }

  return fallback;
}


// ============================================================================
// HELPER - ACTIVE STATUS
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

  if (data['status'] != null) {
    final status =
        data['status'].toString().toLowerCase().trim();

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
// ============================================================================

class BookAppointmentPage extends StatefulWidget {
  final BookingDoctor? initialDoctor;

  const BookAppointmentPage({
    super.key,
    this.initialDoctor,
  });

  @override
  State<BookAppointmentPage> createState() =>
      _BookAppointmentPageState();
}


// ============================================================================
// STATE
// ============================================================================

class _BookAppointmentPageState
    extends State<BookAppointmentPage> {

  final FirebaseFirestore firestore =
      FirebaseFirestore.instance;

  final FirebaseAuth auth =
      FirebaseAuth.instance;


  // --------------------------------------------------------------------------
  // STEP
  // --------------------------------------------------------------------------

  int currentStep = 0;


  // --------------------------------------------------------------------------
  // DOCTORS
  // --------------------------------------------------------------------------

  List<BookingDoctor> doctors = [];

  BookingDoctor? selectedDoctor;


  // --------------------------------------------------------------------------
  // DATE
  // --------------------------------------------------------------------------

  DateTime selectedDate =
      DateTime.now().add(
    const Duration(days: 1),
  );


  // --------------------------------------------------------------------------
  // TIME
  // --------------------------------------------------------------------------

  List<String> timeSlots = [];

  Set<String> bookedSlots = {};

  String? selectedTimeSlot;


  // --------------------------------------------------------------------------
  // LOADING
  // --------------------------------------------------------------------------

  bool loadingDoctors = true;

  bool loadingSlots = false;

  bool booking = false;


  String? errorMessage;


  // --------------------------------------------------------------------------
  // TEXT FIELDS
  // --------------------------------------------------------------------------

  final TextEditingController reasonController =
      TextEditingController();

  final TextEditingController symptomsController =
      TextEditingController();


  // ==========================================================================
  // INIT
  // ==========================================================================

  @override
  void initState() {
    super.initState();

    _loadDoctors();
  }


  // ==========================================================================
  // DISPOSE
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

    if (!mounted) return;

    setState(() {
      loadingDoctors = true;
      errorMessage = null;
    });

    try {

      final snapshot = await firestore
          .collection('users')
          .where(
            'role',
            isEqualTo: 'doctor',
          )
          .get();


      final loadedDoctors = snapshot.docs
          .map(
            (doc) =>
                BookingDoctor.fromFirestore(doc),
          )
          .where(
            (doctor) => doctor.isActive,
          )
          .toList();


      // Sort doctors by name.
      loadedDoctors.sort(
        (a, b) =>
            a.name.toLowerCase().compareTo(
                  b.name.toLowerCase(),
                ),
      );


      if (!mounted) return;

      setState(() {
        doctors = loadedDoctors;
        loadingDoctors = false;
      });


      // If a doctor was passed from another page,
      // automatically select that doctor.
      if (widget.initialDoctor != null) {

        final matchingDoctors =
            loadedDoctors.where(
          (doctor) =>
              doctor.id ==
              widget.initialDoctor!.id,
        );


        if (matchingDoctors.isNotEmpty) {

          selectedDoctor =
              matchingDoctors.first;

          await _loadAvailableSlots();
        }
      }

    } catch (e) {

      debugPrint(
        'Error loading doctors: $e',
      );

      if (!mounted) return;

      setState(() {
        loadingDoctors = false;

        errorMessage =
            'Could not load doctors.\n$e';
      });
    }
  }


  // ==========================================================================
  // DATE KEY
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
  // ==========================================================================

  int? _parseTime(
    String value,
  ) {
    try {

      String text =
          value.trim().toUpperCase();


      // Remove all spaces.
      text =
          text.replaceAll(
        RegExp(r'\s+'),
        '',
      );


      // Convert "." to ":".
      text =
          text.replaceAll(
        '.',
        ':',
      );


      final match =
          RegExp(
        r'^(\d{1,2})(?::(\d{1,2}))?(AM|PM)$',
      ).firstMatch(text);


      if (match == null) {
        return null;
      }


      int hour =
          int.parse(
        match.group(1)!,
      );


      final minute =
          match.group(2) == null
              ? 0
              : int.parse(
                  match.group(2)!,
                );


      final period =
          match.group(3)!;


      if (hour < 1 ||
          hour > 12) {
        return null;
      }


      if (minute < 0 ||
          minute > 59) {
        return null;
      }


      if (period == 'AM') {

        if (hour == 12) {
          hour = 0;
        }

      } else {

        if (hour != 12) {
          hour += 12;
        }
      }


      return hour * 60 + minute;

    } catch (_) {

      return null;
    }
  }


  // ==========================================================================
  // FORMAT TIME
  // ==========================================================================

  String _formatTime(
    int totalMinutes,
  ) {

    int hour =
        totalMinutes ~/ 60;

    final minute =
        totalMinutes % 60;


    final period =
        hour >= 12
            ? 'PM'
            : 'AM';


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
  // ==========================================================================

  List<String> _createOneHourSlots(
    String shift,
  ) {

    try {

      String text =
          shift.trim();


      text =
          text.replaceAll(
        '–',
        '-',
      );


      text =
          text.replaceAll(
        '—',
        '-',
      );


      // Convert "to" into "-".
      text =
          text.replaceAll(
        RegExp(
          r'\s+TO\s+',
          caseSensitive: false,
        ),
        '-',
      );


      // Find the two time values.
      final matches =
          RegExp(
        r'(\d{1,2}(?:[.:]\d{1,2})?\s*(?:AM|PM))',
        caseSensitive: false,
      ).allMatches(text);


      if (matches.length < 2) {

        debugPrint(
          'Could not parse shift: $shift',
        );

        return [];
      }


      final startText =
          matches.elementAt(0).group(1)!;


      final endText =
          matches.elementAt(1).group(1)!;


      final startMinutes =
          _parseTime(
        startText,
      );


      final endMinutes =
          _parseTime(
        endText,
      );


      if (startMinutes == null ||
          endMinutes == null) {

        return [];
      }


      if (endMinutes <=
          startMinutes) {

        return [];
      }


      final slots =
          <String>[];


      // One-hour slots.
      for (
        int current =
            startMinutes;

        current + 60 <=
            endMinutes;

        current += 60
      ) {

        final start =
            _formatTime(
          current,
        );


        final end =
            _formatTime(
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

    final doctor =
        selectedDoctor;


    if (doctor == null) {
      return;
    }


    if (!mounted) return;


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

      final generatedSlots =
          _createOneHourSlots(
        doctor.shift,
      );


      if (generatedSlots.isEmpty) {

        if (!mounted) return;

        setState(() {

          loadingSlots = false;

          errorMessage =
              'Could not create time slots from shift:\n'
              '${doctor.shift}';
        });

        return;
      }


      // --------------------------------------------------------------
      // DATE
      // --------------------------------------------------------------

      final dateKey =
          _dateKey(
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

      final snapshot =
          await firestore
              .collection(
                'appointment_slots',
              )
              .where(
                'doctorUid',
                isEqualTo: doctor.id,
              )
              .get();


      final blocked =
          <String>{};


      // --------------------------------------------------------------
      // FIND BOOKED SLOTS
      // --------------------------------------------------------------

      for (final doc
          in snapshot.docs) {

        final data =
            doc.data();


        final slotDate =
            data['dateKey']
                ?.toString();


        // Different date -> ignore.
        if (slotDate != dateKey) {
          continue;
        }


        final status =
            data['status']
                    ?.toString()
                    .toLowerCase()
                    .trim() ??
                '';


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

          final time =
              data['time']
                  ?.toString();


          if (time != null &&
              time.isNotEmpty) {

            blocked.add(
              time,
            );
          }
        }
      }


      if (!mounted) return;


      setState(() {

        timeSlots =
            generatedSlots;

        bookedSlots =
            blocked;

        loadingSlots =
            false;
      });


    } catch (e) {

      debugPrint(
        'Error loading slots: $e',
      );


      if (!mounted) return;


      setState(() {

        loadingSlots = false;

        errorMessage =
            'Could not load available slots.\n$e';
      });
    }
  }


  // ==========================================================================
  // SELECT DATE
  // ==========================================================================

  Future<void> _selectDate() async {

    final today =
        DateTime.now();


    final picked =
        await showDatePicker(

      context: context,

      initialDate:
          selectedDate,

      firstDate:
          today,

      lastDate:
          today.add(
        const Duration(
          days: 30,
        ),
      ),
    );


    if (picked == null) {
      return;
    }


    setState(() {

      selectedDate =
          DateTime(
        picked.year,
        picked.month,
        picked.day,
      );
    });


    await _loadAvailableSlots();
  }


  // ==========================================================================
  // NEXT
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

      if (reasonController.text
          .trim()
          .isEmpty) {

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

      await _bookAppointment();
    }
  }


  // ==========================================================================
  // BACK
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
  // ==========================================================================

  Future<void> _bookAppointment() async {

    final user =
        auth.currentUser;


    if (user == null) {

      _showMessage(
        'Please login first.',
      );

      return;
    }


    final doctor =
        selectedDoctor;


    if (doctor == null) {

      _showMessage(
        'Please select a doctor.',
      );

      return;
    }


    final selectedSlot =
        selectedTimeSlot;


    if (selectedSlot == null) {

      _showMessage(
        'Please select a time slot.',
      );

      return;
    }


    if (reasonController.text
        .trim()
        .isEmpty) {

      _showMessage(
        'Please enter the reason for your appointment.',
      );

      return;
    }


    if (!mounted) return;


    setState(() {
      booking = true;
      errorMessage = null;
    });


    try {

      // ======================================================================
      // STUDENT DATA
      // ======================================================================

      final studentSnapshot =
          await firestore
              .collection('users')
              .doc(user.uid)
              .get();


      final studentData =
          studentSnapshot.data() ??
              {};


      // ======================================================================
      // DATE
      // ======================================================================

      final dateKey =
          _dateKey(
        selectedDate,
      );


      // ======================================================================
      // CHECK SHIFT AGAIN
      // ======================================================================

      final validSlots =
          _createOneHourSlots(
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
      // ======================================================================

      final safeTime =
          selectedSlot
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


      final slotId =
          '${doctor.id}_'
          '${dateKey}_'
          '$safeTime';


      final slotRef =
          firestore
              .collection(
                'appointment_slots',
              )
              .doc(
                slotId,
              );


      // ======================================================================
      // APPOINTMENT ID
      // ======================================================================

      final appointmentRef =
          firestore
              .collection(
                'appointments',
              )
              .doc();


      // ======================================================================
      // TOKEN COUNTER
      // ======================================================================

      final counterRef =
          firestore
              .collection(
                'appointment_counters',
              )
              .doc(
                '${doctor.id}_$dateKey',
              );


      // ======================================================================
      // TRANSACTION
      // ======================================================================

      final token =
          await firestore.runTransaction<String>(
        (transaction) async {

          // --------------------------------------------------------------
          // READ SLOT
          // --------------------------------------------------------------

          final existingSlot =
              await transaction.get(
            slotRef,
          );


          if (existingSlot.exists) {

            final slotData =
                existingSlot.data();


            final status =
                slotData?['status']
                        ?.toString()
                        .toLowerCase()
                        .trim() ??
                    '';


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
          // --------------------------------------------------------------

          final counterSnapshot =
              await transaction.get(
            counterRef,
          );


          int lastToken = 0;


          if (counterSnapshot.exists) {

            final counterData =
                counterSnapshot.data();


            final value =
                counterData?['lastToken'];


            if (value is int) {

              lastToken = value;

            } else if (value is num) {

              lastToken =
                  value.toInt();
            }
          }


          final nextToken =
              lastToken + 1;


          final tokenString =
              nextToken.toString();


          // --------------------------------------------------------------
          // SLOT LOCK
          // --------------------------------------------------------------

          transaction.set(
            slotRef,
            {
              'doctorUid':
                  doctor.id,

              'doctorName':
                  doctor.name,

              'studentUid':
                  user.uid,

              'appointmentId':
                  appointmentRef.id,

              'dateKey':
                  dateKey,

              'time':
                  selectedSlot,

              'status':
                  'booked',

              'createdAt':
                  FieldValue.serverTimestamp(),

              'updatedAt':
                  FieldValue.serverTimestamp(),
            },
          );


          // --------------------------------------------------------------
          // COUNTER
          // --------------------------------------------------------------

          transaction.set(
            counterRef,
            {
              'doctorUid':
                  doctor.id,

              'dateKey':
                  dateKey,

              'lastToken':
                  nextToken,

              'updatedAt':
                  FieldValue.serverTimestamp(),
            },
            SetOptions(
              merge: true,
            ),
          );


          // --------------------------------------------------------------
          // APPOINTMENT DOCUMENT
          // --------------------------------------------------------------

          transaction.set(
            appointmentRef,
            {

              // ============================================================
              // APPOINTMENT
              // ============================================================

              'appointmentId':
                  appointmentRef.id,

              'status':
                  'booked',


              // ============================================================
              // STUDENT
              // ============================================================

              'studentUid':
                  user.uid,

              'studentId':
                  _studentValue(
                studentData,
                [
                  'studentId',
                  'studentID',
                ],
                user.uid,
              ),

              'studentName':
                  _studentValue(
                studentData,
                [
                  'fullName',
                  'name',
                  'displayName',
                ],
                user.displayName ??
                    '',
              ),

              'studentEmail':
                  studentData['email'] ??
                      user.email ??
                      '',

              'studentDepartment':
                  studentData[
                          'department'] ??
                      studentData[
                          'program'] ??
                      '',

              'studentSession':
                  studentData[
                          'session'] ??
                      '',

              'studentPhone':
                  studentData[
                          'phone'] ??
                      studentData[
                          'phoneNumber'] ??
                      '',

              'studentBloodGroup':
                  studentData[
                          'bloodGroup'] ??
                      '',

              'studentHall':
                  studentData[
                          'hall'] ??
                      studentData[
                          'hallName'] ??
                      '',


              // ============================================================
              // DOCTOR
              // ============================================================

              'doctorUid':
                  doctor.id,

              'doctorId':
                  doctor.id,

              'doctorName':
                  doctor.name,

              'doctorDepartment':
                  doctor.department,

              'doctorDegrees':
                  doctor.degrees,

              'doctorRoom':
                  doctor.room,

              'doctorShift':
                  doctor.shift,


              // ============================================================
              // DATE
              // ============================================================

              'date':
                  _displayDate(
                selectedDate,
              ),

              'dateKey':
                  dateKey,

              'appointmentDate':
                  Timestamp.fromDate(
                DateTime(
                  selectedDate.year,
                  selectedDate.month,
                  selectedDate.day,
                ),
              ),


              // ============================================================
              // TIME
              // ============================================================

              'time':
                  selectedSlot,

              'timeKey':
                  safeTime,

              'timeMinutes':
                  _parseTime(
                    selectedSlot
                        .split(' - ')
                        .first,
                  ),


              // ============================================================
              // PROBLEM
              // ============================================================

              'problem':
                  reasonController.text
                      .trim(),

              'reason':
                  reasonController.text
                      .trim(),

              'symptoms':
                  symptomsController.text
                      .trim(),


              // ============================================================
              // TOKEN
              // ============================================================

              'token':
                  tokenString,

              'queueNumber':
                  tokenString,


              // ============================================================
              // SLOT
              // ============================================================

              'slotLockId':
                  slotId,


              // ============================================================
              // SOURCE
              // ============================================================

              'bookingSource':
                  'student_app',


              // ============================================================
              // TIMESTAMP
              // ============================================================

              'createdAt':
                  FieldValue.serverTimestamp(),

              'updatedAt':
                  FieldValue.serverTimestamp(),
            },
          );


          return tokenString;
        },
      );


      // ======================================================================
      // RESULT
      // ======================================================================

      final result =
          AppointmentResult(

        appointmentId:
            appointmentRef.id,

        doctorId:
            doctor.id,

        doctorName:
            doctor.name,

        department:
            doctor.department,

        reason:
            reasonController.text
                .trim(),

        symptoms:
            symptomsController.text
                .trim(),

        date:
            _displayDate(
          selectedDate,
        ),

        time:
            selectedSlot,

        room:
            doctor.room,

        queueNumber:
            token,
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
      );


    } catch (e) {

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
        ),
      );
    }
  }


  // ==========================================================================
  // STUDENT VALUE
  // ==========================================================================

  String _studentValue(
    Map<String, dynamic> data,
    List<String> keys,
    String fallback,
  ) {

    for (final key in keys) {

      final value =
          data[key];


      if (value != null &&
          value.toString()
              .trim()
              .isNotEmpty) {

        return value
            .toString()
            .trim();
      }
    }


    return fallback;
  }


  // ==========================================================================
  // MESSAGE
  // ==========================================================================

  void _showMessage(
    String message,
  ) {

    if (!mounted) return;


    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content:
            Text(message),

        behavior:
            SnackBarBehavior.floating,
      ),
    );
  }


  // ==========================================================================
  // BUILD
  // ==========================================================================

  @override
  Widget build(
    BuildContext context,
  ) {

    return Scaffold(

      appBar: AppBar(
        title:
            const Text(
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
                  child:
                      CircularProgressIndicator(),
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

                        _buildStepIndicator(),


                        if (errorMessage != null)
                          Padding(
                            padding:
                                const EdgeInsets
                                    .symmetric(
                              horizontal: 16,
                            ),

                            child:
                                Container(
                              width:
                                  double.infinity,

                              padding:
                                  const EdgeInsets
                                      .all(12),

                              decoration:
                                  BoxDecoration(
                                borderRadius:
                                    BorderRadius
                                        .circular(
                                  10,
                                ),

                                color: Colors.red
                                    .withOpacity(
                                  0.08,
                                ),
                              ),

                              child:
                                  Text(
                                errorMessage!,

                                style:
                                    const TextStyle(
                                  color:
                                      Colors.red,
                                ),
                              ),
                            ),
                          ),


                        Expanded(
                          child:
                              SingleChildScrollView(
                            padding:
                                const EdgeInsets
                                    .all(20),

                            child:
                                _buildCurrentStep(),
                          ),
                        ),


                        _buildBottomButtons(),
                      ],
                    ),
    );
  }


  // ==========================================================================
  // NO DOCTORS
  // ==========================================================================

  Widget _buildNoDoctors() {

    return Center(

      child:
          Padding(
        padding:
            const EdgeInsets.all(24),

        child:
            Column(
          mainAxisAlignment:
              MainAxisAlignment.center,

          children: [

            const Icon(
              Icons
                  .medical_services_outlined,

              size: 65,
            ),

            const SizedBox(
              height: 20,
            ),

            const Text(
              'No doctor available',

              style: TextStyle(
                fontSize: 21,
                fontWeight:
                    FontWeight.bold,
              ),
            ),

            const SizedBox(
              height: 10,
            ),

            const Text(
              'No active doctor was found in the users collection.',

              textAlign:
                  TextAlign.center,
            ),

            const SizedBox(
              height: 20,
            ),

            ElevatedButton(
              onPressed:
                  _loadDoctors,

              child:
                  const Text(
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
  // ==========================================================================

  Widget _buildStepIndicator() {

    const labels = [
      'Doctor',
      'Date & Time',
      'Details',
      'Confirm',
    ];


    return Padding(
      padding:
          const EdgeInsets
              .fromLTRB(
        12,
        16,
        12,
        10,
      ),

      child:
          Row(
        children:
            List.generate(
          labels.length,
          (index) {

            final active =
                index <= currentStep;


            return Expanded(

              child:
                  Column(
                children: [

                  CircleAvatar(
                    radius: 16,

                    child:
                        Text(
                      '${index + 1}',
                    ),
                  ),

                  const SizedBox(
                    height: 5,
                  ),

                  Text(
                    labels[index],

                    style:
                        TextStyle(
                      fontSize: 11,

                      fontWeight:
                          active
                              ? FontWeight.bold
                              : FontWeight.normal,
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
  // ==========================================================================

  Widget _buildDoctorStep() {

    return Column(

      crossAxisAlignment:
          CrossAxisAlignment.start,

      children: [

        const Text(
          'Select Doctor',

          style: TextStyle(
            fontSize: 24,
            fontWeight:
                FontWeight.bold,
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


        ...doctors.map(
          (doctor) {

            final selected =
                selectedDoctor?.id ==
                    doctor.id;


            return Container(

              margin:
                  const EdgeInsets.only(
                bottom: 12,
              ),

              decoration:
                  BoxDecoration(
                borderRadius:
                    BorderRadius.circular(
                  12,
                ),

                border:
                    Border.all(
                  color:
                      selected
                          ? Theme.of(
                              context,
                            )
                              .colorScheme
                              .primary
                          : Colors.grey
                              .withOpacity(
                              0.3,
                            ),

                  width:
                      selected ? 2 : 1,
                ),
              ),


              child:
                  InkWell(

                borderRadius:
                    BorderRadius.circular(
                  12,
                ),


                onTap: () async {

                  setState(() {

                    selectedDoctor =
                        doctor;

                    selectedTimeSlot =
                        null;
                  });


                  await _loadAvailableSlots();
                },


                child:
                    Padding(
                  padding:
                      const EdgeInsets
                          .all(16),

                  child:
                      Row(
                    children: [

                      CircleAvatar(
                        radius: 28,

                        child:
                            Text(
                          _doctorInitial(
                            doctor.name,
                          ),
                        ),
                      ),


                      const SizedBox(
                        width: 14,
                      ),


                      Expanded(
                        child:
                            Column(
                          crossAxisAlignment:
                              CrossAxisAlignment
                                  .start,

                          children: [

                            Text(
                              doctor.name,

                              style:
                                  const TextStyle(
                                fontSize: 16,
                                fontWeight:
                                    FontWeight.bold,
                              ),
                            ),

                            const SizedBox(
                              height: 5,
                            ),

                            Text(
                              doctor.department,
                            ),


                            if (doctor.degrees
                                .isNotEmpty)
                              Text(
                                doctor.degrees,

                                style:
                                    const TextStyle(
                                  fontSize: 12,
                                ),
                              ),


                            const SizedBox(
                              height: 5,
                            ),


                            Text(
                              'Room: ${doctor.room}',

                              style:
                                  const TextStyle(
                                fontSize: 12,
                              ),
                            ),


                            if (doctor.shift
                                .isNotEmpty)
                              Padding(
                                padding:
                                    const EdgeInsets
                                        .only(
                                  top: 5,
                                ),

                                child:
                                    Text(
                                  'Shift: ${doctor.shift}',

                                  style:
                                      const TextStyle(
                                    fontSize: 12,
                                    fontWeight:
                                        FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),


                      Radio<String>(
                        value:
                            doctor.id,

                        groupValue:
                            selectedDoctor?.id,

                        onChanged:
                            (_) async {

                          setState(() {

                            selectedDoctor =
                                doctor;
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
  // ==========================================================================

  String _doctorInitial(
    String name,
  ) {

    String clean =
        name
            .replaceAll(
              'Dr.',
              '',
            )
            .trim();


    if (clean.isEmpty) {
      return 'D';
    }


    return clean[0]
        .toUpperCase();
  }


  // ==========================================================================
  // DATE + TIME
  // ==========================================================================

  Widget _buildDateTimeStep() {

    final doctor =
        selectedDoctor;


    return Column(

      crossAxisAlignment:
          CrossAxisAlignment.start,

      children: [

        const Text(
          'Select Date & Time',

          style: TextStyle(
            fontSize: 24,
            fontWeight:
                FontWeight.bold,
          ),
        ),


        const SizedBox(
          height: 20,
        ),


        // ====================================================================
        // DATE
        // ====================================================================

        Card(
          child:
              ListTile(

            leading:
                const Icon(
              Icons.calendar_month,
            ),

            title:
                const Text(
              'Appointment Date',
            ),

            subtitle:
                Text(
              _displayDate(
                selectedDate,
              ),
            ),

            trailing:
                const Icon(
              Icons.arrow_forward_ios,
              size: 16,
            ),

            onTap:
                _selectDate,
          ),
        ),


        const SizedBox(
          height: 14,
        ),


        // ====================================================================
        // SHIFT
        // ====================================================================

        if (doctor != null &&
            doctor.shift.isNotEmpty)

          Card(
            child:
                Padding(
              padding:
                  const EdgeInsets.all(
                14,
              ),

              child:
                  Row(
                children: [

                  const Icon(
                    Icons.access_time,
                  ),

                  const SizedBox(
                    width: 10,
                  ),

                  Expanded(
                    child:
                        Text(
                      'Doctor Shift: ${doctor.shift}',

                      style:
                          const TextStyle(
                        fontWeight:
                            FontWeight.w600,
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
            child:
                Padding(
              padding:
                  EdgeInsets.all(30),

              child:
                  CircularProgressIndicator(),
            ),
          )


        // ====================================================================
        // NO SLOTS
        // ====================================================================

        else if (timeSlots.isEmpty)

          Card(
            child:
                Padding(
              padding:
                  const EdgeInsets.all(
                16,
              ),

              child:
                  Text(
                doctor == null ||
                        doctor.shift.isEmpty
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
  // ==========================================================================

  Widget _buildTimeSlots() {

    return Column(

      crossAxisAlignment:
          CrossAxisAlignment.start,

      children: [

        const Text(
          'Select Time Slot',

          style: TextStyle(
            fontSize: 18,
            fontWeight:
                FontWeight.bold,
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

            final isBooked =
                bookedSlots.contains(
              slot,
            );


            final isSelected =
                selectedTimeSlot ==
                    slot;


            return GestureDetector(

              onTap:
                  isBooked
                      ? null
                      : () {

                          setState(() {

                            selectedTimeSlot =
                                slot;
                          });
                        },


              child:
                  Container(

                width:
                    double.infinity,

                margin:
                    const EdgeInsets.only(
                  bottom: 12,
                ),

                padding:
                    const EdgeInsets
                        .symmetric(
                  horizontal: 16,
                  vertical: 15,
                ),


                decoration:
                    BoxDecoration(

                  color:

                      // BOOKED = RED
                      isBooked

                          ? Colors.red
                              .withOpacity(
                              0.10,
                            )

                          // SELECTED
                          : isSelected

                              ? Theme.of(
                                  context,
                                )
                                    .colorScheme
                                    .primary
                                    .withOpacity(
                                    0.10,
                                  )

                              // AVAILABLE
                              : Colors.white,


                  borderRadius:
                      BorderRadius.circular(
                    12,
                  ),


                  border:
                      Border.all(

                    color:

                        isBooked

                            ? Colors.red

                            : isSelected

                                ? Theme.of(
                                    context,
                                  )
                                    .colorScheme
                                    .primary

                                : Colors.grey
                                    .withOpacity(
                                    0.4,
                                  ),

                    width:
                        isBooked ||
                                isSelected
                            ? 2
                            : 1,
                  ),
                ),


                child:
                    Row(
                  children: [

                    Icon(

                      isBooked
                          ? Icons.event_busy
                          : Icons.access_time,

                      color:

                          isBooked
                              ? Colors.red
                              : Theme.of(
                                  context,
                                )
                                    .colorScheme
                                    .primary,
                    ),


                    const SizedBox(
                      width: 14,
                    ),


                    Expanded(
                      child:
                          Column(
                        crossAxisAlignment:
                            CrossAxisAlignment
                                .start,

                        children: [

                          Text(
                            slot,

                            style:
                                TextStyle(
                              fontSize: 16,

                              fontWeight:
                                  FontWeight.bold,

                              color:
                                  isBooked
                                      ? Colors.red
                                      : null,
                            ),
                          ),


                          const SizedBox(
                            height: 4,
                          ),


                          Text(

                            isBooked
                                ? 'Already booked'
                                : 'Available',

                            style:
                                TextStyle(

                              fontSize: 12,

                              fontWeight:
                                  FontWeight.w500,

                              color:

                                  isBooked
                                      ? Colors.red
                                      : Colors.green,
                            ),
                          ),
                        ],
                      ),
                    ),


                    if (isBooked)

                      const Icon(
                        Icons.lock_outline,
                        color: Colors.red,
                      )

                    else

                      Radio<String>(
                        value:
                            slot,

                        groupValue:
                            selectedTimeSlot,

                        onChanged:
                            (_) {

                          setState(() {

                            selectedTimeSlot =
                                slot;
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
  // ==========================================================================

  Widget _buildDetailsStep() {

    return Column(

      crossAxisAlignment:
          CrossAxisAlignment.start,

      children: [

        const Text(
          'Appointment Details',

          style: TextStyle(
            fontSize: 24,
            fontWeight:
                FontWeight.bold,
          ),
        ),


        const SizedBox(
          height: 20,
        ),


        const Text(
          'Reason for Visit',

          style:
              TextStyle(
            fontWeight:
                FontWeight.bold,
          ),
        ),


        const SizedBox(
          height: 10,
        ),


        TextField(
          controller:
              reasonController,

          maxLines:
              2,

          decoration:
              const InputDecoration(
            labelText:
                'Reason for appointment',

            hintText:
                'Describe your problem...',

            border:
                OutlineInputBorder(),
          ),
        ),


        const SizedBox(
          height: 20,
        ),


        const Text(
          'Symptoms',

          style:
              TextStyle(
            fontWeight:
                FontWeight.bold,
          ),
        ),


        const SizedBox(
          height: 10,
        ),


        TextField(
          controller:
              symptomsController,

          maxLines:
              5,

          decoration:
              const InputDecoration(
            labelText:
                'Symptoms',

            hintText:
                'Describe your symptoms...',

            border:
                OutlineInputBorder(),
          ),
        ),
      ],
    );
  }


  // ==========================================================================
  // CONFIRMATION
  // ==========================================================================

  Widget _buildConfirmationStep() {

    final doctor =
        selectedDoctor;


    return Column(

      crossAxisAlignment:
          CrossAxisAlignment.start,

      children: [

        const Text(
          'Confirm Appointment',

          style: TextStyle(
            fontSize: 24,
            fontWeight:
                FontWeight.bold,
          ),
        ),


        const SizedBox(
          height: 20,
        ),


        Card(

          child:
              Padding(
            padding:
                const EdgeInsets.all(
              18,
            ),

            child:
                Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,

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
                  reasonController.text
                      .trim(),
                ),

                _summaryRow(
                  'Symptoms',
                  symptomsController.text
                          .trim()
                          .isEmpty
                      ? 'Not provided'
                      : symptomsController.text
                          .trim(),
                ),
              ],
            ),
          ),
        ),


        const SizedBox(
          height: 15,
        ),


        Card(
          child:
              const Padding(
            padding:
                EdgeInsets.all(16),

            child:
                Text(
              'A queue token will be generated automatically after confirmation.',
            ),
          ),
        ),
      ],
    );
  }


  // ==========================================================================
  // SUMMARY ROW
  // ==========================================================================

  Widget _summaryRow(
    String title,
    String value,
  ) {

    return Padding(

      padding:
          const EdgeInsets.only(
        bottom: 14,
      ),

      child:
          Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,

        children: [

          SizedBox(
            width: 100,

            child:
                Text(
              title,

              style:
                  const TextStyle(
                fontWeight:
                    FontWeight.bold,
              ),
            ),
          ),


          Expanded(
            child:
                Text(
              value,
            ),
          ),
        ],
      ),
    );
  }


  // ==========================================================================
  // BOTTOM BUTTONS
  // ==========================================================================

  Widget _buildBottomButtons() {

    return SafeArea(

      child:
          Padding(
        padding:
            const EdgeInsets.all(
          16,
        ),

        child:
            Row(
          children: [

            if (currentStep > 0)

              Expanded(
                child:
                    OutlinedButton(
                  onPressed:
                      booking
                          ? null
                          : _previousStep,

                  child:
                      const Text(
                    'Back',
                  ),
                ),
              ),


            if (currentStep > 0)

              const SizedBox(
                width: 12,
              ),


            Expanded(
              child:
                  ElevatedButton(
                onPressed:
                    booking
                        ? null
                        : _nextStep,

                child:

                    booking

                        ? const SizedBox(
                            height: 20,
                            width: 20,

                            child:
                                CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )

                        : Text(
                            currentStep == 3
                                ? 'Confirm Appointment'
                                : 'Next',
                          ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}