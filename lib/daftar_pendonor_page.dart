import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'chat_page.dart';

class DaftarPendonorPage extends StatelessWidget {
  const DaftarPendonorPage({super.key});

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Daftar Pendonor"),
        backgroundColor: Colors.red.shade800,
        foregroundColor: Colors.white,
      ),
      backgroundColor: const Color(0xFFF6F6F6),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('users').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text("Terjadi kesalahan saat memuat data."));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final allDocs = snapshot.data?.docs ?? [];
          // Filter agar akun admin tidak muncul di daftar pendonor
          // Dan filter agar hanya yang Lolos kuesioner & sudah diverifikasi Admin yang muncul
          final docs = allDocs.where((doc) {
            final data = doc.data() as Map<String, dynamic>? ?? {};
            final email = data['email']?.toString().toLowerCase() ?? '';
            final status = data['kuesioner_status']?.toString() ?? '';
            
            return email != 'admin@bloodify.com' && status == 'Lolos';
          }).toList();

          if (docs.isEmpty) {
            return const Center(child: Text("Belum ada data pendonor."));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>? ?? {};
              
              final userId = doc.id;
              final isMe = userId == currentUserId;
              
              final firstName = data['firstName']?.toString() ?? '';
              final lastName = data['lastName']?.toString() ?? '';
              final name = "$firstName $lastName".trim();
              
              final phone = data['nomorTelepon']?.toString() ?? 'Tidak tersedia';
              final bloodType = data['golonganDarah']?.toString() ?? '?';
              final location = data['location']?.toString() ?? 'Belum diatur';
              final profilePic = data['profilePicture']?.toString();

              return Card(
                elevation: 2,
                margin: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: Colors.red.shade100,
                        backgroundImage: profilePic != null && profilePic.isNotEmpty 
                            ? NetworkImage(profilePic) 
                            : null,
                        child: profilePic == null || profilePic.isEmpty 
                            ? Text(
                                name.isNotEmpty ? name[0].toUpperCase() : '?',
                                style: TextStyle(
                                  color: Colors.red.shade900,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name.isNotEmpty ? name : "User",
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.bloodtype, size: 16, color: Colors.red),
                                const SizedBox(width: 4),
                                Text(bloodType, style: const TextStyle(fontWeight: FontWeight.w600)),
                                const SizedBox(width: 12),
                                const Icon(Icons.phone, size: 16, color: Colors.grey),
                                const SizedBox(width: 4),
                                Text(phone, style: const TextStyle(fontSize: 12)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.location_on, size: 16, color: Colors.grey),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    location,
                                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (!isMe && currentUserId != null)
                        IconButton(
                          icon: const Icon(Icons.chat, color: Colors.red),
                          onPressed: () async {
                            final chatQuery = await FirebaseFirestore.instance.collection('chats')
                                .where('participants', arrayContains: currentUserId)
                                .get();
                            
                            String? existingChatId;
                            for (var doc in chatQuery.docs) {
                               final participants = List<String>.from(doc.data()['participants'] ?? []);
                               if (participants.contains(userId)) {
                                 existingChatId = doc.id;
                                 break;
                               }
                            }
                            
                            String chatIdToUse = existingChatId ?? '${currentUserId}_$userId';
                            // Bila belum ada, set pesertanya ke firestore agar muncul di chat_list
                            if (existingChatId == null) {
                               await FirebaseFirestore.instance.collection('chats').doc(chatIdToUse).set({
                                  'participants': [currentUserId, userId],
                                  'timestamp': FieldValue.serverTimestamp(),
                                  'requester_name': FirebaseAuth.instance.currentUser?.displayName ?? 'Pengguna',
                                  'donor_name': name,
                                  'requester_uid': currentUserId,
                                  'donor_uid': userId,
                               }, SetOptions(merge: true));
                            }

                            if (!context.mounted) return;
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ChatPage(
                                  chatId: chatIdToUse,
                                  currentUserId: currentUserId,
                                  chatTitle: name,
                                ),
                              ),
                            );
                          },
                        ),
                    ],
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
