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

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

const Color _kPrimary = Color(0xFF003D9B);
const Color _kPage = Color(0xFFF5F7FB);

/// Creates the same chat ID for both users.
String buildChatId(String uidA, String uidB) {
  final ids = [uidA, uidB]..sort();
  return '${ids[0]}_${ids[1]}';
}

class ChatPage extends StatefulWidget {
  final String peerId;
  final String peerName;
  final String peerRole;

  const ChatPage({
    super.key,
    required this.peerId,
    required this.peerName,
    required this.peerRole,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _db = FirebaseFirestore.instance;

  late final String _myUid;
  late final String _chatId;

  bool _sending = false;
  bool _chatReady = false;
  String? _chatError;

  @override
  void initState() {
    super.initState();

    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      return;
    }

    _myUid = currentUser.uid;
    _chatId = buildChatId(
      _myUid,
      widget.peerId,
    );

    _ensureChatDocument();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ============================================================
  // CREATE / PREPARE CHAT DOCUMENT
  // ============================================================

  Future<void> _ensureChatDocument() async {
    if (mounted) {
      setState(() {
        _chatError = null;
      });
    }

    try {
      final myDoc = await _db
          .collection('users')
          .doc(_myUid)
          .get();

      final myData = myDoc.data() ?? {};

      final myName = (
        myData['name'] ??
        FirebaseAuth.instance.currentUser?.email ??
        'User'
      ).toString();

      final myRole =
          (myData['role'] ?? '').toString();

      final chatRef = _db
          .collection('chats')
          .doc(_chatId);

      final chatSnap = await chatRef.get();

      if (!chatSnap.exists) {
        await chatRef.set({
          'participants': [
            _myUid,
            widget.peerId,
          ],
          'participantNames': {
            _myUid: myName,
            widget.peerId: widget.peerName,
          },
          'participantRoles': {
            _myUid: myRole,
            widget.peerId: widget.peerRole,
          },
          'lastMessage': '',
          'lastMessageAt':
              FieldValue.serverTimestamp(),
          'lastSenderId': '',
        });
      } else {
        await chatRef.update({
          'participantNames.$_myUid': myName,
          'participantNames.${widget.peerId}':
              widget.peerName,
        });
      }

      // Only reached on success: the chat document is now
      // guaranteed to exist, so it's safe to start listening
      // to its /messages subcollection.
      if (mounted) {
        setState(() {
          _chatReady = true;
        });
      }
    } catch (e) {
      // IMPORTANT: do NOT mark the chat as ready here. Previously
      // this error was only logged and _chatReady was still set to
      // true in a `finally` block, so the UI went on to listen to
      // chats/{chatId}/messages even though the chat document was
      // never actually created — that subcollection read then also
      // failed with PERMISSION_DENIED, which is the error you saw.
      debugPrint('Failed to prepare chat: $e');

      if (mounted) {
        setState(() {
          _chatError =
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
    final text =
        _messageController.text.trim();

    if (text.isEmpty || _sending) {
      return;
    }

    setState(() {
      _sending = true;
    });

    _messageController.clear();

    try {
      final myDoc = await _db
          .collection('users')
          .doc(_myUid)
          .get();

      final myName =
          (myDoc.data()?['name'] ?? 'User')
              .toString();

      final chatRef = _db
          .collection('chats')
          .doc(_chatId);

      // Add message
      await chatRef
          .collection('messages')
          .add({
        'senderId': _myUid,
        'senderName': myName,
        'text': text,
        'sentAt':
            FieldValue.serverTimestamp(),
      });

      // Update chat preview
      await chatRef.update({
        'lastMessage': text,
        'lastMessageAt':
            FieldValue.serverTimestamp(),
        'lastSenderId': _myUid,
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            'Failed to send message: $e',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  // ============================================================
  // FORMAT MESSAGE TIME
  // ============================================================

  String _formatTime(dynamic value) {
    if (value is! Timestamp) {
      return '';
    }

    final date = value.toDate();

    final hour12 =
        date.hour % 12 == 0
            ? 12
            : date.hour % 12;

    final period =
        date.hour >= 12 ? 'PM' : 'AM';

    final minute =
        date.minute
            .toString()
            .padLeft(2, '0');

    return '$hour12:$minute $period';
  }

  // ============================================================
  // BUILD PAGE
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final currentUser =
        FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      return const Scaffold(
        body: Center(
          child: Text('Please log in.'),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _kPage,
      appBar: AppBar(
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Text(
              widget.peerName,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            Text(
              widget.peerRole == 'doctor'
                  ? 'Doctor'
                  : 'Student',
              style: const TextStyle(
                fontSize: 11,
                color: Colors.white70,
              ),
            ),
          ],
        ),
      ),
      body: _chatError != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 40,
                      color: Color(0xFF737685),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _chatError!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF737685),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _ensureChatDocument,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kPrimary,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : !_chatReady
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : Column(
              children: [
                Expanded(
                  child: StreamBuilder<
                      QuerySnapshot<
                          Map<String, dynamic>>>(
                    stream: _db
                        .collection('chats')
                        .doc(_chatId)
                        .collection('messages')
                        .orderBy(
                          'sentAt',
                          descending: true,
                        )
                        .snapshots(),
                    builder:
                        (context, snapshot) {
                      if (snapshot
                              .connectionState ==
                          ConnectionState
                              .waiting) {
                        return const Center(
                          child:
                              CircularProgressIndicator(),
                        );
                      }

                      if (snapshot.hasError) {
                        return Center(
                          child: Padding(
                            padding:
                                const EdgeInsets
                                    .all(24),
                            child: Text(
                              'Failed to load messages.\n\n'
                              '${snapshot.error}',
                              textAlign:
                                  TextAlign.center,
                            ),
                          ),
                        );
                      }

                      final docs =
                          snapshot.data?.docs ??
                              [];

                      if (docs.isEmpty) {
                        return Center(
                          child: Padding(
                            padding:
                                const EdgeInsets
                                    .all(24),
                            child: Text(
                              'Say hello to '
                              '${widget.peerName} '
                              'to start the conversation.',
                              textAlign:
                                  TextAlign.center,
                              style:
                                  const TextStyle(
                                color:
                                    Color(
                                  0xFF737685,
                                ),
                              ),
                            ),
                          ),
                        );
                      }

                      return ListView.builder(
                        controller:
                            _scrollController,
                        reverse: true,
                        padding:
                            const EdgeInsets.all(
                          14,
                        ),
                        itemCount: docs.length,
                        itemBuilder:
                            (context, index) {
                          final data =
                              docs[index].data();

                          final isMe =
                              data['senderId'] ==
                                  _myUid;

                          return _MessageBubble(
                            text: (data['text'] ??
                                    '')
                                .toString(),
                            isMe: isMe,
                            time:
                                _formatTime(
                              data['sentAt'],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                _buildInputBar(),
              ],
            ),
    );
  }

  // ============================================================
  // MESSAGE INPUT
  // ============================================================

  Widget _buildInputBar() {
    return SafeArea(
      child: Container(
        padding:
            const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 8,
        ),
        decoration:
            const BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(
              color: Color(0xFFE3E5EE),
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller:
                    _messageController,
                minLines: 1,
                maxLines: 4,
                textCapitalization:
                    TextCapitalization
                        .sentences,
                decoration:
                    InputDecoration(
                  hintText:
                      'Type a message...',
                  filled: true,
                  fillColor:
                      const Color(
                    0xFFF5F7FB,
                  ),
                  contentPadding:
                      const EdgeInsets
                          .symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  border:
                      OutlineInputBorder(
                    borderRadius:
                        BorderRadius
                            .circular(24),
                    borderSide:
                        BorderSide.none,
                  ),
                ),
                onSubmitted: (_) =>
                    _sendMessage(),
              ),
            ),
            const SizedBox(width: 8),
            CircleAvatar(
              backgroundColor:
                  _kPrimary,
              child: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child:
                          CircularProgressIndicator(
                        strokeWidth: 2,
                        color:
                            Colors.white,
                      ),
                    )
                  : IconButton(
                      icon: const Icon(
                        Icons.send,
                        color:
                            Colors.white,
                        size: 20,
                      ),
                      onPressed:
                          _sendMessage,
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

class _MessageBubble
    extends StatelessWidget {
  final String text;
  final bool isMe;
  final String time;

  const _MessageBubble({
    required this.text,
    required this.isMe,
    required this.time,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe
          ? Alignment.centerRight
          : Alignment.centerLeft,
      child: Container(
        margin:
            const EdgeInsets.symmetric(
          vertical: 4,
        ),
        padding:
            const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 10,
        ),
        constraints:
            BoxConstraints(
          maxWidth:
              MediaQuery.of(context)
                      .size
                      .width *
                  0.72,
        ),
        decoration:
            BoxDecoration(
          color: isMe
              ? _kPrimary
              : Colors.white,
          borderRadius:
              BorderRadius.only(
            topLeft:
                const Radius.circular(16),
            topRight:
                const Radius.circular(16),
            bottomLeft:
                Radius.circular(
              isMe ? 16 : 4,
            ),
            bottomRight:
                Radius.circular(
              isMe ? 4 : 16,
            ),
          ),
          border: isMe
              ? null
              : Border.all(
                  color:
                      const Color(
                    0xFFE3E5EE,
                  ),
                ),
        ),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.end,
          mainAxisSize:
              MainAxisSize.min,
          children: [
            Text(
              text,
              style: TextStyle(
                color: isMe
                    ? Colors.white
                    : const Color(
                        0xFF111C2D,
                      ),
                fontSize: 14,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              time,
              style: TextStyle(
                fontSize: 10,
                color: isMe
                    ? Colors.white70
                    : const Color(
                        0xFF9A9DAB,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}