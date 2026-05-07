import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'main.dart';

class PermintaanAktifPage extends StatefulWidget {
  const PermintaanAktifPage({super.key});

  @override
  State<PermintaanAktifPage> createState() => _PermintaanAktifPageState();
}

class _PermintaanAktifPageState extends State<PermintaanAktifPage> {
  final Set<String> _processingIds = {};

  Future<void> _handleDonorAction(
    String requestId,
    Map<String, dynamic> requestData,
  ) async {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Silakan login terlebih dahulu"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _processingIds.add(requestId));

    try {
      final String donorUid = currentUser.uid;
      final String requesterUid =
          requestData["requester_uid"]?.toString() ?? "";

      if (requesterUid.isEmpty) {
        throw "Data pembuat permintaan tidak ditemukan";
      }

      if (donorUid == requesterUid) {
        throw "Kamu tidak bisa donor ke permintaan milik sendiri";
      }

      final FirebaseFirestore firestore = FirebaseFirestore.instance;

      final requestRef =
          firestore.collection("permintaan_darah").doc(requestId);

      final latestRequestSnapshot = await requestRef.get();
      final latestRequestData = latestRequestSnapshot.data();

      if (latestRequestData == null) {
        throw "Data permintaan tidak ditemukan";
      }

      final String currentStatus =
          latestRequestData["status"]?.toString() ?? "aktif";

      final String existingDonorUid =
          latestRequestData["donor_uid"]?.toString() ?? "";

      if (existingDonorUid.isNotEmpty && existingDonorUid != donorUid) {
        throw "Permintaan ini sudah diambil oleh pendonor lain";
      }

      if (currentStatus == "Donor berhasil" || currentStatus == "Selesai") {
        throw "Permintaan ini sudah selesai";
      }

      final List<String> sortedUids = [donorUid, requesterUid]..sort();
      final String chatId = "${requestId}_${sortedUids[0]}_${sortedUids[1]}";

      final chatRef = firestore.collection("chats").doc(chatId);

      final donorDoc = await firestore.collection("users").doc(donorUid).get();
      final donorData = donorDoc.data() ?? {};

      final String firstName = donorData["firstName"]?.toString() ?? "";
      final String lastName = donorData["lastName"]?.toString() ?? "";

      final String donorName = "$firstName $lastName".trim().isEmpty
          ? "Pendonor"
          : "$firstName $lastName".trim();

      final String requesterName =
          requestData["requester_name"]?.toString() ?? "Penerima";

      final chatSnapshot = await chatRef.get();

      if (!chatSnapshot.exists) {
        const firstMessage =
            "Halo, saya siap donor untuk kebutuhan darah ini. Mari kita koordinasikan lebih lanjut.";

        await chatRef.set({
          "request_id": requestId,
          "participants": [donorUid, requesterUid],
          "donor_uid": donorUid,
          "requester_uid": requesterUid,
          "donor_name": donorName,
          "requester_name": requesterName,
          "last_message": firstMessage,
          "timestamp": FieldValue.serverTimestamp(),
          "created_at": FieldValue.serverTimestamp(),
          "unreadCount": {
            donorUid: 0,
            requesterUid: 1,
          },
        });

        await chatRef.collection("messages").add({
          "text": firstMessage,
          "senderId": donorUid,
          "createdAt": FieldValue.serverTimestamp(),
        });
      }

      await requestRef.update({
        "helpers": FieldValue.arrayUnion([donorUid]),

        // Data pendonor yang mengambil permintaan
        "donor_uid": donorUid,
        "donor_name": donorName,
        "donor_email": currentUser.email,

        // Status proses donor
        "status": "Menunggu konfirmasi",
        "donor_confirmed": false,
        "requester_confirmed": false,

        // Waktu update
        "updated_at": FieldValue.serverTimestamp(),
        "donor_taken_at": FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Permintaan berhasil diambil. Silakan lanjutkan lewat chat."),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (context) => MainPage(
            initialIndex: 2,
            forcePushChatId: chatId,
            forcePushChatTitle: requesterName,
          ),
        ),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Terjadi kesalahan: $e"),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _processingIds.remove(requestId));
      }
    }
  }

  Future<void> _generateAndPrintRequestPdf(Map<String, dynamic> request) async {
    final String namaPasien = request["nama_pasien"]?.toString() ?? "-";
    final String umurPasien = request["umur_pasien"]?.toString() ?? "-";
    final String rumahSakit = request["rumah_sakit"]?.toString() ?? "-";
    final String golonganDarah = request["golongan_darah"]?.toString() ?? "-";
    final String komponenDarah = request["komponen_darah"]?.toString() ?? "-";
    final String jumlahKantong = request["jumlah_kantong"]?.toString() ?? "-";
    final String urgensi = request["urgensi"]?.toString() ?? "-";
    final String kontak = request["kontak"]?.toString() ?? "-";
    final String requesterName = request["requester_name"]?.toString() ?? "-";
    final String suratUrl =
        request["dokter_surat_url"]?.toString() ?? "Tidak ada";

    final pdf = pw.Document();

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
                  pw.Text(
                    "Format Permintaan Darah",
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now()),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Text(
              "Detail Permintaan",
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300),
              children: [
                _pdfTableRow("Pemohon", requesterName),
                _pdfTableRow("Nama Pasien", namaPasien),
                _pdfTableRow("Usia Pasien", umurPasien),
                _pdfTableRow("Rumah Sakit", rumahSakit),
                _pdfTableRow("Golongan Darah", golonganDarah),
                _pdfTableRow("Komponen Darah", komponenDarah),
                _pdfTableRow("Jumlah Kantong", jumlahKantong),
                _pdfTableRow("Urgensi", urgensi),
                _pdfTableRow("Kontak", kontak),
                _pdfTableRow("Surat Dokter", suratUrl),
              ],
            ),
          ];
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
    );
  }

  pw.TableRow _pdfTableRow(String label, String value) {
    return pw.TableRow(
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.all(6),
          child: pw.Text(label),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.all(6),
          child: pw.Text(value),
        ),
      ],
    );
  }

  bool _isRequestAvailableForCurrentUser({
    required Map<String, dynamic> data,
    required String? currentUid,
  }) {
    if (currentUid == null) return false;

    final String requesterUid = data["requester_uid"]?.toString() ?? "";
    final String status = data["status"]?.toString() ?? "aktif";
    final List<dynamic> helpers = data["helpers"] ?? [];
    final String donorUid = data["donor_uid"]?.toString() ?? "";

    if (requesterUid == currentUid) return false;
    if (helpers.contains(currentUid)) return false;

    // Permintaan yang sudah ada pendonor tidak ditampilkan lagi ke pendonor lain
    if (donorUid.isNotEmpty && donorUid != currentUid) return false;

    // Yang ditampilkan di halaman aktif hanya yang masih aktif
    if (status != "aktif") return false;

    return true;
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.done_all, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              "Tidak ada permintaan baru untuk Anda",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBanner(String? viewerStatus) {
    if (viewerStatus != null) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: Colors.orange.shade100,
      child: const Text(
        "Harap isi kuesioner terlebih dahulu di halaman Profil untuk melihat kriteria atau status di halaman ini.",
        style: TextStyle(
          color: Colors.brown,
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildActionButton({
    required String viewerStatus,
    required String requestId,
    required Map<String, dynamic> request,
  }) {
    final bool isProcessing = _processingIds.contains(requestId);

    if (viewerStatus == 'Lolos') {
      return ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        onPressed:
            isProcessing ? null : () => _handleDonorAction(requestId, request),
        child: isProcessing
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : const Text("Siap Donor"),
      );
    }

    if (viewerStatus == 'Menunggu Konfirmasi PMI') {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.orange),
        ),
        child: const Text(
          "Menunggu konfirmasi PMI",
          style: TextStyle(
            color: Colors.orange,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }

    if (viewerStatus == 'Ditolak') {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.red),
        ),
        child: const Text(
          "Belum Layak",
          style: TextStyle(
            color: Colors.red,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey),
      ),
      child: const Text(
        "Tidak Layak",
        style: TextStyle(
          color: Colors.grey,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildRequestCard({
    required QueryDocumentSnapshot<Map<String, dynamic>> doc,
    required String? viewerStatus,
  }) {
    final request = doc.data();

    final String golonganDarah = request["golongan_darah"]?.toString() ?? "-";
    final String namaPasien = request["nama_pasien"]?.toString() ?? "-";
    final String umurPasien = request["umur_pasien"]?.toString() ?? "-";
    final String rumahSakit = request["rumah_sakit"]?.toString() ?? "-";
    final String komponenDarah = request["komponen_darah"]?.toString() ?? "-";
    final String jumlahKantong = request["jumlah_kantong"]?.toString() ?? "0";
    final String urgensi = request["urgensi"]?.toString() ?? "-";
    final String kontak = request["kontak"]?.toString() ?? "-";
    final String requesterName = request["requester_name"]?.toString() ?? "-";

    return Card(
      margin: const EdgeInsets.all(10),
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: Colors.red,
                child: Text(
                  golonganDarah,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              title: Text(
                namaPasien,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text("RS: $rumahSakit"),
            ),
            const SizedBox(height: 8),
            Text("Pemohon: $requesterName"),
            Text("Usia Pasien: $umurPasien tahun"),
            Text("Komponen: $komponenDarah"),
            Text("Jumlah: $jumlahKantong kantong"),
            Text("Urgensi: $urgensi"),
            Text("Kontak: $kontak"),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.picture_as_pdf, color: Colors.red),
                    label: const Text(
                      "PDF",
                      style: TextStyle(color: Colors.red),
                    ),
                    onPressed: () => _generateAndPrintRequestPdf(request),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.red),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (viewerStatus != null)
                  Expanded(
                    child: _buildActionButton(
                      viewerStatus: viewerStatus,
                      requestId: doc.id,
                      request: request,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String? currentUid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Permintaan Darah Aktif"),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
      ),
      backgroundColor: const Color(0xFFF6F6F6),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection("users")
            .doc(currentUid)
            .snapshots(),
        builder: (context, userSnapshot) {
          if (userSnapshot.hasError) {
            return const Center(
              child: Text("Terjadi kesalahan saat memuat data user"),
            );
          }

          final userData = userSnapshot.data?.data();
          final String? viewerStatus = userData?['kuesioner_status'];

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection("permintaan_darah")
                .orderBy("created_at", descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(
                  child: Text("Terjadi kesalahan saat memuat data"),
                );
              }

              if (snapshot.connectionState == ConnectionState.waiting ||
                  userSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final allRequests = snapshot.data?.docs ?? [];

              final requests = allRequests.where((doc) {
                return _isRequestAvailableForCurrentUser(
                  data: doc.data(),
                  currentUid: currentUid,
                );
              }).toList();

              if (requests.isEmpty) {
                return Column(
                  children: [
                    _buildStatusBanner(viewerStatus),
                    Expanded(child: _buildEmptyState()),
                  ],
                );
              }

              return Column(
                children: [
                  _buildStatusBanner(viewerStatus),
                  Expanded(
                    child: ListView.builder(
                      itemCount: requests.length,
                      itemBuilder: (context, index) {
                        return _buildRequestCard(
                          doc: requests[index],
                          viewerStatus: viewerStatus,
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}