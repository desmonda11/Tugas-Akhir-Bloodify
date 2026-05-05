import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'dart:convert';
import 'cloudinary_config.dart';

class ChatPage extends StatefulWidget {
  final String chatId;
  final String currentUserId;
  final String? chatTitle;

  const ChatPage({
    super.key,
    required this.chatId,
    required this.currentUserId,
    this.chatTitle,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isUploadingMedia = false;

  @override
  void initState() {
    super.initState();
    _markMessagesAsRead();
  }

  void _markMessagesAsRead() async {
    try {
      final chatRef = _firestore.collection('chats').doc(widget.chatId);
      await chatRef.update({
        'unreadCount.${widget.currentUserId}': 0,
      });
    } catch (e) {
      // Ignored
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _getMessages() {
    return _firestore
        .collection('chats')
        .doc(widget.chatId)
        .collection('messages')
        .snapshots();
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final chatRef = _firestore.collection('chats').doc(widget.chatId);
    final messagesRef = chatRef.collection('messages');

    try {
      await messagesRef.add({
        'text': text,
        'senderId': widget.currentUserId,
        'createdAt': FieldValue.serverTimestamp(),
      });
      final chatDoc = await chatRef.get();
      final participants =
          chatDoc.data()?['participants'] as List<dynamic>? ?? [];
      final otherUserId = participants
          .firstWhere((id) => id != widget.currentUserId, orElse: () => '');

      try {
        await chatRef.update({
          'last_message': text,
          'timestamp': FieldValue.serverTimestamp(),
          if (otherUserId.isNotEmpty)
            'unreadCount.$otherUserId': FieldValue.increment(1),
        });
      } catch (e) {
        await chatRef.set({
          'last_message': text,
          'timestamp': FieldValue.serverTimestamp(),
          if (otherUserId.isNotEmpty) 'unreadCount': {otherUserId: 1},
        }, SetOptions(merge: true));
      }

      _messageController.clear();

      await Future.delayed(const Duration(milliseconds: 150));
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(
          _scrollController.position.maxScrollExtent,
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mengirim pesan: $e')),
      );
    }
  }

  Future<void> _pickAndSendMedia() async {
    final picker = ImagePicker();

    final source = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.blue),
              title: const Text('Ambil Foto dari Kamera'),
              onTap: () => Navigator.pop(ctx, 'camera_image'),
            ),
            ListTile(
              leading: const Icon(Icons.image, color: Colors.blue),
              title: const Text('Pilih Foto dari Galeri'),
              onTap: () => Navigator.pop(ctx, 'gallery_image'),
            ),
            ListTile(
              leading: const Icon(Icons.videocam, color: Colors.orange),
              title: const Text('Ambil Video dari Kamera'),
              onTap: () => Navigator.pop(ctx, 'camera_video'),
            ),
            ListTile(
              leading: const Icon(Icons.video_library, color: Colors.orange),
              title: const Text('Pilih Video dari Galeri'),
              onTap: () => Navigator.pop(ctx, 'gallery_video'),
            ),
          ],
        ),
      ),
    );

    if (source == null) return;

    XFile? pickedFile;
    bool isVideo = source.contains('video');

    if (source == 'camera_image') {
      pickedFile =
          await picker.pickImage(source: ImageSource.camera, imageQuality: 70);
    } else if (source == 'gallery_image') {
      pickedFile =
          await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    } else if (source == 'camera_video') {
      pickedFile = await picker.pickVideo(
          source: ImageSource.camera, maxDuration: const Duration(seconds: 30));
    } else if (source == 'gallery_video') {
      pickedFile = await picker.pickVideo(source: ImageSource.gallery);
    }

    if (pickedFile == null) return;

    setState(() => _isUploadingMedia = true);

    try {
      final bytes = await pickedFile.readAsBytes();

      final resourceType = isVideo ? 'video' : 'image';
      var request = http.MultipartRequest(
          'POST',
          Uri.parse(
              'https://api.cloudinary.com/v1_1/${CloudinaryConfig.cloudName}/$resourceType/upload'));
      request.fields['upload_preset'] = CloudinaryConfig.uploadPreset;
      request.files.add(http.MultipartFile.fromBytes('file', bytes,
          filename: pickedFile.name));

      var response = await request.send();

      if (response.statusCode == 200) {
        final respStr = await response.stream.bytesToString();
        final jsonResponse = json.decode(respStr);
        final downloadUrl = jsonResponse['secure_url'];

        final chatRef = _firestore.collection('chats').doc(widget.chatId);
        final messagesRef = chatRef.collection('messages');

        await messagesRef.add({
          'text': isVideo ? '🎥 Video' : '📷 Foto',
          'imageUrl': isVideo ? null : downloadUrl,
          'videoUrl': isVideo ? downloadUrl : null,
          'senderId': widget.currentUserId,
          'createdAt': FieldValue.serverTimestamp(),
        });
        final chatDoc = await chatRef.get();
        final participants =
            chatDoc.data()?['participants'] as List<dynamic>? ?? [];
        final otherUserId = participants
            .firstWhere((id) => id != widget.currentUserId, orElse: () => '');

        final msgText = isVideo ? '🎥 Video' : '📷 Foto';

        try {
          await chatRef.update({
            'last_message': msgText,
            'timestamp': FieldValue.serverTimestamp(),
            if (otherUserId.isNotEmpty)
              'unreadCount.$otherUserId': FieldValue.increment(1),
          });
        } catch (e) {
          await chatRef.set({
            'last_message': msgText,
            'timestamp': FieldValue.serverTimestamp(),
            if (otherUserId.isNotEmpty) 'unreadCount': {otherUserId: 1},
          }, SetOptions(merge: true));
        }

        await Future.delayed(const Duration(milliseconds: 150));
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  'Gagal mengirim media ke Cloudinary. Status: ${response.statusCode}')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal mengirim media: $e')));
      }
    } finally {
      setState(() => _isUploadingMedia = false);
    }
  }

  Future<void> _refreshChatLastMessage() async {
    try {
      final chatRef = _firestore.collection('chats').doc(widget.chatId);
      final latestMsg = await chatRef
          .collection('messages')
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();

      final newLastMessage = latestMsg.docs.isNotEmpty
          ? latestMsg.docs.first.data()['text']?.toString() ?? ''
          : '';

      await chatRef.set({
        'last_message': newLastMessage,
        'timestamp': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // Ignore failures when refreshing last_message.
    }
  }

  Future<void> _updateMessage(String messageId, String newText) async {
    if (newText.trim().isEmpty) return;

    try {
      final chatRef = _firestore.collection('chats').doc(widget.chatId);
      final messageRef = chatRef.collection('messages').doc(messageId);
      await messageRef.update({
        'text': newText.trim(),
      });
      await _refreshChatLastMessage();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mengubah pesan: $e')),
      );
    }
  }

  Future<void> _deleteMessage(String messageId) async {
    try {
      final chatRef = _firestore.collection('chats').doc(widget.chatId);
      await chatRef.collection('messages').doc(messageId).delete();
      await _refreshChatLastMessage();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menghapus pesan: $e')),
      );
    }
  }

  Future<void> _confirmDeleteMessage(String messageId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Konfirmasi'),
          content: const Text('Anda yakin ingin menghapus pesan ini?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Hapus'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await _deleteMessage(messageId);
    }
  }

  Future<void> _showEditMessageDialog(
      String messageId, String currentText) async {
    final TextEditingController editingController =
        TextEditingController(text: currentText);
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Ubah Pesan'),
          content: TextField(
            controller: editingController,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Tulis pesan baru',
            ),
            minLines: 1,
            maxLines: 4,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () async {
                final newText = editingController.text.trim();
                if (newText.isNotEmpty && newText != currentText) {
                  await _updateMessage(messageId, newText);
                }
                Navigator.of(context).pop();
              },
              child: const Text('Simpan'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showMessageOptions(
      String messageId,
      String currentText,
      bool hasMedia,
      bool isMe,
      String senderId) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              if (isMe && !hasMedia)
                ListTile(
                  leading: const Icon(Icons.edit, color: Colors.blue),
                  title: const Text('Edit Pesan'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _showEditMessageDialog(messageId, currentText);
                  },
                ),
              if (isMe)
                ListTile(
                  leading: const Icon(Icons.delete, color: Colors.red),
                  title: const Text('Hapus Pesan'),
                  onTap: () async {
                    Navigator.of(context).pop();
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) {
                        return AlertDialog(
                          title: const Text('Konfirmasi'),
                          content: const Text(
                              'Anda yakin ingin menghapus pesan ini?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(false),
                              child: const Text('Batal'),
                            ),
                            ElevatedButton(
                              onPressed: () => Navigator.of(context).pop(true),
                              child: const Text('Hapus'),
                            ),
                          ],
                        );
                      },
                    );
                    if (confirmed == true) {
                      await _deleteMessage(messageId);
                    }
                  },
                ),
              ListTile(
                leading: const Icon(Icons.report, color: Colors.orange),
                title: const Text('Laporkan Admin'),
                onTap: () {
                  Navigator.of(context).pop();
                  _showReportDialog(messageId, currentText, senderId);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showReportDialog(String messageId, String messageText, String senderId) async {
    final TextEditingController reportController = TextEditingController();
    final reportTypes = <String>[
      'Transaksional mencurigakan',
      'Penipuan',
      'Pelanggaran aturan',
      'Lainnya',
    ];
    String selectedReason = reportTypes.first;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Laporkan ke Admin'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: selectedReason,
                decoration: const InputDecoration(
                  labelText: 'Jenis laporan',
                ),
                items: reportTypes
                    .map(
                      (reason) => DropdownMenuItem(
                        value: reason,
                        child: Text(reason),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) selectedReason = value;
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reportController,
                decoration: const InputDecoration(
                  labelText: 'Keterangan tambahan (opsional)',
                  hintText: 'Jelaskan mengapa pesan ini mencurigakan...',
                ),
                minLines: 3,
                maxLines: 5,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () async {
                final additionalNote = reportController.text.trim();
                await _sendReportToAdmin(
                  messageId,
                  messageText,
                  senderId,
                  selectedReason,
                  additionalNote,
                );
                Navigator.of(context).pop();
              },
              child: const Text('Kirim Laporan'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _sendReportToAdmin(
    String messageId,
    String messageText,
    String senderId,
    String reason,
    String note,
  ) async {
    try {
      await _firestore.collection('reports').add({
        'chatId': widget.chatId,
        'messageId': messageId,
        'senderId': senderId,
        'messageText': messageText,
        'reportedBy': widget.currentUserId,
        'reason': reason,
        'note': note,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'pending',
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Laporan berhasil dikirim ke admin.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mengirim laporan: $e')),
      );
    }
  }

  String _formatTime(Timestamp? timestamp) {
    if (timestamp == null) return '...';

    final date = timestamp.toDate();
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F6),
      appBar: AppBar(
        title: Text(widget.chatTitle ?? "Chat Donor"),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: Colors.yellow.shade100,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: const Text(
              'APLIKASI INI BERSIFAT SUKARELA, TANPA ADANYA BIAYA APAPUN',
              style: TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _getMessages(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(
                    child: Text('Terjadi kesalahan saat mengambil pesan'),
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data?.docs ?? [];

                // Sorting client-side
                final sortedDocs =
                    List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
                        docs);
                sortedDocs.sort((a, b) {
                  final aTime = (a.data()['createdAt'] as Timestamp?)
                          ?.millisecondsSinceEpoch ??
                      0;
                  final bTime = (b.data()['createdAt'] as Timestamp?)
                          ?.millisecondsSinceEpoch ??
                      0;
                  return aTime.compareTo(bTime);
                });

                if (sortedDocs.isEmpty) {
                  return const Center(
                    child: Text('Belum ada pesan'),
                  );
                }

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scrollController.hasClients) {
                    _scrollController.jumpTo(
                      _scrollController.position.maxScrollExtent,
                    );
                  }
                });

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: sortedDocs.length,
                  itemBuilder: (context, index) {
                    final data = sortedDocs[index].data();

                    final String text = data['text'] ?? '';
                    final String senderId = data['senderId'] ?? '';
                    final Timestamp? createdAt =
                        data['createdAt'] as Timestamp?;
                    final String? imageUrl = data['imageUrl']?.toString();
                    final String? videoUrl = data['videoUrl']?.toString();
                    final bool isMe = senderId == widget.currentUserId;
                    final bool hasMedia = (imageUrl?.isNotEmpty == true) ||
                        (videoUrl?.isNotEmpty == true);

                    return GestureDetector(
                      onLongPress: () => _showMessageOptions(
                          sortedDocs[index].id, text, hasMedia, isMe, senderId),
                      child: _ChatBubble(
                        text: text,
                        time: _formatTime(createdAt),
                        isMe: isMe,
                        imageUrl: imageUrl,
                        videoUrl: videoUrl,
                        onEdit: isMe && !hasMedia
                            ? () => _showEditMessageDialog(
                                sortedDocs[index].id, text)
                            : null,
                        onDelete: isMe
                            ? () => _confirmDeleteMessage(sortedDocs[index].id)
                            : null,
                        onReport: () => _showReportDialog(
                          sortedDocs[index].id,
                          text,
                          senderId,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(
                top: BorderSide(color: Colors.black12),
              ),
            ),
            child: Row(
              children: [
                if (_isUploadingMedia)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.attach_file),
                    color: Colors.grey,
                    onPressed: _pickAndSendMedia,
                  ),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: "Tulis pesan...",
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send),
                  color: Colors.red,
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final String text;
  final String time;
  final bool isMe;
  final String? imageUrl;
  final String? videoUrl;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onReport;

  const _ChatBubble({
    required this.text,
    required this.time,
    required this.isMe,
    this.imageUrl,
    this.videoUrl,
    this.onEdit,
    this.onDelete,
    this.onReport,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.all(12),
            constraints: const BoxConstraints(maxWidth: 280),
            decoration: BoxDecoration(
              color: isMe ? Colors.red : Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (imageUrl != null && imageUrl!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        imageUrl!,
                        width: 200,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return const SizedBox(
                            width: 200,
                            height: 150,
                            child: Center(child: CircularProgressIndicator()),
                          );
                        },
                      ),
                    ),
                  ),
                if (videoUrl != null && videoUrl!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Container(
                      width: 200,
                      height: 150,
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.play_circle_fill,
                                size: 50, color: Colors.white),
                            SizedBox(height: 8),
                            Text("Video",
                                style: TextStyle(color: Colors.white)),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (text.isNotEmpty && text != '🎥 Video' && text != '📷 Foto')
                  Text(
                    text,
                    style: TextStyle(
                      color: isMe ? Colors.white : Colors.black,
                      fontSize: 15,
                    ),
                  ),
              ],
            ),
          ),
          if (onEdit != null || onDelete != null || onReport != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment:
                    isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                children: [
                  if (onEdit != null)
                    IconButton(
                      icon: const Icon(Icons.edit, size: 18),
                      color: isMe ? Colors.red : Colors.black54,
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(),
                      onPressed: onEdit,
                      tooltip: 'Edit Pesan',
                    ),
                  if (onDelete != null)
                    IconButton(
                      icon: const Icon(Icons.delete, size: 18),
                      color: isMe ? Colors.red : Colors.black54,
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(),
                      onPressed: onDelete,
                      tooltip: 'Hapus Pesan',
                    ),
                  if (onReport != null)
                    IconButton(
                      icon: const Icon(Icons.report, size: 18),
                      color: Colors.orange,
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(),
                      onPressed: onReport,
                      tooltip: 'Laporkan Admin',
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              time,
              style: const TextStyle(
                fontSize: 11,
                color: Colors.grey,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
