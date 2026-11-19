// ============================================================
// chat_page.dart
//
// Firestore layout:
//
// chats/{chatId}
//   -> participants       [uidA, uidB]
//   -> participantNames   { uid: displayName }
//   -> participantRoles   { uid: 'student' | 'doctor' }
//   -> lastMessage
//   -> lastMessageAt
//   -> lastSenderId
//
// chats/{chatId}/messages/{messageId}
//   -> senderId
//   -> senderName
//   -> text
//   -> sentAt
//
// chatId is deterministic: the two participants' UIDs are
// sorted alphabetically and joined with an underscore.
// ============================================================

import 'package:flutter/material.dart'; // Flutter UI widgets
import 'package:cloud_firestore/cloud_firestore.dart'; // Firestore database
import 'package:firebase_auth/firebase_auth.dart'; // Login / current user

const Color _kPrimary = Color(0xFF003D9B); // Main blue color of the app
const Color _kPage = Color(0xFFF5F7FB); // Light page background color

/// Creates the same chat ID for both users.
String buildChatId(String uidA, String uidB) {
  final ids = [uidA, uidB]..sort(); // Put both ids in a list and sort A-Z
  return '${ids[0]}_${ids[1]}'; // Join them with "_" (same result for both users)
}

// A page that can change (new messages, loading, etc.), so it is Stateful
class ChatPage extends StatefulWidget {
  final String peerId; // The other person's user id
  final String peerName; // The other person's name
  final String peerRole; // The other person's role (doctor/student)

  const ChatPage({
    super.key, // Optional widget key
    required this.peerId, // Must be given when opening the page
    required this.peerName, // Must be given
    required this.peerRole, // Must be given
  });

  @override
  State<ChatPage> createState() => _ChatPageState(); // Create the state object
}

class _ChatPageState extends State<ChatPage> {
  final _messageController = TextEditingController(); // Reads/clears the text box
  final _scrollController = ScrollController(); // Controls the message list scrolling
  final _db = FirebaseFirestore.instance; // Shortcut to Firestore

  late final String _myUid; // My user id (set later in initState)
  late final String _chatId; // The chat document id (set later)

  bool _sending = false; // True while a message is being sent
  bool _chatReady = false; // True when the chat document exists
  String? _chatError; // Error text (null means no error)

  @override
  void initState() {
    // Runs once when the page opens
    super.initState(); // Run Flutter's own setup first

    final currentUser = FirebaseAuth.instance.currentUser; // Get logged-in user

    if (currentUser == null) {
      // Nobody is logged in?
      return; // Stop here, nothing to prepare
    }

    _myUid = currentUser.uid; // Save my id
    _chatId = buildChatId(
      // Build the shared chat id
      _myUid, // My id
      widget.peerId, // The other person's id
    );

    _ensureChatDocument(); // Make sure the chat document exists in Firestore
  }

  @override
  void dispose() {
    // Runs once when the page closes
    _messageController.dispose(); // Free the text controller memory
    _scrollController.dispose(); // Free the scroll controller memory
    super.dispose(); // Run Flutter's own cleanup
  }

  // ============================================================
  // CREATE / PREPARE CHAT DOCUMENT
  // ============================================================

  Future<void> _ensureChatDocument() async {
    if (mounted) {
      // Only update UI if the page is still on screen
      setState(() {
        _chatError = null; // Clear any old error (for Retry button)
      });
    }

    try {
      // Try the steps; if any fails, go to catch
      final myDoc = await _db
          .collection('users') // Go to "users" collection
          .doc(_myUid) // Open my user document
          .get(); // Read it once

      final myData = myDoc.data() ?? {}; // My data (empty map if missing)

      final myName = (
        myData['name'] ?? // Use my saved name first
        FirebaseAuth.instance.currentUser?.email ?? // Else use my email
        'User' // Else just "User"
      ).toString(); // Make sure it is text

      final myRole = (myData['role'] ?? '').toString(); // My role (empty if missing)

      final chatRef = _db
          .collection('chats') // Go to "chats" collection
          .doc(_chatId); // Point to this chat's document

      final chatSnap = await chatRef.get(); // Read the chat document

      if (!chatSnap.exists) {
        // Chat does not exist yet?
        await chatRef.set({
          // Create it with starting data
          'participants': [
            // The two people in this chat
            _myUid, // Me
            widget.peerId, // The other person
          ],
          'participantNames': {
            // Names of both people
            _myUid: myName, // My name
            widget.peerId: widget.peerName, // Their name
          },
          'participantRoles': {
            // Roles of both people
            _myUid: myRole, // My role
            widget.peerId: widget.peerRole, // Their role
          },
          'lastMessage': '', // No message yet
          'lastMessageAt': FieldValue.serverTimestamp(), // Use server's current time
          'lastSenderId': '', // Nobody sent anything yet
        });
      } else {
        // Chat already exists
        await chatRef.update({
          // Just refresh the names
          'participantNames.$_myUid': myName, // Update my name
          'participantNames.${widget.peerId}': widget.peerName, // Update their name
        });
      }

      // Only reached on success: the chat document is now
      // guaranteed to exist, so it's safe to start listening
      // to its /messages subcollection.
      if (mounted) {
        // Page still open?
        setState(() {
          _chatReady = true; // Chat is ready, show the messages
        });
      }
    } catch (e) {
      // Something went wrong above
      // IMPORTANT: do NOT mark the chat as ready here. Previously
      // this error was only logged and _chatReady was still set to
      // true in a `finally` block, so the UI went on to listen to
      // chats/{chatId}/messages even though the chat document was
      // never actually created — that subcollection read then also
      // failed with PERMISSION_DENIED, which is the error you saw.
      debugPrint('Failed to prepare chat: $e'); // Print error in the console

      if (mounted) {
        // Page still open?
        setState(() {
          _chatError = // Save an error message to show the user
              'Failed to start this conversation. Please check your '
              'connection and try again.';
        });
      }
    }
  }

  // ============================================================
  // SEND MESSAGE
  // ============================================================

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim(); // Get typed text, remove extra spaces

    if (text.isEmpty || _sending) {
      // Empty text, or already sending?
      return; // Do nothing
    }

    setState(() {
      _sending = true; // Show the loading spinner on the send button
    });

    _messageController.clear(); // Empty the text box right away

    try {
      // Try to send the message
      final myDoc = await _db
          .collection('users') // Go to "users" collection
          .doc(_myUid) // Open my user document
          .get(); // Read it once

      final myName = (myDoc.data()?['name'] ?? 'User').toString(); // My name or "User"

      final chatRef = _db
          .collection('chats') // Go to "chats" collection
          .doc(_chatId); // Point to this chat

      // Add message
      await chatRef
          .collection('messages') // Open the messages subcollection
          .add({
        // Add a new message document
        'senderId': _myUid, // Who sent it
        'senderName': myName, // Sender's name
        'text': text, // The message text
        'sentAt': FieldValue.serverTimestamp(), // Server time when sent
      });

      // Update chat preview
      await chatRef.update({
        // Update info used in the chat list
        'lastMessage': text, // Latest message text
        'lastMessageAt': FieldValue.serverTimestamp(), // Latest message time
        'lastSenderId': _myUid, // Who sent the latest message
      });
    } catch (e) {
      // Sending failed
      if (!mounted) {
        // Page already closed?
        return; // Don't touch the UI
      }

      ScaffoldMessenger.of(context).showSnackBar(
        // Show a small message at the bottom
        SnackBar(
          content: Text(
            'Failed to send message: $e', // Tell the user what went wrong
          ),
        ),
      );
    } finally {
      // Always runs, success or fail
      if (mounted) {
        // Page still open?
        setState(() {
          _sending = false; // Stop the loading spinner
        });
      }
    }
  }

  // ============================================================
  // FORMAT MESSAGE TIME
  // ============================================================

  String _formatTime(dynamic value) {
    if (value is! Timestamp) {
      // Not a Firestore time yet? (new messages may be null for a moment)
      return ''; // Show no time
    }

    final date = value.toDate(); // Convert Firestore time to a normal DateTime

    final hour12 = date.hour % 12 == 0 // Convert 24-hour to 12-hour
        ? 12 // 0 and 12 both show as 12
        : date.hour % 12; // Otherwise use the remainder

    final period = date.hour >= 12 ? 'PM' : 'AM'; // Afternoon = PM, else AM

    final minute = date.minute
        .toString() // Turn minutes into text
        .padLeft(2, '0'); // Add a leading zero (5 -> 05)

    return '$hour12:$minute $period'; // Example: 3:07 PM
  }

  // ============================================================
  // BUILD PAGE
  // ============================================================

  @override
  Widget build(BuildContext context) {
    // build() draws the screen
    final currentUser = FirebaseAuth.instance.currentUser; // Get logged-in user

    if (currentUser == null) {
      // Not logged in?
      return const Scaffold(
        // Show a simple page
        body: Center(
          child: Text('Please log in.'), // Ask the user to log in
        ),
      );
    }

    return Scaffold(
      // Basic page layout
      backgroundColor: _kPage, // Page background color
      appBar: AppBar(
        // Top bar
        backgroundColor: _kPrimary, // Blue bar
        foregroundColor: Colors.white, // White text and icons
        elevation: 0, // No shadow
        title: Column(
          // Two lines of text in the title
          crossAxisAlignment: CrossAxisAlignment.start, // Align to the left
          children: [
            Text(
              widget.peerName, // Show the other person's name
              style: const TextStyle(
                fontWeight: FontWeight.bold, // Bold name
                fontSize: 16, // Name size
              ),
            ),
            Text(
              widget.peerRole == 'doctor'
                  ? 'Doctor' // Show "Doctor" for doctors
                  : 'Student', // Otherwise show "Student"
              style: const TextStyle(
                fontSize: 11, // Small text
                color: Colors.white70, // Slightly faded white
              ),
            ),
          ],
        ),
      ),
      body: _chatError != null // Is there an error?
          ? Center(
              // Yes: show the error screen
              child: Padding(
                padding: const EdgeInsets.all(24), // Space around content
                child: Column(
                  mainAxisSize: MainAxisSize.min, // Column only as tall as needed
                  children: [
                    const Icon(
                      Icons.error_outline, // Error icon
                      size: 40, // Icon size
                      color: Color(0xFF737685), // Grey color
                    ),
                    const SizedBox(height: 12), // Gap
                    Text(
                      _chatError!, // Show the error message
                      textAlign: TextAlign.center, // Center the text
                      style: const TextStyle(
                        color: Color(0xFF737685), // Grey text
                      ),
                    ),
                    const SizedBox(height: 16), // Gap
                    ElevatedButton(
                      onPressed: _ensureChatDocument, // Try again when tapped
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kPrimary, // Blue button
                        foregroundColor: Colors.white, // White text
                      ),
                      child: const Text('Retry'), // Button label
                    ),
                  ],
                ),
              ),
            )
          : !_chatReady // No error, but is the chat NOT ready yet?
              ? const Center(
                  // Yes: show a loading spinner
                  child: CircularProgressIndicator(),
                )
              : Column(
                  // Chat is ready: messages on top, input at bottom
                  children: [
                    Expanded(
                      // Messages take all the free space
                      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        // Listens to live message updates
                        stream: _db
                            .collection('chats') // Go to "chats"
                            .doc(_chatId) // Open this chat
                            .collection('messages') // Open its messages
                            .orderBy(
                              // Sort messages
                              'sentAt', // By sent time
                              descending: true, // Newest first
                            )
                            .snapshots(), // Live updates
                        builder: (context, snapshot) {
                          // Runs on every new data
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            // Still loading?
                            return const Center(
                              child: CircularProgressIndicator(), // Show spinner
                            );
                          }

                          if (snapshot.hasError) {
                            // Loading failed?
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24), // Space around
                                child: Text(
                                  'Failed to load messages.\n\n'
                                  '${snapshot.error}', // Show the real error
                                  textAlign: TextAlign.center, // Center the text
                                ),
                              ),
                            );
                          }

                          final docs = snapshot.data?.docs ?? []; // List of messages

                          if (docs.isEmpty) {
                            // No messages yet?
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24), // Space around
                                child: Text(
                                  'Say hello to '
                                  '${widget.peerName} '
                                  'to start the conversation.', // Friendly hint
                                  textAlign: TextAlign.center, // Center the text
                                  style: const TextStyle(
                                    color: Color(0xFF737685), // Grey text
                                  ),
                                ),
                              ),
                            );
                          }

                          return ListView.builder(
                            // Builds the message list
                            controller: _scrollController, // Use our scroll controller
                            reverse: true, // Start from the bottom (newest at bottom)
                            padding: const EdgeInsets.all(14), // Space around list
                            itemCount: docs.length, // Number of messages
                            itemBuilder: (context, index) {
                              // Builds one message
                              final data = docs[index].data(); // This message's data

                              final isMe = data['senderId'] == _myUid; // Did I send it?

                              return _MessageBubble(
                                // Show the message bubble
                                text: (data['text'] ?? '').toString(), // Message text
                                isMe: isMe, // Left or right side
                                time: _formatTime(
                                  data['sentAt'], // Format the sent time
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                    _buildInputBar(), // The typing box at the bottom
                  ],
                ),
    );
  }

  // ============================================================
  // MESSAGE INPUT
  // ============================================================

  Widget _buildInputBar() {
    return SafeArea(
      // Keeps the bar away from phone edges/notches
      child: Container(
        padding: const EdgeInsets.symmetric(
          // Inner space
          horizontal: 12, // Left and right
          vertical: 8, // Top and bottom
        ),
        decoration: const BoxDecoration(
          color: Colors.white, // White background
          border: Border(
            top: BorderSide(
              color: Color(0xFFE3E5EE), // Light grey line on top
            ),
          ),
        ),
        child: Row(
          // Text box and send button side by side
          children: [
            Expanded(
              // Text box takes the remaining width
              child: TextField(
                controller: _messageController, // Connect to our controller
                minLines: 1, // At least 1 line tall
                maxLines: 4, // Grow up to 4 lines
                textCapitalization: TextCapitalization.sentences, // Capital letter at sentence start
                decoration: InputDecoration(
                  hintText: 'Type a message...', // Placeholder text
                  filled: true, // Fill the box with color
                  fillColor: const Color(
                    0xFFF5F7FB, // Light background
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    // Space inside the box
                    horizontal: 16, // Left and right
                    vertical: 10, // Top and bottom
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24), // Round corners
                    borderSide: BorderSide.none, // No border line
                  ),
                ),
                onSubmitted: (_) => _sendMessage(), // Send when keyboard "done" is pressed
              ),
            ),
            const SizedBox(width: 8), // Gap between box and button
            CircleAvatar(
              // Round button background
              backgroundColor: _kPrimary, // Blue circle
              child: _sending // Are we sending right now?
                  ? const SizedBox(
                      // Yes: show a small spinner
                      width: 18, // Spinner width
                      height: 18, // Spinner height
                      child: CircularProgressIndicator(
                        strokeWidth: 2, // Thin line
                        color: Colors.white, // White spinner
                      ),
                    )
                  : IconButton(
                      // No: show the send button
                      icon: const Icon(
                        Icons.send, // Send arrow icon
                        color: Colors.white, // White icon
                        size: 20, // Icon size
                      ),
                      onPressed: _sendMessage, // Send when tapped
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// MESSAGE BUBBLE
// ============================================================

// One chat bubble; it never changes itself, so it is Stateless
class _MessageBubble extends StatelessWidget {
  final String text; // The message text
  final bool isMe; // True if I sent it
  final String time; // The time text to show

  const _MessageBubble({
    required this.text, // Must be given
    required this.isMe, // Must be given
    required this.time, // Must be given
  });

  @override
  Widget build(BuildContext context) {
    // build() draws the bubble
    return Align(
      // Place the bubble left or right
      alignment: isMe
          ? Alignment.centerRight // My messages on the right
          : Alignment.centerLeft, // Their messages on the left
      child: Container(
        margin: const EdgeInsets.symmetric(
          vertical: 4, // Space above and below the bubble
        ),
        padding: const EdgeInsets.symmetric(
          // Space inside the bubble
          horizontal: 14, // Left and right
          vertical: 10, // Top and bottom
        ),
        constraints: BoxConstraints(
          // Limit the bubble width
          maxWidth: MediaQuery.of(context).size.width * // Screen width
              0.72, // Use at most 72% of it
        ),
        decoration: BoxDecoration(
          color: isMe
              ? _kPrimary // Blue for my messages
              : Colors.white, // White for their messages
          borderRadius: BorderRadius.only(
            // Round the corners
            topLeft: const Radius.circular(16), // Top-left round
            topRight: const Radius.circular(16), // Top-right round
            bottomLeft: Radius.circular(
              isMe ? 16 : 4, // Small corner for their message tail
            ),
            bottomRight: Radius.circular(
              isMe ? 4 : 16, // Small corner for my message tail
            ),
          ),
          border: isMe
              ? null // No border for my bubble
              : Border.all(
                  // Light border for their bubble
                  color: const Color(
                    0xFFE3E5EE, // Light grey
                  ),
                ),
        ),
        child: Column(
          // Text on top, time below
          crossAxisAlignment: CrossAxisAlignment.end, // Align to the right
          mainAxisSize: MainAxisSize.min, // Only as tall as needed
          children: [
            Text(
              text, // The message text
              style: TextStyle(
                color: isMe
                    ? Colors.white // White text on blue
                    : const Color(
                        0xFF111C2D, // Dark text on white
                      ),
                fontSize: 14, // Text size
                height: 1.3, // Line spacing
              ),
            ),
            const SizedBox(height: 4), // Small gap
            Text(
              time, // The time text
              style: TextStyle(
                fontSize: 10, // Very small text
                color: isMe
                    ? Colors.white70 // Faded white on blue
                    : const Color(
                        0xFF9A9DAB, // Grey on white
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
