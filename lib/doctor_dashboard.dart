// Doctor Dashboard — Firestore-backed
//
// Firestore layout:
//
// users/{doctorId}
//   -> doctor's account/profile document
//
// appointments/{appointmentId}
//   -> doctorUid
//   -> dateKey
//   -> status        ('booked' | 'cancelled' | 'waiting' |
//                      'inConsultation' | 'completed')
//   -> queueNumber
//   -> studentName
//   -> studentId
//   -> studentDept
//   -> studentBatch
//   -> studentPhone
//   -> reason
//   -> timeSlot
//   -> diagnosis
//   -> symptoms
//   -> treatmentAdvice
//   -> followUpDate
//   -> bloodPressure
//   -> temperature
//   -> pulseRate
//   -> prescriptions
//   -> doctorName            <-- denormalized so student dashboard can
//   -> doctorDesignation         show "who prescribed this" without a
//   -> doctorSpecialization      second Firestore lookup.
//   -> doctorDepartment
//   -> doctorChamber
//
// IMPORTANT / FLOW:
// 1. Doctor taps "Start Consultation" on a queued appointment.
//    -> status is immediately written as 'inConsultation' in Firestore,
//       and the doctor's own profile info (name, designation,
//       specialization, department, chamber) is stamped onto the
//       appointment document at this point.
// 2. The Consultation form opens. The doctor fills symptoms, vitals,
//    diagnosis, treatment advice, follow-up date, and adds medicines
//    to the prescription list.
// 3. Doctor taps "Complete Consultation & Issue Rx".
//    -> status becomes 'completed', 'completedAt' server timestamp is
//       set, and the full clinical record + prescription + doctor info
//       + student info are saved together in the SAME appointment
//       document. This is the exact document the student dashboard
//       should read to show the issued prescription.
//
// This dashboard also loads only the appointments belonging to the
// logged-in doctor FOR ONE SELECTED DAY (defaults to today), and it
// excludes any appointment whose status is 'cancelled'. The doctor
// can step to the previous/next day or open a date picker to review
// a different day's patient list.

import 'package:flutter/material.dart'; // Flutter UI widgets
import 'package:cloud_firestore/cloud_firestore.dart'; // Firestore database
import 'package:firebase_auth/firebase_auth.dart'; // Login / current user

import 'chat_list_page.dart'; // The messages list page

const Color kPrimary = Color(0xFF003D9B); // Main blue
const Color kTeal = Color(0xFF00687A); // Teal accent
const Color kText = Color(0xFF111C2D); // Dark text color
const Color kMuted = Color(0xFF737685); // Grey text color
const Color kBorder = Color(0xFFC3C6D6); // Border grey
const Color kPage = Color(0xFFF5F7FB); // Page background
const Color kSoftBlue = Color(0xFFE7EEFF); // Light blue background
const Color kSoftTeal = Color(0xFFE0F7FA); // Light teal background

// Returns the white rounded "card" look used all over the app
BoxDecoration cardDecoration() => BoxDecoration(
      color: Colors.white, // White card
      borderRadius: BorderRadius.circular(18), // Round corners
      border: Border.all(
        color: kBorder.withOpacity(.7), // Soft border color
        width: .7, // Thin border
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(.035), // Very light shadow
          blurRadius: 10, // Shadow softness
          offset: const Offset(0, 4), // Shadow moves down 4px
        ),
      ],
    );

// Returns the common look for all text fields
InputDecoration inputDecoration(
  String label, {
  String? hint,
}) {
  return InputDecoration(
    labelText: label, // Floating label text
    hintText: hint, // Grey hint text inside the field
    filled: true, // Fill the field with color
    fillColor: const Color(0xFFF9F9FF), // Very light fill color
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12), // Round field corners
    ),
    enabledBorder: OutlineInputBorder(
      // Border when not focused
      borderRadius: BorderRadius.circular(12), // Round corners
      borderSide: const BorderSide(color: kBorder), // Grey border
    ),
    focusedBorder: OutlineInputBorder(
      // Border when typing
      borderRadius: BorderRadius.circular(12), // Round corners
      borderSide: const BorderSide(color: kPrimary, width: 1.5), // Thick blue border
    ),
  );
}

// ============================================================
// MODELS
// ============================================================

// All possible states of an appointment
enum AppointmentStatus {
  waiting,
  upcoming,
  inConsultation,
  completed,
  cancelled,
}

// Converts the text saved in Firestore into an AppointmentStatus
AppointmentStatus statusFromString(String? value) {
  final normalized = value?.trim(); // Remove extra spaces

  // 'booked' is what the student-side booking flow writes for a
  // freshly booked appointment — it belongs in the doctor's
  // waiting queue.
  if (normalized == 'booked') {
    return AppointmentStatus.waiting; // Treat "booked" as waiting
  }

  return AppointmentStatus.values.firstWhere(
    (s) => s.name == normalized, // Find the status with the same name
    orElse: () => AppointmentStatus.waiting, // Not found -> waiting
  );
}

// ============================================================
// PRESCRIPTION ITEM
// ============================================================

// One medicine line in a prescription
class PrescriptionItem {
  final String medicineName; // Name of the medicine
  final String dosage; // How much (e.g. 500mg)
  final String frequency; // How often (e.g. 1+0+1)
  final String duration; // For how long (e.g. 3 days)
  final String timing; // Before / after / with meal

  const PrescriptionItem({
    required this.medicineName, // Must be given
    required this.dosage, // Must be given
    required this.frequency, // Must be given
    required this.duration, // Must be given
    required this.timing, // Must be given
  });

  // Builds a PrescriptionItem from a Firestore map
  factory PrescriptionItem.fromMap(Map<String, dynamic> map) {
    return PrescriptionItem(
      medicineName: (map['medicineName'] ?? '').toString(), // Name or empty
      dosage: (map['dosage'] ?? '').toString(), // Dosage or empty
      frequency: (map['frequency'] ?? '').toString(), // Frequency or empty
      duration: (map['duration'] ?? '').toString(), // Duration or empty
      timing: (map['timing'] ?? 'After Meal').toString(), // Default "After Meal"
    );
  }

  // Converts this item into a map to save in Firestore
  Map<String, dynamic> toMap() {
    return {
      'medicineName': medicineName, // Save name
      'dosage': dosage, // Save dosage
      'frequency': frequency, // Save frequency
      'duration': duration, // Save duration
      'timing': timing, // Save timing
    };
  }
}

// ============================================================
// DOCTOR APPOINTMENT
// ============================================================

// One appointment document, as used by the doctor side
class DoctorAppointment {
  final String id; // Document id
  final String doctorUid; // Which doctor owns it
  final String dateKey; // Date text like 2026-09-04
  final int queueNumber; // Token number in the queue

  final String studentName; // Student's name
  final String studentId; // Student's id
  final String studentDept; // Student's department
  final String studentBatch; // Student's batch
  final String studentPhone; // Student's phone

  final String reason; // Student's complaint
  final String timeSlot; // Appointment time

  final AppointmentStatus status; // Current status

  final String diagnosis; // Doctor's diagnosis
  final String symptoms; // Symptoms found
  final String treatmentAdvice; // Doctor's advice
  final String followUpDate; // Next visit date

  final String bloodPressure; // Blood pressure value
  final String temperature; // Body temperature
  final String pulseRate; // Pulse rate

  final List<PrescriptionItem> prescriptions; // All medicines

  // Denormalized doctor info — stamped onto the appointment the moment
  // consultation starts, so the student dashboard can render "who
  // prescribed this" straight from the appointment/prescription
  // document, without a second lookup into users/{doctorId}.
  final String doctorName; // Doctor's name
  final String doctorDesignation; // Doctor's title
  final String doctorSpecialization; // Doctor's specialty
  final String doctorDepartment; // Doctor's department
  final String doctorChamber; // Doctor's room

  const DoctorAppointment({
    required this.id, // Must be given
    required this.doctorUid, // Must be given
    required this.dateKey, // Must be given
    required this.queueNumber, // Must be given
    required this.studentName, // Must be given
    required this.studentId, // Must be given
    required this.studentDept, // Must be given
    required this.studentBatch, // Must be given
    required this.studentPhone, // Must be given
    required this.reason, // Must be given
    required this.timeSlot, // Must be given
    required this.status, // Must be given
    this.diagnosis = '', // Optional, default empty
    this.symptoms = '', // Optional, default empty
    this.treatmentAdvice = '', // Optional, default empty
    this.followUpDate = '', // Optional, default empty
    this.bloodPressure = '', // Optional, default empty
    this.temperature = '', // Optional, default empty
    this.pulseRate = '', // Optional, default empty
    this.prescriptions = const [], // Optional, default no medicines
    this.doctorName = '', // Optional, default empty
    this.doctorDesignation = '', // Optional, default empty
    this.doctorSpecialization = '', // Optional, default empty
    this.doctorDepartment = '', // Optional, default empty
    this.doctorChamber = '', // Optional, default empty
  });

  // Builds an appointment from a Firestore document
  factory DoctorAppointment.fromMap(
    String id,
    Map<String, dynamic> map,
  ) {
    final rawPrescriptions = map['prescriptions']; // Raw medicines data

    final prescriptionList = <PrescriptionItem>[]; // Empty list to fill

    if (rawPrescriptions is List) {
      // Only continue if it is really a list
      for (final item in rawPrescriptions) {
        // Check each medicine
        if (item is Map) {
          // Only use it if it is a map
          prescriptionList.add(
            PrescriptionItem.fromMap(Map<String, dynamic>.from(item)), // Convert and add
          );
        }
      }
    }

    int queueNumber = 0; // Default queue number

    final rawQueue = map['queueNumber']; // Raw queue value

    if (rawQueue is int) {
      queueNumber = rawQueue; // Already an int
    } else if (rawQueue is num) {
      queueNumber = rawQueue.toInt(); // Number -> int
    } else if (rawQueue is String) {
      queueNumber = int.tryParse(rawQueue) ?? 0; // Text -> int (0 if fails)
    }

    return DoctorAppointment(
      id: id, // Document id
      doctorUid: (map['doctorUid'] ?? '').toString(), // Doctor id
      dateKey: (map['dateKey'] ?? '').toString(), // Date text
      queueNumber: queueNumber, // Queue number

      studentName: (map['studentName'] ?? '').toString(), // Student name
      studentId: (map['studentId'] ?? '').toString(), // Student id
      studentDept: (map['studentDept'] ?? '').toString(), // Student dept
      studentBatch: (map['studentBatch'] ?? '').toString(), // Student batch
      studentPhone: (map['studentPhone'] ?? '').toString(), // Student phone

      reason: (map['reason'] ?? '').toString(), // Complaint
      timeSlot: (map['timeSlot'] ?? map['time'] ?? '').toString(), // Time (old key "time" also works)

      status: statusFromString(map['status']?.toString()), // Convert status text

      diagnosis: (map['diagnosis'] ?? '').toString(), // Diagnosis
      symptoms: (map['symptoms'] ?? '').toString(), // Symptoms
      treatmentAdvice: (map['treatmentAdvice'] ?? '').toString(), // Advice
      followUpDate: (map['followUpDate'] ?? '').toString(), // Follow-up date

      bloodPressure: (map['bloodPressure'] ?? '').toString(), // BP
      temperature: (map['temperature'] ?? '').toString(), // Temperature
      pulseRate: (map['pulseRate'] ?? '').toString(), // Pulse

      prescriptions: prescriptionList, // Medicines list

      doctorName: (map['doctorName'] ?? '').toString(), // Doctor name
      doctorDesignation: (map['doctorDesignation'] ?? '').toString(), // Doctor title
      doctorSpecialization:
          (map['doctorSpecialization'] ?? '').toString(), // Doctor specialty
      doctorDepartment: (map['doctorDepartment'] ?? '').toString(), // Doctor dept
      doctorChamber: (map['doctorChamber'] ?? '').toString(), // Doctor room
    );
  }

  /// Only the fields a doctor is allowed to write (must match
  /// doctorWritableFields() in Firestore security rules).
  /// This prevents PERMISSION_DENIED caused by sending immutable
  /// student / booking fields.
  Map<String, dynamic> toMap({bool forDoctorUpdate = false}) {
    if (forDoctorUpdate) {
      // Only the fields a doctor may change
      final map = <String, dynamic>{
        'status': status.name, // Status as text
        'diagnosis': diagnosis, // Diagnosis
        'symptoms': symptoms, // Symptoms
        'treatmentAdvice': treatmentAdvice, // Advice
        'followUpDate': followUpDate, // Follow-up date
        'bloodPressure': bloodPressure, // BP
        'temperature': temperature, // Temperature
        'pulseRate': pulseRate, // Pulse
        'prescriptions': prescriptions.map((p) => p.toMap()).toList(), // Medicines as maps
        // Doctor attribution stamped onto appointment
        'doctorName': doctorName, // Doctor name
        'doctorDesignation': doctorDesignation, // Doctor title
        'doctorSpecialization': doctorSpecialization, // Doctor specialty
        'doctorDepartment': doctorDepartment, // Doctor dept
        'doctorChamber': doctorChamber, // Doctor room
        'updatedAt': FieldValue.serverTimestamp(), // Last update time
      };

      if (status == AppointmentStatus.completed) {
        // Only when finished
        map['completedAt'] = FieldValue.serverTimestamp(); // Save finish time
      }

      return map; // Return the doctor-only map
    }

    // Full map (kept for completeness / other potential uses)
    return {
      'doctorUid': doctorUid, // Doctor id
      'dateKey': dateKey, // Date text
      'queueNumber': queueNumber, // Queue number
      'studentName': studentName, // Student name
      'studentId': studentId, // Student id
      'studentDept': studentDept, // Student dept
      'studentBatch': studentBatch, // Student batch
      'studentPhone': studentPhone, // Student phone
      'reason': reason, // Complaint
      'timeSlot': timeSlot, // Time
      'status': status.name, // Status as text
      'diagnosis': diagnosis, // Diagnosis
      'symptoms': symptoms, // Symptoms
      'treatmentAdvice': treatmentAdvice, // Advice
      'followUpDate': followUpDate, // Follow-up date
      'bloodPressure': bloodPressure, // BP
      'temperature': temperature, // Temperature
      'pulseRate': pulseRate, // Pulse
      'prescriptions': prescriptions.map((p) => p.toMap()).toList(), // Medicines as maps
      'doctorName': doctorName, // Doctor name
      'doctorDesignation': doctorDesignation, // Doctor title
      'doctorSpecialization': doctorSpecialization, // Doctor specialty
      'doctorDepartment': doctorDepartment, // Doctor dept
      'doctorChamber': doctorChamber, // Doctor room
      if (status == AppointmentStatus.completed)
        'completedAt': FieldValue.serverTimestamp(), // Finish time only if completed
    };
  }

  // Makes a copy of this appointment with some fields changed
  DoctorAppointment copyWith({
    AppointmentStatus? status,
    String? diagnosis,
    String? symptoms,
    String? treatmentAdvice,
    String? followUpDate,
    String? bloodPressure,
    String? temperature,
    String? pulseRate,
    List<PrescriptionItem>? prescriptions,
    String? doctorName,
    String? doctorDesignation,
    String? doctorSpecialization,
    String? doctorDepartment,
    String? doctorChamber,
  }) {
    return DoctorAppointment(
      id: id, // Keep same id
      doctorUid: doctorUid, // Keep same doctor
      dateKey: dateKey, // Keep same date
      queueNumber: queueNumber, // Keep same queue number
      studentName: studentName, // Keep same student name
      studentId: studentId, // Keep same student id
      studentDept: studentDept, // Keep same dept
      studentBatch: studentBatch, // Keep same batch
      studentPhone: studentPhone, // Keep same phone
      reason: reason, // Keep same complaint
      timeSlot: timeSlot, // Keep same time
      status: status ?? this.status, // New value, or old if not given
      diagnosis: diagnosis ?? this.diagnosis, // New or old
      symptoms: symptoms ?? this.symptoms, // New or old
      treatmentAdvice: treatmentAdvice ?? this.treatmentAdvice, // New or old
      followUpDate: followUpDate ?? this.followUpDate, // New or old
      bloodPressure: bloodPressure ?? this.bloodPressure, // New or old
      temperature: temperature ?? this.temperature, // New or old
      pulseRate: pulseRate ?? this.pulseRate, // New or old
      prescriptions: prescriptions ?? this.prescriptions, // New or old
      doctorName: doctorName ?? this.doctorName, // New or old
      doctorDesignation: doctorDesignation ?? this.doctorDesignation, // New or old
      doctorSpecialization:
          doctorSpecialization ?? this.doctorSpecialization, // New or old
      doctorDepartment: doctorDepartment ?? this.doctorDepartment, // New or old
      doctorChamber: doctorChamber ?? this.doctorChamber, // New or old
    );
  }
}

// ============================================================
// DOCTOR PROFILE
// ============================================================

// The doctor's professional profile (stored in users/{doctorId})
class DoctorProfile {
  final String id; // Doctor's user id

  final String fullName; // Full name
  final String designation; // Title (e.g. Assistant Professor)
  final String specialization; // Specialty
  final String department; // Department
  final String bmdcRegNo; // Medical registration number

  final List<String> qualifications; // Degrees list

  final int experienceYears; // Years of experience

  final String chamber; // Duty room
  final String shift; // Duty time

  final String phone; // Contact phone
  final String email; // Contact email

  final String bio; // Short bio
  final String photoUrl; // Photo link

  const DoctorProfile({
    required this.id, // Must be given
    this.fullName = '', // Optional, default empty
    this.designation = '', // Optional, default empty
    this.specialization = '', // Optional, default empty
    this.department = '', // Optional, default empty
    this.bmdcRegNo = '', // Optional, default empty
    this.qualifications = const [], // Optional, default empty list
    this.experienceYears = 0, // Optional, default 0
    this.chamber = '', // Optional, default empty
    this.shift = '', // Optional, default empty
    this.phone = '', // Optional, default empty
    this.email = '', // Optional, default empty
    this.bio = '', // Optional, default empty
    this.photoUrl = '', // Optional, default empty
  });

  // True when the three important fields are filled
  bool get isComplete {
    return fullName.isNotEmpty && // Name is filled
        specialization.isNotEmpty && // Specialty is filled
        department.isNotEmpty; // Department is filled
  }

  // Builds a profile from a Firestore document
  factory DoctorProfile.fromMap(
    String id,
    Map<String, dynamic> map,
  ) {
    final rawQualifications = map['qualifications']; // Raw degrees data

    final qualifications = <String>[]; // Empty list to fill

    if (rawQualifications is List) {
      // Saved as a list
      for (final q in rawQualifications) {
        // Check each degree
        final value = q.toString().trim(); // Make it clean text

        if (value.isNotEmpty) {
          // Skip empty ones
          qualifications.add(value); // Add to the list
        }
      }
    } else if (rawQualifications is String) {
      // Saved as one text like "MBBS, MD"
      qualifications.addAll(
        rawQualifications
            .split(',') // Split at commas
            .map((q) => q.trim()) // Remove spaces
            .where((q) => q.isNotEmpty), // Skip empty ones
      );
    }

    int experienceYears = 0; // Default years

    final rawExperience = map['experienceYears']; // Raw years value

    if (rawExperience is int) {
      experienceYears = rawExperience; // Already an int
    } else if (rawExperience is num) {
      experienceYears = rawExperience.toInt(); // Number -> int
    } else if (rawExperience is String) {
      experienceYears = int.tryParse(rawExperience) ?? 0; // Text -> int
    }

    return DoctorProfile(
      id: id, // User id
      fullName: (map['fullName'] ?? '').toString(), // Name
      designation: (map['designation'] ?? '').toString(), // Title
      specialization: (map['specialization'] ?? '').toString(), // Specialty
      department: (map['department'] ?? '').toString(), // Department
      bmdcRegNo: (map['bmdcRegNo'] ?? '').toString(), // Reg number
      qualifications: qualifications, // Degrees
      experienceYears: experienceYears, // Years
      chamber: (map['chamber'] ?? '').toString(), // Room
      shift: (map['shift'] ?? '').toString(), // Shift
      phone: (map['phone'] ?? '').toString(), // Phone
      email: (map['email'] ?? '').toString(), // Email
      bio: (map['bio'] ?? '').toString(), // Bio
      photoUrl: (map['photoUrl'] ?? '').toString(), // Photo link
    );
  }

  // Converts the profile to a map to save in Firestore
  Map<String, dynamic> toMap() {
    return {
      'fullName': fullName, // Name
      'designation': designation, // Title
      'specialization': specialization, // Specialty
      'department': department, // Department
      'bmdcRegNo': bmdcRegNo, // Reg number
      'qualifications': qualifications, // Degrees
      'experienceYears': experienceYears, // Years
      'chamber': chamber, // Room
      'shift': shift, // Shift
      'phone': phone, // Phone
      'email': email, // Email
      'bio': bio, // Bio
      'photoUrl': photoUrl, // Photo link
      'updatedAt': FieldValue.serverTimestamp(), // Last update time
    };
  }
}

// ============================================================
// FIRESTORE REPOSITORY
// ============================================================

// All Firestore reading/writing for the doctor side lives here
class DoctorRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance; // Shortcut to Firestore

  // Returns the reference to one doctor's document
  DocumentReference<Map<String, dynamic>> _doctorDoc(String doctorId) {
    return _db.collection('users').doc(doctorId); // users/{doctorId}
  }

  // ----------------------------------------------------------
  // DOCTOR PROFILE
  // ----------------------------------------------------------

  // Live stream of the doctor's profile
  Stream<DoctorProfile?> watchProfile(String doctorId) {
    return _doctorDoc(doctorId).snapshots().map((snap) {
      // Convert each snapshot
      if (!snap.exists || snap.data() == null) {
        // No document?
        return null; // No profile
      }

      return DoctorProfile.fromMap(snap.id, snap.data()!); // Build profile object
    });
  }

  // Saves the profile to Firestore
  Future<void> saveProfile(DoctorProfile profile) async {
    await _doctorDoc(profile.id).set(
      profile.toMap(), // Data to save
      SetOptions(merge: true), // Merge, don't erase other fields
    );
  }

  // ----------------------------------------------------------
  // APPOINTMENTS FOR THIS DOCTOR, FOR ONE DAY
  //
  // Filters:
  //   doctorUid == doctorId
  //   dateKey   == dateKey   (e.g. '2026-09-04')
  //
  // Both are equality filters, so no composite index is
  // required. Cancelled appointments are dropped BEFORE they
  // are ever turned into a DoctorAppointment, so a cancelled
  // booking can never be mistaken for a waiting patient.
  // ----------------------------------------------------------

  // Live stream of one day's appointments for this doctor
  Stream<List<DoctorAppointment>> watchDoctorAppointmentsForDay(
    String doctorId,
    String dateKey,
  ) {
    return _db
        .collection('appointments') // Go to appointments
        .where('doctorUid', isEqualTo: doctorId) // Only this doctor's
        .where('dateKey', isEqualTo: dateKey) // Only this day's
        .snapshots() // Live updates
        .map((snap) {
      final appointments = snap.docs
          .where((doc) {
            final status =
                doc.data()['status']?.toString().trim().toLowerCase(); // Status in lowercase

            // Cancelled appointments never appear in the doctor's
            // day view.
            return status != 'cancelled'; // Keep only non-cancelled
          })
          .map((doc) => DoctorAppointment.fromMap(doc.id, doc.data())) // Convert to objects
          .toList(); // Make a list

      // Sort by queue token, falling back to time slot.
      appointments.sort((a, b) {
        final queueCompare = a.queueNumber.compareTo(b.queueNumber); // Compare queue numbers

        if (queueCompare != 0) {
          // Different numbers?
          return queueCompare; // Sort by queue number
        }

        return a.timeSlot.compareTo(b.timeSlot); // Same number: sort by time
      });

      return appointments; // Return the sorted list
    });
  }

  // ----------------------------------------------------------
  // COMPLETED HEALTH RECORDS (ALL DAYS)
  // ----------------------------------------------------------

  // Live stream of all completed consultations for this doctor
  Stream<List<DoctorAppointment>> watchHealthRecords(String doctorId) {
    return _db
        .collection('appointments') // Go to appointments
        .where('doctorUid', isEqualTo: doctorId) // Only this doctor's
        .where('status', isEqualTo: AppointmentStatus.completed.name) // Only completed
        .snapshots() // Live updates
        .map((snap) {
      final records = snap.docs
          .map((doc) => DoctorAppointment.fromMap(doc.id, doc.data())) // Convert to objects
          .toList(); // Make a list

      records.sort((a, b) => b.dateKey.compareTo(a.dateKey)); // Newest date first

      return records; // Return the list
    });
  }

  // ----------------------------------------------------------
  // UPDATE APPOINTMENT
  //
  // IMPORTANT: only writes the fields listed in
  // doctorWritableFields() in the security rules.
  // This prevents the PERMISSION_DENIED error that occurred
  // when the full document (including immutable student fields)
  // was sent with set(merge: true).
  // ----------------------------------------------------------

  // Saves the doctor's changes to an appointment
  Future<void> updateAppointment(DoctorAppointment appointment) async {
    await _db.collection('appointments').doc(appointment.id).set(
          appointment.toMap(forDoctorUpdate: true), // Only doctor-allowed fields
          SetOptions(merge: true), // Merge with existing data
        );
  }
}

// ============================================================
// DOCTOR ANNOUNCEMENTS
// ============================================================

// One announcement shown on the doctor dashboard
class DoctorAnnouncement {
  final String id; // Document id
  final String title; // Announcement title
  final String content; // Announcement message
  final String audience; // Who it is for (all/doctor)
  final String priority; // normal / urgent
  final dynamic createdAt; // Creation time (any type)

  const DoctorAnnouncement({
    required this.id, // Must be given
    required this.title, // Must be given
    required this.content, // Must be given
    required this.audience, // Must be given
    required this.priority, // Must be given
    required this.createdAt, // Must be given
  });

  // Builds an announcement from a Firestore document
  factory DoctorAnnouncement.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{}; // Data (empty map if missing)

    return DoctorAnnouncement(
      id: doc.id, // Document id
      title: (data['title'] ?? data['announcementTitle'] ?? '').toString(), // Title (2 possible keys)
      content: (data['content'] ?? data['message'] ?? data['description'] ?? '')
          .toString(), // Message (3 possible keys)
      audience: (data['audience'] ?? '').toString(), // Audience
      priority: (data['priority'] ?? 'normal').toString(), // Priority, default normal
      createdAt: data['createdAt'], // Raw time value
    );
  }

  // Converts createdAt (whatever type it is) into a DateTime for sorting
  DateTime get sortDate {
    final value = createdAt; // Short name
    if (value is Timestamp) return value.toDate(); // Firestore time
    if (value is DateTime) return value; // Already a DateTime
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value); // Milliseconds
    if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt()); // Number
    if (value is String) {
      // Text date
      return DateTime.tryParse(value) ?? DateTime.fromMillisecondsSinceEpoch(0); // Parse or use 1970
    }
    return DateTime.fromMillisecondsSinceEpoch(0); // Unknown type -> 1970
  }
}

// The announcements block shown at the bottom of the dashboard
class DoctorAnnouncementsSection extends StatelessWidget {
  const DoctorAnnouncementsSection({super.key});

  // Live stream of announcements meant for doctors
  Stream<List<DoctorAnnouncement>> _announcementsStream() {
    return FirebaseFirestore.instance
        .collection('announcements') // Go to announcements
        .snapshots() // Live updates
        .map((snapshot) {
      final announcements = snapshot.docs
          .map(DoctorAnnouncement.fromDocument) // Convert to objects
          .where((announcement) {
            final audience = announcement.audience.trim().toLowerCase(); // Clean audience text
            return audience == 'all' || // For everyone
                audience == 'doctor' || // For doctor
                audience == 'doctors'; // For doctors
          })
          .toList(); // Make a list

      announcements.sort((a, b) {
        final dateCompare = b.sortDate.compareTo(a.sortDate); // Newest first
        if (dateCompare != 0) return dateCompare; // Different dates: done
        return b.id.compareTo(a.id); // Same date: sort by id
      });

      return announcements; // Return the sorted list
    });
  }

  // Turns a time value into text like 04/09/2026 • 3:07 PM
  String _formatDate(dynamic value) {
    DateTime? date; // Will hold the date
    if (value is Timestamp) {
      date = value.toDate(); // Firestore time
    } else if (value is DateTime) {
      date = value; // Already a DateTime
    } else if (value is int) {
      date = DateTime.fromMillisecondsSinceEpoch(value); // Milliseconds
    } else if (value is num) {
      date = DateTime.fromMillisecondsSinceEpoch(value.toInt()); // Number
    } else if (value is String) {
      date = DateTime.tryParse(value); // Text date
    }

    if (date == null) return 'Date not available'; // Could not read it

    final day = date.day.toString().padLeft(2, '0'); // Day with 2 digits
    final month = date.month.toString().padLeft(2, '0'); // Month with 2 digits
    final year = date.year.toString(); // Year
    var hour = date.hour; // Hour (24h)
    final minute = date.minute.toString().padLeft(2, '0'); // Minute with 2 digits
    final period = hour >= 12 ? 'PM' : 'AM'; // AM or PM
    hour %= 12; // Convert to 12h
    if (hour == 0) hour = 12; // 0 becomes 12

    return '$day/$month/$year • $hour:$minute $period'; // Final text
  }

  // Makes the audience text look nice
  String _displayAudience(String audience) {
    final normalized = audience.trim().toLowerCase(); // Clean text
    if (normalized == 'all') return 'All'; // For everyone
    if (normalized == 'doctor' || normalized == 'doctors') return 'Doctor'; // For doctors
    return audience.isEmpty ? 'Announcement' : audience; // Fallback
  }

  // Chooses the badge color from the priority
  Color _priorityColor(String priority) {
    if (priority.trim().toLowerCase() == 'urgent') {
      // Urgent?
      return Colors.red.shade700; // Red
    }
    return kPrimary; // Otherwise blue
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start, // Align left
      children: [
        const Text(
          'Announcements', // Section title
          style: TextStyle(
            fontSize: 17, // Title size
            fontWeight: FontWeight.bold, // Bold
            color: kText, // Dark color
          ),
        ),
        const SizedBox(height: 4), // Small gap
        const Text(
          'Latest announcements for all users and doctors.', // Subtitle
          style: TextStyle(fontSize: 11, color: kMuted), // Small grey text
        ),
        const SizedBox(height: 15), // Gap
        StreamBuilder<List<DoctorAnnouncement>>(
          // Listens to the announcements stream
          stream: _announcementsStream(), // The data source
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              // Still loading?
              return Container(
                width: double.infinity, // Full width
                padding: const EdgeInsets.symmetric(vertical: 32), // Space top/bottom
                decoration: cardDecoration(), // Card look
                child: const Center(child: CircularProgressIndicator()), // Spinner
              );
            }

            if (snapshot.hasError) {
              // Failed to load?
              return Container(
                width: double.infinity, // Full width
                padding: const EdgeInsets.all(20), // Space around
                decoration: cardDecoration(), // Card look
                child: Column(
                  children: [
                    const Icon(Icons.campaign_outlined, size: 38, color: kPrimary), // Megaphone icon
                    const SizedBox(height: 8), // Gap
                    const Text(
                      'Could not load announcements', // Error title
                      style: TextStyle(fontWeight: FontWeight.bold, color: kText), // Bold dark
                    ),
                    const SizedBox(height: 5), // Gap
                    Text(
                      '${snapshot.error}', // The real error text
                      textAlign: TextAlign.center, // Center it
                      style: const TextStyle(fontSize: 10, color: kMuted), // Small grey
                    ),
                  ],
                ),
              );
            }

            final announcements = snapshot.data ?? const <DoctorAnnouncement>[]; // List (empty if null)

            if (announcements.isEmpty) {
              // No announcements?
              return Container(
                width: double.infinity, // Full width
                padding: const EdgeInsets.all(24), // Space around
                decoration: cardDecoration(), // Card look
                child: const Center(
                  child: Column(
                    children: [
                      Icon(Icons.campaign_outlined, size: 38, color: kPrimary), // Megaphone icon
                      SizedBox(height: 8), // Gap
                      Text(
                        'No Announcements', // Empty title
                        style: TextStyle(fontWeight: FontWeight.bold, color: kText), // Bold dark
                      ),
                      SizedBox(height: 4), // Gap
                      Text(
                        'New announcements will appear here.', // Empty hint
                        textAlign: TextAlign.center, // Center it
                        style: TextStyle(fontSize: 11, color: kMuted), // Small grey
                      ),
                    ],
                  ),
                ),
              );
            }

            return Column(
              children: [
                for (final announcement in announcements)
                  // One card for each announcement
                  Container(
                    width: double.infinity, // Full width
                    margin: const EdgeInsets.only(bottom: 12), // Gap below card
                    padding: const EdgeInsets.all(16), // Space inside
                    decoration: cardDecoration(), // Card look
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start, // Align to top
                      children: [
                        Container(
                          width: 44, // Icon box width
                          height: 44, // Icon box height
                          decoration: BoxDecoration(
                            color: kSoftBlue, // Light blue box
                            borderRadius: BorderRadius.circular(13), // Round corners
                          ),
                          child: const Icon(
                            Icons.campaign_outlined, // Megaphone icon
                            color: kPrimary, // Blue
                            size: 23, // Icon size
                          ),
                        ),
                        const SizedBox(width: 12), // Gap
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start, // Align left
                            children: [
                              Wrap(
                                spacing: 7, // Horizontal gap
                                runSpacing: 5, // Vertical gap
                                crossAxisAlignment: WrapCrossAlignment.center, // Center vertically
                                children: [
                                  Text(
                                    announcement.title.isEmpty
                                        ? 'Announcement' // Default title
                                        : announcement.title, // Real title
                                    style: const TextStyle(
                                      fontSize: 14, // Title size
                                      fontWeight: FontWeight.bold, // Bold
                                      color: kText, // Dark
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7, // Left/right space
                                      vertical: 3, // Top/bottom space
                                    ),
                                    decoration: BoxDecoration(
                                      color: kSoftBlue, // Light blue badge
                                      borderRadius: BorderRadius.circular(20), // Pill shape
                                    ),
                                    child: Text(
                                      _displayAudience(announcement.audience), // Audience label
                                      style: const TextStyle(
                                        fontSize: 8, // Tiny text
                                        fontWeight: FontWeight.bold, // Bold
                                        color: kPrimary, // Blue
                                      ),
                                    ),
                                  ),
                                  if (announcement.priority.trim().isNotEmpty)
                                    // Show priority badge only if it exists
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7, // Left/right space
                                        vertical: 3, // Top/bottom space
                                      ),
                                      decoration: BoxDecoration(
                                        color: _priorityColor(announcement.priority)
                                            .withOpacity(.10), // Faded priority color
                                        borderRadius: BorderRadius.circular(20), // Pill shape
                                      ),
                                      child: Text(
                                        announcement.priority, // Priority text
                                        style: TextStyle(
                                          fontSize: 8, // Tiny text
                                          fontWeight: FontWeight.bold, // Bold
                                          color: _priorityColor(announcement.priority), // Priority color
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              if (announcement.content.isNotEmpty) ...[
                                // Show message only if it exists
                                const SizedBox(height: 6), // Gap
                                Text(
                                  announcement.content, // The message
                                  style: const TextStyle(
                                    fontSize: 11, // Small text
                                    color: Color(0xFF434654), // Dark grey
                                    height: 1.45, // Line spacing
                                  ),
                                ),
                              ],
                              const SizedBox(height: 8), // Gap
                              Row(
                                children: [
                                  const Icon(Icons.schedule_outlined, size: 13, color: kMuted), // Clock icon
                                  const SizedBox(width: 5), // Gap
                                  Text(
                                    _formatDate(announcement.createdAt), // Formatted date
                                    style: const TextStyle(fontSize: 9, color: kMuted), // Tiny grey
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ============================================================
// DOCTOR DASHBOARD
// ============================================================

// The main doctor page; it changes (selected day etc.), so it is Stateful
class DoctorDashboard extends StatefulWidget {
  final String doctorId; // Logged-in doctor's id

  const DoctorDashboard({
    super.key, // Optional widget key
    required this.doctorId, // Must be given
  });

  @override
  State<DoctorDashboard> createState() => _DoctorDashboardState(); // Create the state
}

class _DoctorDashboardState extends State<DoctorDashboard> {
  final DoctorRepository repo = DoctorRepository(); // Our Firestore helper

  // ----------------------------------------------------------
  // SELECTED DAY
  //
  // Defaults to today. The doctor can step back/forward a day
  // or open a date picker to review a different day's queue.
  // ----------------------------------------------------------

  DateTime selectedDate = DateTime.now(); // Currently viewed day (starts today)

  String get selectedDateKey => _dateKey(selectedDate); // Selected day as text key

  bool get isToday => _isSameDay(selectedDate, DateTime.now()); // Is the selected day today?

  // Turns a date into text like 2026-09-04
  String _dateKey(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-' // Year
        '${date.month.toString().padLeft(2, '0')}-' // Month
        '${date.day.toString().padLeft(2, '0')}'; // Day
  }

  // Turns a date into text like 04/09/2026
  String _displayDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/' // Day
        '${date.month.toString().padLeft(2, '0')}/' // Month
        '${date.year}'; // Year
  }

  // Checks if two dates are the same calendar day
  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day; // Same y/m/d
  }

  // Moves the selected day back by 1
  void goToPreviousDay() {
    setState(() {
      selectedDate = selectedDate.subtract(const Duration(days: 1)); // Minus 1 day
    });
  }

  // Moves the selected day forward by 1
  void goToNextDay() {
    setState(() {
      selectedDate = selectedDate.add(const Duration(days: 1)); // Plus 1 day
    });
  }

  // Jumps back to today
  void goToToday() {
    setState(() {
      selectedDate = DateTime.now(); // Reset to now
    });
  }

  // Opens a calendar to choose a day
  Future<void> pickDate() async {
    final now = DateTime.now(); // Current time

    final picked = await showDatePicker(
      context: context, // Current screen
      initialDate: selectedDate, // Start on the selected day
      firstDate: now.subtract(const Duration(days: 365)), // Up to 1 year back
      lastDate: now.add(const Duration(days: 90)), // Up to 90 days ahead
    );

    if (picked == null) return; // User cancelled

    setState(() {
      selectedDate = picked; // Use the chosen day
    });
  }

  // ----------------------------------------------------------
  // LOGOUT
  // ----------------------------------------------------------

  // Signs the doctor out and goes to the login page
  Future<void> logout() async {
    try {
      await FirebaseAuth.instance.signOut(); // Sign out from Firebase

      if (!mounted) return; // Page closed? stop

      Navigator.pushNamedAndRemoveUntil(
        context, // Current screen
        '/login', // Go to login page
        (route) => false, // Remove all old pages
      );
    } catch (e) {
      if (!mounted) return; // Page closed? stop

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Logout failed. Please try again.')), // Error message
      );
    }
  }

  // ----------------------------------------------------------
  // PROFILE
  // ----------------------------------------------------------

  // Opens the profile form page
  void openProfileForm(DoctorProfile? existing) {
    Navigator.push(
      context, // Current screen
      MaterialPageRoute(
        builder: (_) => DoctorProfileFormPage(
          doctorId: widget.doctorId, // Pass doctor id
          existing: existing, // Pass current profile (if any)
          repo: repo, // Pass the repository
        ),
      ),
    );
  }

  // ----------------------------------------------------------
  // START CONSULTATION
  //
  // 1. Stamp the doctor's own profile info onto the appointment
  //    (so the eventual prescription always carries who wrote it),
  //    and flip status -> inConsultation, immediately in Firestore.
  // 2. Open the Consultation form for the doctor to fill in.
  // ----------------------------------------------------------

  // Starts (or continues) a consultation for one appointment
  Future<void> startConsultation(
    DoctorAppointment appointment,
    DoctorProfile? profile,
  ) async {
    if (appointment.status == AppointmentStatus.completed) {
      // Already finished?
      return; // Do nothing
    }

    final updated = appointment.copyWith(
      status: AppointmentStatus.inConsultation, // Mark as in consultation
      doctorName: profile?.fullName ?? '', // Stamp doctor name
      doctorDesignation: profile?.designation ?? '', // Stamp doctor title
      doctorSpecialization: profile?.specialization ?? '', // Stamp specialty
      doctorDepartment: profile?.department ?? '', // Stamp department
      doctorChamber: profile?.chamber ?? '', // Stamp room
    );

    try {
      await repo.updateAppointment(updated); // Save it to Firestore now

      if (!mounted) return; // Page closed? stop

      await Navigator.push(
        context, // Current screen
        MaterialPageRoute(
          builder: (_) => ConsultationPage(
            appointment: updated, // Pass the updated appointment
            repo: repo, // Pass the repository
            doctorProfile: profile, // Pass the doctor profile
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return; // Page closed? stop

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start consultation: $e')), // Show error
      );
    }
  }

  // ----------------------------------------------------------
  // VIEW PRESCRIPTION
  // ----------------------------------------------------------

  // Opens the prescription page
  void viewPrescription(DoctorAppointment appointment) {
    Navigator.push(
      context, // Current screen
      MaterialPageRoute(
        builder: (_) => PrescriptionPage(appointment: appointment), // Show prescription
      ),
    );
  }

  // ----------------------------------------------------------
  // HEALTH RECORDS
  // ----------------------------------------------------------

  // Opens the list of all completed records
  void openHealthRecords() {
    Navigator.push(
      context, // Current screen
      MaterialPageRoute(
        builder: (_) => HealthRecordsPage(
          doctorId: widget.doctorId, // Pass doctor id
          repo: repo, // Pass the repository
        ),
      ),
    );
  }

  // ----------------------------------------------------------
  // BUILD
  // ----------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kPage, // Page background
      appBar: AppBar(
        backgroundColor: kPrimary, // Blue top bar
        foregroundColor: Colors.white, // White text/icons
        elevation: 0, // No shadow
        title: const Text(
          'Doctor Dashboard', // Bar title
          style: TextStyle(fontWeight: FontWeight.bold), // Bold
        ),
        actions: [
          IconButton(
            tooltip: 'Messages', // Hover text
            onPressed: () {
              Navigator.push(
                context, // Current screen
                MaterialPageRoute(builder: (_) => const ChatListPage()), // Open chat list
              );
            },
            icon: const Icon(Icons.chat_bubble_outline), // Chat icon
          ),
          IconButton(
            tooltip: 'Logout', // Hover text
            onPressed: logout, // Run logout
            icon: const Icon(Icons.logout_rounded), // Logout icon
          ),
        ],
      ),
      body: StreamBuilder<DoctorProfile?>(
        // First listen to the doctor profile
        stream: repo.watchProfile(widget.doctorId), // Profile data source
        builder: (context, profileSnap) {
          if (profileSnap.connectionState == ConnectionState.waiting) {
            // Still loading?
            return const Center(child: CircularProgressIndicator()); // Spinner
          }

          if (profileSnap.hasError) {
            // Failed?
            return Center(
              child: Text(
                'Failed to load doctor profile.\n${profileSnap.error}', // Error text
                textAlign: TextAlign.center, // Center it
              ),
            );
          }

          final profile = profileSnap.data; // The profile (can be null)

          return StreamBuilder<List<DoctorAppointment>>(
            // Then listen to the day's appointments
            stream: repo.watchDoctorAppointmentsForDay(
              widget.doctorId, // This doctor
              selectedDateKey, // Selected day
            ),
            builder: (context, apptSnap) {
              final appointments =
                  apptSnap.data ?? const <DoctorAppointment>[]; // List (empty if null)

              final loadingAppointments =
                  apptSnap.connectionState == ConnectionState.waiting; // Still loading?

              final waitingCount = appointments
                  .where((a) => a.status == AppointmentStatus.waiting) // Only waiting ones
                  .length; // Count them

              final completedCount = appointments
                  .where((a) => a.status == AppointmentStatus.completed) // Only completed ones
                  .length; // Count them

              final totalCount = appointments.length; // All appointments today

              return SafeArea(
                // Avoid phone notches
                child: SingleChildScrollView(
                  // Make the page scrollable
                  padding: const EdgeInsets.all(20), // Space around
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1000), // Limit width on big screens
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start, // Align left
                        children: [
                          _welcomeSection(profile), // Welcome card

                          const SizedBox(height: 20), // Gap

                          _dateSelector(), // Day selector

                          const SizedBox(height: 20), // Gap

                          _statistics(
                            totalCount, // Total count
                            waitingCount, // Waiting count
                            completedCount, // Completed count
                          ),

                          const SizedBox(height: 26), // Gap

                          _patientQueue(
                            appointments, // The list
                            waitingCount, // Waiting count
                            loadingAppointments, // Loading flag
                            profile, // Doctor profile
                          ),

                          const SizedBox(height: 28), // Gap

                          const DoctorAnnouncementsSection(), // Announcements

                          const SizedBox(height: 28), // Gap

                          Center(
                            child: Text(
                              'CUET SmartCare • Central Medical Services', // Footer text
                              style: TextStyle(
                                fontSize: 11, // Small text
                                color: Colors.grey.shade600, // Grey
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  // ==========================================================
  // DATE SELECTOR
  //
  // Lets the doctor step through days or jump straight to a
  // date. This is what scopes the whole dashboard to a single
  // day's worth of appointments.
  // ==========================================================

  Widget _dateSelector() {
    return Container(
      width: double.infinity, // Full width
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), // Space inside
      decoration: cardDecoration(), // Card look
      child: Row(
        children: [
          IconButton(
            tooltip: 'Previous day', // Hover text
            onPressed: goToPreviousDay, // Go back 1 day
            icon: const Icon(Icons.chevron_left_rounded, color: kPrimary), // Left arrow
          ),

          Expanded(
            child: InkWell(
              onTap: pickDate, // Tap to open the calendar
              borderRadius: BorderRadius.circular(10), // Round ripple
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6), // Space top/bottom
                child: Column(
                  children: [
                    Text(
                      isToday ? 'Today' : _displayDate(selectedDate), // "Today" or the date
                      style: const TextStyle(
                        fontSize: 15, // Text size
                        fontWeight: FontWeight.bold, // Bold
                        color: kText, // Dark
                      ),
                    ),
                    const SizedBox(height: 2), // Tiny gap
                    Text(
                      _displayDate(selectedDate), // Always show the real date
                      style: const TextStyle(
                        fontSize: 10, // Small text
                        color: kMuted, // Grey
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          IconButton(
            tooltip: 'Next day', // Hover text
            onPressed: goToNextDay, // Go forward 1 day
            icon: const Icon(Icons.chevron_right_rounded, color: kPrimary), // Right arrow
          ),

          if (!isToday)
            // Show "Today" button only when not on today
            TextButton(
              onPressed: goToToday, // Jump to today
              child: const Text('Today'), // Button label
            ),

          IconButton(
            tooltip: 'Pick a date', // Hover text
            onPressed: pickDate, // Open calendar
            icon: const Icon(Icons.calendar_month_outlined, color: kTeal), // Calendar icon
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // WELCOME
  // ==========================================================

  // The top card with doctor info and buttons
  Widget _welcomeSection(DoctorProfile? profile) {
    final hasProfile = profile != null && profile.isComplete; // Is the profile filled in?

    return Container(
      width: double.infinity, // Full width
      padding: const EdgeInsets.all(20), // Space inside
      decoration: cardDecoration(), // Card look
      child: LayoutBuilder(
        // Lets us change layout by screen width
        builder: (context, constraints) {
          final small = constraints.maxWidth < 600; // Is it a small screen?

          final avatar = Container(
            width: 64, // Avatar width
            height: 64, // Avatar height
            decoration: BoxDecoration(
              color: kSoftBlue, // Light blue background
              borderRadius: BorderRadius.circular(18), // Round corners
              border: Border.all(color: kPrimary.withOpacity(.2)), // Faint blue border
              image: (profile?.photoUrl.isNotEmpty ?? false)
                  ? DecorationImage(
                      image: NetworkImage(profile!.photoUrl), // Load photo from link
                      fit: BoxFit.cover, // Fill the box
                    )
                  : null, // No photo
            ),
            child: (profile?.photoUrl.isNotEmpty ?? false)
                ? null // Photo exists: no icon
                : const Icon(
                    Icons.medical_services_rounded, // Default doctor icon
                    color: kPrimary, // Blue
                    size: 32, // Icon size
                  ),
          );

          final info = Row(
            crossAxisAlignment: CrossAxisAlignment.start, // Align to top
            children: [
              avatar, // Photo/icon
              const SizedBox(width: 15), // Gap
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, // Align left
                  children: [
                    if (hasProfile)
                      // Profile filled: show duty chamber badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10, // Left/right space
                          vertical: 5, // Top/bottom space
                        ),
                        decoration: BoxDecoration(
                          color: kSoftTeal, // Light teal
                          borderRadius: BorderRadius.circular(20), // Pill shape
                        ),
                        child: Text(
                          'Duty Chamber: '
                          '${profile.chamber.isEmpty ? "Not set" : profile.chamber}' // Chamber or "Not set"
                          ' • '
                          '${profile.shift.isEmpty ? "Shift not set" : profile.shift}', // Shift or "Shift not set"
                          style: const TextStyle(
                            fontSize: 10, // Small text
                            fontWeight: FontWeight.bold, // Bold
                            color: kTeal, // Teal
                          ),
                        ),
                      )
                    else
                      // Profile not filled: show warning badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10, // Left/right space
                          vertical: 5, // Top/bottom space
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF0C2), // Light yellow
                          borderRadius: BorderRadius.circular(20), // Pill shape
                        ),
                        child: const Text(
                          'Professional profile incomplete', // Warning text
                          style: TextStyle(
                            fontSize: 10, // Small text
                            fontWeight: FontWeight.bold, // Bold
                            color: Color(0xFF805A00), // Brown
                          ),
                        ),
                      ),

                    const SizedBox(height: 7), // Gap

                    Text(
                      hasProfile
                          ? 'Good day, Dr. ${profile.fullName}' // Greeting with name
                          : 'Welcome, Doctor', // Generic greeting
                      style: const TextStyle(
                        fontSize: 20, // Big text
                        fontWeight: FontWeight.bold, // Bold
                        color: kText, // Dark
                      ),
                    ),

                    const SizedBox(height: 3), // Gap

                    Text(
                      hasProfile
                          ? '${profile.specialization} • '
                              '${profile.department} • '
                              "Use the date selector below to review a day's appointments." // Hint
                          : 'Add your professional details so students and staff can see who you are.', // Ask to fill profile
                      style: const TextStyle(
                        fontSize: 12, // Small text
                        color: kMuted, // Grey
                        height: 1.4, // Line spacing
                      ),
                    ),

                    if (!hasProfile) ...[
                      // Extra note only when profile is incomplete
                      const SizedBox(height: 6), // Gap
                      const Text(
                        'Note: until this is filled in, prescriptions you '
                        'issue will not show your name/specialization to '
                        'students.', // Note text
                        style: TextStyle(
                          fontSize: 10, // Small text
                          color: Color(0xFF805A00), // Brown
                          fontStyle: FontStyle.italic, // Italic
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );

          final buttons = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch, // Buttons fill the width
            children: [
              ElevatedButton.icon(
                onPressed: () => openProfileForm(profile), // Open profile form
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      hasProfile ? const Color(0xFFF0F3FF) : kPrimary, // Light if filled, blue if not
                  foregroundColor: hasProfile ? kPrimary : Colors.white, // Text color
                  elevation: 0, // No shadow
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16, // Left/right space
                    vertical: 12, // Top/bottom space
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12), // Round corners
                  ),
                ),
                icon: Icon(
                  hasProfile ? Icons.edit_outlined : Icons.badge_outlined, // Edit or badge icon
                  size: 17, // Icon size
                ),
                label: Text(
                  hasProfile
                      ? 'Edit Professional Profile' // Label when filled
                      : 'Add Professional Profile', // Label when empty
                  style: const TextStyle(
                    fontSize: 12, // Small text
                    fontWeight: FontWeight.bold, // Bold
                  ),
                ),
              ),

              const SizedBox(height: 10), // Gap

              OutlinedButton.icon(
                onPressed: openHealthRecords, // Open health records
                style: OutlinedButton.styleFrom(
                  foregroundColor: kTeal, // Teal text
                  side: const BorderSide(color: kTeal), // Teal border
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16, // Left/right space
                    vertical: 12, // Top/bottom space
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12), // Round corners
                  ),
                ),
                icon: const Icon(Icons.folder_shared_outlined, size: 17), // Folder icon
                label: const Text(
                  'All Health Records', // Button label
                  style: TextStyle(
                    fontSize: 12, // Small text
                    fontWeight: FontWeight.bold, // Bold
                  ),
                ),
              ),
            ],
          );

          if (small) {
            // Small screen: stack info then buttons
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start, // Align left
              children: [info, const SizedBox(height: 16), buttons], // Info, gap, buttons
            );
          }

          // Big screen: info on left, buttons on right
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start, // Align to top
            children: [
              Expanded(child: info), // Info takes free space
              const SizedBox(width: 20), // Gap
              SizedBox(width: 220, child: buttons), // Buttons fixed width
            ],
          );
        },
      ),
    );
  }

  // ==========================================================
  // STATISTICS
  // ==========================================================

  // The three number cards (total / waiting / completed)
  Widget _statistics(int total, int waiting, int completed) {
    final cards = [
      _statCard(
        title: 'Appointments', // Card title
        value: '$total', // Number to show
        subtitle: isToday
            ? "Booked for today" // Text for today
            : 'Booked for ${_displayDate(selectedDate)}', // Text for other day
        icon: Icons.calendar_month_rounded, // Calendar icon
        iconColor: kPrimary, // Blue
        backgroundColor: kSoftBlue, // Light blue
      ),
      _statCard(
        title: 'Waiting in Queue', // Card title
        value: '$waiting', // Number to show
        subtitle: 'Ready for consultation', // Small text
        icon: Icons.hourglass_top_rounded, // Hourglass icon
        iconColor: kTeal, // Teal
        backgroundColor: kSoftTeal, // Light teal
      ),
      _statCard(
        title: 'Completed', // Card title
        value: '$completed', // Number to show
        subtitle: 'Completed consultations', // Small text
        icon: Icons.check_circle_outline, // Check icon
        iconColor: Colors.green.shade700, // Green
        backgroundColor: Colors.green.shade50, // Light green
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 650) {
          // Small screen: cards stacked vertically
          return Column(
            children: [
              for (int i = 0; i < cards.length; i++) ...[
                cards[i], // Show the card
                if (i != cards.length - 1) const SizedBox(height: 12), // Gap between cards
              ],
            ],
          );
        }

        // Big screen: cards side by side
        return Row(
          children: [
            for (int i = 0; i < cards.length; i++) ...[
              Expanded(child: cards[i]), // Card shares width equally
              if (i != cards.length - 1) const SizedBox(width: 14), // Gap between cards
            ],
          ],
        );
      },
    );
  }

  // One number card
  Widget _statCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required Color backgroundColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(18), // Space inside
      decoration: cardDecoration(), // Card look
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, // Align left
              children: [
                Text(
                  title.toUpperCase(), // Title in CAPITALS
                  style: TextStyle(
                    fontSize: 10, // Small text
                    fontWeight: FontWeight.bold, // Bold
                    letterSpacing: 1, // Spread letters
                    color: iconColor, // Card color
                  ),
                ),
                const SizedBox(height: 5), // Gap
                Text(
                  value, // The big number
                  style: TextStyle(
                    fontSize: 30, // Very big
                    fontWeight: FontWeight.bold, // Bold
                    color: iconColor, // Card color
                  ),
                ),
                const SizedBox(height: 2), // Tiny gap
                Text(
                  subtitle, // Small description
                  style: const TextStyle(fontSize: 10, color: kMuted), // Small grey
                ),
              ],
            ),
          ),
          Container(
            width: 50, // Icon box width
            height: 50, // Icon box height
            decoration: BoxDecoration(
              color: backgroundColor, // Soft background
              borderRadius: BorderRadius.circular(16), // Round corners
            ),
            child: Icon(icon, color: iconColor, size: 25), // The icon
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // PATIENT QUEUE
  // ==========================================================

  // The list of patient cards for the selected day
  Widget _patientQueue(
    List<DoctorAppointment> appointments,
    int waiting,
    bool loading,
    DoctorProfile? profile,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start, // Align left
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, // Align left
                children: [
                  Text(
                    isToday
                        ? "Today's Patient Appointments" // Title for today
                        : 'Appointments • ${_displayDate(selectedDate)}', // Title for other day
                    style: const TextStyle(
                      fontSize: 17, // Title size
                      fontWeight: FontWeight.bold, // Bold
                      color: kText, // Dark
                    ),
                  ),
                  const SizedBox(height: 3), // Tiny gap
                  const Text(
                    'Cancelled appointments are hidden from this list.', // Info text
                    style: TextStyle(fontSize: 11, color: kMuted), // Small grey
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10), // Gap
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 11, // Left/right space
                vertical: 6, // Top/bottom space
              ),
              decoration: BoxDecoration(
                color: kSoftBlue, // Light blue
                borderRadius: BorderRadius.circular(20), // Pill shape
              ),
              child: Text(
                '$waiting Pending', // Pending count badge
                style: const TextStyle(
                  fontSize: 10, // Small text
                  fontWeight: FontWeight.bold, // Bold
                  color: kPrimary, // Blue
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 15), // Gap

        if (loading)
          // Still loading: show spinner
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 30), // Space top/bottom
            child: Center(child: CircularProgressIndicator()), // Spinner
          )
        else if (appointments.isEmpty)
          // No appointments: show empty message
          Container(
            width: double.infinity, // Full width
            padding: const EdgeInsets.all(24), // Space inside
            decoration: cardDecoration(), // Card look
            child: Center(
              child: Text(
                isToday
                    ? 'No appointments booked for today.' // Today message
                    : 'No appointments booked for ${_displayDate(selectedDate)}.', // Other day message
                style: const TextStyle(fontSize: 12, color: kMuted), // Small grey
              ),
            ),
          )
        else
          // Otherwise show one card per appointment
          for (final appointment in appointments)
            _patientCard(appointment, profile),
      ],
    );
  }

  // ==========================================================
  // PATIENT CARD
  // ==========================================================

  // One patient's card in the queue
  Widget _patientCard(
    DoctorAppointment appointment,
    DoctorProfile? profile,
  ) {
    final waiting = appointment.status == AppointmentStatus.waiting; // Is waiting?
    final completed = appointment.status == AppointmentStatus.completed; // Is completed?
    final inConsultation =
        appointment.status == AppointmentStatus.inConsultation; // Is in consultation?

    Color queueBackground = kSoftBlue; // Default queue box color
    Color queueText = const Color(0xFF434654); // Default queue text color

    if (waiting) {
      queueBackground = kPrimary; // Blue box
      queueText = Colors.white; // White text
    } else if (completed) {
      queueBackground = const Color(0xFFDDF5E3); // Light green box
      queueText = Colors.green.shade800; // Green text
    } else if (inConsultation) {
      queueBackground = kSoftTeal; // Light teal box
      queueText = kTeal; // Teal text
    }

    return Container(
      width: double.infinity, // Full width
      margin: const EdgeInsets.only(bottom: 12), // Gap below card
      padding: const EdgeInsets.all(16), // Space inside
      decoration: BoxDecoration(
        color: Colors.white, // White card
        borderRadius: BorderRadius.circular(18), // Round corners
        border: Border.all(
          color: waiting ? kPrimary : kBorder, // Blue border if waiting
          width: waiting ? 1.5 : .7, // Thicker if waiting
        ),
        boxShadow: waiting
            ? [
                BoxShadow(
                  color: kPrimary.withOpacity(.10), // Faint blue shadow
                  blurRadius: 12, // Shadow softness
                  offset: const Offset(0, 4), // Shadow moves down
                ),
              ]
            : null, // No shadow otherwise
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final small = constraints.maxWidth < 650; // Small screen?

          final patientInfo = Row(
            crossAxisAlignment: CrossAxisAlignment.start, // Align to top
            children: [
              Container(
                width: 48, // Queue box width
                height: 48, // Queue box height
                decoration: BoxDecoration(
                  color: queueBackground, // Status color
                  borderRadius: BorderRadius.circular(14), // Round corners
                ),
                child: Center(
                  child: Text(
                    '#${appointment.queueNumber}', // Queue number like #3
                    style: TextStyle(
                      fontSize: 14, // Text size
                      fontWeight: FontWeight.bold, // Bold
                      color: queueText, // Status text color
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 13), // Gap
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, // Align left
                  children: [
                    Wrap(
                      spacing: 7, // Horizontal gap
                      runSpacing: 4, // Vertical gap
                      crossAxisAlignment: WrapCrossAlignment.center, // Center vertically
                      children: [
                        Text(
                          appointment.studentName.isEmpty
                              ? 'Student' // Default name
                              : appointment.studentName, // Real name
                          style: const TextStyle(
                            fontSize: 14, // Name size
                            fontWeight: FontWeight.bold, // Bold
                            color: kText, // Dark
                          ),
                        ),
                        if (appointment.studentId.isNotEmpty)
                          // Show ID badge only if ID exists
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7, // Left/right space
                              vertical: 3, // Top/bottom space
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0F3FF), // Very light blue
                              borderRadius: BorderRadius.circular(5), // Small round corners
                            ),
                            child: Text(
                              'ID: ${appointment.studentId}', // Student ID
                              style: const TextStyle(
                                fontSize: 9, // Tiny text
                                fontWeight: FontWeight.w600, // Semi-bold
                                color: kPrimary, // Blue
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 5), // Gap
                    Text(
                      'Date: ${appointment.dateKey.isEmpty ? "Not set" : appointment.dateKey}' // Date
                      ' • Time: ${appointment.timeSlot.isEmpty ? "Not set" : appointment.timeSlot}', // Time
                      style: const TextStyle(
                        fontSize: 10, // Small text
                        fontWeight: FontWeight.w600, // Semi-bold
                        color: kPrimary, // Blue
                      ),
                    ),
                    const SizedBox(height: 4), // Gap
                    Text(
                      'Dept: ${appointment.studentDept.isEmpty ? "Not set" : appointment.studentDept}' // Department
                      ' • Batch: ${appointment.studentBatch.isEmpty ? "Not set" : appointment.studentBatch}' // Batch
                      ' • ${appointment.studentPhone}', // Phone
                      style: const TextStyle(
                        fontSize: 10, // Small text
                        color: Color(0xFF434654), // Dark grey
                      ),
                    ),
                    const SizedBox(height: 4), // Gap
                    Text(
                      'Complaint: '
                      '"${appointment.reason.isEmpty ? "Not provided" : appointment.reason}"', // Complaint text
                      maxLines: 2, // At most 2 lines
                      overflow: TextOverflow.ellipsis, // Show "..." if too long
                      style: const TextStyle(
                        fontSize: 10, // Small text
                        fontStyle: FontStyle.italic, // Italic
                        color: kMuted, // Grey
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );

          final actions = _patientActions(
            appointment, // This appointment
            profile, // Doctor profile
            compact: small, // Compact layout on small screens
          );

          if (small) {
            // Small screen: info on top, actions below
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start, // Align left
              children: [
                patientInfo, // Info
                const SizedBox(height: 14), // Gap
                actions, // Buttons
              ],
            );
          }

          // Big screen: info on left, actions on right
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center, // Center vertically
            children: [
              Expanded(flex: 2, child: patientInfo), // Info takes more space
              const SizedBox(width: 15), // Gap
              actions, // Buttons
            ],
          );
        },
      ),
    );
  }

  // ==========================================================
  // PATIENT ACTIONS
  // ==========================================================

  // The time, status badge and action button for one patient
  Widget _patientActions(
    DoctorAppointment appointment,
    DoctorProfile? profile, {
    required bool compact,
  }) {
    final completed = appointment.status == AppointmentStatus.completed; // Is completed?
    final inConsultation =
        appointment.status == AppointmentStatus.inConsultation; // Is in consultation?

    final statusAndTime = Row(
      mainAxisSize: MainAxisSize.min, // Only as wide as needed
      children: [
        const Icon(Icons.access_time_rounded, size: 15, color: kPrimary), // Clock icon
        const SizedBox(width: 5), // Gap
        Text(
          appointment.timeSlot.isEmpty
              ? 'Time not set' // Default text
              : appointment.timeSlot, // Real time
          style: const TextStyle(
            fontSize: 11, // Small text
            fontWeight: FontWeight.bold, // Bold
            color: Color(0xFF434654), // Dark grey
          ),
        ),
        const SizedBox(width: 12), // Gap
        _statusBadge(appointment.status), // Status badge
      ],
    );

    Widget button; // Will hold the action button

    if (completed) {
      // Completed: show "View Prescription"
      button = OutlinedButton.icon(
        onPressed: () => viewPrescription(appointment), // Open prescription
        style: OutlinedButton.styleFrom(
          foregroundColor: kTeal, // Teal text
          side: const BorderSide(color: kTeal), // Teal border
          padding: const EdgeInsets.symmetric(
            horizontal: 13, // Left/right space
            vertical: 10, // Top/bottom space
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(11), // Round corners
          ),
        ),
        icon: const Icon(Icons.description_outlined, size: 15), // Document icon
        label: const Text(
          'View Prescription', // Button label
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold), // Small bold
        ),
      );
    } else {
      // Not completed: show Start/Continue button
      button = ElevatedButton.icon(
        onPressed: () => startConsultation(appointment, profile), // Start consultation
        style: ElevatedButton.styleFrom(
          backgroundColor: inConsultation ? kTeal : kPrimary, // Teal if ongoing, else blue
          foregroundColor: Colors.white, // White text
          elevation: 0, // No shadow
          padding: const EdgeInsets.symmetric(
            horizontal: 14, // Left/right space
            vertical: 11, // Top/bottom space
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(11), // Round corners
          ),
        ),
        icon: Icon(
          inConsultation
              ? Icons.medical_services_outlined // Ongoing icon
              : Icons.play_arrow_rounded, // Start icon
          size: 16, // Icon size
        ),
        label: Text(
          inConsultation ? 'Continue Consultation' : 'Start Consultation', // Button label
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold), // Small bold
        ),
      );
    }

    if (compact) {
      // Small screen layout
      return SizedBox(
        width: double.infinity, // Full width
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft, // Align left
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal, // Scroll sideways if too wide
                child: statusAndTime, // Time + badge
              ),
            ),
            const SizedBox(height: 10), // Gap
            SizedBox(width: double.infinity, child: button), // Full-width button
          ],
        ),
      );
    }

    // Big screen layout: time/badge and button in one row
    return Row(
      mainAxisSize: MainAxisSize.min, // Only as wide as needed
      children: [statusAndTime, const SizedBox(width: 12), button], // Time, gap, button
    );
  }

  // ==========================================================
  // STATUS BADGE
  // ==========================================================

  // The small colored status label
  Widget _statusBadge(AppointmentStatus status) {
    String text; // Label text
    Color background; // Badge color
    Color foreground; // Text color

    switch (status) {
      // Choose text and colors by status
      case AppointmentStatus.waiting:
        text = 'Waiting in Queue'; // Label
        background = const Color(0xFFFFF0C2); // Light yellow
        foreground = const Color(0xFF805A00); // Brown
        break;

      case AppointmentStatus.completed:
        text = 'Completed'; // Label
        background = const Color(0xFFDDF5E3); // Light green
        foreground = Colors.green.shade800; // Green
        break;

      case AppointmentStatus.inConsultation:
        text = 'In Consultation'; // Label
        background = kSoftBlue; // Light blue
        foreground = kPrimary; // Blue
        break;

      case AppointmentStatus.upcoming:
        text = 'Upcoming'; // Label
        background = const Color(0xFFF0F0F0); // Light grey
        foreground = const Color(0xFF434654); // Dark grey
        break;

      case AppointmentStatus.cancelled:
        text = 'Cancelled'; // Label
        background = const Color(0xFFFDE2E1); // Light red
        foreground = Colors.red.shade800; // Red
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5), // Space inside
      decoration: BoxDecoration(
        color: background, // Badge color
        borderRadius: BorderRadius.circular(20), // Pill shape
      ),
      child: Text(
        text, // Label text
        style: TextStyle(
          fontSize: 9, // Tiny text
          fontWeight: FontWeight.bold, // Bold
          color: foreground, // Text color
        ),
      ),
    );
  }
}

// ============================================================
// DOCTOR PROFESSIONAL PROFILE FORM
// ============================================================

// The page where the doctor edits their professional profile
class DoctorProfileFormPage extends StatefulWidget {
  final String doctorId; // Doctor's id
  final DoctorProfile? existing; // Current profile (null if new)
  final DoctorRepository repo; // Firestore helper

  const DoctorProfileFormPage({
    super.key, // Optional widget key
    required this.doctorId, // Must be given
    required this.repo, // Must be given
    this.existing, // Optional
  });

  @override
  State<DoctorProfileFormPage> createState() =>
      _DoctorProfileFormPageState(); // Create the state
}

class _DoctorProfileFormPageState extends State<DoctorProfileFormPage> {
  late final TextEditingController nameCtrl; // Full name box
  late final TextEditingController designationCtrl; // Designation box
  late final TextEditingController specializationCtrl; // Specialization box
  late final TextEditingController departmentCtrl; // Department box
  late final TextEditingController bmdcCtrl; // BMDC number box
  late final TextEditingController qualificationsCtrl; // Qualifications box
  late final TextEditingController experienceCtrl; // Experience box
  late final TextEditingController chamberCtrl; // Chamber box
  late final TextEditingController shiftCtrl; // Shift box
  late final TextEditingController phoneCtrl; // Phone box
  late final TextEditingController emailCtrl; // Email box
  late final TextEditingController bioCtrl; // Bio box
  late final TextEditingController photoUrlCtrl; // Photo link box

  bool saving = false; // True while saving

  @override
  void initState() {
    // Runs once when the page opens
    super.initState(); // Flutter's own setup

    final p = widget.existing; // Short name for the existing profile

    nameCtrl = TextEditingController(text: p?.fullName ?? ''); // Fill name
    designationCtrl = TextEditingController(text: p?.designation ?? ''); // Fill designation
    specializationCtrl =
        TextEditingController(text: p?.specialization ?? ''); // Fill specialization
    departmentCtrl = TextEditingController(text: p?.department ?? ''); // Fill department
    bmdcCtrl = TextEditingController(text: p?.bmdcRegNo ?? ''); // Fill BMDC
    qualificationsCtrl = TextEditingController(
      text: (p?.qualifications ?? []).join(', '), // List -> "MBBS, MD"
    );
    experienceCtrl = TextEditingController(
      text: p != null && p.experienceYears > 0
          ? '${p.experienceYears}' // Show years
          : '', // Empty if 0
    );
    chamberCtrl = TextEditingController(text: p?.chamber ?? ''); // Fill chamber
    shiftCtrl = TextEditingController(text: p?.shift ?? ''); // Fill shift
    phoneCtrl = TextEditingController(text: p?.phone ?? ''); // Fill phone
    emailCtrl = TextEditingController(text: p?.email ?? ''); // Fill email
    bioCtrl = TextEditingController(text: p?.bio ?? ''); // Fill bio
    photoUrlCtrl = TextEditingController(text: p?.photoUrl ?? ''); // Fill photo link
  }

  @override
  void dispose() {
    // Runs when the page closes: free memory
    nameCtrl.dispose();
    designationCtrl.dispose();
    specializationCtrl.dispose();
    departmentCtrl.dispose();
    bmdcCtrl.dispose();
    qualificationsCtrl.dispose();
    experienceCtrl.dispose();
    chamberCtrl.dispose();
    shiftCtrl.dispose();
    phoneCtrl.dispose();
    emailCtrl.dispose();
    bioCtrl.dispose();
    photoUrlCtrl.dispose();

    super.dispose(); // Flutter's own cleanup
  }

  // Validates and saves the profile
  Future<void> save() async {
    if (nameCtrl.text.trim().isEmpty ||
        specializationCtrl.text.trim().isEmpty ||
        departmentCtrl.text.trim().isEmpty) {
      // A required field is empty
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Name, specialization and department are required.'), // Warning
        ),
      );

      return; // Stop here
    }

    setState(() => saving = true); // Show "Saving..."

    final profile = DoctorProfile(
      id: widget.doctorId, // Doctor id
      fullName: nameCtrl.text.trim(), // Name
      designation: designationCtrl.text.trim(), // Designation
      specialization: specializationCtrl.text.trim(), // Specialization
      department: departmentCtrl.text.trim(), // Department
      bmdcRegNo: bmdcCtrl.text.trim(), // BMDC number
      qualifications: qualificationsCtrl.text
          .split(',') // Split at commas
          .map((q) => q.trim()) // Remove spaces
          .where((q) => q.isNotEmpty) // Skip empty
          .toList(), // Make a list
      experienceYears: int.tryParse(experienceCtrl.text.trim()) ?? 0, // Text -> number
      chamber: chamberCtrl.text.trim(), // Chamber
      shift: shiftCtrl.text.trim(), // Shift
      phone: phoneCtrl.text.trim(), // Phone
      email: emailCtrl.text.trim(), // Email
      bio: bioCtrl.text.trim(), // Bio
      photoUrl: photoUrlCtrl.text.trim(), // Photo link
    );

    try {
      await widget.repo.saveProfile(profile); // Save to Firestore

      if (!mounted) return; // Page closed? stop

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Professional profile saved.')), // Success message
      );

      Navigator.pop(context); // Close this page
    } catch (e) {
      if (!mounted) return; // Page closed? stop

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save: $e')), // Error message
      );
    } finally {
      // Always runs
      if (mounted) {
        setState(() => saving = false); // Stop "Saving..."
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kPage, // Page background
      appBar: AppBar(
        backgroundColor: kPrimary, // Blue bar
        foregroundColor: Colors.white, // White text
        title: const Text(
          'Professional Profile', // Bar title
          style: TextStyle(fontWeight: FontWeight.bold), // Bold
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20), // Space around
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700), // Limit width
              child: Container(
                padding: const EdgeInsets.all(18), // Space inside
                decoration: cardDecoration(), // Card look
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, // Align left
                  children: [
                    const Text(
                      'Your details', // Form title
                      style: TextStyle(
                        fontSize: 15, // Text size
                        fontWeight: FontWeight.bold, // Bold
                        color: kText, // Dark
                      ),
                    ),
                    const SizedBox(height: 4), // Gap
                    const Text(
                      'This information is shown on your dashboard and on prescriptions.', // Info
                      style: TextStyle(fontSize: 11, color: kMuted), // Small grey
                    ),
                    const SizedBox(height: 16), // Gap
                    TextField(
                      controller: nameCtrl, // Connected to name controller
                      decoration: inputDecoration(
                        'Full Name', // Label
                        hint: 'e.g. Rahat Khan', // Example
                      ),
                    ),
                    const SizedBox(height: 10), // Gap
                    TextField(
                      controller: designationCtrl, // Connected to designation controller
                      decoration: inputDecoration(
                        'Designation', // Label
                        hint: 'e.g. Assistant Professor', // Example
                      ),
                    ),
                    const SizedBox(height: 10), // Gap
                    TextField(
                      controller: specializationCtrl, // Connected to specialization controller
                      decoration: inputDecoration(
                        'Specialization', // Label
                        hint: 'e.g. Medicine, Cardiology', // Example
                      ),
                    ),
                    const SizedBox(height: 10), // Gap
                    TextField(
                      controller: departmentCtrl, // Connected to department controller
                      decoration: inputDecoration(
                        'Department', // Label
                        hint: 'e.g. Medicine', // Example
                      ),
                    ),
                    const SizedBox(height: 10), // Gap
                    TextField(
                      controller: bmdcCtrl, // Connected to BMDC controller
                      decoration: inputDecoration(
                        'BMDC Registration No.', // Label
                        hint: 'e.g. A-12345', // Example
                      ),
                    ),
                    const SizedBox(height: 10), // Gap
                    TextField(
                      controller: qualificationsCtrl, // Connected to qualifications controller
                      decoration: inputDecoration(
                        'Qualifications (comma separated)', // Label
                        hint: 'MBBS, MD, FCPS', // Example
                      ),
                    ),
                    const SizedBox(height: 10), // Gap
                    TextField(
                      controller: experienceCtrl, // Connected to experience controller
                      keyboardType: TextInputType.number, // Number keyboard
                      decoration: inputDecoration(
                        'Years of Experience', // Label
                        hint: 'e.g. 8', // Example
                      ),
                    ),
                    const SizedBox(height: 10), // Gap
                    TextField(
                      controller: chamberCtrl, // Connected to chamber controller
                      decoration: inputDecoration(
                        'Duty Chamber / Room', // Label
                        hint: 'e.g. Chamber 02', // Example
                      ),
                    ),
                    const SizedBox(height: 10), // Gap
                    TextField(
                      controller: shiftCtrl, // Connected to shift controller
                      decoration: inputDecoration(
                        'Duty Shift', // Label
                        hint: 'e.g. 10:00 AM - 04:00 PM', // Example
                      ),
                    ),
                    const SizedBox(height: 10), // Gap
                    TextField(
                      controller: phoneCtrl, // Connected to phone controller
                      decoration: inputDecoration('Contact Phone'), // Label
                    ),
                    const SizedBox(height: 10), // Gap
                    TextField(
                      controller: emailCtrl, // Connected to email controller
                      decoration: inputDecoration('Contact Email'), // Label
                    ),
                    const SizedBox(height: 10), // Gap
                    TextField(
                      controller: photoUrlCtrl, // Connected to photo controller
                      decoration: inputDecoration(
                        'Photo URL', // Label
                        hint: 'link to a profile photo (optional)', // Example
                      ),
                    ),
                    const SizedBox(height: 10), // Gap
                    TextField(
                      controller: bioCtrl, // Connected to bio controller
                      maxLines: 4, // 4 lines tall
                      decoration: inputDecoration(
                        'Short Bio', // Label
                        hint: 'A short professional summary', // Example
                      ),
                    ),
                    const SizedBox(height: 18), // Gap
                    SizedBox(
                      width: double.infinity, // Full width button
                      child: ElevatedButton.icon(
                        onPressed: saving ? null : save, // Disabled while saving
                        icon: saving
                            ? const SizedBox(
                                width: 16, // Spinner width
                                height: 16, // Spinner height
                                child: CircularProgressIndicator(
                                  strokeWidth: 2, // Thin line
                                  color: Colors.white, // White spinner
                                ),
                              )
                            : const Icon(Icons.save_outlined), // Save icon
                        label: Text(saving ? 'Saving...' : 'Save Profile'), // Button label
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPrimary, // Blue
                          foregroundColor: Colors.white, // White text
                          padding:
                              const EdgeInsets.symmetric(vertical: 14), // Button height
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12), // Round corners
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// ADD MEDICINE DIALOG
// ============================================================

// The popup used to add one medicine
class _AddMedicineDialog extends StatefulWidget {
  const _AddMedicineDialog();

  @override
  State<_AddMedicineDialog> createState() => _AddMedicineDialogState(); // Create the state
}

class _AddMedicineDialogState extends State<_AddMedicineDialog> {
  final nameController = TextEditingController(); // Medicine name box
  final dosageController = TextEditingController(); // Dosage box
  final frequencyController = TextEditingController(); // Frequency box
  final durationController = TextEditingController(); // Duration box

  String timing = 'After Meal'; // Selected timing (default)

  String? nameError; // Error text for the name box

  @override
  void dispose() {
    // Free memory when the dialog closes
    nameController.dispose();
    dosageController.dispose();
    frequencyController.dispose();
    durationController.dispose();

    super.dispose(); // Flutter's own cleanup
  }

  // Checks the input and returns the new medicine
  void _submit() {
    final name = nameController.text.trim(); // Typed medicine name

    if (name.isEmpty) {
      // Name is required
      setState(() => nameError = 'Medicine name is required'); // Show error
      return; // Stop here
    }

    Navigator.of(context).pop(
      // Close the dialog and send back the medicine
      PrescriptionItem(
        medicineName: name, // Name
        dosage: dosageController.text.trim(), // Dosage
        frequency: frequencyController.text.trim(), // Frequency
        duration: durationController.text.trim(), // Duration
        timing: timing, // Timing
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20), // Round dialog corners
      ),
      title: const Text(
        'Add Medicine', // Dialog title
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold), // Big bold
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min, // Only as tall as needed
          children: [
            TextField(
              controller: nameController, // Connected to name controller
              autofocus: true, // Open keyboard immediately
              textCapitalization: TextCapitalization.words, // Capitalize each word
              decoration: inputDecoration(
                'Medicine name', // Label
                hint: 'e.g. Paracetamol 500mg', // Example
              ).copyWith(errorText: nameError), // Add error text if any
              onChanged: (_) {
                // Runs on every typed letter
                if (nameError != null) {
                  setState(() => nameError = null); // Clear the error
                }
              },
            ),
            const SizedBox(height: 10), // Gap
            TextField(
              controller: dosageController, // Connected to dosage controller
              decoration: inputDecoration('Dosage', hint: 'e.g. 500mg'), // Label + example
            ),
            const SizedBox(height: 10), // Gap
            TextField(
              controller: frequencyController, // Connected to frequency controller
              decoration:
                  inputDecoration('Frequency', hint: 'e.g. 1+0+1'), // Label + example
            ),
            const SizedBox(height: 10), // Gap
            TextField(
              controller: durationController, // Connected to duration controller
              decoration:
                  inputDecoration('Duration', hint: 'e.g. 3 days'), // Label + example
            ),
            const SizedBox(height: 10), // Gap
            DropdownButtonFormField<String>(
              value: timing, // Currently selected value
              decoration: inputDecoration('Timing'), // Label
              items: const [
                DropdownMenuItem(
                  value: 'After Meal', // Option value
                  child: Text('After Meal'), // Option text
                ),
                DropdownMenuItem(
                  value: 'Before Meal', // Option value
                  child: Text('Before Meal'), // Option text
                ),
                DropdownMenuItem(
                  value: 'With Meal', // Option value
                  child: Text('With Meal'), // Option text
                ),
              ],
              onChanged: (value) {
                // Runs when user picks an option
                if (value != null) {
                  setState(() => timing = value); // Save the choice
                }
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(), // Close without result
          child: const Text('Cancel'), // Button label
        ),
        ElevatedButton.icon(
          onPressed: _submit, // Validate and add
          icon: const Icon(Icons.add, size: 17), // Plus icon
          label: const Text('Add Medicine'), // Button label
          style: ElevatedButton.styleFrom(
            backgroundColor: kPrimary, // Blue
            foregroundColor: Colors.white, // White text
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10), // Round corners
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// CONSULTATION PAGE
//
// The doctor fills the full clinical record here (symptoms, vitals,
// diagnosis, treatment advice, follow-up, prescription items). Both
// "Save Draft" and "Complete Consultation" write the SAME
// appointment document, re-stamping the doctor's info every time so
// it can never go stale even if the doctor edited their profile
// mid-consultation.
// ============================================================

// The page where the doctor examines the patient and writes the prescription
class ConsultationPage extends StatefulWidget {
  final DoctorAppointment appointment; // The appointment being handled
  final DoctorRepository repo; // Firestore helper
  final DoctorProfile? doctorProfile; // The doctor's profile (can be null)

  const ConsultationPage({
    super.key, // Optional widget key
    required this.appointment, // Must be given
    required this.repo, // Must be given
    this.doctorProfile, // Optional
  });

  @override
  State<ConsultationPage> createState() => _ConsultationPageState(); // Create the state
}

class _ConsultationPageState extends State<ConsultationPage> {
  late final TextEditingController symptomsController; // Symptoms box
  late final TextEditingController diagnosisController; // Diagnosis box
  late final TextEditingController treatmentController; // Treatment advice box
  late final TextEditingController bpController; // Blood pressure box
  late final TextEditingController tempController; // Temperature box
  late final TextEditingController pulseController; // Pulse box

  DateTime? followUpDate; // Chosen follow-up date (null = none)

  late List<PrescriptionItem> prescriptions; // Medicines list being edited

  bool saving = false; // True while saving

  @override
  void initState() {
    // Runs once when the page opens
    super.initState(); // Flutter's own setup

    final a = widget.appointment; // Short name for the appointment

    symptomsController = TextEditingController(
      text: a.symptoms.isEmpty ? a.reason : a.symptoms, // Use complaint if no symptoms yet
    );
    diagnosisController = TextEditingController(text: a.diagnosis); // Fill diagnosis
    treatmentController = TextEditingController(text: a.treatmentAdvice); // Fill advice
    bpController = TextEditingController(text: a.bloodPressure); // Fill BP
    tempController = TextEditingController(text: a.temperature); // Fill temperature
    pulseController = TextEditingController(text: a.pulseRate); // Fill pulse

    prescriptions = List<PrescriptionItem>.from(a.prescriptions); // Copy existing medicines

    if (a.followUpDate.isNotEmpty) {
      // A follow-up date was saved before?
      followUpDate = DateTime.tryParse(a.followUpDate); // Convert text to date
    }
  }

  @override
  void dispose() {
    // Free memory when the page closes
    symptomsController.dispose();
    diagnosisController.dispose();
    treatmentController.dispose();
    bpController.dispose();
    tempController.dispose();
    pulseController.dispose();

    super.dispose(); // Flutter's own cleanup
  }

  // Opens the dialog and adds the new medicine to the list
  Future<void> addMedicine() async {
    final item = await showDialog<PrescriptionItem>(
      context: context, // Current screen
      barrierDismissible: true, // Tap outside to close
      builder: (_) => const _AddMedicineDialog(), // Show the dialog
    );

    if (!mounted || item == null) {
      // Page closed or user cancelled
      return; // Do nothing
    }

    setState(() => prescriptions.add(item)); // Add medicine and refresh
  }

  // Opens a calendar to choose the follow-up date
  Future<void> chooseFollowUpDate() async {
    final now = DateTime.now(); // Current time

    final selected = await showDatePicker(
      context: context, // Current screen
      firstDate: now, // Cannot pick the past
      lastDate: now.add(const Duration(days: 365)), // Up to 1 year ahead
      initialDate: followUpDate ?? now, // Start on saved date or today
    );

    if (selected != null) {
      // User picked a date
      setState(() => followUpDate = selected); // Save it
    }
  }

  // Saves the consultation (as draft, or completed if complete = true)
  Future<void> saveConsultation({required bool complete}) async {
    // A completed consultation must have at least one prescription
    // item OR a diagnosis — otherwise the student dashboard would show
    // an "empty" prescription, which is almost always a mistake.
    if (complete &&
        prescriptions.isEmpty &&
        diagnosisController.text.trim().isEmpty) {
      // Completing with no medicine and no diagnosis: ask first
      final proceed = await showDialog<bool>(
        context: context, // Current screen
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16), // Round corners
          ),
          title: const Text('No diagnosis or medicine added'), // Dialog title
          content: const Text(
            'You are about to complete this consultation without a '
            'diagnosis or any prescribed medicine. Continue anyway?', // Warning text
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false), // Answer: no
              child: const Text('Go back'), // Button label
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true), // Answer: yes
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimary, // Blue
                foregroundColor: Colors.white, // White text
              ),
              child: const Text('Complete anyway'), // Button label
            ),
          ],
        ),
      );

      if (proceed != true) {
        // User did not confirm
        return; // Stop here
      }
    }

    setState(() => saving = true); // Show the spinner

    final followUpStr = followUpDate == null
        ? '' // No date chosen
        : '${followUpDate!.year.toString().padLeft(4, '0')}-' // Year
            '${followUpDate!.month.toString().padLeft(2, '0')}-' // Month
            '${followUpDate!.day.toString().padLeft(2, '0')}'; // Day

    final profile = widget.doctorProfile; // Short name for the profile

    final updated = widget.appointment.copyWith(
      symptoms: symptomsController.text.trim(), // Symptoms text
      diagnosis: diagnosisController.text.trim(), // Diagnosis text
      treatmentAdvice: treatmentController.text.trim(), // Advice text
      bloodPressure: bpController.text.trim(), // BP text
      temperature: tempController.text.trim(), // Temperature text
      pulseRate: pulseController.text.trim(), // Pulse text
      followUpDate: followUpStr, // Follow-up date text
      prescriptions: List<PrescriptionItem>.from(prescriptions), // Copy of medicines
      status: complete
          ? AppointmentStatus.completed // Finished
          : AppointmentStatus.inConsultation, // Still ongoing (draft)
      // Re-stamp doctor info every save so the final prescription
      // record always carries accurate attribution, even if this
      // page was opened with a stale/null profile.
      doctorName: profile?.fullName ?? widget.appointment.doctorName, // Doctor name
      doctorDesignation:
          profile?.designation ?? widget.appointment.doctorDesignation, // Doctor title
      doctorSpecialization: profile?.specialization ??
          widget.appointment.doctorSpecialization, // Doctor specialty
      doctorDepartment:
          profile?.department ?? widget.appointment.doctorDepartment, // Doctor dept
      doctorChamber: profile?.chamber ?? widget.appointment.doctorChamber, // Doctor room
    );

    try {
      await widget.repo.updateAppointment(updated); // Save to Firestore

      if (!mounted) return; // Page closed? stop

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            complete
                ? 'Consultation completed and prescription issued.' // Completed message
                : 'Consultation saved as draft.', // Draft message
          ),
          behavior: SnackBarBehavior.floating, // Floating style
        ),
      );

      if (complete) {
        // Finished: leave the page
        Navigator.pop(context); // Go back
      }
    } catch (e) {
      if (!mounted) return; // Page closed? stop

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save: $e')), // Error message
      );
    } finally {
      // Always runs
      if (mounted) {
        setState(() => saving = false); // Hide the spinner
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.appointment; // Short name for the appointment

    return Scaffold(
      backgroundColor: kPage, // Page background
      appBar: AppBar(
        backgroundColor: kPrimary, // Blue bar
        foregroundColor: Colors.white, // White text
        title: const Text(
          'Clinical Consultation', // Bar title
          style: TextStyle(fontWeight: FontWeight.bold), // Bold
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20), // Space around
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 850), // Limit width
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, // Align left
                children: [
                  _patientHeader(a), // Patient info card
                  const SizedBox(height: 16), // Gap
                  _section(
                    title: 'Patient Complaint', // Section title
                    child: _readOnlyBox(
                      a.reason.isEmpty
                          ? 'No complaint provided.' // Default text
                          : a.reason, // Student's complaint
                    ),
                  ),
                  _section(
                    title: "Today's Chamber Vitals", // Section title
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final small = constraints.maxWidth < 600; // Small screen?

                        final fields = [
                          TextField(
                            controller: bpController, // BP box
                            decoration:
                                inputDecoration('Blood Pressure'), // Label
                          ),
                          TextField(
                            controller: tempController, // Temperature box
                            decoration:
                                inputDecoration('Body Temperature'), // Label
                          ),
                          TextField(
                            controller: pulseController, // Pulse box
                            decoration: inputDecoration('Pulse Rate'), // Label
                          ),
                        ];

                        if (small) {
                          // Small screen: stack fields vertically
                          return Column(
                            children: [
                              for (int i = 0; i < fields.length; i++) ...[
                                fields[i], // Show the field
                                if (i != fields.length - 1)
                                  const SizedBox(height: 10), // Gap between fields
                              ],
                            ],
                          );
                        }

                        // Big screen: fields side by side
                        return Row(
                          children: [
                            for (int i = 0; i < fields.length; i++) ...[
                              Expanded(child: fields[i]), // Equal width
                              if (i != fields.length - 1)
                                const SizedBox(width: 10), // Gap between fields
                            ],
                          ],
                        );
                      },
                    ),
                  ),
                  _section(
                    title: 'Clinical Symptoms & Physical Findings', // Section title
                    child: TextField(
                      controller: symptomsController, // Symptoms box
                      maxLines: 4, // 4 lines tall
                      decoration: inputDecoration(
                        '', // No label
                        hint: 'Record physical observations...', // Hint
                      ),
                    ),
                  ),
                  _section(
                    title: 'Definitive / Working Diagnosis', // Section title
                    child: TextField(
                      controller: diagnosisController, // Diagnosis box
                      maxLines: 4, // 4 lines tall
                      decoration: inputDecoration(
                        '', // No label
                        hint: 'Enter diagnosis...', // Hint
                      ),
                    ),
                  ),
                  _prescriptionSection(), // Medicine list section
                  _section(
                    title: 'Treatment Advice & Follow-Up', // Section title
                    child: TextField(
                      controller: treatmentController, // Advice box
                      maxLines: 4, // 4 lines tall
                      decoration: inputDecoration(
                        '', // No label
                        hint: 'Hydration, rest, precautions, tests...', // Hint
                      ),
                    ),
                  ),
                  _section(
                    title: 'Recommended Follow-Up Date', // Section title
                    child: InkWell(
                      onTap: chooseFollowUpDate, // Tap to open calendar
                      borderRadius: BorderRadius.circular(12), // Round ripple
                      child: InputDecorator(
                        decoration: inputDecoration('Follow-up date'), // Field look
                        child: Text(
                          followUpDate == null
                              ? 'Optional' // No date chosen
                              : '${followUpDate!.day.toString().padLeft(2, '0')}/' // Day
                                  '${followUpDate!.month.toString().padLeft(2, '0')}/' // Month
                                  '${followUpDate!.year}', // Year
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 5), // Gap
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final draftBtn = OutlinedButton.icon(
                        onPressed: saving
                            ? null // Disabled while saving
                            : () => saveConsultation(complete: false), // Save as draft
                        icon: const Icon(Icons.save_outlined), // Save icon
                        label: const Text('Save Draft'), // Button label
                        style: OutlinedButton.styleFrom(
                          foregroundColor: kTeal, // Teal text
                          side: const BorderSide(color: kTeal), // Teal border
                          padding:
                              const EdgeInsets.symmetric(vertical: 14), // Button height
                        ),
                      );

                      final completeBtn = ElevatedButton.icon(
                        onPressed: saving
                            ? null // Disabled while saving
                            : () => saveConsultation(complete: true), // Complete and issue Rx
                        icon: saving
                            ? const SizedBox(
                                width: 16, // Spinner width
                                height: 16, // Spinner height
                                child: CircularProgressIndicator(
                                  strokeWidth: 2, // Thin line
                                  color: Colors.white, // White spinner
                                ),
                              )
                            : const Icon(Icons.check_circle_outline), // Check icon
                        label: const Text(
                          'Complete Consultation & Issue Rx', // Button label
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPrimary, // Blue
                          foregroundColor: Colors.white, // White text
                          padding:
                              const EdgeInsets.symmetric(vertical: 14), // Button height
                        ),
                      );

                      if (constraints.maxWidth < 600) {
                        // Small screen: buttons stacked
                        return Column(
                          children: [
                            SizedBox(
                              width: double.infinity, // Full width
                              child: draftBtn, // Draft button
                            ),
                            const SizedBox(height: 10), // Gap
                            SizedBox(
                              width: double.infinity, // Full width
                              child: completeBtn, // Complete button
                            ),
                          ],
                        );
                      }

                      // Big screen: buttons side by side
                      return Row(
                        children: [
                          Expanded(child: draftBtn), // Draft takes 1 part
                          const SizedBox(width: 12), // Gap
                          Expanded(flex: 2, child: completeBtn), // Complete takes 2 parts
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // The card at the top showing the patient's details
  Widget _patientHeader(DoctorAppointment a) {
    return Container(
      padding: const EdgeInsets.all(18), // Space inside
      decoration: cardDecoration(), // Card look
      child: Row(
        children: [
          Container(
            width: 54, // Icon box width
            height: 54, // Icon box height
            decoration: BoxDecoration(
              color: kSoftBlue, // Light blue
              borderRadius: BorderRadius.circular(15), // Round corners
            ),
            child: const Icon(Icons.person, color: kPrimary), // Person icon
          ),
          const SizedBox(width: 13), // Gap
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, // Align left
              children: [
                Text(
                  a.studentName.isEmpty ? 'Student' : a.studentName, // Name or default
                  style: const TextStyle(
                    fontSize: 18, // Big text
                    fontWeight: FontWeight.bold, // Bold
                    color: kText, // Dark
                  ),
                ),
                const SizedBox(height: 4), // Gap
                Text(
                  'ID: ${a.studentId} • ' // Student id
                  '${a.studentDept} • ' // Department
                  "Batch '${a.studentBatch} • " // Batch
                  '${a.studentPhone}', // Phone
                  style: const TextStyle(fontSize: 11, color: kMuted), // Small grey
                ),
                const SizedBox(height: 4), // Gap
                Text(
                  'Appointment: ${a.dateKey} • ${a.timeSlot}', // Date and time
                  style: const TextStyle(
                    fontSize: 11, // Small text
                    fontWeight: FontWeight.w600, // Semi-bold
                    color: kPrimary, // Blue
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // The medicine (Rx) section with list and "Add" button
  Widget _prescriptionSection() {
    return _section(
      title: 'Medication Prescription (Rx)', // Section title
      child: Column(
        children: [
          if (prescriptions.isEmpty)
            _readOnlyBox('No medicines prescribed yet.') // Empty message
          else
            for (int i = 0; i < prescriptions.length; i++)
              // One box per medicine
              Container(
                margin: const EdgeInsets.only(bottom: 8), // Gap below
                padding: const EdgeInsets.all(12), // Space inside
                decoration: BoxDecoration(
                  color: const Color(0xFFF9F9FF), // Very light fill
                  borderRadius: BorderRadius.circular(12), // Round corners
                  border: Border.all(color: kBorder.withOpacity(.6)), // Soft border
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.medication_outlined, // Medicine icon
                      color: kPrimary, // Blue
                    ),
                    const SizedBox(width: 10), // Gap
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start, // Align left
                        children: [
                          Text(
                            prescriptions[i].medicineName, // Medicine name
                            style: const TextStyle(
                              fontSize: 12, // Text size
                              fontWeight: FontWeight.bold, // Bold
                            ),
                          ),
                          const SizedBox(height: 3), // Tiny gap
                          Text(
                            '${prescriptions[i].dosage} • ' // Dosage
                            '${prescriptions[i].frequency} • ' // Frequency
                            '${prescriptions[i].duration} • ' // Duration
                            '${prescriptions[i].timing}', // Timing
                            style: const TextStyle(
                              fontSize: 10, // Small text
                              color: kTeal, // Teal
                              fontWeight: FontWeight.w600, // Semi-bold
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove', // Hover text
                      onPressed: () =>
                          setState(() => prescriptions.removeAt(i)), // Delete this medicine
                      icon: const Icon(
                        Icons.delete_outline, // Trash icon
                        color: Colors.red, // Red
                        size: 19, // Icon size
                      ),
                    ),
                  ],
                ),
              ),
          const SizedBox(height: 4), // Gap
          SizedBox(
            width: double.infinity, // Full width
            child: OutlinedButton.icon(
              onPressed: addMedicine, // Open the add dialog
              icon: const Icon(Icons.add), // Plus icon
              label: const Text('Add New Medicine'), // Button label
              style: OutlinedButton.styleFrom(
                foregroundColor: kPrimary, // Blue text
                side: const BorderSide(color: kPrimary), // Blue border
              ),
            ),
          ),
        ],
      ),
    );
  }

  // A titled white card used for each form section
  Widget _section({required String title, required Widget child}) {
    return Container(
      width: double.infinity, // Full width
      margin: const EdgeInsets.only(bottom: 14), // Gap below
      padding: const EdgeInsets.all(16), // Space inside
      decoration: cardDecoration(), // Card look
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, // Align left
        children: [
          Text(
            title, // Section title
            style: const TextStyle(
              fontSize: 12, // Small text
              fontWeight: FontWeight.bold, // Bold
              color: kText, // Dark
            ),
          ),
          const SizedBox(height: 9), // Gap
          child, // The section content
        ],
      ),
    );
  }

  // A grey box that shows read-only text
  Widget _readOnlyBox(String text) {
    return Container(
      width: double.infinity, // Full width
      padding: const EdgeInsets.all(12), // Space inside
      decoration: BoxDecoration(
        color: const Color(0xFFF9F9FF), // Very light fill
        borderRadius: BorderRadius.circular(12), // Round corners
        border: Border.all(color: kBorder.withOpacity(.5)), // Soft border
      ),
      child: Text(
        text, // The text to show
        style: const TextStyle(fontSize: 11, color: kText, height: 1.5), // Small dark text
      ),
    );
  }
}

// ============================================================
// PRESCRIPTION PAGE
//
// This is what both the doctor and the STUDENT should be shown once
// an appointment is completed. It now displays who prescribed it
// (doctorName / designation / specialization), read straight off the
// appointment document — the same fields your student-side dashboard
// query should render.
// ============================================================

// Shows the final prescription (read-only)
class PrescriptionPage extends StatelessWidget {
  final DoctorAppointment appointment; // The completed appointment

  const PrescriptionPage({
    super.key, // Optional widget key
    required this.appointment, // Must be given
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kPage, // Page background
      appBar: AppBar(
        backgroundColor: kPrimary, // Blue bar
        foregroundColor: Colors.white, // White text
        title: const Text(
          'Prescription', // Bar title
          style: TextStyle(fontWeight: FontWeight.bold), // Bold
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20), // Space around
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700), // Limit width
            child: Container(
              padding: const EdgeInsets.all(22), // Space inside
              decoration: BoxDecoration(
                color: Colors.white, // White paper
                borderRadius: BorderRadius.circular(20), // Round corners
                border: Border.all(color: kBorder), // Grey border
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, // Align left
                children: [
                  const Text(
                    'CUET SmartCare', // App name
                    style: TextStyle(
                      fontSize: 22, // Big text
                      fontWeight: FontWeight.bold, // Bold
                      color: kPrimary, // Blue
                    ),
                  ),
                  const Text(
                    'Medical Center Prescription', // Subtitle
                    style: TextStyle(fontSize: 12, color: kMuted), // Small grey
                  ),

                  const SizedBox(height: 14), // Gap

                  // Prescribing doctor — the piece that was missing
                  // before: student dashboards read this straight off
                  // the appointment document.
                  Container(
                    width: double.infinity, // Full width
                    padding: const EdgeInsets.all(12), // Space inside
                    decoration: BoxDecoration(
                      color: kSoftBlue, // Light blue
                      borderRadius: BorderRadius.circular(12), // Round corners
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.medical_services_rounded, // Doctor icon
                          color: kPrimary, // Blue
                          size: 20, // Icon size
                        ),
                        const SizedBox(width: 10), // Gap
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start, // Align left
                            children: [
                              Text(
                                appointment.doctorName.isEmpty
                                    ? 'Attending Doctor' // Default text
                                    : 'Dr. ${appointment.doctorName}', // Doctor's name
                                style: const TextStyle(
                                  fontSize: 13, // Text size
                                  fontWeight: FontWeight.bold, // Bold
                                  color: kPrimary, // Blue
                                ),
                              ),
                              if (appointment.doctorDesignation
                                      .isNotEmpty ||
                                  appointment.doctorSpecialization
                                      .isNotEmpty)
                                // Show only if title or specialty exists
                                Text(
                                  [
                                    appointment.doctorDesignation, // Title
                                    appointment.doctorSpecialization, // Specialty
                                  ].where((s) => s.isNotEmpty).join(' • '), // Join non-empty with " • "
                                  style: const TextStyle(
                                    fontSize: 10, // Small text
                                    color: kMuted, // Grey
                                  ),
                                ),
                              if (appointment.doctorChamber.isNotEmpty)
                                // Show chamber only if it exists
                                Text(
                                  'Chamber: ${appointment.doctorChamber}', // Chamber text
                                  style: const TextStyle(
                                    fontSize: 10, // Small text
                                    color: kMuted, // Grey
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Divider(height: 30), // Horizontal line
                  Text(
                    appointment.studentName, // Student's name
                    style: const TextStyle(
                      fontSize: 18, // Big text
                      fontWeight: FontWeight.bold, // Bold
                    ),
                  ),
                  const SizedBox(height: 5), // Gap
                  Text(
                    'Student ID: '
                    '${appointment.studentId} • ' // Student id
                    '${appointment.studentDept}', // Department
                    style: const TextStyle(fontSize: 12, color: kMuted), // Small grey
                  ),
                  const SizedBox(height: 20), // Gap
                  _labelValue(
                    'Diagnosis', // Label
                    appointment.diagnosis.isEmpty
                        ? 'Not recorded' // Default text
                        : appointment.diagnosis, // Diagnosis text
                  ),
                  const SizedBox(height: 16), // Gap
                  const Text(
                    'Prescription', // Section label
                    style: TextStyle(
                      fontSize: 12, // Small text
                      fontWeight: FontWeight.bold, // Bold
                      color: kPrimary, // Blue
                    ),
                  ),
                  const SizedBox(height: 8), // Gap
                  if (appointment.prescriptions.isEmpty)
                    _rxBox('No prescription items recorded.') // Empty message
                  else
                    for (
                      int i = 0;
                      i < appointment.prescriptions.length;
                      i++
                    )
                      // One box per medicine
                      _rxBox(
                        '${i + 1}. ' // Number (1, 2, 3...)
                        '${appointment.prescriptions[i].medicineName}\n' // Name
                        '${appointment.prescriptions[i].dosage} • ' // Dosage
                        '${appointment.prescriptions[i].frequency} • ' // Frequency
                        '${appointment.prescriptions[i].duration} • ' // Duration
                        '${appointment.prescriptions[i].timing}', // Timing
                      ),
                  if (appointment.treatmentAdvice.isNotEmpty) ...[
                    // Show advice only if it exists
                    const SizedBox(height: 18), // Gap
                    _labelValue(
                      'Treatment Advice', // Label
                      appointment.treatmentAdvice, // Advice text
                    ),
                  ],
                  if (appointment.followUpDate.isNotEmpty) ...[
                    // Show follow-up only if it exists
                    const SizedBox(height: 18), // Gap
                    _labelValue('Follow-Up', appointment.followUpDate), // Follow-up date
                  ],
                  const SizedBox(height: 18), // Gap
                  _labelValue(
                    'Vitals', // Label
                    'BP: ${appointment.bloodPressure.isEmpty ? "Not recorded" : appointment.bloodPressure}\n' // Blood pressure
                    'Temperature: ${appointment.temperature.isEmpty ? "Not recorded" : appointment.temperature}\n' // Temperature
                    'Pulse: ${appointment.pulseRate.isEmpty ? "Not recorded" : appointment.pulseRate}', // Pulse
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // A blue label with its value text below
  Widget _labelValue(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start, // Align left
      children: [
        Text(
          label, // The label
          style: const TextStyle(
            fontSize: 12, // Small text
            fontWeight: FontWeight.bold, // Bold
            color: kPrimary, // Blue
          ),
        ),
        const SizedBox(height: 5), // Gap
        Text(value, style: const TextStyle(fontSize: 13, height: 1.5)), // The value text
      ],
    );
  }

  // A light box that holds one medicine line
  Widget _rxBox(String text) {
    return Container(
      width: double.infinity, // Full width
      margin: const EdgeInsets.only(bottom: 7), // Gap below
      padding: const EdgeInsets.all(12), // Space inside
      decoration: BoxDecoration(
        color: const Color(0xFFF9F9FF), // Very light fill
        borderRadius: BorderRadius.circular(12), // Round corners
      ),
      child: Text(text, style: const TextStyle(fontSize: 12, height: 1.6)), // The text
    );
  }
}

// ============================================================
// HEALTH RECORDS PAGE
// ============================================================

// Lists every completed consultation of this doctor
class HealthRecordsPage extends StatelessWidget {
  final String doctorId; // Doctor's id
  final DoctorRepository repo; // Firestore helper

  const HealthRecordsPage({
    super.key, // Optional widget key
    required this.doctorId, // Must be given
    required this.repo, // Must be given
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kPage, // Page background
      appBar: AppBar(
        backgroundColor: kPrimary, // Blue bar
        foregroundColor: Colors.white, // White text
        title: const Text(
          'Health Records', // Bar title
          style: TextStyle(fontWeight: FontWeight.bold), // Bold
        ),
      ),
      body: StreamBuilder<List<DoctorAppointment>>(
        // Listen to completed records
        stream: repo.watchHealthRecords(doctorId), // Data source
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            // Still loading?
            return const Center(child: CircularProgressIndicator()); // Spinner
          }

          if (snap.hasError) {
            // Failed to load?
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20), // Space around
                child: Text(
                  'Failed to load health records.\n${snap.error}', // Error text
                  textAlign: TextAlign.center, // Center it
                ),
              ),
            );
          }

          final records = snap.data ?? const <DoctorAppointment>[]; // List (empty if null)

          if (records.isEmpty) {
            // No records yet?
            return const Center(
              child: Text('No completed health records yet.'), // Empty message
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(20), // Space around list
            itemCount: records.length, // Number of records
            itemBuilder: (context, index) {
              // Builds one row per record
              final a = records[index]; // This record

              return Container(
                margin: const EdgeInsets.only(bottom: 12), // Gap below
                padding: const EdgeInsets.all(16), // Space inside
                decoration: BoxDecoration(
                  color: Colors.white, // White card
                  borderRadius: BorderRadius.circular(16), // Round corners
                  border: Border.all(color: kBorder), // Grey border
                ),
                child: ListTile(
                  contentPadding: EdgeInsets.zero, // No extra padding
                  leading: const CircleAvatar(
                    backgroundColor: kSoftBlue, // Light blue circle
                    child: Icon(
                      Icons.medical_information_outlined, // Medical icon
                      color: kPrimary, // Blue
                    ),
                  ),
                  title: Text(
                    a.diagnosis.isEmpty ? 'Consultation' : a.diagnosis, // Diagnosis or default
                    style: const TextStyle(
                      fontWeight: FontWeight.bold, // Bold
                      fontSize: 13, // Text size
                    ),
                  ),
                  subtitle: Text(
                    '${a.studentName} • ' // Student name
                    'ID: ${a.studentId}\n' // Student id
                    '${a.dateKey} • ' // Date
                    '${a.prescriptions.length} prescription item(s)', // Medicine count
                    style: const TextStyle(fontSize: 10, height: 1.5), // Small text
                  ),
                  trailing: IconButton(
                    tooltip: 'View prescription', // Hover text
                    onPressed: () {
                      Navigator.push(
                        context, // Current screen
                        MaterialPageRoute(
                          builder: (_) =>
                              PrescriptionPage(appointment: a), // Open prescription
                        ),
                      );
                    },
                    icon: const Icon(
                      Icons.chevron_right, // Right arrow
                      color: kPrimary, // Blue
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
