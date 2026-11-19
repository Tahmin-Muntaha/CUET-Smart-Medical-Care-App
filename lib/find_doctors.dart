import 'package:flutter/material.dart'; // Flutter UI widgets
import 'package:cloud_firestore/cloud_firestore.dart'; // Firestore database

import 'chat_page.dart'; // The chat screen (opened by the Message button)

// Holds the information of one doctor shown in the list
class DoctorProfile {
  final String id; // Doctor's user id
  final String name; // Doctor's name
  final String title; // Doctor's title (e.g. Assistant Professor)
  final String department; // Doctor's department
  final List<String> degrees; // List of degrees
  final List<String> specialties; // List of specialties
  final bool isAvailableToday; // Is the doctor available today?
  final String nextAvailableTime; // Next available time text
  final String room; // Room / chamber
  final String shift; // Duty shift time
  final String bio; // Short bio
  final String avatar; // Photo link

  const DoctorProfile({
    required this.id, // Must be given
    required this.name, // Must be given
    required this.title, // Must be given
    required this.department, // Must be given
    required this.degrees, // Must be given
    required this.specialties, // Must be given
    required this.isAvailableToday, // Must be given
    required this.nextAvailableTime, // Must be given
    required this.room, // Must be given
    required this.shift, // Must be given
    required this.bio, // Must be given
    required this.avatar, // Must be given
  });

  // Builds a DoctorProfile from a Firestore document
  factory DoctorProfile.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {}; // Document data (empty map if missing)

    return DoctorProfile(
      id: doc.id, // Use the document id

      name: _firstString([
        data['fullName'], // Try fullName first
        data['name'], // Then name
        data['displayName'], // Then displayName
      ], fallback: 'Doctor'), // Else "Doctor"

      title: _firstString([
        data['title'], // Try title first
        data['designation'], // Then designation
        data['professionalTitle'], // Then professionalTitle
      ], fallback: 'Medical Doctor'), // Else "Medical Doctor"

      // IMPORTANT:
      // Department comes directly from users/{doctorId}.department
      department: _firstString([
        data['department'], // Read the department field
      ], fallback: 'General'), // Else "General"

      degrees: _stringList(
        data['degrees'] ?? // Try degrees
            data['qualification'] ?? // Then qualification
            data['qualifications'], // Then qualifications
      ),

      specialties: _stringList(
        data['specialties'] ?? // Try specialties
            data['specializations'] ?? // Then specializations
            data['areasOfCare'], // Then areasOfCare
      ),

      isAvailableToday:
          _boolValue(
            data['isAvailableToday'] ?? // Try isAvailableToday
                data['availableToday'] ?? // Then availableToday
                data['isAvailable'], // Then isAvailable
          ),

      nextAvailableTime: _firstString([
        data['nextAvailableTime'], // Try nextAvailableTime
        data['nextAvailable'], // Then nextAvailable
      ], fallback: ''), // Else empty

      room: _firstString([
        data['room'], // Try room
        data['chamber'], // Then chamber
      ], fallback: 'Not assigned'), // Else "Not assigned"

      shift: _firstString([
        data['shift'], // Read shift
      ], fallback: ''), // Else empty

      bio: _firstString([
        data['bio'], // Try bio
        data['about'], // Then about
      ], fallback: ''), // Else empty

      avatar: _firstString([
        data['avatar'], // Try avatar
        data['photoUrl'], // Then photoUrl
        data['profileImage'], // Then profileImage
        data['imageUrl'], // Then imageUrl
      ], fallback: ''), // Else empty
    );
  }

  // Returns the first non-empty text from a list of values
  static String _firstString(
    List<dynamic> values, {
    required String fallback,
  }) {
    for (final value in values) {
      // Check each value in order
      if (value == null) continue; // Skip nulls

      final text = value.toString().trim(); // Make clean text

      if (text.isNotEmpty) {
        // Found a real value?
        return text; // Use it
      }
    }

    return fallback; // Nothing found: use the fallback
  }

  // Converts a value to true/false
  static bool _boolValue(dynamic value) {
    if (value is bool) {
      // Already true/false?
      return value; // Use it
    }

    if (value is String) {
      // Text like "true"?
      return value.toLowerCase() == 'true'; // True only if it says "true"
    }

    return false; // Anything else is false
  }

  // Converts a value into a list of texts
  static List<String> _stringList(dynamic value) {
    if (value is List) {
      // Already a list?
      return value
          .map((item) => item.toString().trim()) // Clean each item
          .where((item) => item.isNotEmpty) // Remove empty ones
          .toList(); // Make a list
    }

    if (value is String) {
      // One text like "MBBS, MD"?
      return value
          .split(',') // Split at commas
          .map((item) => item.trim()) // Clean each item
          .where((item) => item.isNotEmpty) // Remove empty ones
          .toList(); // Make a list
    }

    return []; // Anything else: empty list
  }
}

// The page that lists doctors; it changes (search/filter), so it is Stateful
class FindDoctors extends StatefulWidget {
  const FindDoctors({super.key});

  @override
  State<FindDoctors> createState() => _FindDoctorsState(); // Create the state
}

class _FindDoctorsState extends State<FindDoctors> {
  final TextEditingController _searchController =
      TextEditingController(); // Controls the search box

  String _searchText = ''; // The current search text (lowercase)

  // null means "All Departments"
  String? _selectedDepartment; // Currently selected department

  @override
  void initState() {
    // Runs once when the page opens
    super.initState(); // Flutter's own setup

    _searchController.addListener(() {
      // Runs every time the search text changes
      setState(() {
        _searchText = _searchController.text.trim().toLowerCase(); // Save clean lowercase text
      });
    });
  }

  @override
  void dispose() {
    // Runs when the page closes
    _searchController.dispose(); // Free memory
    super.dispose(); // Flutter's own cleanup
  }

  // ============================================================
  // FIRESTORE DOCTORS
  // ============================================================

  // Live stream of all users who are doctors
  Stream<QuerySnapshot<Map<String, dynamic>>> _doctorStream() {
    return FirebaseFirestore.instance
        .collection('users') // Go to "users" collection
        .where('role', isEqualTo: 'doctor') // Only doctors
        .snapshots(); // Live updates
  }

  // ============================================================
  // BUILD DOCTOR LIST
  // ============================================================

  // Converts Firestore documents into a sorted list of doctors
  List<DoctorProfile> _getDoctors(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final doctors = snapshot.docs
        .map(
          (doc) => DoctorProfile.fromFirestore(doc), // Convert each document
        )
        .toList(); // Make a list

    // Sort alphabetically by doctor name.
    doctors.sort(
      (a, b) => a.name.toLowerCase().compareTo(
            b.name.toLowerCase(), // Compare names ignoring capital letters
          ),
    );

    return doctors; // Return the sorted list
  }

  // ============================================================
  // GET DEPARTMENTS FROM DATABASE
  // ============================================================

  // Collects the unique department names from the doctors
  List<String> _getDepartments(
    List<DoctorProfile> doctors,
  ) {
    final departments = <String>{}; // A set (no duplicates)

    for (final doctor in doctors) {
      // Check each doctor
      final department = doctor.department.trim(); // Clean department text

      if (department.isNotEmpty &&
          department.toLowerCase() != 'general') {
        // Skip empty and "General"
        departments.add(department); // Add to the set
      }
    }

    final result = departments.toList(); // Set -> list

    result.sort(
      (a, b) => a.toLowerCase().compareTo(
            b.toLowerCase(), // Sort A-Z ignoring capitals
          ),
    );

    return result; // Return the sorted list
  }

  // ============================================================
  // FILTER DOCTORS
  // ============================================================

  // Keeps only doctors matching the department and search text
  List<DoctorProfile> _filterDoctors(
    List<DoctorProfile> doctors,
  ) {
    return doctors.where((doctor) {
      // Department filter
      final departmentMatches =
          _selectedDepartment == null || // "All" selected: always matches
          doctor.department.trim().toLowerCase() ==
              _selectedDepartment!.trim().toLowerCase(); // Else must be the same department

      if (!departmentMatches) {
        // Wrong department?
        return false; // Remove this doctor
      }

      // Search filter
      if (_searchText.isEmpty) {
        // Nothing typed?
        return true; // Keep this doctor
      }

      final searchableText = [
        doctor.name, // Name
        doctor.title, // Title
        doctor.department, // Department
        doctor.degrees.join(' '), // Degrees
        doctor.specialties.join(' '), // Specialties
        doctor.room, // Room
        doctor.shift, // Shift
      ].join(' ').toLowerCase(); // Join all into one lowercase text

      return searchableText.contains(_searchText); // Keep if the text contains the search
    }).toList(); // Make a list
  }

  // ============================================================
  // DEPARTMENT FILTER
  // ============================================================

  // The row of department chips (scrolls sideways)
  Widget _buildDepartmentFilter(
    List<String> departments,
  ) {
    return SizedBox(
      height: 48, // Row height
      child: ListView(
        scrollDirection: Axis.horizontal, // Scroll left/right
        children: [
          _departmentChip(
            title: 'All', // The "All" chip
            selected: _selectedDepartment == null, // Selected when no department chosen
            onTap: () {
              setState(() {
                _selectedDepartment = null; // Show all departments
              });
            },
          ),

          const SizedBox(width: 8), // Gap

          ...departments.map(
            // One chip per department
            (department) {
              return Padding(
                padding: const EdgeInsets.only(right: 8), // Gap on the right
                child: _departmentChip(
                  title: department, // Department name
                  selected:
                      _selectedDepartment == department, // Selected if it is the chosen one
                  onTap: () {
                    setState(() {
                      _selectedDepartment = department; // Choose this department
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

  // One department chip
  Widget _departmentChip({
    required String title,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return ChoiceChip(
      label: Text(
        title, // Chip text
        overflow: TextOverflow.ellipsis, // "..." if too long
      ),
      selected: selected, // Is it selected?
      onSelected: (_) {
        // Runs when tapped
        onTap(); // Call the given function
      },
      selectedColor: const Color(0xFF003D9B), // Blue when selected
      backgroundColor: Colors.white, // White when not selected
      side: const BorderSide(
        color: Color(0xFFC3C6D6), // Grey border
      ),
      labelStyle: TextStyle(
        color: selected
            ? Colors.white // White text when selected
            : const Color(0xFF30313D), // Dark text otherwise
        fontWeight: FontWeight.w600, // Semi-bold
      ),
    );
  }

  // ============================================================
  // DOCTOR CARD
  // ============================================================

  // The card that shows one doctor
  Widget _buildDoctorCard(
    DoctorProfile doctor,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14), // Gap below the card
      padding: const EdgeInsets.all(16), // Space inside
      decoration: BoxDecoration(
        color: Colors.white, // White card
        borderRadius: BorderRadius.circular(18), // Round corners
        border: Border.all(
          color: const Color(0xFFC3C6D6), // Grey border
        ),
        boxShadow: const [
          BoxShadow(
            blurRadius: 8, // Shadow softness
            offset: Offset(0, 3), // Shadow moves down
            color: Color(0x12000000), // Very light shadow
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, // Align left
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start, // Align to top
            children: [
              _buildDoctorAvatar(doctor), // Doctor photo

              const SizedBox(width: 14), // Gap

              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start, // Align left
                  children: [
                    Text(
                      doctor.name, // Doctor's name
                      style: const TextStyle(
                        fontSize: 18, // Big text
                        fontWeight: FontWeight.bold, // Bold
                        color: Color(0xFF003D9B), // Blue
                      ),
                    ),

                    const SizedBox(height: 4), // Gap

                    Text(
                      doctor.title, // Doctor's title
                      style: const TextStyle(
                        fontSize: 14, // Medium text
                        color: Color(0xFF5F6270), // Grey
                        fontWeight: FontWeight.w600, // Semi-bold
                      ),
                    ),

                    const SizedBox(height: 6), // Gap

                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9, // Left/right space
                        vertical: 5, // Top/bottom space
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F3FF), // Light blue
                        borderRadius:
                            BorderRadius.circular(8), // Round corners
                      ),
                      child: Text(
                        doctor.department, // Department badge
                        style: const TextStyle(
                          fontSize: 12, // Small text
                          color: Color(0xFF003D9B), // Blue
                          fontWeight: FontWeight.bold, // Bold
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14), // Gap

          if (doctor.degrees.isNotEmpty)
            // Show degrees only if they exist
            _infoRow(
              Icons.school_outlined, // School icon
              doctor.degrees.join(', '), // Degrees as one text
            ),

          if (doctor.specialties.isNotEmpty) ...[
            // Show specialties only if they exist
            const SizedBox(height: 8), // Gap
            _infoRow(
              Icons.medical_services_outlined, // Medical icon
              doctor.specialties.join(', '), // Specialties as one text
            ),
          ],

          if (doctor.room.isNotEmpty) ...[
            // Show room only if it exists
            const SizedBox(height: 8), // Gap
            _infoRow(
              Icons.location_on_outlined, // Location icon
              'Room: ${doctor.room}', // Room text
            ),
          ],

          if (doctor.shift.isNotEmpty) ...[
            // Show shift only if it exists
            const SizedBox(height: 8), // Gap
            _infoRow(
              Icons.access_time_outlined, // Clock icon
              'Shift: ${doctor.shift}', // Shift text
            ),
          ],

          if (doctor.bio.isNotEmpty) ...[
            // Show bio only if it exists
            const SizedBox(height: 12), // Gap
            Text(
              doctor.bio, // Bio text
              maxLines: 3, // At most 3 lines
              overflow: TextOverflow.ellipsis, // "..." if too long
              style: const TextStyle(
                fontSize: 13, // Small text
                height: 1.4, // Line spacing
                color: Color(0xFF656876), // Grey
              ),
            ),
          ],

          const SizedBox(height: 14), // Gap

          SizedBox(
            width: double.infinity, // Full width button
            child: OutlinedButton.icon(
              onPressed: () {
                // Runs when "Message" is tapped
                Navigator.push(
                  context, // Current screen
                  MaterialPageRoute(
                    builder: (_) => ChatPage(
                      peerId: doctor.id, // Doctor's id
                      peerName: doctor.name, // Doctor's name
                      peerRole: 'doctor', // Role is doctor
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.chat_bubble_outline, size: 18), // Chat icon
              label: const Text('Message'), // Button label
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF003D9B), // Blue text
                side: const BorderSide(color: Color(0xFF003D9B)), // Blue border
                padding: const EdgeInsets.symmetric(vertical: 12), // Button height
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12), // Round corners
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

  // Shows the doctor's photo, or a default icon
  Widget _buildDoctorAvatar(
    DoctorProfile doctor,
  ) {
    if (doctor.avatar.isNotEmpty) {
      // Photo link exists?
      return ClipRRect(
        borderRadius: BorderRadius.circular(16), // Round the photo corners
        child: Image.network(
          doctor.avatar, // Load photo from the link
          width: 72, // Photo width
          height: 72, // Photo height
          fit: BoxFit.cover, // Fill the box
          errorBuilder: (
            context,
            error,
            stackTrace,
          ) {
            // Runs if the photo fails to load
            return _defaultDoctorAvatar(); // Show the default icon
          },
        ),
      );
    }

    return _defaultDoctorAvatar(); // No photo: show the default icon
  }

  // The default avatar (person icon in a box)
  Widget _defaultDoctorAvatar() {
    return Container(
      width: 72, // Box width
      height: 72, // Box height
      decoration: BoxDecoration(
        color: const Color(0xFFE8EEFF), // Light blue
        borderRadius: BorderRadius.circular(16), // Round corners
      ),
      child: const Icon(
        Icons.person, // Person icon
        size: 38, // Icon size
        color: Color(0xFF003D9B), // Blue
      ),
    );
  }

  // ============================================================
  // INFO ROW
  // ============================================================

  // One line with an icon and text
  Widget _infoRow(
    IconData icon,
    String text,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start, // Align to top
      children: [
        Icon(
          icon, // The given icon
          size: 18, // Icon size
          color: const Color(0xFF00687A), // Teal
        ),

        const SizedBox(width: 8), // Gap

        Expanded(
          child: Text(
            text, // The given text
            style: const TextStyle(
              fontSize: 13, // Small text
              color: Color(0xFF4F5260), // Dark grey
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // EMPTY STATE
  // ============================================================

  // The box shown when no doctor matches
  Widget _emptyState(String message) {
    return Container(
      width: double.infinity, // Full width
      padding: const EdgeInsets.all(30), // Space inside
      decoration: BoxDecoration(
        color: Colors.white, // White box
        borderRadius: BorderRadius.circular(18), // Round corners
        border: Border.all(
          color: const Color(0xFFC3C6D6), // Grey border
        ),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.medical_services_outlined, // Medical icon
            size: 48, // Big icon
            color: Color(0xFF8A8D9B), // Grey
          ),

          const SizedBox(height: 12), // Gap

          Text(
            message, // The message to show
            textAlign: TextAlign.center, // Center the text
            style: const TextStyle(
              color: Color(0xFF656876), // Grey
              fontSize: 14, // Text size
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
    // build() draws the screen
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC), // Page background

      appBar: AppBar(
        backgroundColor: Colors.white, // White top bar
        elevation: 0, // No shadow
        centerTitle: false, // Title on the left
        title: const Text(
          'Find Doctors', // Bar title
          style: TextStyle(
            color: Color(0xFF003D9B), // Blue
            fontWeight: FontWeight.bold, // Bold
          ),
        ),
        iconTheme: const IconThemeData(
          color: Color(0xFF003D9B), // Blue back arrow
        ),
      ),

      body: StreamBuilder<
          QuerySnapshot<Map<String, dynamic>>>(
        // Listens to live doctor data
        stream: _doctorStream(), // The data source

        builder: (
          context,
          snapshot,
        ) {
          // Runs every time new data arrives
          if (snapshot.connectionState ==
              ConnectionState.waiting) {
            // Still loading?
            return const Center(
              child: CircularProgressIndicator(), // Spinner
            );
          }

          if (snapshot.hasError) {
            // Failed to load?
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24), // Space around
                child: Column(
                  mainAxisSize: MainAxisSize.min, // Only as tall as needed
                  children: [
                    const Icon(
                      Icons.error_outline, // Error icon
                      size: 48, // Big icon
                      color: Colors.red, // Red
                    ),

                    const SizedBox(height: 12), // Gap

                    const Text(
                      'Could not load doctors.', // Error title
                      style: TextStyle(
                        fontSize: 17, // Text size
                        fontWeight: FontWeight.bold, // Bold
                      ),
                    ),

                    const SizedBox(height: 8), // Gap

                    Text(
                      snapshot.error.toString(), // The real error text
                      textAlign: TextAlign.center, // Center it
                      style: const TextStyle(
                        fontSize: 12, // Small text
                        color: Colors.grey, // Grey
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          final doctors = _getDoctors(
            snapshot.data!, // Convert data into doctor list
          );

          final departments =
              _getDepartments(doctors); // Get department names

          final filteredDoctors =
              _filterDoctors(doctors); // Apply search + department filter

          return RefreshIndicator(
            // Pull down to refresh
            onRefresh: () async {
              // Stream automatically updates.
              await Future<void>.delayed(
                const Duration(milliseconds: 300), // Short fake wait for the animation
              );
            },

            child: ListView(
              physics:
                  const AlwaysScrollableScrollPhysics(), // Always allow pulling

              padding: const EdgeInsets.all(16), // Space around

              children: [
                // ==================================================
                // SEARCH
                // ==================================================

                TextField(
                  controller: _searchController, // Connect the search controller

                  decoration: InputDecoration(
                    hintText:
                        'Search doctor, specialty, or department...', // Hint text

                    prefixIcon: const Icon(
                      Icons.search, // Search icon
                      color: Color(0xFF003D9B), // Blue
                    ),

                    suffixIcon:
                        _searchText.isNotEmpty
                            ? IconButton(
                                // Show clear button when text exists
                                icon: const Icon(
                                  Icons.clear, // X icon
                                ),
                                onPressed: () {
                                  _searchController.clear(); // Empty the search box
                                },
                              )
                            : null, // No button when empty

                    filled: true, // Fill the box with color

                    fillColor: Colors.white, // White fill

                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(14), // Round corners
                      borderSide: const BorderSide(
                        color: Color(0xFFC3C6D6), // Grey border
                      ),
                    ),

                    enabledBorder:
                        OutlineInputBorder(
                      // Border when not focused
                      borderRadius:
                          BorderRadius.circular(14), // Round corners
                      borderSide: const BorderSide(
                        color: Color(0xFFC3C6D6), // Grey border
                      ),
                    ),

                    focusedBorder:
                        OutlineInputBorder(
                      // Border when typing
                      borderRadius:
                          BorderRadius.circular(14), // Round corners
                      borderSide: const BorderSide(
                        color: Color(0xFF003D9B), // Blue border
                        width: 1.5, // Thicker line
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16), // Gap

                // ==================================================
                // DEPARTMENTS FROM FIRESTORE
                // ==================================================

                const Text(
                  'Department', // Section label
                  style: TextStyle(
                    fontSize: 15, // Text size
                    fontWeight: FontWeight.bold, // Bold
                    color: Color(0xFF30313D), // Dark
                  ),
                ),

                const SizedBox(height: 8), // Gap

                if (departments.isEmpty)
                  // No departments in the database?
                  const Text(
                    'No departments found.', // Message
                    style: TextStyle(
                      fontSize: 13, // Small text
                      color: Color(0xFF777A87), // Grey
                    ),
                  )
                else
                  // Otherwise show the chips
                  _buildDepartmentFilter(
                    departments, // Pass the department names
                  ),

                const SizedBox(height: 18), // Gap

                // ==================================================
                // RESULT COUNT
                // ==================================================

                Text(
                  '${filteredDoctors.length} doctor${filteredDoctors.length == 1 ? '' : 's'} found', // "1 doctor found" / "3 doctors found"
                  style: const TextStyle(
                    fontSize: 14, // Text size
                    fontWeight: FontWeight.w600, // Semi-bold
                    color: Color(0xFF656876), // Grey
                  ),
                ),

                const SizedBox(height: 12), // Gap

                // ==================================================
                // DOCTORS
                // ==================================================

                if (filteredDoctors.isEmpty)
                  // No match?
                  _emptyState(
                    'No doctors match your search or selected department.', // Message
                  )
                else
                  // Otherwise show one card per doctor
                  ...filteredDoctors.map(
                    (doctor) =>
                        _buildDoctorCard(doctor), // Build the card
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
