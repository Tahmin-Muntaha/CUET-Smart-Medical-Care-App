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

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'chat_list_page.dart';

const Color kPrimary = Color(0xFF003D9B);
const Color kTeal = Color(0xFF00687A);
const Color kText = Color(0xFF111C2D);
const Color kMuted = Color(0xFF737685);
const Color kBorder = Color(0xFFC3C6D6);
const Color kPage = Color(0xFFF5F7FB);
const Color kSoftBlue = Color(0xFFE7EEFF);
const Color kSoftTeal = Color(0xFFE0F7FA);

BoxDecoration cardDecoration() => BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: kBorder.withOpacity(.7),
        width: .7,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(.035),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ],
    );

InputDecoration inputDecoration(
  String label, {
  String? hint,
}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    filled: true,
    fillColor: const Color(0xFFF9F9FF),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: kBorder),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: kPrimary, width: 1.5),
    ),
  );
}

// ============================================================
// MODELS
// ============================================================

enum AppointmentStatus {
  waiting,
  upcoming,
  inConsultation,
  completed,
  cancelled,
}

AppointmentStatus statusFromString(String? value) {
  final normalized = value?.trim();

  // 'booked' is what the student-side booking flow writes for a
  // freshly booked appointment — it belongs in the doctor's
  // waiting queue.
  if (normalized == 'booked') {
    return AppointmentStatus.waiting;
  }

  return AppointmentStatus.values.firstWhere(
    (s) => s.name == normalized,
    orElse: () => AppointmentStatus.waiting,
  );
}

// ============================================================
// PRESCRIPTION ITEM
// ============================================================

class PrescriptionItem {
  final String medicineName;
  final String dosage;
  final String frequency;
  final String duration;
  final String timing;

  const PrescriptionItem({
    required this.medicineName,
    required this.dosage,
    required this.frequency,
    required this.duration,
    required this.timing,
  });

  factory PrescriptionItem.fromMap(Map<String, dynamic> map) {
    return PrescriptionItem(
      medicineName: (map['medicineName'] ?? '').toString(),
      dosage: (map['dosage'] ?? '').toString(),
      frequency: (map['frequency'] ?? '').toString(),
      duration: (map['duration'] ?? '').toString(),
      timing: (map['timing'] ?? 'After Meal').toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'medicineName': medicineName,
      'dosage': dosage,
      'frequency': frequency,
      'duration': duration,
      'timing': timing,
    };
  }
}

// ============================================================
// DOCTOR APPOINTMENT
// ============================================================

class DoctorAppointment {
  final String id;
  final String doctorUid;
  final String dateKey;
  final int queueNumber;

  final String studentName;
  final String studentId;
  final String studentDept;
  final String studentBatch;
  final String studentPhone;

  final String reason;
  final String timeSlot;

  final AppointmentStatus status;

  final String diagnosis;
  final String symptoms;
  final String treatmentAdvice;
  final String followUpDate;

  final String bloodPressure;
  final String temperature;
  final String pulseRate;

  final List<PrescriptionItem> prescriptions;

  // Denormalized doctor info — stamped onto the appointment the moment
  // consultation starts, so the student dashboard can render "who
  // prescribed this" straight from the appointment/prescription
  // document, without a second lookup into users/{doctorId}.
  final String doctorName;
  final String doctorDesignation;
  final String doctorSpecialization;
  final String doctorDepartment;
  final String doctorChamber;

  const DoctorAppointment({
    required this.id,
    required this.doctorUid,
    required this.dateKey,
    required this.queueNumber,
    required this.studentName,
    required this.studentId,
    required this.studentDept,
    required this.studentBatch,
    required this.studentPhone,
    required this.reason,
    required this.timeSlot,
    required this.status,
    this.diagnosis = '',
    this.symptoms = '',
    this.treatmentAdvice = '',
    this.followUpDate = '',
    this.bloodPressure = '',
    this.temperature = '',
    this.pulseRate = '',
    this.prescriptions = const [],
    this.doctorName = '',
    this.doctorDesignation = '',
    this.doctorSpecialization = '',
    this.doctorDepartment = '',
    this.doctorChamber = '',
  });

  factory DoctorAppointment.fromMap(
    String id,
    Map<String, dynamic> map,
  ) {
    final rawPrescriptions = map['prescriptions'];

    final prescriptionList = <PrescriptionItem>[];

    if (rawPrescriptions is List) {
      for (final item in rawPrescriptions) {
        if (item is Map) {
          prescriptionList.add(
            PrescriptionItem.fromMap(Map<String, dynamic>.from(item)),
          );
        }
      }
    }

    int queueNumber = 0;

    final rawQueue = map['queueNumber'];

    if (rawQueue is int) {
      queueNumber = rawQueue;
    } else if (rawQueue is num) {
      queueNumber = rawQueue.toInt();
    } else if (rawQueue is String) {
      queueNumber = int.tryParse(rawQueue) ?? 0;
    }

    return DoctorAppointment(
      id: id,
      doctorUid: (map['doctorUid'] ?? '').toString(),
      dateKey: (map['dateKey'] ?? '').toString(),
      queueNumber: queueNumber,

      studentName: (map['studentName'] ?? '').toString(),
      studentId: (map['studentId'] ?? '').toString(),
      studentDept: (map['studentDept'] ?? '').toString(),
      studentBatch: (map['studentBatch'] ?? '').toString(),
      studentPhone: (map['studentPhone'] ?? '').toString(),

      reason: (map['reason'] ?? '').toString(),
      timeSlot: (map['timeSlot'] ?? map['time'] ?? '').toString(),

      status: statusFromString(map['status']?.toString()),

      diagnosis: (map['diagnosis'] ?? '').toString(),
      symptoms: (map['symptoms'] ?? '').toString(),
      treatmentAdvice: (map['treatmentAdvice'] ?? '').toString(),
      followUpDate: (map['followUpDate'] ?? '').toString(),

      bloodPressure: (map['bloodPressure'] ?? '').toString(),
      temperature: (map['temperature'] ?? '').toString(),
      pulseRate: (map['pulseRate'] ?? '').toString(),

      prescriptions: prescriptionList,

      doctorName: (map['doctorName'] ?? '').toString(),
      doctorDesignation: (map['doctorDesignation'] ?? '').toString(),
      doctorSpecialization:
          (map['doctorSpecialization'] ?? '').toString(),
      doctorDepartment: (map['doctorDepartment'] ?? '').toString(),
      doctorChamber: (map['doctorChamber'] ?? '').toString(),
    );
  }

  /// Only the fields a doctor is allowed to write (must match
  /// doctorWritableFields() in Firestore security rules).
  /// This prevents PERMISSION_DENIED caused by sending immutable
  /// student / booking fields.
  Map<String, dynamic> toMap({bool forDoctorUpdate = false}) {
    if (forDoctorUpdate) {
      final map = <String, dynamic>{
        'status': status.name,
        'diagnosis': diagnosis,
        'symptoms': symptoms,
        'treatmentAdvice': treatmentAdvice,
        'followUpDate': followUpDate,
        'bloodPressure': bloodPressure,
        'temperature': temperature,
        'pulseRate': pulseRate,
        'prescriptions': prescriptions.map((p) => p.toMap()).toList(),
        // Doctor attribution stamped onto appointment
        'doctorName': doctorName,
        'doctorDesignation': doctorDesignation,
        'doctorSpecialization': doctorSpecialization,
        'doctorDepartment': doctorDepartment,
        'doctorChamber': doctorChamber,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (status == AppointmentStatus.completed) {
        map['completedAt'] = FieldValue.serverTimestamp();
      }

      return map;
    }

    // Full map (kept for completeness / other potential uses)
    return {
      'doctorUid': doctorUid,
      'dateKey': dateKey,
      'queueNumber': queueNumber,
      'studentName': studentName,
      'studentId': studentId,
      'studentDept': studentDept,
      'studentBatch': studentBatch,
      'studentPhone': studentPhone,
      'reason': reason,
      'timeSlot': timeSlot,
      'status': status.name,
      'diagnosis': diagnosis,
      'symptoms': symptoms,
      'treatmentAdvice': treatmentAdvice,
      'followUpDate': followUpDate,
      'bloodPressure': bloodPressure,
      'temperature': temperature,
      'pulseRate': pulseRate,
      'prescriptions': prescriptions.map((p) => p.toMap()).toList(),
      'doctorName': doctorName,
      'doctorDesignation': doctorDesignation,
      'doctorSpecialization': doctorSpecialization,
      'doctorDepartment': doctorDepartment,
      'doctorChamber': doctorChamber,
      if (status == AppointmentStatus.completed)
        'completedAt': FieldValue.serverTimestamp(),
    };
  }

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
      id: id,
      doctorUid: doctorUid,
      dateKey: dateKey,
      queueNumber: queueNumber,
      studentName: studentName,
      studentId: studentId,
      studentDept: studentDept,
      studentBatch: studentBatch,
      studentPhone: studentPhone,
      reason: reason,
      timeSlot: timeSlot,
      status: status ?? this.status,
      diagnosis: diagnosis ?? this.diagnosis,
      symptoms: symptoms ?? this.symptoms,
      treatmentAdvice: treatmentAdvice ?? this.treatmentAdvice,
      followUpDate: followUpDate ?? this.followUpDate,
      bloodPressure: bloodPressure ?? this.bloodPressure,
      temperature: temperature ?? this.temperature,
      pulseRate: pulseRate ?? this.pulseRate,
      prescriptions: prescriptions ?? this.prescriptions,
      doctorName: doctorName ?? this.doctorName,
      doctorDesignation: doctorDesignation ?? this.doctorDesignation,
      doctorSpecialization:
          doctorSpecialization ?? this.doctorSpecialization,
      doctorDepartment: doctorDepartment ?? this.doctorDepartment,
      doctorChamber: doctorChamber ?? this.doctorChamber,
    );
  }
}

// ============================================================
// DOCTOR PROFILE
// ============================================================

class DoctorProfile {
  final String id;

  final String fullName;
  final String designation;
  final String specialization;
  final String department;
  final String bmdcRegNo;

  final List<String> qualifications;

  final int experienceYears;

  final String chamber;
  final String shift;

  final String phone;
  final String email;

  final String bio;
  final String photoUrl;

  const DoctorProfile({
    required this.id,
    this.fullName = '',
    this.designation = '',
    this.specialization = '',
    this.department = '',
    this.bmdcRegNo = '',
    this.qualifications = const [],
    this.experienceYears = 0,
    this.chamber = '',
    this.shift = '',
    this.phone = '',
    this.email = '',
    this.bio = '',
    this.photoUrl = '',
  });

  bool get isComplete {
    return fullName.isNotEmpty &&
        specialization.isNotEmpty &&
        department.isNotEmpty;
  }

  factory DoctorProfile.fromMap(
    String id,
    Map<String, dynamic> map,
  ) {
    final rawQualifications = map['qualifications'];

    final qualifications = <String>[];

    if (rawQualifications is List) {
      for (final q in rawQualifications) {
        final value = q.toString().trim();

        if (value.isNotEmpty) {
          qualifications.add(value);
        }
      }
    } else if (rawQualifications is String) {
      qualifications.addAll(
        rawQualifications
            .split(',')
            .map((q) => q.trim())
            .where((q) => q.isNotEmpty),
      );
    }

    int experienceYears = 0;

    final rawExperience = map['experienceYears'];

    if (rawExperience is int) {
      experienceYears = rawExperience;
    } else if (rawExperience is num) {
      experienceYears = rawExperience.toInt();
    } else if (rawExperience is String) {
      experienceYears = int.tryParse(rawExperience) ?? 0;
    }

    return DoctorProfile(
      id: id,
      fullName: (map['fullName'] ?? '').toString(),
      designation: (map['designation'] ?? '').toString(),
      specialization: (map['specialization'] ?? '').toString(),
      department: (map['department'] ?? '').toString(),
      bmdcRegNo: (map['bmdcRegNo'] ?? '').toString(),
      qualifications: qualifications,
      experienceYears: experienceYears,
      chamber: (map['chamber'] ?? '').toString(),
      shift: (map['shift'] ?? '').toString(),
      phone: (map['phone'] ?? '').toString(),
      email: (map['email'] ?? '').toString(),
      bio: (map['bio'] ?? '').toString(),
      photoUrl: (map['photoUrl'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'fullName': fullName,
      'designation': designation,
      'specialization': specialization,
      'department': department,
      'bmdcRegNo': bmdcRegNo,
      'qualifications': qualifications,
      'experienceYears': experienceYears,
      'chamber': chamber,
      'shift': shift,
      'phone': phone,
      'email': email,
      'bio': bio,
      'photoUrl': photoUrl,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}

// ============================================================
// FIRESTORE REPOSITORY
// ============================================================

class DoctorRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _doctorDoc(String doctorId) {
    return _db.collection('users').doc(doctorId);
  }

  // ----------------------------------------------------------
  // DOCTOR PROFILE
  // ----------------------------------------------------------

  Stream<DoctorProfile?> watchProfile(String doctorId) {
    return _doctorDoc(doctorId).snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) {
        return null;
      }

      return DoctorProfile.fromMap(snap.id, snap.data()!);
    });
  }

  Future<void> saveProfile(DoctorProfile profile) async {
    await _doctorDoc(profile.id).set(
      profile.toMap(),
      SetOptions(merge: true),
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

  Stream<List<DoctorAppointment>> watchDoctorAppointmentsForDay(
    String doctorId,
    String dateKey,
  ) {
    return _db
        .collection('appointments')
        .where('doctorUid', isEqualTo: doctorId)
        .where('dateKey', isEqualTo: dateKey)
        .snapshots()
        .map((snap) {
      final appointments = snap.docs
          .where((doc) {
            final status =
                doc.data()['status']?.toString().trim().toLowerCase();

            // Cancelled appointments never appear in the doctor's
            // day view.
            return status != 'cancelled';
          })
          .map((doc) => DoctorAppointment.fromMap(doc.id, doc.data()))
          .toList();

      // Sort by queue token, falling back to time slot.
      appointments.sort((a, b) {
        final queueCompare = a.queueNumber.compareTo(b.queueNumber);

        if (queueCompare != 0) {
          return queueCompare;
        }

        return a.timeSlot.compareTo(b.timeSlot);
      });

      return appointments;
    });
  }

  // ----------------------------------------------------------
  // COMPLETED HEALTH RECORDS (ALL DAYS)
  // ----------------------------------------------------------

  Stream<List<DoctorAppointment>> watchHealthRecords(String doctorId) {
    return _db
        .collection('appointments')
        .where('doctorUid', isEqualTo: doctorId)
        .where('status', isEqualTo: AppointmentStatus.completed.name)
        .snapshots()
        .map((snap) {
      final records = snap.docs
          .map((doc) => DoctorAppointment.fromMap(doc.id, doc.data()))
          .toList();

      records.sort((a, b) => b.dateKey.compareTo(a.dateKey));

      return records;
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

  Future<void> updateAppointment(DoctorAppointment appointment) async {
    await _db.collection('appointments').doc(appointment.id).set(
          appointment.toMap(forDoctorUpdate: true),
          SetOptions(merge: true),
        );
  }
}

// ============================================================
// DOCTOR ANNOUNCEMENTS
// ============================================================

class DoctorAnnouncement {
  final String id;
  final String title;
  final String content;
  final String audience;
  final String priority;
  final dynamic createdAt;

  const DoctorAnnouncement({
    required this.id,
    required this.title,
    required this.content,
    required this.audience,
    required this.priority,
    required this.createdAt,
  });

  factory DoctorAnnouncement.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};

    return DoctorAnnouncement(
      id: doc.id,
      title: (data['title'] ?? data['announcementTitle'] ?? '').toString(),
      content: (data['content'] ?? data['message'] ?? data['description'] ?? '')
          .toString(),
      audience: (data['audience'] ?? '').toString(),
      priority: (data['priority'] ?? 'normal').toString(),
      createdAt: data['createdAt'],
    );
  }

  DateTime get sortDate {
    final value = createdAt;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    if (value is String) {
      return DateTime.tryParse(value) ?? DateTime.fromMillisecondsSinceEpoch(0);
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
}

class DoctorAnnouncementsSection extends StatelessWidget {
  const DoctorAnnouncementsSection({super.key});

  Stream<List<DoctorAnnouncement>> _announcementsStream() {
    return FirebaseFirestore.instance
        .collection('announcements')
        .snapshots()
        .map((snapshot) {
      final announcements = snapshot.docs
          .map(DoctorAnnouncement.fromDocument)
          .where((announcement) {
            final audience = announcement.audience.trim().toLowerCase();
            return audience == 'all' ||
                audience == 'doctor' ||
                audience == 'doctors';
          })
          .toList();

      announcements.sort((a, b) {
        final dateCompare = b.sortDate.compareTo(a.sortDate);
        if (dateCompare != 0) return dateCompare;
        return b.id.compareTo(a.id);
      });

      return announcements;
    });
  }

  String _formatDate(dynamic value) {
    DateTime? date;
    if (value is Timestamp) {
      date = value.toDate();
    } else if (value is DateTime) {
      date = value;
    } else if (value is int) {
      date = DateTime.fromMillisecondsSinceEpoch(value);
    } else if (value is num) {
      date = DateTime.fromMillisecondsSinceEpoch(value.toInt());
    } else if (value is String) {
      date = DateTime.tryParse(value);
    }

    if (date == null) return 'Date not available';

    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString();
    var hour = date.hour;
    final minute = date.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    hour %= 12;
    if (hour == 0) hour = 12;

    return '$day/$month/$year • $hour:$minute $period';
  }

  String _displayAudience(String audience) {
    final normalized = audience.trim().toLowerCase();
    if (normalized == 'all') return 'All';
    if (normalized == 'doctor' || normalized == 'doctors') return 'Doctor';
    return audience.isEmpty ? 'Announcement' : audience;
  }

  Color _priorityColor(String priority) {
    if (priority.trim().toLowerCase() == 'urgent') {
      return Colors.red.shade700;
    }
    return kPrimary;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Announcements',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: kText,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Latest announcements for all users and doctors.',
          style: TextStyle(fontSize: 11, color: kMuted),
        ),
        const SizedBox(height: 15),
        StreamBuilder<List<DoctorAnnouncement>>(
          stream: _announcementsStream(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 32),
                decoration: cardDecoration(),
                child: const Center(child: CircularProgressIndicator()),
              );
            }

            if (snapshot.hasError) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: cardDecoration(),
                child: Column(
                  children: [
                    const Icon(Icons.campaign_outlined, size: 38, color: kPrimary),
                    const SizedBox(height: 8),
                    const Text(
                      'Could not load announcements',
                      style: TextStyle(fontWeight: FontWeight.bold, color: kText),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 10, color: kMuted),
                    ),
                  ],
                ),
              );
            }

            final announcements = snapshot.data ?? const <DoctorAnnouncement>[];

            if (announcements.isEmpty) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: cardDecoration(),
                child: const Center(
                  child: Column(
                    children: [
                      Icon(Icons.campaign_outlined, size: 38, color: kPrimary),
                      SizedBox(height: 8),
                      Text(
                        'No Announcements',
                        style: TextStyle(fontWeight: FontWeight.bold, color: kText),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'New announcements will appear here.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11, color: kMuted),
                      ),
                    ],
                  ),
                ),
              );
            }

            return Column(
              children: [
                for (final announcement in announcements)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: cardDecoration(),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: kSoftBlue,
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: const Icon(
                            Icons.campaign_outlined,
                            color: kPrimary,
                            size: 23,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 7,
                                runSpacing: 5,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    announcement.title.isEmpty
                                        ? 'Announcement'
                                        : announcement.title,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: kText,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: kSoftBlue,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      _displayAudience(announcement.audience),
                                      style: const TextStyle(
                                        fontSize: 8,
                                        fontWeight: FontWeight.bold,
                                        color: kPrimary,
                                      ),
                                    ),
                                  ),
                                  if (announcement.priority.trim().isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _priorityColor(announcement.priority)
                                            .withOpacity(.10),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        announcement.priority,
                                        style: TextStyle(
                                          fontSize: 8,
                                          fontWeight: FontWeight.bold,
                                          color: _priorityColor(announcement.priority),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              if (announcement.content.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  announcement.content,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF434654),
                                    height: 1.45,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Icon(Icons.schedule_outlined, size: 13, color: kMuted),
                                  const SizedBox(width: 5),
                                  Text(
                                    _formatDate(announcement.createdAt),
                                    style: const TextStyle(fontSize: 9, color: kMuted),
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

class DoctorDashboard extends StatefulWidget {
  final String doctorId;

  const DoctorDashboard({
    super.key,
    required this.doctorId,
  });

  @override
  State<DoctorDashboard> createState() => _DoctorDashboardState();
}

class _DoctorDashboardState extends State<DoctorDashboard> {
  final DoctorRepository repo = DoctorRepository();

  // ----------------------------------------------------------
  // SELECTED DAY
  //
  // Defaults to today. The doctor can step back/forward a day
  // or open a date picker to review a different day's queue.
  // ----------------------------------------------------------

  DateTime selectedDate = DateTime.now();

  String get selectedDateKey => _dateKey(selectedDate);

  bool get isToday => _isSameDay(selectedDate, DateTime.now());

  String _dateKey(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  String _displayDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  void goToPreviousDay() {
    setState(() {
      selectedDate = selectedDate.subtract(const Duration(days: 1));
    });
  }

  void goToNextDay() {
    setState(() {
      selectedDate = selectedDate.add(const Duration(days: 1));
    });
  }

  void goToToday() {
    setState(() {
      selectedDate = DateTime.now();
    });
  }

  Future<void> pickDate() async {
    final now = DateTime.now();

    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 90)),
    );

    if (picked == null) return;

    setState(() {
      selectedDate = picked;
    });
  }

  // ----------------------------------------------------------
  // LOGOUT
  // ----------------------------------------------------------

  Future<void> logout() async {
    try {
      await FirebaseAuth.instance.signOut();

      if (!mounted) return;

      Navigator.pushNamedAndRemoveUntil(
        context,
        '/login',
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Logout failed. Please try again.')),
      );
    }
  }

  // ----------------------------------------------------------
  // PROFILE
  // ----------------------------------------------------------

  void openProfileForm(DoctorProfile? existing) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DoctorProfileFormPage(
          doctorId: widget.doctorId,
          existing: existing,
          repo: repo,
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

  Future<void> startConsultation(
    DoctorAppointment appointment,
    DoctorProfile? profile,
  ) async {
    if (appointment.status == AppointmentStatus.completed) {
      return;
    }

    final updated = appointment.copyWith(
      status: AppointmentStatus.inConsultation,
      doctorName: profile?.fullName ?? '',
      doctorDesignation: profile?.designation ?? '',
      doctorSpecialization: profile?.specialization ?? '',
      doctorDepartment: profile?.department ?? '',
      doctorChamber: profile?.chamber ?? '',
    );

    try {
      await repo.updateAppointment(updated);

      if (!mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ConsultationPage(
            appointment: updated,
            repo: repo,
            doctorProfile: profile,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start consultation: $e')),
      );
    }
  }

  // ----------------------------------------------------------
  // VIEW PRESCRIPTION
  // ----------------------------------------------------------

  void viewPrescription(DoctorAppointment appointment) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PrescriptionPage(appointment: appointment),
      ),
    );
  }

  // ----------------------------------------------------------
  // HEALTH RECORDS
  // ----------------------------------------------------------

  void openHealthRecords() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => HealthRecordsPage(
          doctorId: widget.doctorId,
          repo: repo,
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
      backgroundColor: kPage,
      appBar: AppBar(
        backgroundColor: kPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Doctor Dashboard',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'Messages',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ChatListPage()),
              );
            },
            icon: const Icon(Icons.chat_bubble_outline),
          ),
          IconButton(
            tooltip: 'Logout',
            onPressed: logout,
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: StreamBuilder<DoctorProfile?>(
        stream: repo.watchProfile(widget.doctorId),
        builder: (context, profileSnap) {
          if (profileSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (profileSnap.hasError) {
            return Center(
              child: Text(
                'Failed to load doctor profile.\n${profileSnap.error}',
                textAlign: TextAlign.center,
              ),
            );
          }

          final profile = profileSnap.data;

          return StreamBuilder<List<DoctorAppointment>>(
            stream: repo.watchDoctorAppointmentsForDay(
              widget.doctorId,
              selectedDateKey,
            ),
            builder: (context, apptSnap) {
              final appointments =
                  apptSnap.data ?? const <DoctorAppointment>[];

              final loadingAppointments =
                  apptSnap.connectionState == ConnectionState.waiting;

              final waitingCount = appointments
                  .where((a) => a.status == AppointmentStatus.waiting)
                  .length;

              final completedCount = appointments
                  .where((a) => a.status == AppointmentStatus.completed)
                  .length;

              final totalCount = appointments.length;

              return SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1000),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _welcomeSection(profile),

                          const SizedBox(height: 20),

                          _dateSelector(),

                          const SizedBox(height: 20),

                          _statistics(
                            totalCount,
                            waitingCount,
                            completedCount,
                          ),

                          const SizedBox(height: 26),

                          _patientQueue(
                            appointments,
                            waitingCount,
                            loadingAppointments,
                            profile,
                          ),

                          const SizedBox(height: 28),

                          const DoctorAnnouncementsSection(),

                          const SizedBox(height: 28),

                          Center(
                            child: Text(
                              'CUET SmartCare • Central Medical Services',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
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
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: cardDecoration(),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Previous day',
            onPressed: goToPreviousDay,
            icon: const Icon(Icons.chevron_left_rounded, color: kPrimary),
          ),

          Expanded(
            child: InkWell(
              onTap: pickDate,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  children: [
                    Text(
                      isToday ? 'Today' : _displayDate(selectedDate),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: kText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _displayDate(selectedDate),
                      style: const TextStyle(
                        fontSize: 10,
                        color: kMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          IconButton(
            tooltip: 'Next day',
            onPressed: goToNextDay,
            icon: const Icon(Icons.chevron_right_rounded, color: kPrimary),
          ),

          if (!isToday)
            TextButton(
              onPressed: goToToday,
              child: const Text('Today'),
            ),

          IconButton(
            tooltip: 'Pick a date',
            onPressed: pickDate,
            icon: const Icon(Icons.calendar_month_outlined, color: kTeal),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // WELCOME
  // ==========================================================

  Widget _welcomeSection(DoctorProfile? profile) {
    final hasProfile = profile != null && profile.isComplete;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: cardDecoration(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final small = constraints.maxWidth < 600;

          final avatar = Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: kSoftBlue,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: kPrimary.withOpacity(.2)),
              image: (profile?.photoUrl.isNotEmpty ?? false)
                  ? DecorationImage(
                      image: NetworkImage(profile!.photoUrl),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: (profile?.photoUrl.isNotEmpty ?? false)
                ? null
                : const Icon(
                    Icons.medical_services_rounded,
                    color: kPrimary,
                    size: 32,
                  ),
          );

          final info = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              avatar,
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (hasProfile)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: kSoftTeal,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Duty Chamber: '
                          '${profile.chamber.isEmpty ? "Not set" : profile.chamber}'
                          ' • '
                          '${profile.shift.isEmpty ? "Shift not set" : profile.shift}',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: kTeal,
                          ),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF0C2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Professional profile incomplete',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF805A00),
                          ),
                        ),
                      ),

                    const SizedBox(height: 7),

                    Text(
                      hasProfile
                          ? 'Good day, Dr. ${profile.fullName}'
                          : 'Welcome, Doctor',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: kText,
                      ),
                    ),

                    const SizedBox(height: 3),

                    Text(
                      hasProfile
                          ? '${profile.specialization} • '
                              '${profile.department} • '
                              "Use the date selector below to review a day's appointments."
                          : 'Add your professional details so students and staff can see who you are.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: kMuted,
                        height: 1.4,
                      ),
                    ),

                    if (!hasProfile) ...[
                      const SizedBox(height: 6),
                      const Text(
                        'Note: until this is filled in, prescriptions you '
                        'issue will not show your name/specialization to '
                        'students.',
                        style: TextStyle(
                          fontSize: 10,
                          color: Color(0xFF805A00),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );

          final buttons = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ElevatedButton.icon(
                onPressed: () => openProfileForm(profile),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      hasProfile ? const Color(0xFFF0F3FF) : kPrimary,
                  foregroundColor: hasProfile ? kPrimary : Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: Icon(
                  hasProfile ? Icons.edit_outlined : Icons.badge_outlined,
                  size: 17,
                ),
                label: Text(
                  hasProfile
                      ? 'Edit Professional Profile'
                      : 'Add Professional Profile',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              const SizedBox(height: 10),

              OutlinedButton.icon(
                onPressed: openHealthRecords,
                style: OutlinedButton.styleFrom(
                  foregroundColor: kTeal,
                  side: const BorderSide(color: kTeal),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.folder_shared_outlined, size: 17),
                label: const Text(
                  'All Health Records',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          );

          if (small) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [info, const SizedBox(height: 16), buttons],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: info),
              const SizedBox(width: 20),
              SizedBox(width: 220, child: buttons),
            ],
          );
        },
      ),
    );
  }

  // ==========================================================
  // STATISTICS
  // ==========================================================

  Widget _statistics(int total, int waiting, int completed) {
    final cards = [
      _statCard(
        title: 'Appointments',
        value: '$total',
        subtitle: isToday
            ? "Booked for today"
            : 'Booked for ${_displayDate(selectedDate)}',
        icon: Icons.calendar_month_rounded,
        iconColor: kPrimary,
        backgroundColor: kSoftBlue,
      ),
      _statCard(
        title: 'Waiting in Queue',
        value: '$waiting',
        subtitle: 'Ready for consultation',
        icon: Icons.hourglass_top_rounded,
        iconColor: kTeal,
        backgroundColor: kSoftTeal,
      ),
      _statCard(
        title: 'Completed',
        value: '$completed',
        subtitle: 'Completed consultations',
        icon: Icons.check_circle_outline,
        iconColor: Colors.green.shade700,
        backgroundColor: Colors.green.shade50,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 650) {
          return Column(
            children: [
              for (int i = 0; i < cards.length; i++) ...[
                cards[i],
                if (i != cards.length - 1) const SizedBox(height: 12),
              ],
            ],
          );
        }

        return Row(
          children: [
            for (int i = 0; i < cards.length; i++) ...[
              Expanded(child: cards[i]),
              if (i != cards.length - 1) const SizedBox(width: 14),
            ],
          ],
        );
      },
    );
  }

  Widget _statCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required Color backgroundColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: cardDecoration(),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                    color: iconColor,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    color: iconColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 10, color: kMuted),
                ),
              ],
            ),
          ),
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: iconColor, size: 25),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // PATIENT QUEUE
  // ==========================================================

  Widget _patientQueue(
    List<DoctorAppointment> appointments,
    int waiting,
    bool loading,
    DoctorProfile? profile,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isToday
                        ? "Today's Patient Appointments"
                        : 'Appointments • ${_displayDate(selectedDate)}',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: kText,
                    ),
                  ),
                  const SizedBox(height: 3),
                  const Text(
                    'Cancelled appointments are hidden from this list.',
                    style: TextStyle(fontSize: 11, color: kMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 11,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: kSoftBlue,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$waiting Pending',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: kPrimary,
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 15),

        if (loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 30),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (appointments.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: cardDecoration(),
            child: Center(
              child: Text(
                isToday
                    ? 'No appointments booked for today.'
                    : 'No appointments booked for ${_displayDate(selectedDate)}.',
                style: const TextStyle(fontSize: 12, color: kMuted),
              ),
            ),
          )
        else
          for (final appointment in appointments)
            _patientCard(appointment, profile),
      ],
    );
  }

  // ==========================================================
  // PATIENT CARD
  // ==========================================================

  Widget _patientCard(
    DoctorAppointment appointment,
    DoctorProfile? profile,
  ) {
    final waiting = appointment.status == AppointmentStatus.waiting;
    final completed = appointment.status == AppointmentStatus.completed;
    final inConsultation =
        appointment.status == AppointmentStatus.inConsultation;

    Color queueBackground = kSoftBlue;
    Color queueText = const Color(0xFF434654);

    if (waiting) {
      queueBackground = kPrimary;
      queueText = Colors.white;
    } else if (completed) {
      queueBackground = const Color(0xFFDDF5E3);
      queueText = Colors.green.shade800;
    } else if (inConsultation) {
      queueBackground = kSoftTeal;
      queueText = kTeal;
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: waiting ? kPrimary : kBorder,
          width: waiting ? 1.5 : .7,
        ),
        boxShadow: waiting
            ? [
                BoxShadow(
                  color: kPrimary.withOpacity(.10),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final small = constraints.maxWidth < 650;

          final patientInfo = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: queueBackground,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Text(
                    '#${appointment.queueNumber}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: queueText,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 7,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          appointment.studentName.isEmpty
                              ? 'Student'
                              : appointment.studentName,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: kText,
                          ),
                        ),
                        if (appointment.studentId.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0F3FF),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              'ID: ${appointment.studentId}',
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: kPrimary,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Date: ${appointment.dateKey.isEmpty ? "Not set" : appointment.dateKey}'
                      ' • Time: ${appointment.timeSlot.isEmpty ? "Not set" : appointment.timeSlot}',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: kPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Dept: ${appointment.studentDept.isEmpty ? "Not set" : appointment.studentDept}'
                      ' • Batch: ${appointment.studentBatch.isEmpty ? "Not set" : appointment.studentBatch}'
                      ' • ${appointment.studentPhone}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF434654),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Complaint: '
                      '"${appointment.reason.isEmpty ? "Not provided" : appointment.reason}"',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10,
                        fontStyle: FontStyle.italic,
                        color: kMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );

          final actions = _patientActions(
            appointment,
            profile,
            compact: small,
          );

          if (small) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                patientInfo,
                const SizedBox(height: 14),
                actions,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(flex: 2, child: patientInfo),
              const SizedBox(width: 15),
              actions,
            ],
          );
        },
      ),
    );
  }

  // ==========================================================
  // PATIENT ACTIONS
  // ==========================================================

  Widget _patientActions(
    DoctorAppointment appointment,
    DoctorProfile? profile, {
    required bool compact,
  }) {
    final completed = appointment.status == AppointmentStatus.completed;
    final inConsultation =
        appointment.status == AppointmentStatus.inConsultation;

    final statusAndTime = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.access_time_rounded, size: 15, color: kPrimary),
        const SizedBox(width: 5),
        Text(
          appointment.timeSlot.isEmpty
              ? 'Time not set'
              : appointment.timeSlot,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Color(0xFF434654),
          ),
        ),
        const SizedBox(width: 12),
        _statusBadge(appointment.status),
      ],
    );

    Widget button;

    if (completed) {
      button = OutlinedButton.icon(
        onPressed: () => viewPrescription(appointment),
        style: OutlinedButton.styleFrom(
          foregroundColor: kTeal,
          side: const BorderSide(color: kTeal),
          padding: const EdgeInsets.symmetric(
            horizontal: 13,
            vertical: 10,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(11),
          ),
        ),
        icon: const Icon(Icons.description_outlined, size: 15),
        label: const Text(
          'View Prescription',
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
        ),
      );
    } else {
      button = ElevatedButton.icon(
        onPressed: () => startConsultation(appointment, profile),
        style: ElevatedButton.styleFrom(
          backgroundColor: inConsultation ? kTeal : kPrimary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 11,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(11),
          ),
        ),
        icon: Icon(
          inConsultation
              ? Icons.medical_services_outlined
              : Icons.play_arrow_rounded,
          size: 16,
        ),
        label: Text(
          inConsultation ? 'Continue Consultation' : 'Start Consultation',
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
        ),
      );
    }

    if (compact) {
      return SizedBox(
        width: double.infinity,
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: statusAndTime,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, child: button),
          ],
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [statusAndTime, const SizedBox(width: 12), button],
    );
  }

  // ==========================================================
  // STATUS BADGE
  // ==========================================================

  Widget _statusBadge(AppointmentStatus status) {
    String text;
    Color background;
    Color foreground;

    switch (status) {
      case AppointmentStatus.waiting:
        text = 'Waiting in Queue';
        background = const Color(0xFFFFF0C2);
        foreground = const Color(0xFF805A00);
        break;

      case AppointmentStatus.completed:
        text = 'Completed';
        background = const Color(0xFFDDF5E3);
        foreground = Colors.green.shade800;
        break;

      case AppointmentStatus.inConsultation:
        text = 'In Consultation';
        background = kSoftBlue;
        foreground = kPrimary;
        break;

      case AppointmentStatus.upcoming:
        text = 'Upcoming';
        background = const Color(0xFFF0F0F0);
        foreground = const Color(0xFF434654);
        break;

      case AppointmentStatus.cancelled:
        text = 'Cancelled';
        background = const Color(0xFFFDE2E1);
        foreground = Colors.red.shade800;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: foreground,
        ),
      ),
    );
  }
}

// ============================================================
// DOCTOR PROFESSIONAL PROFILE FORM
// ============================================================

class DoctorProfileFormPage extends StatefulWidget {
  final String doctorId;
  final DoctorProfile? existing;
  final DoctorRepository repo;

  const DoctorProfileFormPage({
    super.key,
    required this.doctorId,
    required this.repo,
    this.existing,
  });

  @override
  State<DoctorProfileFormPage> createState() =>
      _DoctorProfileFormPageState();
}

class _DoctorProfileFormPageState extends State<DoctorProfileFormPage> {
  late final TextEditingController nameCtrl;
  late final TextEditingController designationCtrl;
  late final TextEditingController specializationCtrl;
  late final TextEditingController departmentCtrl;
  late final TextEditingController bmdcCtrl;
  late final TextEditingController qualificationsCtrl;
  late final TextEditingController experienceCtrl;
  late final TextEditingController chamberCtrl;
  late final TextEditingController shiftCtrl;
  late final TextEditingController phoneCtrl;
  late final TextEditingController emailCtrl;
  late final TextEditingController bioCtrl;
  late final TextEditingController photoUrlCtrl;

  bool saving = false;

  @override
  void initState() {
    super.initState();

    final p = widget.existing;

    nameCtrl = TextEditingController(text: p?.fullName ?? '');
    designationCtrl = TextEditingController(text: p?.designation ?? '');
    specializationCtrl =
        TextEditingController(text: p?.specialization ?? '');
    departmentCtrl = TextEditingController(text: p?.department ?? '');
    bmdcCtrl = TextEditingController(text: p?.bmdcRegNo ?? '');
    qualificationsCtrl = TextEditingController(
      text: (p?.qualifications ?? []).join(', '),
    );
    experienceCtrl = TextEditingController(
      text: p != null && p.experienceYears > 0
          ? '${p.experienceYears}'
          : '',
    );
    chamberCtrl = TextEditingController(text: p?.chamber ?? '');
    shiftCtrl = TextEditingController(text: p?.shift ?? '');
    phoneCtrl = TextEditingController(text: p?.phone ?? '');
    emailCtrl = TextEditingController(text: p?.email ?? '');
    bioCtrl = TextEditingController(text: p?.bio ?? '');
    photoUrlCtrl = TextEditingController(text: p?.photoUrl ?? '');
  }

  @override
  void dispose() {
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

    super.dispose();
  }

  Future<void> save() async {
    if (nameCtrl.text.trim().isEmpty ||
        specializationCtrl.text.trim().isEmpty ||
        departmentCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Name, specialization and department are required.'),
        ),
      );

      return;
    }

    setState(() => saving = true);

    final profile = DoctorProfile(
      id: widget.doctorId,
      fullName: nameCtrl.text.trim(),
      designation: designationCtrl.text.trim(),
      specialization: specializationCtrl.text.trim(),
      department: departmentCtrl.text.trim(),
      bmdcRegNo: bmdcCtrl.text.trim(),
      qualifications: qualificationsCtrl.text
          .split(',')
          .map((q) => q.trim())
          .where((q) => q.isNotEmpty)
          .toList(),
      experienceYears: int.tryParse(experienceCtrl.text.trim()) ?? 0,
      chamber: chamberCtrl.text.trim(),
      shift: shiftCtrl.text.trim(),
      phone: phoneCtrl.text.trim(),
      email: emailCtrl.text.trim(),
      bio: bioCtrl.text.trim(),
      photoUrl: photoUrlCtrl.text.trim(),
    );

    try {
      await widget.repo.saveProfile(profile);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Professional profile saved.')),
      );

      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kPage,
      appBar: AppBar(
        backgroundColor: kPrimary,
        foregroundColor: Colors.white,
        title: const Text(
          'Professional Profile',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: cardDecoration(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Your details',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: kText,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'This information is shown on your dashboard and on prescriptions.',
                      style: TextStyle(fontSize: 11, color: kMuted),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nameCtrl,
                      decoration: inputDecoration(
                        'Full Name',
                        hint: 'e.g. Rahat Khan',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: designationCtrl,
                      decoration: inputDecoration(
                        'Designation',
                        hint: 'e.g. Assistant Professor',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: specializationCtrl,
                      decoration: inputDecoration(
                        'Specialization',
                        hint: 'e.g. Medicine, Cardiology',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: departmentCtrl,
                      decoration: inputDecoration(
                        'Department',
                        hint: 'e.g. Medicine',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: bmdcCtrl,
                      decoration: inputDecoration(
                        'BMDC Registration No.',
                        hint: 'e.g. A-12345',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: qualificationsCtrl,
                      decoration: inputDecoration(
                        'Qualifications (comma separated)',
                        hint: 'MBBS, MD, FCPS',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: experienceCtrl,
                      keyboardType: TextInputType.number,
                      decoration: inputDecoration(
                        'Years of Experience',
                        hint: 'e.g. 8',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: chamberCtrl,
                      decoration: inputDecoration(
                        'Duty Chamber / Room',
                        hint: 'e.g. Chamber 02',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: shiftCtrl,
                      decoration: inputDecoration(
                        'Duty Shift',
                        hint: 'e.g. 10:00 AM - 04:00 PM',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: phoneCtrl,
                      decoration: inputDecoration('Contact Phone'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: emailCtrl,
                      decoration: inputDecoration('Contact Email'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: photoUrlCtrl,
                      decoration: inputDecoration(
                        'Photo URL',
                        hint: 'link to a profile photo (optional)',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: bioCtrl,
                      maxLines: 4,
                      decoration: inputDecoration(
                        'Short Bio',
                        hint: 'A short professional summary',
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: saving ? null : save,
                        icon: saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.save_outlined),
                        label: Text(saving ? 'Saving...' : 'Save Profile'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPrimary,
                          foregroundColor: Colors.white,
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
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

class _AddMedicineDialog extends StatefulWidget {
  const _AddMedicineDialog();

  @override
  State<_AddMedicineDialog> createState() => _AddMedicineDialogState();
}

class _AddMedicineDialogState extends State<_AddMedicineDialog> {
  final nameController = TextEditingController();
  final dosageController = TextEditingController();
  final frequencyController = TextEditingController();
  final durationController = TextEditingController();

  String timing = 'After Meal';

  String? nameError;

  @override
  void dispose() {
    nameController.dispose();
    dosageController.dispose();
    frequencyController.dispose();
    durationController.dispose();

    super.dispose();
  }

  void _submit() {
    final name = nameController.text.trim();

    if (name.isEmpty) {
      setState(() => nameError = 'Medicine name is required');
      return;
    }

    Navigator.of(context).pop(
      PrescriptionItem(
        medicineName: name,
        dosage: dosageController.text.trim(),
        frequency: frequencyController.text.trim(),
        duration: durationController.text.trim(),
        timing: timing,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      title: const Text(
        'Add Medicine',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: inputDecoration(
                'Medicine name',
                hint: 'e.g. Paracetamol 500mg',
              ).copyWith(errorText: nameError),
              onChanged: (_) {
                if (nameError != null) {
                  setState(() => nameError = null);
                }
              },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: dosageController,
              decoration: inputDecoration('Dosage', hint: 'e.g. 500mg'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: frequencyController,
              decoration:
                  inputDecoration('Frequency', hint: 'e.g. 1+0+1'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: durationController,
              decoration:
                  inputDecoration('Duration', hint: 'e.g. 3 days'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: timing,
              decoration: inputDecoration('Timing'),
              items: const [
                DropdownMenuItem(
                  value: 'After Meal',
                  child: Text('After Meal'),
                ),
                DropdownMenuItem(
                  value: 'Before Meal',
                  child: Text('Before Meal'),
                ),
                DropdownMenuItem(
                  value: 'With Meal',
                  child: Text('With Meal'),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => timing = value);
                }
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.add, size: 17),
          label: const Text('Add Medicine'),
          style: ElevatedButton.styleFrom(
            backgroundColor: kPrimary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
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

class ConsultationPage extends StatefulWidget {
  final DoctorAppointment appointment;
  final DoctorRepository repo;
  final DoctorProfile? doctorProfile;

  const ConsultationPage({
    super.key,
    required this.appointment,
    required this.repo,
    this.doctorProfile,
  });

  @override
  State<ConsultationPage> createState() => _ConsultationPageState();
}

class _ConsultationPageState extends State<ConsultationPage> {
  late final TextEditingController symptomsController;
  late final TextEditingController diagnosisController;
  late final TextEditingController treatmentController;
  late final TextEditingController bpController;
  late final TextEditingController tempController;
  late final TextEditingController pulseController;

  DateTime? followUpDate;

  late List<PrescriptionItem> prescriptions;

  bool saving = false;

  @override
  void initState() {
    super.initState();

    final a = widget.appointment;

    symptomsController = TextEditingController(
      text: a.symptoms.isEmpty ? a.reason : a.symptoms,
    );
    diagnosisController = TextEditingController(text: a.diagnosis);
    treatmentController = TextEditingController(text: a.treatmentAdvice);
    bpController = TextEditingController(text: a.bloodPressure);
    tempController = TextEditingController(text: a.temperature);
    pulseController = TextEditingController(text: a.pulseRate);

    prescriptions = List<PrescriptionItem>.from(a.prescriptions);

    if (a.followUpDate.isNotEmpty) {
      followUpDate = DateTime.tryParse(a.followUpDate);
    }
  }

  @override
  void dispose() {
    symptomsController.dispose();
    diagnosisController.dispose();
    treatmentController.dispose();
    bpController.dispose();
    tempController.dispose();
    pulseController.dispose();

    super.dispose();
  }

  Future<void> addMedicine() async {
    final item = await showDialog<PrescriptionItem>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const _AddMedicineDialog(),
    );

    if (!mounted || item == null) {
      return;
    }

    setState(() => prescriptions.add(item));
  }

  Future<void> chooseFollowUpDate() async {
    final now = DateTime.now();

    final selected = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      initialDate: followUpDate ?? now,
    );

    if (selected != null) {
      setState(() => followUpDate = selected);
    }
  }

  Future<void> saveConsultation({required bool complete}) async {
    // A completed consultation must have at least one prescription
    // item OR a diagnosis — otherwise the student dashboard would show
    // an "empty" prescription, which is almost always a mistake.
    if (complete &&
        prescriptions.isEmpty &&
        diagnosisController.text.trim().isEmpty) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text('No diagnosis or medicine added'),
          content: const Text(
            'You are about to complete this consultation without a '
            'diagnosis or any prescribed medicine. Continue anyway?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Go back'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Complete anyway'),
            ),
          ],
        ),
      );

      if (proceed != true) {
        return;
      }
    }

    setState(() => saving = true);

    final followUpStr = followUpDate == null
        ? ''
        : '${followUpDate!.year.toString().padLeft(4, '0')}-'
            '${followUpDate!.month.toString().padLeft(2, '0')}-'
            '${followUpDate!.day.toString().padLeft(2, '0')}';

    final profile = widget.doctorProfile;

    final updated = widget.appointment.copyWith(
      symptoms: symptomsController.text.trim(),
      diagnosis: diagnosisController.text.trim(),
      treatmentAdvice: treatmentController.text.trim(),
      bloodPressure: bpController.text.trim(),
      temperature: tempController.text.trim(),
      pulseRate: pulseController.text.trim(),
      followUpDate: followUpStr,
      prescriptions: List<PrescriptionItem>.from(prescriptions),
      status: complete
          ? AppointmentStatus.completed
          : AppointmentStatus.inConsultation,
      // Re-stamp doctor info every save so the final prescription
      // record always carries accurate attribution, even if this
      // page was opened with a stale/null profile.
      doctorName: profile?.fullName ?? widget.appointment.doctorName,
      doctorDesignation:
          profile?.designation ?? widget.appointment.doctorDesignation,
      doctorSpecialization: profile?.specialization ??
          widget.appointment.doctorSpecialization,
      doctorDepartment:
          profile?.department ?? widget.appointment.doctorDepartment,
      doctorChamber: profile?.chamber ?? widget.appointment.doctorChamber,
    );

    try {
      await widget.repo.updateAppointment(updated);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            complete
                ? 'Consultation completed and prescription issued.'
                : 'Consultation saved as draft.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );

      if (complete) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.appointment;

    return Scaffold(
      backgroundColor: kPage,
      appBar: AppBar(
        backgroundColor: kPrimary,
        foregroundColor: Colors.white,
        title: const Text(
          'Clinical Consultation',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 850),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _patientHeader(a),
                  const SizedBox(height: 16),
                  _section(
                    title: 'Patient Complaint',
                    child: _readOnlyBox(
                      a.reason.isEmpty
                          ? 'No complaint provided.'
                          : a.reason,
                    ),
                  ),
                  _section(
                    title: "Today's Chamber Vitals",
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final small = constraints.maxWidth < 600;

                        final fields = [
                          TextField(
                            controller: bpController,
                            decoration:
                                inputDecoration('Blood Pressure'),
                          ),
                          TextField(
                            controller: tempController,
                            decoration:
                                inputDecoration('Body Temperature'),
                          ),
                          TextField(
                            controller: pulseController,
                            decoration: inputDecoration('Pulse Rate'),
                          ),
                        ];

                        if (small) {
                          return Column(
                            children: [
                              for (int i = 0; i < fields.length; i++) ...[
                                fields[i],
                                if (i != fields.length - 1)
                                  const SizedBox(height: 10),
                              ],
                            ],
                          );
                        }

                        return Row(
                          children: [
                            for (int i = 0; i < fields.length; i++) ...[
                              Expanded(child: fields[i]),
                              if (i != fields.length - 1)
                                const SizedBox(width: 10),
                            ],
                          ],
                        );
                      },
                    ),
                  ),
                  _section(
                    title: 'Clinical Symptoms & Physical Findings',
                    child: TextField(
                      controller: symptomsController,
                      maxLines: 4,
                      decoration: inputDecoration(
                        '',
                        hint: 'Record physical observations...',
                      ),
                    ),
                  ),
                  _section(
                    title: 'Definitive / Working Diagnosis',
                    child: TextField(
                      controller: diagnosisController,
                      maxLines: 4,
                      decoration: inputDecoration(
                        '',
                        hint: 'Enter diagnosis...',
                      ),
                    ),
                  ),
                  _prescriptionSection(),
                  _section(
                    title: 'Treatment Advice & Follow-Up',
                    child: TextField(
                      controller: treatmentController,
                      maxLines: 4,
                      decoration: inputDecoration(
                        '',
                        hint: 'Hydration, rest, precautions, tests...',
                      ),
                    ),
                  ),
                  _section(
                    title: 'Recommended Follow-Up Date',
                    child: InkWell(
                      onTap: chooseFollowUpDate,
                      borderRadius: BorderRadius.circular(12),
                      child: InputDecorator(
                        decoration: inputDecoration('Follow-up date'),
                        child: Text(
                          followUpDate == null
                              ? 'Optional'
                              : '${followUpDate!.day.toString().padLeft(2, '0')}/'
                                  '${followUpDate!.month.toString().padLeft(2, '0')}/'
                                  '${followUpDate!.year}',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final draftBtn = OutlinedButton.icon(
                        onPressed: saving
                            ? null
                            : () => saveConsultation(complete: false),
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('Save Draft'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: kTeal,
                          side: const BorderSide(color: kTeal),
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                        ),
                      );

                      final completeBtn = ElevatedButton.icon(
                        onPressed: saving
                            ? null
                            : () => saveConsultation(complete: true),
                        icon: saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.check_circle_outline),
                        label: const Text(
                          'Complete Consultation & Issue Rx',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPrimary,
                          foregroundColor: Colors.white,
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                        ),
                      );

                      if (constraints.maxWidth < 600) {
                        return Column(
                          children: [
                            SizedBox(
                              width: double.infinity,
                              child: draftBtn,
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: completeBtn,
                            ),
                          ],
                        );
                      }

                      return Row(
                        children: [
                          Expanded(child: draftBtn),
                          const SizedBox(width: 12),
                          Expanded(flex: 2, child: completeBtn),
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

  Widget _patientHeader(DoctorAppointment a) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: cardDecoration(),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: kSoftBlue,
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Icon(Icons.person, color: kPrimary),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.studentName.isEmpty ? 'Student' : a.studentName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: kText,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'ID: ${a.studentId} • '
                  '${a.studentDept} • '
                  "Batch '${a.studentBatch} • "
                  '${a.studentPhone}',
                  style: const TextStyle(fontSize: 11, color: kMuted),
                ),
                const SizedBox(height: 4),
                Text(
                  'Appointment: ${a.dateKey} • ${a.timeSlot}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: kPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _prescriptionSection() {
    return _section(
      title: 'Medication Prescription (Rx)',
      child: Column(
        children: [
          if (prescriptions.isEmpty)
            _readOnlyBox('No medicines prescribed yet.')
          else
            for (int i = 0; i < prescriptions.length; i++)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9F9FF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: kBorder.withOpacity(.6)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.medication_outlined,
                      color: kPrimary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            prescriptions[i].medicineName,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${prescriptions[i].dosage} • '
                            '${prescriptions[i].frequency} • '
                            '${prescriptions[i].duration} • '
                            '${prescriptions[i].timing}',
                            style: const TextStyle(
                              fontSize: 10,
                              color: kTeal,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove',
                      onPressed: () =>
                          setState(() => prescriptions.removeAt(i)),
                      icon: const Icon(
                        Icons.delete_outline,
                        color: Colors.red,
                        size: 19,
                      ),
                    ),
                  ],
                ),
              ),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: addMedicine,
              icon: const Icon(Icons.add),
              label: const Text('Add New Medicine'),
              style: OutlinedButton.styleFrom(
                foregroundColor: kPrimary,
                side: const BorderSide(color: kPrimary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: kText,
            ),
          ),
          const SizedBox(height: 9),
          child,
        ],
      ),
    );
  }

  Widget _readOnlyBox(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F9FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorder.withOpacity(.5)),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 11, color: kText, height: 1.5),
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

class PrescriptionPage extends StatelessWidget {
  final DoctorAppointment appointment;

  const PrescriptionPage({
    super.key,
    required this.appointment,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kPage,
      appBar: AppBar(
        backgroundColor: kPrimary,
        foregroundColor: Colors.white,
        title: const Text(
          'Prescription',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: kBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'CUET SmartCare',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: kPrimary,
                    ),
                  ),
                  const Text(
                    'Medical Center Prescription',
                    style: TextStyle(fontSize: 12, color: kMuted),
                  ),

                  const SizedBox(height: 14),

                  // Prescribing doctor — the piece that was missing
                  // before: student dashboards read this straight off
                  // the appointment document.
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: kSoftBlue,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.medical_services_rounded,
                          color: kPrimary,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                appointment.doctorName.isEmpty
                                    ? 'Attending Doctor'
                                    : 'Dr. ${appointment.doctorName}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: kPrimary,
                                ),
                              ),
                              if (appointment.doctorDesignation
                                      .isNotEmpty ||
                                  appointment.doctorSpecialization
                                      .isNotEmpty)
                                Text(
                                  [
                                    appointment.doctorDesignation,
                                    appointment.doctorSpecialization,
                                  ].where((s) => s.isNotEmpty).join(' • '),
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: kMuted,
                                  ),
                                ),
                              if (appointment.doctorChamber.isNotEmpty)
                                Text(
                                  'Chamber: ${appointment.doctorChamber}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: kMuted,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Divider(height: 30),
                  Text(
                    appointment.studentName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Student ID: '
                    '${appointment.studentId} • '
                    '${appointment.studentDept}',
                    style: const TextStyle(fontSize: 12, color: kMuted),
                  ),
                  const SizedBox(height: 20),
                  _labelValue(
                    'Diagnosis',
                    appointment.diagnosis.isEmpty
                        ? 'Not recorded'
                        : appointment.diagnosis,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Prescription',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: kPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (appointment.prescriptions.isEmpty)
                    _rxBox('No prescription items recorded.')
                  else
                    for (
                      int i = 0;
                      i < appointment.prescriptions.length;
                      i++
                    )
                      _rxBox(
                        '${i + 1}. '
                        '${appointment.prescriptions[i].medicineName}\n'
                        '${appointment.prescriptions[i].dosage} • '
                        '${appointment.prescriptions[i].frequency} • '
                        '${appointment.prescriptions[i].duration} • '
                        '${appointment.prescriptions[i].timing}',
                      ),
                  if (appointment.treatmentAdvice.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    _labelValue(
                      'Treatment Advice',
                      appointment.treatmentAdvice,
                    ),
                  ],
                  if (appointment.followUpDate.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    _labelValue('Follow-Up', appointment.followUpDate),
                  ],
                  const SizedBox(height: 18),
                  _labelValue(
                    'Vitals',
                    'BP: ${appointment.bloodPressure.isEmpty ? "Not recorded" : appointment.bloodPressure}\n'
                    'Temperature: ${appointment.temperature.isEmpty ? "Not recorded" : appointment.temperature}\n'
                    'Pulse: ${appointment.pulseRate.isEmpty ? "Not recorded" : appointment.pulseRate}',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _labelValue(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: kPrimary,
          ),
        ),
        const SizedBox(height: 5),
        Text(value, style: const TextStyle(fontSize: 13, height: 1.5)),
      ],
    );
  }

  Widget _rxBox(String text) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F9FF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text, style: const TextStyle(fontSize: 12, height: 1.6)),
    );
  }
}

// ============================================================
// HEALTH RECORDS PAGE
// ============================================================

class HealthRecordsPage extends StatelessWidget {
  final String doctorId;
  final DoctorRepository repo;

  const HealthRecordsPage({
    super.key,
    required this.doctorId,
    required this.repo,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kPage,
      appBar: AppBar(
        backgroundColor: kPrimary,
        foregroundColor: Colors.white,
        title: const Text(
          'Health Records',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: StreamBuilder<List<DoctorAppointment>>(
        stream: repo.watchHealthRecords(doctorId),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'Failed to load health records.\n${snap.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final records = snap.data ?? const <DoctorAppointment>[];

          if (records.isEmpty) {
            return const Center(
              child: Text('No completed health records yet.'),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: records.length,
            itemBuilder: (context, index) {
              final a = records[index];

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: kBorder),
                ),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                    backgroundColor: kSoftBlue,
                    child: Icon(
                      Icons.medical_information_outlined,
                      color: kPrimary,
                    ),
                  ),
                  title: Text(
                    a.diagnosis.isEmpty ? 'Consultation' : a.diagnosis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  subtitle: Text(
                    '${a.studentName} • '
                    'ID: ${a.studentId}\n'
                    '${a.dateKey} • '
                    '${a.prescriptions.length} prescription item(s)',
                    style: const TextStyle(fontSize: 10, height: 1.5),
                  ),
                  trailing: IconButton(
                    tooltip: 'View prescription',
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              PrescriptionPage(appointment: a),
                        ),
                      );
                    },
                    icon: const Icon(
                      Icons.chevron_right,
                      color: kPrimary,
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