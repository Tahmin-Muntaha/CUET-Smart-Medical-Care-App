import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'chat_page.dart';

class DoctorProfile {
  final String id;
  final String name;
  final String title;
  final String department;
  final List<String> degrees;
  final List<String> specialties;
  final bool isAvailableToday;
  final String nextAvailableTime;
  final String room;
  final String shift;
  final String bio;
  final String avatar;

  const DoctorProfile({
    required this.id,
    required this.name,
    required this.title,
    required this.department,
    required this.degrees,
    required this.specialties,
    required this.isAvailableToday,
    required this.nextAvailableTime,
    required this.room,
    required this.shift,
    required this.bio,
    required this.avatar,
  });

  factory DoctorProfile.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};

    return DoctorProfile(
      id: doc.id,

      name: _firstString([
        data['fullName'],
        data['name'],
        data['displayName'],
      ], fallback: 'Doctor'),

      title: _firstString([
        data['title'],
        data['designation'],
        data['professionalTitle'],
      ], fallback: 'Medical Doctor'),

      // IMPORTANT:
      // Department comes directly from users/{doctorId}.department
      department: _firstString([
        data['department'],
      ], fallback: 'General'),

      degrees: _stringList(
        data['degrees'] ??
            data['qualification'] ??
            data['qualifications'],
      ),

      specialties: _stringList(
        data['specialties'] ??
            data['specializations'] ??
            data['areasOfCare'],
      ),

      isAvailableToday:
          _boolValue(
            data['isAvailableToday'] ??
                data['availableToday'] ??
                data['isAvailable'],
          ),

      nextAvailableTime: _firstString([
        data['nextAvailableTime'],
        data['nextAvailable'],
      ], fallback: ''),

      room: _firstString([
        data['room'],
        data['chamber'],
      ], fallback: 'Not assigned'),

      shift: _firstString([
        data['shift'],
      ], fallback: ''),

      bio: _firstString([
        data['bio'],
        data['about'],
      ], fallback: ''),

      avatar: _firstString([
        data['avatar'],
        data['photoUrl'],
        data['profileImage'],
        data['imageUrl'],
      ], fallback: ''),
    );
  }

  static String _firstString(
    List<dynamic> values, {
    required String fallback,
  }) {
    for (final value in values) {
      if (value == null) continue;

      final text = value.toString().trim();

      if (text.isNotEmpty) {
        return text;
      }
    }

    return fallback;
  }

  static bool _boolValue(dynamic value) {
    if (value is bool) {
      return value;
    }

    if (value is String) {
      return value.toLowerCase() == 'true';
    }

    return false;
  }

  static List<String> _stringList(dynamic value) {
    if (value is List) {
      return value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }

    if (value is String) {
      return value
          .split(',')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }

    return [];
  }
}

class FindDoctors extends StatefulWidget {
  const FindDoctors({super.key});

  @override
  State<FindDoctors> createState() => _FindDoctorsState();
}

class _FindDoctorsState extends State<FindDoctors> {
  final TextEditingController _searchController =
      TextEditingController();

  String _searchText = '';

  // null means "All Departments"
  String? _selectedDepartment;

  @override
  void initState() {
    super.initState();

    _searchController.addListener(() {
      setState(() {
        _searchText = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ============================================================
  // FIRESTORE DOCTORS
  // ============================================================

  Stream<QuerySnapshot<Map<String, dynamic>>> _doctorStream() {
    return FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'doctor')
        .snapshots();
  }

  // ============================================================
  // BUILD DOCTOR LIST
  // ============================================================

  List<DoctorProfile> _getDoctors(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final doctors = snapshot.docs
        .map(
          (doc) => DoctorProfile.fromFirestore(doc),
        )
        .toList();

    // Sort alphabetically by doctor name.
    doctors.sort(
      (a, b) => a.name.toLowerCase().compareTo(
            b.name.toLowerCase(),
          ),
    );

    return doctors;
  }

  // ============================================================
  // GET DEPARTMENTS FROM DATABASE
  // ============================================================

  List<String> _getDepartments(
    List<DoctorProfile> doctors,
  ) {
    final departments = <String>{};

    for (final doctor in doctors) {
      final department = doctor.department.trim();

      if (department.isNotEmpty &&
          department.toLowerCase() != 'general') {
        departments.add(department);
      }
    }

    final result = departments.toList();

    result.sort(
      (a, b) => a.toLowerCase().compareTo(
            b.toLowerCase(),
          ),
    );

    return result;
  }

  // ============================================================
  // FILTER DOCTORS
  // ============================================================

  List<DoctorProfile> _filterDoctors(
    List<DoctorProfile> doctors,
  ) {
    return doctors.where((doctor) {
      // Department filter
      final departmentMatches =
          _selectedDepartment == null ||
          doctor.department.trim().toLowerCase() ==
              _selectedDepartment!.trim().toLowerCase();

      if (!departmentMatches) {
        return false;
      }

      // Search filter
      if (_searchText.isEmpty) {
        return true;
      }

      final searchableText = [
        doctor.name,
        doctor.title,
        doctor.department,
        doctor.degrees.join(' '),
        doctor.specialties.join(' '),
        doctor.room,
        doctor.shift,
      ].join(' ').toLowerCase();

      return searchableText.contains(_searchText);
    }).toList();
  }

  // ============================================================
  // DEPARTMENT FILTER
  // ============================================================

  Widget _buildDepartmentFilter(
    List<String> departments,
  ) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _departmentChip(
            title: 'All',
            selected: _selectedDepartment == null,
            onTap: () {
              setState(() {
                _selectedDepartment = null;
              });
            },
          ),

          const SizedBox(width: 8),

          ...departments.map(
            (department) {
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _departmentChip(
                  title: department,
                  selected:
                      _selectedDepartment == department,
                  onTap: () {
                    setState(() {
                      _selectedDepartment = department;
                    });
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _departmentChip({
    required String title,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return ChoiceChip(
      label: Text(
        title,
        overflow: TextOverflow.ellipsis,
      ),
      selected: selected,
      onSelected: (_) {
        onTap();
      },
      selectedColor: const Color(0xFF003D9B),
      backgroundColor: Colors.white,
      side: const BorderSide(
        color: Color(0xFFC3C6D6),
      ),
      labelStyle: TextStyle(
        color: selected
            ? Colors.white
            : const Color(0xFF30313D),
        fontWeight: FontWeight.w600,
      ),
    );
  }

  // ============================================================
  // DOCTOR CARD
  // ============================================================

  Widget _buildDoctorCard(
    DoctorProfile doctor,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFC3C6D6),
        ),
        boxShadow: const [
          BoxShadow(
            blurRadius: 8,
            offset: Offset(0, 3),
            color: Color(0x12000000),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDoctorAvatar(doctor),

              const SizedBox(width: 14),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      doctor.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF003D9B),
                      ),
                    ),

                    const SizedBox(height: 4),

                    Text(
                      doctor.title,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF5F6270),
                        fontWeight: FontWeight.w600,
                      ),
                    ),

                    const SizedBox(height: 6),

                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F3FF),
                        borderRadius:
                            BorderRadius.circular(8),
                      ),
                      child: Text(
                        doctor.department,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF003D9B),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          if (doctor.degrees.isNotEmpty)
            _infoRow(
              Icons.school_outlined,
              doctor.degrees.join(', '),
            ),

          if (doctor.specialties.isNotEmpty) ...[
            const SizedBox(height: 8),
            _infoRow(
              Icons.medical_services_outlined,
              doctor.specialties.join(', '),
            ),
          ],

          if (doctor.room.isNotEmpty) ...[
            const SizedBox(height: 8),
            _infoRow(
              Icons.location_on_outlined,
              'Room: ${doctor.room}',
            ),
          ],

          if (doctor.shift.isNotEmpty) ...[
            const SizedBox(height: 8),
            _infoRow(
              Icons.access_time_outlined,
              'Shift: ${doctor.shift}',
            ),
          ],

          if (doctor.bio.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              doctor.bio,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                color: Color(0xFF656876),
              ),
            ),
          ],

          const SizedBox(height: 14),

          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatPage(
                      peerId: doctor.id,
                      peerName: doctor.name,
                      peerRole: 'doctor',
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.chat_bubble_outline, size: 18),
              label: const Text('Message'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF003D9B),
                side: const BorderSide(color: Color(0xFF003D9B)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // DOCTOR AVATAR
  // ============================================================

  Widget _buildDoctorAvatar(
    DoctorProfile doctor,
  ) {
    if (doctor.avatar.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.network(
          doctor.avatar,
          width: 72,
          height: 72,
          fit: BoxFit.cover,
          errorBuilder: (
            context,
            error,
            stackTrace,
          ) {
            return _defaultDoctorAvatar();
          },
        ),
      );
    }

    return _defaultDoctorAvatar();
  }

  Widget _defaultDoctorAvatar() {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: const Color(0xFFE8EEFF),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Icon(
        Icons.person,
        size: 38,
        color: Color(0xFF003D9B),
      ),
    );
  }

  // ============================================================
  // INFO ROW
  // ============================================================

  Widget _infoRow(
    IconData icon,
    String text,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 18,
          color: const Color(0xFF00687A),
        ),

        const SizedBox(width: 8),

        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF4F5260),
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // EMPTY STATE
  // ============================================================

  Widget _emptyState(String message) {
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
            Icons.medical_services_outlined,
            size: 48,
            color: Color(0xFF8A8D9B),
          ),

          const SizedBox(height: 12),

          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF656876),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // MAIN UI
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),

      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        title: const Text(
          'Find Doctors',
          style: TextStyle(
            color: Color(0xFF003D9B),
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: const IconThemeData(
          color: Color(0xFF003D9B),
        ),
      ),

      body: StreamBuilder<
          QuerySnapshot<Map<String, dynamic>>>(
        stream: _doctorStream(),

        builder: (
          context,
          snapshot,
        ) {
          if (snapshot.connectionState ==
              ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 48,
                      color: Colors.red,
                    ),

                    const SizedBox(height: 12),

                    const Text(
                      'Could not load doctors.',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 8),

                    Text(
                      snapshot.error.toString(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          final doctors = _getDoctors(
            snapshot.data!,
          );

          final departments =
              _getDepartments(doctors);

          final filteredDoctors =
              _filterDoctors(doctors);

          return RefreshIndicator(
            onRefresh: () async {
              // Stream automatically updates.
              await Future<void>.delayed(
                const Duration(milliseconds: 300),
              );
            },

            child: ListView(
              physics:
                  const AlwaysScrollableScrollPhysics(),

              padding: const EdgeInsets.all(16),

              children: [
                // ==================================================
                // SEARCH
                // ==================================================

                TextField(
                  controller: _searchController,

                  decoration: InputDecoration(
                    hintText:
                        'Search doctor, specialty, or department...',

                    prefixIcon: const Icon(
                      Icons.search,
                      color: Color(0xFF003D9B),
                    ),

                    suffixIcon:
                        _searchText.isNotEmpty
                            ? IconButton(
                                icon: const Icon(
                                  Icons.clear,
                                ),
                                onPressed: () {
                                  _searchController.clear();
                                },
                              )
                            : null,

                    filled: true,

                    fillColor: Colors.white,

                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(14),
                      borderSide: const BorderSide(
                        color: Color(0xFFC3C6D6),
                      ),
                    ),

                    enabledBorder:
                        OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(14),
                      borderSide: const BorderSide(
                        color: Color(0xFFC3C6D6),
                      ),
                    ),

                    focusedBorder:
                        OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(14),
                      borderSide: const BorderSide(
                        color: Color(0xFF003D9B),
                        width: 1.5,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // ==================================================
                // DEPARTMENTS FROM FIRESTORE
                // ==================================================

                const Text(
                  'Department',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF30313D),
                  ),
                ),

                const SizedBox(height: 8),

                if (departments.isEmpty)
                  const Text(
                    'No departments found.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF777A87),
                    ),
                  )
                else
                  _buildDepartmentFilter(
                    departments,
                  ),

                const SizedBox(height: 18),

                // ==================================================
                // RESULT COUNT
                // ==================================================

                Text(
                  '${filteredDoctors.length} doctor${filteredDoctors.length == 1 ? '' : 's'} found',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF656876),
                  ),
                ),

                const SizedBox(height: 12),

                // ==================================================
                // DOCTORS
                // ==================================================

                if (filteredDoctors.isEmpty)
                  _emptyState(
                    'No doctors match your search or selected department.',
                  )
                else
                  ...filteredDoctors.map(
                    (doctor) =>
                        _buildDoctorCard(doctor),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}