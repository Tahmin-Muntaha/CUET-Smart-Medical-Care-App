// ============================================================
// chat_list_page.dart
//
// Shows every chats/{chatId} document where the logged-in user's
// uid is in the `participants` array, most recently active first.
//
// Works for both students and doctors.
// ============================================================

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'chat_page.dart';

const Color _kPrimary = Color(0xFF003D9B);
const Color _kPage = Color(0xFFF5F7FB);

class ChatListPage extends StatelessWidget {
  const ChatListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: _kPage,
      appBar: AppBar(
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Messages'),
      ),
      body: myUid == null
          ? const Center(
              child: Text('Please log in.'),
            )
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('chats')
                  .where(
                    'participants',
                    arrayContains: myUid,
                  )
                  .orderBy(
                    'lastMessageAt',
                    descending: true,
                  )
                  .snapshots(),
              builder: (context, snapshot) {
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
                      child: Text(
                        'Could not load messages.\n\n${snapshot.error}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                final docs = snapshot.data?.docs ?? [];

                if (docs.isEmpty) {
                  return ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 140),
                      Icon(
                        Icons.chat_bubble_outline,
                        size: 56,
                        color: _kPrimary,
                      ),
                      SizedBox(height: 16),
                      Center(
                        child: Text(
                          'No conversations yet',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      SizedBox(height: 6),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 40),
                        child: Text(
                          'Start a conversation from Find Doctors.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFF737685),
                          ),
                        ),
                      ),
                    ],
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final data = docs[index].data();

                    final participants =
                        List<String>.from(
                      data['participants'] ?? [],
                    );

                    final peerId = participants.firstWhere(
                      (id) => id != myUid,
                      orElse: () => '',
                    );

                    if (peerId.isEmpty) {
                      return const SizedBox.shrink();
                    }

                    final names =
                        Map<String, dynamic>.from(
                      data['participantNames'] ?? {},
                    );

                    final roles =
                        Map<String, dynamic>.from(
                      data['participantRoles'] ?? {},
                    );

                    final peerName =
                        (names[peerId] ?? 'User').toString();

                    final peerRole =
                        (roles[peerId] ?? '').toString();

                    final lastMessage =
                        (data['lastMessage'] ?? '').toString();

                    final lastSenderId =
                        (data['lastSenderId'] ?? '').toString();

                    return ListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      leading: CircleAvatar(
                        backgroundColor:
                            const Color(0xFFE7EEFF),
                        child: Icon(
                          peerRole == 'doctor'
                              ? Icons.medical_services_outlined
                              : Icons.person,
                          color: _kPrimary,
                        ),
                      ),
                      title: Text(
                        peerName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        lastMessage.isEmpty
                            ? 'Say hello 👋'
                            : (lastSenderId == myUid
                                ? 'You: $lastMessage'
                                : lastMessage),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF737685),
                        ),
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChatPage(
                              peerId: peerId,
                              peerName: peerName,
                              peerRole: peerRole,
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