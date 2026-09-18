import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';

import 'login_page.dart'; // adjust if your LoginPage lives in a different file

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  // ============================================================
  // FIRESTORE REFERENCES
  // ============================================================

  final CollectionReference usersRef =
      FirebaseFirestore.instance.collection('users');
  final CollectionReference activitiesRef =
      FirebaseFirestore.instance.collection('activities');
  final CollectionReference alertsRef =
      FirebaseFirestore.instance.collection('alerts');
  final CollectionReference appointmentsRef =
      FirebaseFirestore.instance.collection('appointments');
  final CollectionReference announcementsRef =
      FirebaseFirestore.instance.collection('announcements');
  final CollectionReference chatsRef =
      FirebaseFirestore.instance.collection('chats');

  // ============================================================
  // STREAMS
  // ============================================================

  Stream<QuerySnapshot> get studentsStream =>
      usersRef.where('role', isEqualTo: 'student').snapshots();

  Stream<QuerySnapshot> get doctorsStream =>
      usersRef.where('role', isEqualTo: 'doctor').snapshots();

  Stream<QuerySnapshot> get activitiesStream => activitiesRef
      .orderBy('timestamp', descending: true)
      .limit(10)
      .snapshots();

  Stream<QuerySnapshot> get alertsStream =>
      alertsRef.orderBy('timestamp', descending: true).snapshots();

  // All appointments (newest first) – used by the new All Appointments dialog
  Stream<QuerySnapshot> get allAppointmentsStream => appointmentsRef
      .orderBy('date', descending: true)
      .limit(150)
      .snapshots();

  // Kept for the overview card count (today only)
  Stream<QuerySnapshot> get appointmentsTodayStream =>
      appointmentsRef.where('date', isEqualTo: _todayString()).snapshots();

  Stream<QuerySnapshot> get announcementsStream =>
      announcementsRef.orderBy('timestamp', descending: true).snapshots();

  // All conversations, newest activity first.
  Stream<QuerySnapshot> get allChatsStream =>
      chatsRef.orderBy('lastMessageAt', descending: true).snapshots();

  /// Appointments for the last 7 days (used by the System Stats trend chart).
  Stream<QuerySnapshot> get last7DaysAppointmentsStream => appointmentsRef
      .where('date', whereIn: _last7Days.map((d) => d.dateString).toList())
      .snapshots();

  String _todayString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  /// Rolling list of the last 7 days (oldest -> newest), with a pre-built
  /// 'yyyy-MM-dd' string for querying and a short weekday label for charts.
  List<({String dateString, String label})> get _last7Days {
    final now = DateTime.now();
    const weekdayLabels = [
      'Mon',
      'Tue',
      'Wed',
      'Thu',
      'Fri',
      'Sat',
      'Sun',
    ];
    return List.generate(7, (i) {
      final d = now.subtract(Duration(days: 6 - i));
      final dateString = '${d.year}-${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';
      return (
        dateString: dateString,
        label: weekdayLabels[d.weekday - 1],
      );
    });
  }

  String _timeAgo(Timestamp? timestamp) {
    if (timestamp == null) return '';
    final diff = DateTime.now().difference(timestamp.toDate());
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} minutes ago';
    if (diff.inHours < 24) return '${diff.inHours} hours ago';
    return '${diff.inDays} days ago';
  }

  String _formatTimestamp(Timestamp? timestamp) {
    if (timestamp == null) return '';
    final d = timestamp.toDate();
    final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final ampm = d.hour >= 12 ? 'PM' : 'AM';
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/${d.year}  '
        '$hour:${d.minute.toString().padLeft(2, '0')} $ampm';
  }

  // ============================================================
  // TOAST
  // ============================================================

  void showMessage(String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF003D9B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  // ============================================================
  // BROADCAST FORM (shared by Create + Edit)
  // ============================================================

  /// If [docId] is provided we're editing an existing announcement,
  /// pre-filled from [existing]. Otherwise this creates a brand new one.
  void showBroadcastFormDialog({String? docId, Map<String, dynamic>? existing}) {
    final bool isEditing = docId != null;

    final titleController =
        TextEditingController(text: existing?['title'] as String? ?? '');
    final contentController =
        TextEditingController(text: existing?['content'] as String? ?? '');

    String audience = (existing?['audience'] as String?) ?? 'All';
    String priority = (existing?['priority'] as String?) ?? 'Normal';

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE7EEFF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isEditing ? Icons.edit : Icons.campaign,
                      color: const Color(0xFF003D9B),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      isEditing
                          ? 'Edit Announcement'
                          : 'Broadcast Announcement',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  children: [
                    TextField(
                      controller: titleController,
                      decoration: InputDecoration(
                        labelText: 'Announcement Title',
                        hintText: 'e.g. Free Blood Grouping Camp',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: contentController,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: 'Detailed Content',
                        hintText: 'Enter announcement details...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      value: audience,
                      decoration: InputDecoration(
                        labelText: 'Target Audience',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'All',
                          child: Text('All Students & Doctors'),
                        ),
                        DropdownMenuItem(
                          value: 'Students',
                          child: Text('Students Only'),
                        ),
                        DropdownMenuItem(
                          value: 'Doctors',
                          child: Text('Doctors & Staff Only'),
                        ),
                      ],
                      onChanged: (value) {
                        setDialogState(() {
                          audience = value!;
                        });
                      },
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      value: priority,
                      decoration: InputDecoration(
                        labelText: 'Priority Level',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'Normal',
                          child: Text('Normal Announcement'),
                        ),
                        DropdownMenuItem(
                          value: 'Urgent',
                          child: Text('Urgent / High Priority'),
                        ),
                      ],
                      onChanged: (value) {
                        setDialogState(() {
                          priority = value!;
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton.icon(
                  onPressed: () async {
                    if (titleController.text.trim().isEmpty ||
                        contentController.text.trim().isEmpty) {
                      showMessage('Please fill in all announcement fields.');
                      return;
                    }

                    final navigator = Navigator.of(context);

                    try {
                      if (isEditing) {
                        await announcementsRef.doc(docId).update({
                          'title': titleController.text.trim(),
                          'content': contentController.text.trim(),
                          'audience': audience,
                          'priority': priority,
                          'updatedAt': FieldValue.serverTimestamp(),
                        });

                        await activitiesRef.add({
                          'title': 'Announcement updated: '
                              '${titleController.text.trim()}',
                          'timestamp': FieldValue.serverTimestamp(),
                        });

                        navigator.pop();
                        showMessage('Announcement updated successfully!');
                      } else {
                        await announcementsRef.add({
                          'title': titleController.text.trim(),
                          'content': contentController.text.trim(),
                          'audience': audience,
                          'priority': priority,
                          'timestamp': FieldValue.serverTimestamp(),
                        });

                        await activitiesRef.add({
                          'title': 'Announcement published: '
                              '${titleController.text.trim()}',
                          'timestamp': FieldValue.serverTimestamp(),
                        });

                        navigator.pop();
                        showMessage('Announcement broadcast successfully!');
                      }
                    } catch (e) {
                      showMessage(
                        isEditing
                            ? 'Failed to update: $e'
                            : 'Failed to broadcast: $e',
                      );
                    }
                  },
                  icon: Icon(isEditing ? Icons.save : Icons.send, size: 17),
                  label: Text(isEditing ? 'Save Changes' : 'Broadcast'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF003D9B),
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ============================================================
  // BROADCAST MANAGEMENT MODAL (list + edit + delete)
  // ============================================================

  void showBroadcastManagementDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFE7EEFF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.campaign, color: Color(0xFF003D9B)),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Broadcast Management',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  showBroadcastFormDialog();
                },
                icon: const Icon(Icons.add, size: 16),
                label: const Text('New'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF003D9B),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 680,
            height: 480,
            child: StreamBuilder<QuerySnapshot>(
              stream: announcementsStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data!.docs;

                if (docs.isEmpty) {
                  return const Center(
                    child: Text(
                      'No announcements broadcast yet.\nTap "New" to publish one.',
                      textAlign: TextAlign.center,
                    ),
                  );
                }

                return ListView.separated(
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final a = doc.data() as Map<String, dynamic>;
                    final bool urgent = a['priority'] == 'Urgent';

                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9F9FF),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: urgent
                              ? Colors.red.shade200
                              : const Color(0xFFC3C6D6),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        (a['title'] as String?) ?? '',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF111C2D),
                                        ),
                                      ),
                                    ),
                                    if (urgent)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.red.shade100,
                                          borderRadius:
                                              BorderRadius.circular(20),
                                        ),
                                        child: Text(
                                          'Urgent',
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.red.shade800,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  (a['content'] as String?) ?? '',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF434654),
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  children: [
                                    _pill(
                                      'Audience: ${a['audience'] ?? 'All'}',
                                    ),
                                    _pill(_formatTimestamp(
                                      a['timestamp'] as Timestamp?,
                                    )),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          Column(
                            children: [
                              IconButton(
                                tooltip: 'Edit',
                                icon: const Icon(
                                  Icons.edit,
                                  color: Color(0xFF003D9B),
                                  size: 20,
                                ),
                                onPressed: () {
                                  Navigator.pop(context);
                                  showBroadcastFormDialog(
                                    docId: doc.id,
                                    existing: a,
                                  );
                                },
                              ),
                              IconButton(
                                tooltip: 'Delete',
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.red,
                                  size: 20,
                                ),
                                onPressed: () => _confirmDeleteAnnouncement(
                                  doc.id,
                                  (a['title'] as String?) ?? 'this announcement',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF003D9B),
                foregroundColor: Colors.white,
              ),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _pill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFE7EEFF),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w600,
          color: Color(0xFF003D9B),
        ),
      ),
    );
  }

  void _confirmDeleteAnnouncement(String docId, String title) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text('Delete Announcement?'),
          content: Text(
            'This will permanently remove "$title" from the database. '
            'It will immediately disappear from student and doctor '
            'dashboards.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final navigator = Navigator.of(dialogContext);
                try {
                  await announcementsRef.doc(docId).delete();

                  await activitiesRef.add({
                    'title': 'Announcement deleted: $title',
                    'timestamp': FieldValue.serverTimestamp(),
                  });

                  navigator.pop();
                  showMessage('Announcement deleted.');
                } catch (e) {
                  navigator.pop();
                  showMessage('Failed to delete: $e');
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  // ============================================================
  // STUDENTS MODAL
  // ============================================================

  void showStudentsDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Row(
            children: [
              Icon(Icons.people, color: Color(0xFF003D9B)),
              SizedBox(width: 10),
              Text(
                'Registered Students',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: SizedBox(
            width: 650,
            height: 450,
            child: StreamBuilder<QuerySnapshot>(
              stream: studentsStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text('Error: ${snapshot.error}'),
                  );
                }

                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                final docs = snapshot.data!.docs;

                if (docs.isEmpty) {
                  return const Center(
                    child: Text('No registered students yet.'),
                  );
                }

                return ListView.separated(
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final student =
                        docs[index].data() as Map<String, dynamic>;
                    final name = (student['name'] as String?) ?? 'Unknown';
                    final bloodGroup =
                        (student['bloodGroup'] as String?) ?? 'Not set';
                    final hall = (student['hall'] as String?) ?? 'Not set';

                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9F9FF),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: const Color(0xFFC3C6D6),
                        ),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 23,
                            backgroundColor: const Color(0xFFE7EEFF),
                            child: Text(
                              name.isNotEmpty ? name[0].toUpperCase() : '?',
                              style: const TextStyle(
                                color: Color(0xFF003D9B),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF111C2D),
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'ID: ${student['studentId'] ?? 'N/A'}  •  '
                                  "Session: ${student['session'] ?? 'N/A'}",
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF434654),
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${student['email'] ?? 'N/A'}  •  Hall: $hall',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Color(0xFF737685),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE7EEFF),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'Blood: $bloodGroup',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF003D9B),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF003D9B),
                foregroundColor: Colors.white,
              ),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  // ============================================================
  // DOCTORS MODAL
  // ============================================================

  void showDoctorsDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Row(
            children: [
              Icon(Icons.medical_services, color: Color(0xFF00687A)),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Medical Center Physicians',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 650,
            height: 420,
            child: StreamBuilder<QuerySnapshot>(
              stream: doctorsStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                // Exclude rejected doctors, pending first.
                final docs = snapshot.data!.docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return data['status'] != 'rejected';
                }).toList()
                  ..sort((a, b) {
                    final statusA =
                        (a.data() as Map<String, dynamic>)['status'] ?? '';
                    final statusB =
                        (b.data() as Map<String, dynamic>)['status'] ?? '';
                    if (statusA == statusB) return 0;
                    if (statusA == 'pending') return -1;
                    if (statusB == 'pending') return 1;
                    return 0;
                  });

                if (docs.isEmpty) {
                  return const Center(child: Text('No doctors found.'));
                }

                return ListView.separated(
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final doctor = doc.data() as Map<String, dynamic>;
                    final String status =
                        (doctor['status'] as String?) ?? 'pending';
                    final bool isPending = status == 'pending';
                    final bool isApproved = status == 'approved';
                    final String licenseNumber =
                        (doctor['licenseNumber'] as String?) ?? 'N/A';

                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9F9FF),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isPending
                              ? Colors.amber.shade300
                              : const Color(0xFFC3C6D6),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE0F7FA),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.person,
                              color: Color(0xFF00687A),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  doctor['name'] ?? 'Unknown',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF111C2D),
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'License: $licenseNumber',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF00687A),
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${doctor['email'] ?? 'N/A'}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Color(0xFF737685),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (isPending)
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.shade100,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    'Pending',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.amber.shade900,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: 'Approve',
                                      icon: const Icon(
                                        Icons.check_circle,
                                        color: Colors.green,
                                      ),
                                      onPressed: () => _updateDoctorStatus(
                                        doc.id,
                                        'approved',
                                        doctor['name'] ?? 'Doctor',
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Reject',
                                      icon: const Icon(
                                        Icons.cancel,
                                        color: Colors.red,
                                      ),
                                      onPressed: () => _updateDoctorStatus(
                                        doc.id,
                                        'rejected',
                                        doctor['name'] ?? 'Doctor',
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            )
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: isApproved
                                    ? Colors.green.shade100
                                    : Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                isApproved ? 'Approved' : status,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: isApproved
                                      ? Colors.green.shade800
                                      : Colors.grey.shade800,
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF003D9B),
                foregroundColor: Colors.white,
              ),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _updateDoctorStatus(
    String docId,
    String newStatus,
    String doctorName,
  ) async {
    try {
      await usersRef.doc(docId).update({'status': newStatus});

      await activitiesRef.add({
        'title': newStatus == 'approved'
            ? 'Dr. $doctorName approved and can now log in'
            : 'Dr. $doctorName application rejected',
        'timestamp': FieldValue.serverTimestamp(),
      });

      showMessage(
        newStatus == 'approved'
            ? 'Doctor approved. They can now log in.'
            : 'Doctor application rejected.',
      );
    } catch (e) {
      debugPrint('Failed to update doctor status for $docId: $e');
      showMessage('Failed to update doctor status: $e');
    }
  }

  // ============================================================
  // DEPARTMENT MANAGEMENT MODAL
  // ============================================================

  static const List<MapEntry<String, String>> _cuetFacultyList = [
    MapEntry(
      'Faculty of Civil Engineering',
      'Civil Engineering (CE) • Water Resources Engineering (WRE) • '
          'Urban & Regional Planning (URP) • Architecture',
    ),
    MapEntry(
      'Faculty of Electrical & Computer Engineering',
      'Electrical & Electronic Engineering (EEE) • Computer Science & '
          'Engineering (CSE) • Electronics & Telecommunication Engineering '
          '(ETE) • Biomedical Engineering (BME)',
    ),
    MapEntry(
      'Faculty of Mechanical Engineering',
      'Mechanical Engineering (ME) • Industrial & Production Engineering '
          '(IPE) • Petroleum & Mining Engineering (PME) • Mechatronics & '
          'Industrial Engineering (MIE) • Materials Science & Engineering '
          '(MSE)',
    ),
    MapEntry(
      'Faculty of Science',
      'Physics • Chemistry • Mathematics',
    ),
    MapEntry(
      'Faculty of Humanities',
      'Humanities',
    ),
  ];

  void showDepartmentsDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Row(
            children: [
              Icon(Icons.business, color: Color(0xFF003D9B)),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'CUET Department Directory',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 650,
            height: 460,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE7EEFF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Chittagong University of Engineering & Technology '
                      'operates 5 faculties and 17 academic departments. '
                      'This directory is reference data (cuet.ac.bd) for '
                      'routing patient records and appointment requests to '
                      'the correct department.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF003D9B),
                        height: 1.5,
                      ),
                    ),
                  ),
                  ..._cuetFacultyList.map((entry) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9F9FF),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFC3C6D6)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.account_balance,
                                size: 16,
                                color: Color(0xFF003D9B),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  entry.key,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12.5,
                                    color: Color(0xFF111C2D),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            entry.value,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF434654),
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF003D9B),
                foregroundColor: Colors.white,
              ),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  // ============================================================
  // SCHEDULE MANAGEMENT MODAL
  // ============================================================

  static const List<Map<String, String>> _weeklySchedule = [
    {
      'day': 'Saturday',
      'hours': '8:00 AM – 8:00 PM',
      'service': 'General OPD, Pharmacy, Emergency',
      'duty': 'Dr. On Duty (Rotating Roster)',
    },
    {
      'day': 'Sunday',
      'hours': '8:00 AM – 8:00 PM',
      'service': 'General OPD, Pharmacy, Emergency',
      'duty': 'Dr. On Duty (Rotating Roster)',
    },
    {
      'day': 'Monday',
      'hours': '8:00 AM – 8:00 PM',
      'service': 'General OPD + Dental Checkup',
      'duty': 'Dental Surgeon available 10 AM – 1 PM',
    },
    {
      'day': 'Tuesday',
      'hours': '8:00 AM – 8:00 PM',
      'service': 'General OPD, Pharmacy, Emergency',
      'duty': 'Dr. On Duty (Rotating Roster)',
    },
    {
      'day': 'Wednesday',
      'hours': '8:00 AM – 8:00 PM',
      'service': 'General OPD + Gynecology Consultation',
      'duty': 'Gynecologist available 11 AM – 1 PM',
    },
    {
      'day': 'Thursday',
      'hours': '8:00 AM – 2:00 PM',
      'service': 'General OPD (Half Day)',
      'duty': 'Dr. On Duty (Rotating Roster)',
    },
    {
      'day': 'Friday',
      'hours': '24 Hours',
      'service': 'Emergency & Ambulance Only',
      'duty': 'On-Call Physician + Ambulance Crew',
    },
  ];

  void showSchedulesDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Row(
            children: [
              Icon(Icons.schedule, color: Color(0xFF00687A)),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Medical Center Weekly Schedule',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 680,
            height: 470,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0F7FA),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.local_hospital,
                            size: 16, color: Color(0xFF00687A)),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Ambulance & emergency line stay active 24/7, '
                            'every day of the week.',
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF00687A),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  ..._weeklySchedule.map((row) {
                    final bool isFriday = row['day'] == 'Friday';
                    return Container(
                      margin: const EdgeInsets.only(bottom: 9),
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: isFriday
                            ? Colors.amber.shade50
                            : const Color(0xFFF9F9FF),
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(
                          color: isFriday
                              ? Colors.amber.shade300
                              : const Color(0xFFC3C6D6),
                        ),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 90,
                            child: Text(
                              row['day']!,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: Color(0xFF111C2D),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  row['service']!,
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF111C2D),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  row['duty']!,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Color(0xFF737685),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: isFriday
                                  ? Colors.amber.shade100
                                  : const Color(0xFFE7EEFF),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              row['hours']!,
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                color: isFriday
                                    ? Colors.amber.shade900
                                    : const Color(0xFF003D9B),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF003D9B),
                foregroundColor: Colors.white,
              ),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  // ============================================================
  // ALL APPOINTMENTS DIALOG (new – full details + sort today’s)
  // ============================================================

  void showAllAppointmentsDialog() {
    bool showOnlyToday = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE7EEFF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.calendar_month,
                        color: Color(0xFF003D9B)),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'All Appointments',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 720,
                height: 520,
                child: Column(
                  children: [
                    // Sort / Filter controls
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              setDialogState(() {
                                showOnlyToday = true;
                              });
                            },
                            icon: const Icon(Icons.sort, size: 18),
                            label: const Text('Sort Today’s Appointments'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: showOnlyToday
                                  ? const Color(0xFF003D9B)
                                  : Colors.grey.shade300,
                              foregroundColor: showOnlyToday
                                  ? Colors.white
                                  : const Color(0xFF111C2D),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton.icon(
                          onPressed: () {
                            setDialogState(() {
                              showOnlyToday = false;
                            });
                          },
                          icon: const Icon(Icons.list, size: 18),
                          label: const Text('Show All'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: !showOnlyToday
                                ? const Color(0xFF003D9B)
                                : Colors.grey.shade300,
                            foregroundColor: !showOnlyToday
                                ? Colors.white
                                : const Color(0xFF111C2D),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: StreamBuilder<QuerySnapshot>(
                        stream: allAppointmentsStream,
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return Center(
                                child: Text('Error: ${snapshot.error}'));
                          }
                          if (!snapshot.hasData) {
                            return const Center(
                                child: CircularProgressIndicator());
                          }

                          List<QueryDocumentSnapshot> docs =
                              snapshot.data!.docs.toList();

                          // Filter to today if requested
                          if (showOnlyToday) {
                            final today = _todayString();
                            docs = docs
                                .where((d) {
                                  final data =
                                      d.data() as Map<String, dynamic>;
                                  return data['date'] == today;
                                })
                                .toList();
                          }

                          // Sort: pending → inConsultation → completed, then by time/queue
                          docs.sort((a, b) {
                            final da = a.data() as Map<String, dynamic>;
                            final db = b.data() as Map<String, dynamic>;

                            int statusOrder(String? s) {
                              switch (s) {
                                case 'booked':
                                  return 0;
                                case 'inConsultation':
                                  return 1;
                                case 'completed':
                                  return 2;
                                default:
                                  return 3;
                              }
                            }

                            final statusCmp = statusOrder(da['status'] as String?)
                                .compareTo(statusOrder(db['status'] as String?));
                            if (statusCmp != 0) return statusCmp;

                            // Secondary: time / queue number if present
                            final timeA = (da['time'] ?? da['appointmentTime'] ?? da['queueNumber'] ?? '').toString();
                            final timeB = (db['time'] ?? db['appointmentTime'] ?? db['queueNumber'] ?? '').toString();
                            return timeA.compareTo(timeB);
                          });

                          if (docs.isEmpty) {
                            return Center(
                              child: Text(
                                showOnlyToday
                                    ? 'No appointments scheduled for today.'
                                    : 'No appointments found.',
                                style: const TextStyle(
                                    color: Color(0xFF737685)),
                              ),
                            );
                          }

                          return ListView.separated(
                            itemCount: docs.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final doc = docs[index];
                              final data =
                                  doc.data() as Map<String, dynamic>;
                              return _appointmentCard(data);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF003D9B),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Beautiful detailed card for a single appointment
  Widget _appointmentCard(Map<String, dynamic> data) {
    final String status = (data['status'] as String?) ?? 'booked';
    final bool isCompleted = status == 'completed';
    final bool isInConsult = status == 'inConsultation';

    Color statusColor;
    String statusLabel;
    if (isCompleted) {
      statusColor = Colors.green;
      statusLabel = 'Completed';
    } else if (isInConsult) {
      statusColor = Colors.orange;
      statusLabel = 'In Consultation';
    } else {
      statusColor = const Color(0xFF003D9B);
      statusLabel = 'Booked';
    }

    // Helper to safely get string
    String s(String key, [String fallback = '—']) =>
        (data[key] as String?)?.trim().isNotEmpty == true
            ? data[key] as String
            : fallback;

    // Prescriptions may be String or List
    String prescriptionText = '';
    final presc = data['prescriptions'];
    if (presc is String && presc.trim().isNotEmpty) {
      prescriptionText = presc;
    } else if (presc is List && presc.isNotEmpty) {
      prescriptionText = presc.map((e) => e.toString()).join('\n');
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F9FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCompleted
              ? Colors.green.shade200
              : isInConsult
                  ? Colors.orange.shade200
                  : const Color(0xFFC3C6D6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Expanded(
                child: Text(
                  s('studentName', s('patientName', 'Student')),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Color(0xFF111C2D),
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Basic info
          _infoRow(Icons.calendar_today, 'Date', s('date')),
          _infoRow(Icons.access_time, 'Time / Queue',
              s('time', s('appointmentTime', s('queueNumber', '—')))),
          _infoRow(Icons.person, 'Doctor',
              s('doctorName', s('doctor', 'Not assigned'))),
          _infoRow(Icons.local_hospital, 'Department',
              s('doctorDepartment', s('department', '—'))),
          _infoRow(Icons.notes, 'Reason', s('reason', s('symptoms', '—'))),

          // Completed-only section
          if (isCompleted) ...[
            const Divider(height: 20),
            const Text(
              'Clinical Summary',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: Color(0xFF003D9B),
              ),
            ),
            const SizedBox(height: 6),
            _infoRow(Icons.medical_services, 'Diagnosis', s('diagnosis')),
            _infoRow(Icons.healing, 'Treatment Advice',
                s('treatmentAdvice')),
            if (prescriptionText.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.medication,
                        size: 16, color: Color(0xFF003D9B)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Prescription',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF737685),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            prescriptionText,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF111C2D),
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            // Vitals if present
            if (data['bloodPressure'] != null ||
                data['temperature'] != null ||
                data['pulseRate'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    if (data['bloodPressure'] != null)
                      _vitalChip('BP', data['bloodPressure'].toString()),
                    if (data['temperature'] != null)
                      _vitalChip('Temp', data['temperature'].toString()),
                    if (data['pulseRate'] != null)
                      _vitalChip('Pulse', data['pulseRate'].toString()),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: const Color(0xFF737685)),
          const SizedBox(width: 8),
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF737685),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF111C2D),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _vitalChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFE7EEFF),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Color(0xFF003D9B),
        ),
      ),
    );
  }

  // ============================================================
  // STATISTICS MODAL
  // ============================================================

  void showStatsDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Row(
            children: [
              Icon(Icons.bar_chart, color: Color(0xFF003D9B)),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'CUET Medical Center Analytics',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 700,
            height: 560,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _chartCard(
                    title: 'Appointments — Last 7 Days',
                    child: _appointmentsTrendChart(),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _chartCard(
                          title: 'Students vs Doctors',
                          child: _peopleBarChart(),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: _chartCard(
                          title: 'System Alerts',
                          child: _alertsPieChart(),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF003D9B),
                foregroundColor: Colors.white,
              ),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _chartCard({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F9FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFC3C6D6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Color(0xFF111C2D),
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _appointmentsTrendChart() {
    final days = _last7Days;

    return SizedBox(
      height: 190,
      child: StreamBuilder<QuerySnapshot>(
        stream: last7DaysAppointmentsStream,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final counts = {for (final d in days) d.dateString: 0};
          for (final doc in snapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            final date = data['date'] as String?;
            if (date != null && counts.containsKey(date)) {
              counts[date] = counts[date]! + 1;
            }
          }

          final spots = <FlSpot>[
            for (int i = 0; i < days.length; i++)
              FlSpot(i.toDouble(), counts[days[i].dateString]!.toDouble()),
          ];

          final maxY = counts.values.isEmpty
              ? 5.0
              : (counts.values.reduce((a, b) => a > b ? a : b) + 2)
                  .toDouble();

          return LineChart(
            LineChartData(
              minY: 0,
              maxY: maxY < 5 ? 5 : maxY,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: 1,
                getDrawingHorizontalLine: (value) => FlLine(
                  color: const Color(0xFFE3E6EF),
                  strokeWidth: 1,
                ),
              ),
              titlesData: FlTitlesData(
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 26,
                    interval: 1,
                    getTitlesWidget: (value, meta) {
                      if (value % 1 != 0) return const SizedBox.shrink();
                      return Text(
                        value.toInt().toString(),
                        style: const TextStyle(
                          fontSize: 9,
                          color: Color(0xFF737685),
                        ),
                      );
                    },
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    getTitlesWidget: (value, meta) {
                      final i = value.toInt();
                      if (i < 0 || i >= days.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          days[i].label,
                          style: const TextStyle(
                            fontSize: 9,
                            color: Color(0xFF737685),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  color: const Color(0xFF003D9B),
                  barWidth: 3,
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (spot, percent, bar, index) =>
                        FlDotCirclePainter(
                      radius: 3.5,
                      color: const Color(0xFF003D9B),
                      strokeWidth: 2,
                      strokeColor: Colors.white,
                    ),
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    color: const Color(0xFF003D9B).withOpacity(0.10),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _peopleBarChart() {
    return SizedBox(
      height: 190,
      child: StreamBuilder<QuerySnapshot>(
        stream: studentsStream,
        builder: (context, studentSnap) {
          return StreamBuilder<QuerySnapshot>(
            stream: doctorsStream,
            builder: (context, doctorSnap) {
              if (!studentSnap.hasData || !doctorSnap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final studentCount = studentSnap.data!.docs.length;
              final doctorCount = doctorSnap.data!.docs.where((d) {
                final data = d.data() as Map<String, dynamic>;
                return data['status'] == 'approved';
              }).length;

              final maxY = ([studentCount, doctorCount]
                          .reduce((a, b) => a > b ? a : b) +
                      2)
                  .toDouble();

              return BarChart(
                BarChartData(
                  maxY: maxY < 5 ? 5 : maxY,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: 1,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: const Color(0xFFE3E6EF),
                      strokeWidth: 1,
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 26,
                        getTitlesWidget: (value, meta) {
                          if (value % 1 != 0) return const SizedBox.shrink();
                          return Text(
                            value.toInt().toString(),
                            style: const TextStyle(
                              fontSize: 9,
                              color: Color(0xFF737685),
                            ),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 26,
                        getTitlesWidget: (value, meta) {
                          final label =
                              value.toInt() == 0 ? 'Students' : 'Doctors';
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              label,
                              style: const TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF737685),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barGroups: [
                    BarChartGroupData(
                      x: 0,
                      barRods: [
                        BarChartRodData(
                          toY: studentCount.toDouble(),
                          color: const Color(0xFF003D9B),
                          width: 34,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ],
                    ),
                    BarChartGroupData(
                      x: 1,
                      barRods: [
                        BarChartRodData(
                          toY: doctorCount.toDouble(),
                          color: const Color(0xFF00687A),
                          width: 34,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _alertsPieChart() {
    return SizedBox(
      height: 190,
      child: StreamBuilder<QuerySnapshot>(
        stream: alertsStream,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;
          final active = docs.where((d) {
            final data = d.data() as Map<String, dynamic>;
            return data['resolved'] == false;
          }).length;
          final resolved = docs.length - active;

          if (docs.isEmpty) {
            return const Center(
              child: Text(
                'No alerts recorded yet.',
                style: TextStyle(fontSize: 11, color: Color(0xFF737685)),
              ),
            );
          }

          return Row(
            children: [
              Expanded(
                child: PieChart(
                  PieChartData(
                    sectionsSpace: 3,
                    centerSpaceRadius: 32,
                    sections: [
                      PieChartSectionData(
                        value: active.toDouble(),
                        color: Colors.red.shade400,
                        title: active > 0 ? '$active' : '',
                        radius: 46,
                        titleStyle: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      PieChartSectionData(
                        value: resolved.toDouble(),
                        color: Colors.green.shade400,
                        title: resolved > 0 ? '$resolved' : '',
                        radius: 46,
                        titleStyle: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _legendDot('Active', Colors.red.shade400),
                  const SizedBox(height: 10),
                  _legendDot('Resolved', Colors.green.shade400),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _legendDot(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 10.5, color: Color(0xFF434654)),
        ),
      ],
    );
  }

  // ============================================================
  // LOGOUT
  // ============================================================

  Future<void> logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginPage()),
      (route) => false,
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFF003D9B),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Row(
          children: [
            Icon(Icons.favorite, color: Color(0xFF6AE1FF)),
            SizedBox(width: 10),
            Text(
              'CUET SmartCare',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: PopupMenuButton<String>(
              icon: const CircleAvatar(
                radius: 18,
                backgroundColor: Colors.white,
                child: Icon(
                  Icons.admin_panel_settings,
                  color: Color(0xFF003D9B),
                ),
              ),
              onSelected: (value) {
                if (value == 'logout') logout();
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'profile',
                  child: Row(
                    children: [
                      Icon(Icons.person_outline),
                      SizedBox(width: 10),
                      Text('Administrator'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'logout',
                  child: Row(
                    children: [
                      Icon(Icons.logout),
                      SizedBox(width: 10),
                      Text('Logout'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE7EEFF),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Text(
                                'Central Medical Administration',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF003D9B),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Administrative Dashboard',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF111C2D),
                              ),
                            ),
                            const SizedBox(height: 5),
                            const Text(
                              'CUET Medical Center System Overview, '
                              'Patient Operations & Resource Management.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF737685),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: () => showBroadcastFormDialog(),
                        icon: const Icon(Icons.campaign, size: 18),
                        label: const Text('Broadcast'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF003D9B),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 15,
                            vertical: 13,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _overviewCardsSection(),
                  const SizedBox(height: 25),
                  _allChatsDashboardSection(),
                  const SizedBox(height: 25),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth < 800) {
                        return Column(
                          children: [
                            _managementTools(),
                            const SizedBox(height: 25),
                            _activityFeed(),
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 2, child: _managementTools()),
                          const SizedBox(width: 25),
                          Expanded(child: _activityFeed()),
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

  // ============================================================
  // OVERVIEW CARDS SECTION
  // ============================================================

  Widget _overviewCardsSection() {
    return LayoutBuilder(
      builder: (context, constraints) {
        int columns = 1;
        if (constraints.maxWidth > 900) {
          columns = 4;
        } else if (constraints.maxWidth > 550) {
          columns = 2;
        }

        return GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 2.2,
          children: [
            StreamBuilder<QuerySnapshot>(
              stream: studentsStream,
              builder: (context, snapshot) {
                final count = snapshot.data?.docs.length ?? 0;
                return _overviewCard(
                  title: 'Registered Students',
                  value: snapshot.hasData ? '$count' : '...',
                  subtitle: 'Tap to view all',
                  icon: Icons.school,
                  color: const Color(0xFF003D9B),
                  onTap: showStudentsDialog,
                );
              },
            ),
            StreamBuilder<QuerySnapshot>(
              stream: doctorsStream,
              builder: (context, snapshot) {
                final docs = snapshot.data?.docs ?? [];
                final onDutyCount = docs.where((d) {
                  final data = d.data() as Map<String, dynamic>;
                  return data['status'] == 'approved';
                }).length;
                final pendingCount = docs.where((d) {
                  final data = d.data() as Map<String, dynamic>;
                  return data['status'] == 'pending';
                }).length;
                return _overviewCard(
                  title: 'Approved Doctors',
                  value: snapshot.hasData ? '$onDutyCount' : '...',
                  subtitle: pendingCount > 0
                      ? '$pendingCount Pending Approval'
                      : 'All Approved',
                  icon: Icons.medical_services,
                  color: const Color(0xFF00687A),
                  background: pendingCount > 0
                      ? Colors.amber.shade50
                      : Colors.white,
                  onTap: showDoctorsDialog,
                );
              },
            ),
            StreamBuilder<QuerySnapshot>(
              stream: allChatsStream,
              builder: (context, snapshot) {
                final count = snapshot.data?.docs.length ?? 0;
                return _overviewCard(
                  title: 'All Chats',
                  value: snapshot.hasData ? '$count' : '...',
                  subtitle: count > 0
                      ? 'Latest chat at top'
                      : 'No conversations',
                  icon: Icons.chat_bubble_outline,
                  color: const Color(0xFF003D9B),
                  background: const Color(0xFFF0F5FF),
                  onTap: showAllChatsDialog,
                );
              },
            ),
            // UPDATED: All Appointments card
            StreamBuilder<QuerySnapshot>(
              stream: allAppointmentsStream,
              builder: (context, snapshot) {
                final count = snapshot.data?.docs.length ?? 0;
                return _overviewCard(
                  title: 'All Appointments',
                  value: snapshot.hasData ? '$count' : '...',
                  subtitle: 'Tap to view details',
                  icon: Icons.calendar_month,
                  color: Colors.amber.shade700,
                  onTap: showAllAppointmentsDialog,
                );
              },
            ),
            StreamBuilder<QuerySnapshot>(
              stream: alertsStream,
              builder: (context, snapshot) {
                final docs = snapshot.data?.docs ?? [];
                final pending = docs.where((d) {
                  final data = d.data() as Map<String, dynamic>;
                  return data['resolved'] == false;
                }).length;
                return _overviewCard(
                  title: 'System Alerts',
                  value: snapshot.hasData ? '$pending' : '...',
                  subtitle: pending > 0 ? 'Requires Review' : 'All Clear',
                  icon: Icons.warning_amber,
                  color: Colors.red.shade700,
                  background:
                      pending > 0 ? const Color(0xFFFFF1F1) : Colors.white,
                  onTap: () {},
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _overviewCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    Color background = Colors.white,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFC3C6D6)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.7,
                      color: Color(0xFF737685),
                    ),
                  ),
                ),
                Icon(icon, color: color, size: 21),
              ],
            ),
            const Spacer(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 27,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF111C2D),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // ALL CHATS - ADMIN SECURITY MONITORING
  // ============================================================

  void showAllChatsDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.all(18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: SizedBox(
            width: 850,
            height: MediaQuery.of(context).size.height * 0.82,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 18, 12, 18),
                  decoration: const BoxDecoration(
                    color: Color(0xFF003D9B),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                    ),
                  ),
                  child: Row(
                    children: [
                      const CircleAvatar(
                        backgroundColor: Colors.white,
                        child: Icon(
                          Icons.security,
                          color: Color(0xFF003D9B),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'All Chats',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 19,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 3),
                            Text(
                              'Security monitoring • Most recent chat first',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: const Icon(Icons.close, color: Colors.white),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: allChatsStream,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'Could not load chats.\n\n${snapshot.error}',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        );
                      }

                      if (!snapshot.hasData) {
                        return const Center(
                          child: CircularProgressIndicator(),
                        );
                      }

                      final docs = snapshot.data!.docs;

                      if (docs.isEmpty) {
                        return const Center(
                          child: Text('No conversations yet.'),
                        );
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: docs.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final data =
                              docs[index].data() as Map<String, dynamic>;

                          return _adminChatCard(
                            chatId: docs[index].id,
                            data: data,
                            isCurrent: index == 0,
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _adminChatCard({
    required String chatId,
    required Map<String, dynamic> data,
    required bool isCurrent,
  }) {
    final participants = List<String>.from(data['participants'] ?? const []);
    final names = Map<String, dynamic>.from(
      data['participantNames'] ?? const {},
    );
    final roles = Map<String, dynamic>.from(
      data['participantRoles'] ?? const {},
    );

    String getName(String uid) =>
        (names[uid] ?? 'Unknown User').toString();

    String getRole(String uid) =>
        (roles[uid] ?? '').toString();

    final uid1 = participants.isNotEmpty ? participants[0] : '';
    final uid2 = participants.length > 1 ? participants[1] : '';
    final name1 = uid1.isEmpty ? 'Unknown User' : getName(uid1);
    final name2 = uid2.isEmpty ? 'Unknown User' : getName(uid2);
    final role1 = uid1.isEmpty ? '' : getRole(uid1);
    final role2 = uid2.isEmpty ? '' : getRole(uid2);

    final lastMessage = (data['lastMessage'] ?? '').toString();
    final lastSenderId = (data['lastSenderId'] ?? '').toString();
    final timestamp = data['lastMessageAt'] is Timestamp
        ? data['lastMessageAt'] as Timestamp
        : null;

    final preview = lastMessage.isEmpty
        ? 'No messages yet'
        : lastSenderId.isEmpty
            ? lastMessage
            : '${getName(lastSenderId)}: $lastMessage';

    return InkWell(
      onTap: () => showAdminChatMessagesDialog(
        chatId: chatId,
        title: '$name1 ↔ $name2',
      ),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: isCurrent ? const Color(0xFFF0F5FF) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isCurrent
                ? const Color(0xFF003D9B)
                : const Color(0xFFC3C6D6),
            width: isCurrent ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.035),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 25,
              backgroundColor: const Color(0xFFE7EEFF),
              child: Icon(
                role1 == 'doctor' || role2 == 'doctor'
                    ? Icons.medical_services_outlined
                    : Icons.forum_outlined,
                color: const Color(0xFF003D9B),
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '$name1  ↔  $name2',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF111C2D),
                          ),
                        ),
                      ),
                      if (isCurrent)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF003D9B),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: const Text(
                            'CURRENT',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 7,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${role1.isEmpty ? 'User' : role1} • '
                    '${role2.isEmpty ? 'User' : role2}',
                    style: const TextStyle(
                      fontSize: 9,
                      color: Color(0xFF003D9B),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    preview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF737685),
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _timeAgo(timestamp),
                  style: const TextStyle(
                    fontSize: 8,
                    color: Color(0xFF9A9DAB),
                  ),
                ),
                const SizedBox(height: 6),
                const Icon(
                  Icons.chevron_right,
                  color: Color(0xFF737685),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void showAdminChatMessagesDialog({
    required String chatId,
    required String title,
  }) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.all(18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: SizedBox(
            width: 700,
            height: MediaQuery.of(context).size.height * 0.78,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(18, 16, 10, 16),
                  decoration: const BoxDecoration(
                    color: Color(0xFF003D9B),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.visibility_outlined,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      const Text(
                        'READ ONLY',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: const Icon(Icons.close, color: Colors.white),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: chatsRef
                        .doc(chatId)
                        .collection('messages')
                        .orderBy('sentAt', descending: false)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'Could not load messages.\n\n${snapshot.error}',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        );
                      }

                      if (!snapshot.hasData) {
                        return const Center(
                          child: CircularProgressIndicator(),
                        );
                      }

                      final docs = snapshot.data!.docs;

                      if (docs.isEmpty) {
                        return const Center(
                          child: Text('No messages in this conversation.'),
                        );
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final message =
                              docs[index].data() as Map<String, dynamic>;
                          final senderName =
                              (message['senderName'] ?? 'User').toString();
                          final text =
                              (message['text'] ?? '').toString();
                          final sentAt = message['sentAt'] is Timestamp
                              ? message['sentAt'] as Timestamp
                              : null;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: const Color(0xFFE3E5EE),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.person_outline,
                                      size: 15,
                                      color: Color(0xFF003D9B),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        senderName,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF003D9B),
                                        ),
                                      ),
                                    ),
                                    Text(
                                      _formatTimestamp(sentAt),
                                      style: const TextStyle(
                                        fontSize: 9,
                                        color: Color(0xFF9A9DAB),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 7),
                                Text(
                                  text,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    height: 1.35,
                                    color: Color(0xFF111C2D),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _allChatsDashboardSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'All Conversations',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF111C2D),
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Security monitoring • Latest activity is shown first',
                    style: TextStyle(
                      fontSize: 10,
                      color: Color(0xFF737685),
                    ),
                  ),
                ],
              ),
            ),
            OutlinedButton.icon(
              onPressed: showAllChatsDialog,
              icon: const Icon(Icons.open_in_new, size: 15),
              label: const Text('View All'),
              style: ButtonStyle(
                foregroundColor:
                    const WidgetStatePropertyAll(Color(0xFF003D9B)),
                side: const WidgetStatePropertyAll(
                  BorderSide(color: Color(0xFF003D9B)),
                ),
                shape: WidgetStatePropertyAll(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(10)),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        StreamBuilder<QuerySnapshot>(
          stream: allChatsStream,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _chatStatusContainer('Failed to load conversations.');
            }
            if (!snapshot.hasData) {
              return _chatStatusContainer('Loading conversations...', true);
            }

            final docs = snapshot.data!.docs;
            if (docs.isEmpty) {
              return _chatStatusContainer('No conversations have been started yet.');
            }

            final visibleDocs = docs.take(5).toList();

            return Column(
              children: visibleDocs.asMap().entries.map((entry) {
                final index = entry.key;
                final doc = entry.value;
                final data = doc.data() as Map<String, dynamic>;
                final participants =
                    List<String>.from(data['participants'] ?? const []);
                final names = Map<String, dynamic>.from(
                    data['participantNames'] ?? const {});
                final firstName = participants.isNotEmpty
                    ? (names[participants[0]] ?? 'Unknown User').toString()
                    : 'Unknown User';
                final secondName = participants.length > 1
                    ? (names[participants[1]] ?? 'Unknown User').toString()
                    : 'Unknown User';
                final lastMessage = (data['lastMessage'] ?? '').toString();
                final timestamp = data['lastMessageAt'] is Timestamp
                    ? data['lastMessageAt'] as Timestamp
                    : null;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: InkWell(
                    onTap: () => showAdminChatMessagesDialog(
                      chatId: doc.id,
                      title: '$firstName ↔ $secondName',
                    ),
                    borderRadius: BorderRadius.circular(15),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: index == 0
                            ? const Color(0xFFF0F5FF)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                          color: index == 0
                              ? const Color(0xFF003D9B)
                              : const Color(0xFFC3C6D6),
                        ),
                      ),
                      child: Row(
                        children: [
                          const CircleAvatar(
                            radius: 20,
                            backgroundColor: Color(0xFFE7EEFF),
                            child: Icon(
                              Icons.forum_outlined,
                              size: 19,
                              color: Color(0xFF003D9B),
                            ),
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '$firstName ↔ $secondName',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF111C2D),
                                        ),
                                      ),
                                    ),
                                    if (index == 0)
                                      Container(
                                        margin: const EdgeInsets.only(left: 6),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF003D9B),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: const Text(
                                          'CURRENT',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 7,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  lastMessage.isEmpty
                                      ? 'No messages yet'
                                      : lastMessage,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Color(0xFF737685),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _timeAgo(timestamp),
                            style: const TextStyle(
                              fontSize: 8,
                              color: Color(0xFF9A9DAB),
                            ),
                          ),
                          const SizedBox(width: 3),
                          const Icon(
                            Icons.chevron_right,
                            size: 18,
                            color: Color(0xFF737685),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _chatStatusContainer(String message, [bool showProgress = false]) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFC3C6D6)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (showProgress)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF003D9B),
              ),
            )
          else
            const Icon(
              Icons.chat_bubble_outline,
              color: Color(0xFF737685),
              size: 22,
            ),
          const SizedBox(width: 10),
          Text(
            message,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF737685),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // MANAGEMENT TOOLS
  // ============================================================

  Widget _managementTools() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Administrative Tools',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: Color(0xFF111C2D),
          ),
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.35,
          children: [
            _toolButton('Manage\nStudents', Icons.people,
                const Color(0xFF003D9B), showStudentsDialog),
            _toolButton('Manage\nDoctors', Icons.medical_services,
                const Color(0xFF00687A), showDoctorsDialog),
            _toolButton('Manage\nDepartments', Icons.business,
                const Color(0xFF003D9B), showDepartmentsDialog),
            _toolButton('Manage\nSchedules', Icons.schedule,
                const Color(0xFF00687A), showSchedulesDialog),
            _toolButton('System\nStats', Icons.bar_chart,
                const Color(0xFF003D9B), showStatsDialog),
            _toolButton('Broadcast\nManagement', Icons.campaign,
                Colors.red.shade700, showBroadcastManagementDialog),
          ],
        ),
        const SizedBox(height: 20),
        _alertsSection(),
      ],
    );
  }

  Widget _toolButton(
    String title,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(17),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: const Color(0xFFC3C6D6)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withOpacity(0.10),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Color(0xFF111C2D),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // ALERTS SECTION
  // ============================================================

  Widget _alertsSection() {
    return StreamBuilder<QuerySnapshot>(
      stream: alertsStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final activeAlerts = snapshot.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return data['resolved'] == false;
        }).toList();

        if (activeAlerts.isEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 10),
                Text(
                  'All system alerts have been resolved.',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
          );
        }

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.red.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.warning_amber,
                      color: Colors.red.shade700, size: 19),
                  const SizedBox(width: 7),
                  Text(
                    'ACTIVE CAMPUS HEALTH ALERTS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.red.shade900,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...activeAlerts.map((doc) {
                final alert = doc.data() as Map<String, dynamic>;
                return Container(
                  margin: const EdgeInsets.only(bottom: 9),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              alert['title'] ?? '',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.red.shade900,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              alert['message'] ?? '',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.red.shade800,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              _timeAgo(alert['timestamp'] as Timestamp?),
                              style: TextStyle(
                                fontSize: 9,
                                color: Colors.red.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          try {
                            await alertsRef
                                .doc(doc.id)
                                .update({'resolved': true});
                            showMessage('Alert marked as resolved.');
                          } catch (e) {
                            showMessage('Failed to resolve alert: $e');
                          }
                        },
                        child: const Text(
                          'Resolve',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  // ============================================================
  // ACTIVITY FEED
  // ============================================================

  Widget _activityFeed() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Recent Campus Activity',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: Color(0xFF111C2D),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFC3C6D6)),
          ),
          child: StreamBuilder<QuerySnapshot>(
            stream: activitiesStream,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              final docs = snapshot.data!.docs;

              if (docs.isEmpty) {
                return const Text(
                  'No recent activity yet.',
                  style: TextStyle(fontSize: 11, color: Color(0xFF737685)),
                );
              }

              return Column(
                children: docs.map((doc) {
                  final activity = doc.data() as Map<String, dynamic>;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 15),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0F3FF),
                            borderRadius: BorderRadius.circular(50),
                          ),
                          child: const Icon(
                            Icons.check_circle_outline,
                            color: Color(0xFF003D9B),
                            size: 17,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                activity['title'] ?? '',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF111C2D),
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _timeAgo(activity['timestamp'] as Timestamp?),
                                style: const TextStyle(
                                  fontSize: 9,
                                  color: Color(0xFF737685),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ),
      ],
    );
  }
}