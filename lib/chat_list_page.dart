import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'chat_page.dart';

class ChatListPage extends StatelessWidget {
  const ChatListPage({super.key});

  String _formatTime(Timestamp? timestamp) {
    if (timestamp == null) return '';

    final date = timestamp.toDate();
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      return const Scaffold(
        body: Center(
          child: Text("Silakan login terlebih dahulu"),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Chat"),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      backgroundColor: const Color(0xFFF6F6F6),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('chats')
            .where('participants', arrayContains: currentUser.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text("Terjadi kesalahan saat memuat chat: ${snapshot.error}"),
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data?.docs ?? [];

          // Sorting client-side untuk menghindari kebutuhan manual Index di Firebase
          final sortedDocs = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(docs);
          sortedDocs.sort((a, b) {
            final aTime = (a.data()['timestamp'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
            final bTime = (b.data()['timestamp'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
            return bTime.compareTo(aTime);
          });

          if (sortedDocs.isEmpty) {
            return const Center(
              child: Text("Belum ada percakapan"),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: sortedDocs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final doc = sortedDocs[index];
              final data = doc.data();

              final String donorUid = data['donor_uid']?.toString() ?? '';

              final bool isDonor = currentUser.uid == donorUid;

              final String chatTitle = isDonor
                  ? (data['requester_name']?.toString() ?? 'Penerima')
                  : (data['donor_name']?.toString() ?? 'Pendonor');

              final String lastMessage =
                  data['last_message']?.toString().trim().isNotEmpty == true
                      ? data['last_message'].toString()
                      : 'Belum ada pesan';

              final Timestamp? timestamp = data['timestamp'] as Timestamp?;
              
              int unreadCount = 0;
              if (data['unreadCount'] != null && data['unreadCount'][currentUser.uid] != null) {
                 unreadCount = data['unreadCount'][currentUser.uid] as int;
              }

              return Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                elevation: 2,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatPage(
                          chatId: doc.id,
                          currentUserId: currentUser.uid,
                          chatTitle: chatTitle,
                        ),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    child: Row(
                      children: [
                        FutureBuilder<DocumentSnapshot>(
                          future: FirebaseFirestore.instance.collection('users').doc(
                            (data['participants'] as List<dynamic>?)?.firstWhere(
                              (id) => id != currentUser.uid, 
                              orElse: () => ''
                            ) ?? ''
                          ).get(),
                          builder: (context, userSnapshot) {
                            String? profilePic;
                            if (userSnapshot.hasData && userSnapshot.data != null && userSnapshot.data!.exists) {
                              final userData = userSnapshot.data!.data() as Map<String, dynamic>?;
                              profilePic = userData?['profilePicture']?.toString();
                            }

                            return CircleAvatar(
                              radius: 24,
                              backgroundColor: Colors.red,
                              backgroundImage: profilePic != null && profilePic.isNotEmpty ? NetworkImage(profilePic) : null,
                              child: profilePic == null || profilePic.isEmpty ? Text(
                                chatTitle.isNotEmpty
                                    ? chatTitle[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ) : null,
                            );
                          }
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                chatTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: unreadCount > 0 ? Colors.black : Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                lastMessage,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: unreadCount > 0 ? Colors.black87 : Colors.black54,
                                  fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _formatTime(timestamp),
                              style: TextStyle(
                                color: unreadCount > 0 ? Colors.green : Colors.grey,
                                fontSize: 12,
                                fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                            if (unreadCount > 0)
                              Container(
                                margin: const EdgeInsets.only(top: 6),
                                padding: const EdgeInsets.all(6),
                                decoration: const BoxDecoration(
                                  color: Colors.green,
                                  shape: BoxShape.circle,
                                ),
                                child: Text(
                                  unreadCount.toString(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
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