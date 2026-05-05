import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'login_page.dart';
import 'cloudinary_config.dart';

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  int _selectedIndex = 0; // Default to Event

  final List<Widget> _pages = [
    const _AdminEventSection(),
    const _AdminKuesionerSection(),
    const _AdminNotificationSection(),
    const _AdminDonorSection(),
    const _AdminReportSection(),
    const _AdminProfileSection(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        selectedItemColor: Colors.red.shade800,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.event), label: "Event"),
          BottomNavigationBarItem(
              icon: Icon(Icons.assignment), label: "Kuesioner"),
          BottomNavigationBarItem(
              icon: Icon(Icons.notifications), label: "Notifikasi"),
          BottomNavigationBarItem(icon: Icon(Icons.people), label: "Pendonor"),
          BottomNavigationBarItem(icon: Icon(Icons.report), label: "Laporan"),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: "Profil"),
        ],
      ),
    );
  }
}

// --- SECTION: EVENT (CRUD) ---
class _AdminEventSection extends StatefulWidget {
  const _AdminEventSection();

  @override
  State<_AdminEventSection> createState() => _AdminEventSectionState();
}

class _AdminEventSectionState extends State<_AdminEventSection> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descController = TextEditingController();

  String? _imageUrl;
  bool _isUploading = false;
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _pickAndUploadImage() async {
    final picker = ImagePicker();
    final pickedFile =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (pickedFile == null) return;

    setState(() => _isUploading = true);
    try {
      final bytes = await pickedFile.readAsBytes();
      var request = http.MultipartRequest(
          'POST',
          Uri.parse(
              'https://api.cloudinary.com/v1_1/${CloudinaryConfig.cloudName}/upload'));
      request.fields['upload_preset'] = CloudinaryConfig.uploadPreset;
      request.files.add(http.MultipartFile.fromBytes('file', bytes,
          filename: 'event_poster.jpg'));

      var response = await request.send();
      if (response.statusCode == 200) {
        final respStr = await response.stream.bytesToString();
        final jsonResponse = json.decode(respStr);
        setState(() => _imageUrl = jsonResponse['secure_url']);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Gagal upload: $e")));
      }
    } finally {
      setState(() => _isUploading = false);
    }
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _selectTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    if (picked != null) setState(() => _selectedTime = picked);
  }

  Future<void> _saveEvent({String? docId}) async {
    if (_titleController.text.isEmpty || _imageUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Judul dan Gambar wajib diisi!")));
      return;
    }

    final data = {
      'title': _titleController.text.trim(),
      'description': _descController.text.trim(),
      'imageUrl': _imageUrl,
      'date': DateFormat('dd MMMM yyyy').format(_selectedDate),
      'time': _selectedTime.format(context),
      'createdAt': FieldValue.serverTimestamp(),
    };

    if (docId == null) {
      await _db.collection('events').add(data);
    } else {
      await _db.collection('events').doc(docId).update(data);
    }

    _titleController.clear();
    _descController.clear();
    setState(() {
      _imageUrl = null;
      _selectedDate = DateTime.now();
      _selectedTime = TimeOfDay.now();
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Event berhasil disimpan"),
          backgroundColor: Colors.green));
    }
  }

  void _showForm({String? docId, Map<String, dynamic>? currentData}) {
    if (currentData != null) {
      _titleController.text = currentData['title'] ?? '';
      _descController.text = currentData['description'] ?? '';
      _imageUrl = currentData['imageUrl'];
      // Note: Parsing date/time from string back to DateTime/TimeOfDay if editing
    } else {
      _titleController.clear();
      _descController.clear();
      _imageUrl = null;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
              left: 16,
              right: 16,
              top: 16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Tambah / Edit Event",
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () async {
                    await _pickAndUploadImage();
                    setModalState(() {});
                  },
                  child: Container(
                    height: 150,
                    width: double.infinity,
                    decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300)),
                    child: _imageUrl != null
                        ? Image.network(_imageUrl!, fit: BoxFit.cover)
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                                if (_isUploading)
                                  const CircularProgressIndicator()
                                else
                                  const Icon(Icons.add_a_photo,
                                      size: 40, color: Colors.grey),
                                const SizedBox(height: 8),
                                const Text("Pilih Gambar Poster"),
                              ]),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                    controller: _titleController,
                    decoration: const InputDecoration(
                        labelText: "Judul Event",
                        border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(
                    controller: _descController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                        labelText: "Deskripsi", border: OutlineInputBorder())),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                        child: ListTile(
                            title: const Text("Tanggal"),
                            subtitle: Text(DateFormat('dd MMMM yyyy')
                                .format(_selectedDate)),
                            leading: const Icon(Icons.calendar_today),
                            onTap: () async {
                              await _selectDate();
                              setModalState(() {});
                            })),
                    Expanded(
                        child: ListTile(
                            title: const Text("Jam"),
                            subtitle: Text(_selectedTime.format(context)),
                            leading: const Icon(Icons.access_time),
                            onTap: () async {
                              await _selectTime();
                              setModalState(() {});
                            })),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () {
                      _saveEvent(docId: docId);
                      Navigator.pop(ctx);
                    },
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade800,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12))),
                    child: const Text("Simpan Event"),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Manajemen Event",
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.red.shade800,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showForm(),
        backgroundColor: Colors.red.shade800,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _db
            .collection('events')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'Error: ${snapshot.error}\n\nSilakan cek apakah perlu membuat index di Firestore.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return const Center(child: Text("Belum ada event."));
          }

          return ListView.builder(
            itemCount: docs.length,
            padding: const EdgeInsets.all(16),
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Image.network(data['imageUrl'],
                        height: 150, width: double.infinity, fit: BoxFit.cover),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(data['title'],
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text("${data['date']} • ${data['time']}",
                              style: TextStyle(
                                  color: Colors.red.shade800,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          Text(data['description'],
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton.icon(
                                  onPressed: () => _showForm(
                                      docId: docs[index].id, currentData: data),
                                  icon: const Icon(Icons.edit),
                                  label: const Text("Edit")),
                              const SizedBox(width: 8),
                              TextButton.icon(
                                onPressed: () async {
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text("Hapus Event?"),
                                      content: const Text(
                                          "Event ini akan dihapus secara permanen."),
                                      actions: [
                                        TextButton(
                                            onPressed: () =>
                                                Navigator.pop(ctx, false),
                                            child: const Text("Batal")),
                                        TextButton(
                                            onPressed: () =>
                                                Navigator.pop(ctx, true),
                                            child: const Text("Hapus",
                                                style: TextStyle(
                                                    color: Colors.red))),
                                      ],
                                    ),
                                  );
                                  if (confirm == true) {
                                    await _db
                                        .collection('events')
                                        .doc(docs[index].id)
                                        .delete();
                                  }
                                },
                                icon:
                                    const Icon(Icons.delete, color: Colors.red),
                                label: const Text("Hapus",
                                    style: TextStyle(color: Colors.red)),
                              ),
                            ],
                          ),
                        ],
                      ),
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
}

// --- SECTION: NOTIFIKASI (Broadcast) ---
class _AdminNotificationSection extends StatefulWidget {
  const _AdminNotificationSection();

  @override
  State<_AdminNotificationSection> createState() =>
      _AdminNotificationSectionState();
}

class _AdminNotificationSectionState extends State<_AdminNotificationSection> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final TextEditingController _titleTemplateController =
      TextEditingController();
  final TextEditingController _bodyTemplateController = TextEditingController();
  bool _isSavingTemplate = false;

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  Future<void> _loadTemplates() async {
    final doc =
        await _db.collection('settings').doc('notification_template').get();
    if (doc.exists) {
      setState(() {
        _titleTemplateController.text =
            doc.data()?['request_title_template'] ?? '';
        _bodyTemplateController.text =
            doc.data()?['request_body_template'] ?? '';
      });
    }
  }

  Future<void> _saveTemplate() async {
    setState(() => _isSavingTemplate = true);
    try {
      await _db.collection('settings').doc('notification_template').set({
        'request_title_template': _titleTemplateController.text.trim(),
        'request_body_template': _bodyTemplateController.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Template berhasil disimpan!"),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text("Gagal simpan: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingTemplate = false);
    }
  }

  @override
  void dispose() {
    _titleTemplateController.dispose();
    _bodyTemplateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F6),
      appBar: AppBar(
        title: const Text("Kelola Notifikasi",
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.red.shade800,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _db
            .collection('notifications')
            .orderBy('sentAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;

          return ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              // TEMPLATE SETTINGS
              Card(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: ExpansionTile(
                  leading: const Icon(Icons.settings, color: Colors.blue),
                  title: const Text("Atur Template Notifikasi Otomatis",
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text("Gunakan [NAMA] dan [GOL] sebagai kode",
                      style: TextStyle(fontSize: 12)),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          TextField(
                            controller: _titleTemplateController,
                            decoration: const InputDecoration(
                              labelText: "Template Judul",
                              border: OutlineInputBorder(),
                              hintText: "Contoh: 🔴 [NAMA] Butuh Darah",
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _bodyTemplateController,
                            maxLines: 3,
                            decoration: const InputDecoration(
                              labelText: "Template Isi Pesan",
                              border: OutlineInputBorder(),
                              hintText: "Gunakan [NAMA] dan [GOL] di sini.",
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed:
                                  _isSavingTemplate ? null : _saveTemplate,
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue.shade700,
                                  foregroundColor: Colors.white),
                              child: _isSavingTemplate
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Text("SIMPAN TEMPLATE"),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const Divider(height: 32),
              const Row(
                children: [
                  Icon(Icons.history, size: 20, color: Colors.grey),
                  SizedBox(width: 8),
                  Text("Riwayat Pengiriman",
                      style: TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.grey)),
                ],
              ),
              const SizedBox(height: 12),

              // DAFTAR RIWAYAT
              if (docs.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20.0),
                    child: Text("Belum ada riwayat notifikasi."),
                  ),
                )
              else
                ...docs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final DateTime sentAt =
                      (data['sentAt'] as Timestamp?)?.toDate() ??
                          DateTime.now();
                  final timeStr = DateFormat('dd MMM, HH:mm').format(sentAt);

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Colors.blueGrey,
                        child: Icon(Icons.notifications_active,
                            color: Colors.white, size: 20),
                      ),
                      title: Text(data['title'] ?? '',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(data['body'] ?? ''),
                      trailing: Text(timeStr,
                          style: const TextStyle(
                              fontSize: 10, color: Colors.grey)),
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }
}

class _AdminDonorSection extends StatefulWidget {
  const _AdminDonorSection();

  @override
  State<_AdminDonorSection> createState() => _AdminDonorSectionState();
}

class _AdminDonorSectionState extends State<_AdminDonorSection> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> _updateStatus(String userId, String newStatus) async {
    try {
      await _db.collection('users').doc(userId).update({
        'kuesioner_status': newStatus,
        'verification_at': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Status berhasil diubah menjadi $newStatus"),
            backgroundColor: newStatus == 'Lolos' ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showKuesionerDetail(Map<String, dynamic> data) {
    final List<dynamic> details = data['detail_kuesioner'] ?? [];
    final firstName = data['firstName'] ?? '';
    final lastName = data['lastName'] ?? '';
    final name = "$firstName $lastName".trim();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Detail Kuesioner: $name"),
        content: SizedBox(
          width: double.maxFinite,
          child: details.isEmpty
              ? const Center(child: Text("Tidak ada data detail kuesioner."))
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: details.length,
                  itemBuilder: (context, index) {
                    final item = details[index] as Map<String, dynamic>;
                    final String res = item['hasil'] ?? 'Lolos';
                    Color resColor = Colors.green;
                    if (res == 'Tunda') resColor = Colors.orange;
                    if (res == 'Ditolak') resColor = Colors.red;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "${index + 1}. ${item['pertanyaan'] ?? ''}",
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text("Jawaban: ${item['jawaban']}"),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: resColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    res,
                                    style: TextStyle(
                                        color: resColor,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text("Tutup")),
          ElevatedButton.icon(
            onPressed: () => _generateAndPrintPdf(data, details),
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text("Download/Print PDF"),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade800,
                foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }

  Future<void> _generateAndPrintPdf(
      Map<String, dynamic> data, List<dynamic> details) async {
    final firstName = data['firstName'] ?? '';
    final lastName = data['lastName'] ?? '';
    final name = "$firstName $lastName".trim();
    final email = data['email'] ?? '-';
    final phone = data['nomorTelepon'] ?? '-';
    final bloodType = data['golonganDarah'] ?? '?';

    debugPrint("AdminPdf: Memulai pembuatan PDF untuk $name");
    try {
      final pdf = pw.Document();
      // ... (kode tetap sama)
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return [
              pw.Header(
                level: 0,
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text("Laporan Hasil Kuesioner Bloodify",
                        style: pw.TextStyle(
                            fontSize: 18, fontWeight: pw.FontWeight.bold)),
                    pw.Text(
                        DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),
              pw.Text("Informasi Pendonor:",
                  style: pw.TextStyle(
                      fontSize: 14, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 10),
              pw.Table(
                border: pw.TableBorder.all(),
                children: [
                  pw.TableRow(children: [
                    pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text("Nama")),
                    pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text(name))
                  ]),
                  pw.TableRow(children: [
                    pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text("Email")),
                    pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text(email))
                  ]),
                  pw.TableRow(children: [
                    pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text("Telepon")),
                    pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text(phone))
                  ]),
                  pw.TableRow(children: [
                    pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text("Golongan Darah")),
                    pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text(bloodType))
                  ]),
                ],
              ),
              pw.SizedBox(height: 20),
              pw.Text("Daftar Pertanyaan & Jawaban:",
                  style: pw.TextStyle(
                      fontSize: 14, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 10),
              ...details.asMap().entries.map((entry) {
                final index = entry.key;
                final item = entry.value as Map<String, dynamic>;
                return pw.Container(
                  margin: const pw.EdgeInsets.only(bottom: 10),
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey300)),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text("${index + 1}. ${item['pertanyaan']}",
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(height: 4),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text("Jawaban: ${item['jawaban']}"),
                          pw.Text("Hasil: ${item['hasil']}",
                              style: pw.TextStyle(
                                  color: item['hasil'] == 'Lolos'
                                      ? PdfColors.green
                                      : (item['hasil'] == 'Tunda'
                                          ? PdfColors.orange
                                          : PdfColors.red))),
                        ],
                      ),
                    ],
                  ),
                );
              }),
            ];
          },
        ),
      );

      debugPrint("AdminPdf: PDF berhasil digenerate, memanggil dialog cetak");
      await Printing.layoutPdf(
          onLayout: (PdfPageFormat format) async => pdf.save());
      debugPrint("AdminPdf: Dialog cetak selesai");
    } catch (e) {
      debugPrint("AdminPdf: Error saat membuat PDF: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F6),
      appBar: AppBar(
        title: const Text("Konfirmasi Pendonor (Tunda)",
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.red.shade800,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _db
            .collection('users')
            .where('kuesioner_status', isEqualTo: 'Menunggu Konfirmasi PMI')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.person_search, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text("Tidak ada pendonor yang menunggu konfirmasi.",
                      style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;
              final firstName = data['firstName'] ?? '';
              final lastName = data['lastName'] ?? '';
              final name = "$firstName $lastName".trim();
              final bloodType = data['golonganDarah'] ?? '?';
              final phone = data['nomorTelepon'] ?? '-';
              final profilePic = data['profilePicture']?.toString();

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(12),
                  leading: CircleAvatar(
                    radius: 25,
                    backgroundImage: profilePic != null && profilePic.isNotEmpty
                        ? NetworkImage(profilePic)
                        : null,
                    child: profilePic == null || profilePic.isEmpty
                        ? const Icon(Icons.person)
                        : null,
                  ),
                  title: Text(name.isNotEmpty ? name : "User",
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text("Golongan Darah: $bloodType",
                          style: const TextStyle(
                              color: Colors.red, fontWeight: FontWeight.bold)),
                      Text("Telp: $phone"),
                      const SizedBox(height: 4),
                      const Text("Status: Menunggu Konfirmasi",
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.orange,
                              fontStyle: FontStyle.italic)),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // TOMBOL DETAIL
                      IconButton(
                        icon:
                            const Icon(Icons.info_outline, color: Colors.blue),
                        onPressed: () => _showKuesionerDetail(data),
                        tooltip: 'Lihat Detail Kuesioner',
                      ),
                      // TOMBOL SILANG (TOLAK)
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.red),
                        onPressed: () => _updateStatus(doc.id, 'Ditolak'),
                        tooltip: 'Tolak',
                      ),
                      // TOMBOL CENTANG (LOLOS)
                      IconButton(
                        icon: const Icon(Icons.check, color: Colors.green),
                        onPressed: () => _updateStatus(doc.id, 'Lolos'),
                        tooltip: 'Loloskan',
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

// --- SECTION: LAPORAN CHAT MENCURIGAKAN ---
class _AdminReportSection extends StatefulWidget {
  const _AdminReportSection();

  @override
  State<_AdminReportSection> createState() => _AdminReportSectionState();
}

class _AdminReportSectionState extends State<_AdminReportSection> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> _addSampleReport() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final reporter = currentUser?.uid ?? 'sample_admin';

    await _db.collection('reports').add({
      'chatId': 'sample_chat_001',
      'messageId': 'sample_message_001',
      'senderId': 'sample_user_001',
      'messageText':
          'Pesan transaksi mencurigakan, minta data pribadi dan uang.',
      'reportedBy': reporter,
      'reason': 'Penipuan',
      'note': 'Contoh laporan untuk pengujian admin.',
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'pending',
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Laporan contoh berhasil ditambahkan.')),
      );
    }
  }

  Future<void> _resolveReport(String reportId) async {
    await _db.collection('reports').doc(reportId).update({
      'status': 'resolved',
      'reviewedAt': FieldValue.serverTimestamp(),
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Laporan berhasil diselesaikan.')),
      );
    }
  }

  Future<void> _banUser(String userId, String reportId) async {
    final userRef = _db.collection('users').doc(userId);
    final reportRef = _db.collection('reports').doc(reportId);
    await _db.runTransaction((transaction) async {
      transaction.set(userRef, {'isBanned': true}, SetOptions(merge: true));
      transaction.update(reportRef, {
        'status': 'banned',
        'reviewedAt': FieldValue.serverTimestamp(),
      });
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Akun terlapor telah dibanned.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F6),
      appBar: AppBar(
        title: const Text("Laporan Chat"),
        backgroundColor: Colors.red.shade800,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addSampleReport,
        icon: const Icon(Icons.add),
        label: const Text('Tambah Laporan Contoh'),
        backgroundColor: Colors.red.shade800,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _db
            .collection('reports')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Terjadi kesalahan: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.report, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('Belum ada laporan chat mencurigakan.',
                      style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;
              final chatId = data['chatId'] ?? '-';
              final messageText = data['messageText'] ?? '-';
              final reportedBy = data['reportedBy'] ?? '-';
              final senderId = data['senderId'] ?? '-';
              final reason = data['reason'] ?? '-';
              final note = data['note'] ?? '';
              final status = data['status'] ?? 'pending';
              final createdAt = (data['createdAt'] as Timestamp?)?.toDate();

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Laporan #${doc.id.substring(0, 6)}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: status == 'pending'
                                  ? Colors.orange.shade100
                                  : Colors.green.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(status.toString().toUpperCase(),
                                style: TextStyle(
                                    color: status == 'pending'
                                        ? Colors.orange.shade800
                                        : Colors.green.shade800,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text('Chat ID: $chatId',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey)),
                      const SizedBox(height: 4),
                      Text('Akun terlapor: $senderId',
                          style: const TextStyle(fontSize: 13)),
                      const SizedBox(height: 4),
                      Text('Dilaporkan oleh: $reportedBy',
                          style: const TextStyle(fontSize: 13)),
                      const SizedBox(height: 8),
                      Text('Alasan: $reason',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text('Pesan: $messageText'),
                      if (note.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text('Catatan: $note'),
                      ],
                      if (createdAt != null) ...[
                        const SizedBox(height: 10),
                        Text(
                            'Waktu: ${DateFormat('dd MMM yyyy HH:mm').format(createdAt)}',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey)),
                      ],
                      if (status == 'pending') ...[
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () => _resolveReport(doc.id),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green.shade700,
                                ),
                                child: const Text('Tandai Selesai'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () => _banUser(senderId, doc.id),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red.shade700,
                                ),
                                child: const Text('Banned Akun'),
                              ),
                            ),
                          ],
                        ),
                      ],
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

// --- SECTION: KUESIONER (CRUD) ---
class _AdminKuesionerSection extends StatefulWidget {
  const _AdminKuesionerSection();

  @override
  State<_AdminKuesionerSection> createState() => _AdminKuesionerSectionState();
}

class _AdminKuesionerSectionState extends State<_AdminKuesionerSection> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final TextEditingController _inputController = TextEditingController();
  String _selectedCategory = "Lolos";

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _tambahPertanyaan() async {
    final teks = _inputController.text.trim();
    if (teks.isEmpty) return;

    final snapshot = await _db.collection('kuesioner_syarat').get();
    final order = snapshot.docs.length;

    await _db.collection('kuesioner_syarat').add({
      'text': teks,
      'category': _selectedCategory,
      'order': order,
    });

    _inputController.clear();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Pertanyaan berhasil ditambahkan"),
            backgroundColor: Colors.green),
      );
    }
  }

  Future<void> _editPertanyaan(
      String docId, String current, String currentCat) async {
    final ctrl = TextEditingController(text: current);
    String cat = currentCat;

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("Edit Pertanyaan"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                maxLines: 3,
                decoration: const InputDecoration(
                    border: OutlineInputBorder(), labelText: "Teks Pertanyaan"),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: cat,
                decoration: const InputDecoration(
                    border: OutlineInputBorder(), labelText: "Kategori"),
                items: ["Lolos", "Tunda", "Ditolak"]
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (val) {
                  if (val != null) setDialogState(() => cat = val);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Batal")),
            ElevatedButton(
              onPressed: () => Navigator.pop(
                  ctx, {'text': ctrl.text.trim(), 'category': cat}),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child:
                  const Text("Simpan", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (result != null && result['text']!.isNotEmpty) {
      await _db.collection('kuesioner_syarat').doc(docId).update({
        'text': result['text'],
        'category': result['category'],
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Pertanyaan berhasil diperbarui"),
              backgroundColor: Colors.green),
        );
      }
    }
  }

  Future<void> _hapusPertanyaan(String docId, String teks) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Hapus Pertanyaan?"),
        content: Text("\"$teks\"\n\nTindakan ini tidak bisa dibatalkan."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Batal")),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Hapus", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _db.collection('kuesioner_syarat').doc(docId).delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Pertanyaan dihapus"), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F6),
      appBar: AppBar(
        title: const Text("Kelola Kuesioner",
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.red.shade800,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Colors.red.shade50,
            child: const Text(
              "Manajemen kuesioner kelayakan donor darah.\nPilih kategori Lolos, Tunda, atau Ditolak untuk setiap pertanyaan.",
              style: TextStyle(
                  color: Colors.blueGrey, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _inputController,
                        decoration: InputDecoration(
                          hintText: "Tambah pertanyaan baru...",
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _tambahPertanyaan,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade800,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(
                            vertical: 20, horizontal: 12),
                      ),
                      child: const Icon(Icons.add),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12)),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedCategory,
                      isExpanded: true,
                      items: ["Lolos", "Tunda", "Ditolak"]
                          .map((c) => DropdownMenuItem(
                              value: c, child: Text("Kategori: $c")))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _selectedCategory = val);
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _db
                  .collection('kuesioner_syarat')
                  .orderBy('order')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text("Error: ${snapshot.error}"));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data!.docs;
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    final String cat = data['category'] ?? 'Lolos';
                    Color catColor = Colors.green;
                    if (cat == 'Tunda') catColor = Colors.orange;
                    if (cat == 'Ditolak') catColor = Colors.red;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: CircleAvatar(child: Text("${index + 1}")),
                        title: Text(data['text'] ?? ''),
                        subtitle: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          margin: const EdgeInsets.only(top: 4),
                          decoration: BoxDecoration(
                              color: catColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4)),
                          child: Text(cat,
                              style: TextStyle(
                                  color: catColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12)),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                                icon:
                                    const Icon(Icons.edit, color: Colors.blue),
                                onPressed: () => _editPertanyaan(
                                    docs[index].id, data['text'], cat)),
                            IconButton(
                                icon:
                                    const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => _hapusPertanyaan(
                                    docs[index].id, data['text'])),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// --- SECTION: PROFILE ---
class _AdminProfileSection extends StatefulWidget {
  const _AdminProfileSection();

  @override
  State<_AdminProfileSection> createState() => _AdminProfileSectionState();
}

class _AdminProfileSectionState extends State<_AdminProfileSection> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();

  String? _profilePicUrl;
  bool _isLoading = false;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _fetchAdminData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _fetchAdminData() async {
    setState(() => _isLoading = true);
    try {
      final user = _auth.currentUser;
      if (user != null) {
        final doc = await _db.collection('users').doc(user.uid).get();
        if (doc.exists) {
          final data = doc.data()!;
          _nameController.text =
              "${data['firstName'] ?? ''} ${data['lastName'] ?? ''}".trim();
          _emailController.text = data['email'] ?? user.email ?? '';
          _profilePicUrl = data['profilePicture'];
        } else {
          // Jika belum ada record di users, pakai data dari auth
          _emailController.text = user.email ?? '';
          _nameController.text = "Admin Bloodify";
        }
      }
    } catch (e) {
      debugPrint("Error fetching admin data: $e");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _uploadImage() async {
    final picker = ImagePicker();
    final pickedFile =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (pickedFile == null) return;

    setState(() => _isUploading = true);
    try {
      final bytes = await pickedFile.readAsBytes();
      var request = http.MultipartRequest(
          'POST',
          Uri.parse(
              'https://api.cloudinary.com/v1_1/${CloudinaryConfig.cloudName}/upload'));
      request.fields['upload_preset'] = CloudinaryConfig.uploadPreset;
      request.files.add(http.MultipartFile.fromBytes('file', bytes,
          filename: 'admin_profile.jpg'));

      var response = await request.send();
      if (response.statusCode == 200) {
        final respStr = await response.stream.bytesToString();
        final jsonResponse = json.decode(respStr);
        final url = jsonResponse['secure_url'];

        await _db.collection('users').doc(_auth.currentUser!.uid).set({
          'profilePicture': url,
          'email': _auth.currentUser!.email,
          'firstName': 'Admin',
          'lastName': 'Bloodify',
        }, SetOptions(merge: true));

        setState(() => _profilePicUrl = url);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Gagal upload: $e")));
    } finally {
      setState(() => _isUploading = false);
    }
  }

  Future<void> _updateProfile() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final names = _nameController.text.split(' ');
    final first = names.isNotEmpty ? names[0] : 'Admin';
    final last = names.length > 1 ? names.sublist(1).join(' ') : '';

    await _db.collection('users').doc(user.uid).set({
      'firstName': first,
      'lastName': last,
      'email': _emailController.text,
      'role': 'admin', // Pastikan role admin tersimpan
    }, SetOptions(merge: true));

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Profil diperbarui"), backgroundColor: Colors.green));
  }

  Future<void> _changePassword() async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Ganti Kata Sandi"),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          decoration: const InputDecoration(
              labelText: "Kata Sandi Baru", border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text("Batal")),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            style:
                ElevatedButton.styleFrom(backgroundColor: Colors.red.shade800),
            child: const Text("Simpan", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      try {
        await _auth.currentUser!.updatePassword(result);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Kata sandi berhasil diperbarui!"),
            backgroundColor: Colors.green));
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Gagal ganti kata sandi: $e. Silakan relogin."),
            backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Profil Admin",
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.red.shade800,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              final navigator = Navigator.of(context);
              await _auth.signOut();
              navigator.pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginPage()),
                  (route) => false);
            },
          )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _uploadImage,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CircleAvatar(
                          radius: 60,
                          backgroundColor: Colors.grey.shade200,
                          backgroundImage: _profilePicUrl != null
                              ? NetworkImage(_profilePicUrl!)
                              : null,
                          child: _profilePicUrl == null
                              ? const Icon(Icons.person,
                                  size: 60, color: Colors.grey)
                              : null,
                        ),
                        if (_isUploading) const CircularProgressIndicator(),
                        Positioned(
                            bottom: 0,
                            right: 0,
                            child: CircleAvatar(
                                radius: 18,
                                backgroundColor: Colors.red.shade800,
                                child: const Icon(Icons.camera_alt,
                                    color: Colors.white, size: 18))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                          labelText: "Nama Lengkap",
                          prefixIcon: Icon(Icons.badge))),
                  const SizedBox(height: 16),
                  TextField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                          labelText: "Email", prefixIcon: Icon(Icons.email))),
                  const SizedBox(height: 16),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.lock, color: Colors.grey),
                    title: const Text("Kata Sandi"),
                    subtitle: const Text("********"),
                    trailing: TextButton(
                      onPressed: _changePassword,
                      child: const Text("Ubah"),
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _updateProfile,
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade800,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12))),
                      child: const Text("Simpan Profil",
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
