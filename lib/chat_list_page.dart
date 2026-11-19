// ============================================================
// chat_list_page.dart
//
// Shows every chats/{chatId} document where the logged-in user's
// uid is in the `participants` array, most recently active first.
//
// Works for both students and doctors.
// ============================================================

import 'package:flutter/material.dart'; // Flutter UI widgets
import 'package:cloud_firestore/cloud_firestore.dart'; // Firestore database
import 'package:firebase_auth/firebase_auth.dart'; // Login / current user

import 'chat_page.dart'; // The single chat screen we open on tap

const Color _kPrimary = Color(0xFF003D9B); // Main blue color of the app
const Color _kPage = Color(0xFFF5F7FB); // Light background color

// A page that never changes its own state, so StatelessWidget is enough
class ChatListPage extends StatelessWidget {
  const ChatListPage({super.key}); // Constructor (key is optional)

  @override
  Widget build(BuildContext context) {
    // build() draws the screen
    // Get the logged-in user's id (null if nobody is logged in)
    final myUid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      // Scaffold = basic page layout (app bar + body)
      backgroundColor: _kPage, // Set the page background color
      appBar: AppBar(
        // Top bar of the page
        backgroundColor: _kPrimary, // Blue top bar
        foregroundColor: Colors.white, // White text and icons on it
        elevation: 0, // Remove the shadow under the bar
        title: const Text('Messages'), // Title shown in the bar
      ),
      body: myUid == null // Check: is the user NOT logged in?
          ? const Center(
              // If yes, show a message in the center
              child: Text('Please log in.'), // Ask the user to log in
            )
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              // If logged in, listen to live Firestore data
              stream: FirebaseFirestore.instance // Open Firestore
                  .collection('chats') // Go to the "chats" collection
                  .where(
                    // Keep only chats that include me
                    'participants', // Look in the participants list
                    arrayContains: myUid, // It must contain my uid
                  )
                  .orderBy(
                    // Sort the chats
                    'lastMessageAt', // By the time of the last message
                    descending: true, // Newest chat first
                  )
                  .snapshots(), // Give live updates whenever data changes
              builder: (context, snapshot) {
                // Runs every time the stream sends new data
                if (snapshot.connectionState == ConnectionState.waiting) {
                  // Still loading the first data?
                  return const Center(
                    // Show a spinner in the center
                    child: CircularProgressIndicator(), // Loading circle
                  );
                }

                if (snapshot.hasError) {
                  // Did something go wrong?
                  return Center(
                    // Center the error message
                    child: Padding(
                      // Add space around the text
                      padding: const EdgeInsets.all(24), // 24 pixels on all sides
                      child: Text(
                        // Show the error text
                        'Could not load messages.\n\n${snapshot.error}', // Message + real error
                        textAlign: TextAlign.center, // Center the text
                      ),
                    ),
                  );
                }

                // Get the list of chat documents (empty list if null)
                final docs = snapshot.data?.docs ?? [];

                if (docs.isEmpty) {
                  // No chats exist yet?
                  return ListView(
                    // Use a list so the page can still be pulled
                    physics: const AlwaysScrollableScrollPhysics(), // Always scrollable
                    children: const [
                      SizedBox(height: 140), // Empty space at the top
                      Icon(
                        // Big chat icon
                        Icons.chat_bubble_outline, // Outline bubble shape
                        size: 56, // Icon size
                        color: _kPrimary, // Blue color
                      ),
                      SizedBox(height: 16), // Small gap
                      Center(
                        // Center the title text
                        child: Text(
                          'No conversations yet', // Title text
                          style: TextStyle(
                            // Text style
                            fontSize: 17, // Text size
                            fontWeight: FontWeight.bold, // Bold text
                          ),
                        ),
                      ),
                      SizedBox(height: 6), // Tiny gap
                      Padding(
                        // Space on left and right
                        padding: EdgeInsets.symmetric(horizontal: 40), // 40 px each side
                        child: Text(
                          'Start a conversation from Find Doctors.', // Hint text
                          textAlign: TextAlign.center, // Center it
                          style: TextStyle(
                            color: Color(0xFF737685), // Grey color
                          ),
                        ),
                      ),
                    ],
                  );
                }

                return ListView.separated(
                  // List with a line between items
                  padding: const EdgeInsets.all(12), // Space around the list
                  itemCount: docs.length, // How many chats to show
                  separatorBuilder: (_, __) => const Divider(height: 1), // Thin line between items
                  itemBuilder: (context, index) {
                    // Builds one row per chat
                    final data = docs[index].data(); // Data of this chat as a Map

                    // Convert the participants field into a list of strings
                    final participants = List<String>.from(
                      data['participants'] ?? [], // Use empty list if missing
                    );

                    // Find the other person's id (the one who is not me)
                    final peerId = participants.firstWhere(
                      (id) => id != myUid, // Pick the id that is not mine
                      orElse: () => '', // If none found, use empty text
                    );

                    if (peerId.isEmpty) {
                      // No other person found?
                      return const SizedBox.shrink(); // Show nothing for this row
                    }

                    // Map of userId -> name stored in the chat document
                    final names = Map<String, dynamic>.from(
                      data['participantNames'] ?? {}, // Empty map if missing
                    );

                    // Map of userId -> role ("doctor" or "student")
                    final roles = Map<String, dynamic>.from(
                      data['participantRoles'] ?? {}, // Empty map if missing
                    );

                    // The other person's name (default is "User")
                    final peerName = (names[peerId] ?? 'User').toString();

                    // The other person's role (default is empty)
                    final peerRole = (roles[peerId] ?? '').toString();

                    // The last message text (empty if none)
                    final lastMessage = (data['lastMessage'] ?? '').toString();

                    // Who sent the last message
                    final lastSenderId = (data['lastSenderId'] ?? '').toString();

                    return ListTile(
                      // One row in the list
                      contentPadding: const EdgeInsets.symmetric(
                        // Inner space of the row
                        horizontal: 8, // Left and right space
                        vertical: 6, // Top and bottom space
                      ),
                      leading: CircleAvatar(
                        // Round picture on the left
                        backgroundColor: const Color(0xFFE7EEFF), // Light blue circle
                        child: Icon(
                          // Icon inside the circle
                          peerRole == 'doctor'
                              ? Icons.medical_services_outlined // Doctor icon
                              : Icons.person, // Normal person icon
                          color: _kPrimary, // Blue icon color
                        ),
                      ),
                      title: Text(
                        // Main text of the row
                        peerName, // The other person's name
                        style: const TextStyle(
                          fontWeight: FontWeight.bold, // Make the name bold
                        ),
                      ),
                      subtitle: Text(
                        // Small text under the name
                        lastMessage.isEmpty
                            ? 'Say hello 👋' // No message yet
                            : (lastSenderId == myUid
                                ? 'You: $lastMessage' // I sent the last message
                                : lastMessage), // The other person sent it
                        maxLines: 1, // Only one line allowed
                        overflow: TextOverflow.ellipsis, // Show "..." if too long
                        style: const TextStyle(
                          color: Color(0xFF737685), // Grey text
                        ),
                      ),
                      onTap: () {
                        // Runs when the user taps this row
                        Navigator.push(
                          // Go to a new screen
                          context, // Current screen info
                          MaterialPageRoute(
                            // Normal slide animation
                            builder: (_) => ChatPage(
                              // Open the chat screen
                              peerId: peerId, // Pass the other person's id
                              peerName: peerName, // Pass their name
                              peerRole: peerRole, // Pass their role
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
    );
  }
}
