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

      final List<String> sortedUids = [donorUid, requesterUid]..sort();
      final String chatId = "${requestId}_${sortedUids[0]}_${sortedUids[1]}";

      final FirebaseFirestore firestore = FirebaseFirestore.instance;
      final chatRef = firestore.collection("chats").doc(chatId);

      final donorDoc = await firestore.collection("users").doc(donorUid).get();
      final donorData = donorDoc.data() ?? {};

      final String donorName =
          "${donorData["firstName"] ?? ""} ${donorData["lastName"] ?? ""}"
                  .trim()
                  .isEmpty
              ? "Pendonor"
              : "${donorData["firstName"] ?? ""} ${donorData["lastName"] ?? ""}"
                  .trim();

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
        });

        await chatRef.collection("messages").add({
          "text": firstMessage,
          "senderId": donorUid,
          "createdAt": FieldValue.serverTimestamp(),
        });
      }

      // TAMBAHAN: Catat bahwa user ini sudah menekan siap donor ke permintaan ini
      await firestore.collection("permintaan_darah").doc(requestId).update({
        "helpers": FieldValue.arrayUnion([donorUid]),
      });

      if (!mounted) return;

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
                  pw.Text("Format Permintaan Darah",
                      style: pw.TextStyle(
                          fontSize: 18, fontWeight: pw.FontWeight.bold)),
                  pw.Text(
                      DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())),
                ],
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Text("Detail Permintaan",
                style:
                    pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 10),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300),
              children: [
                pw.TableRow(children: [
                  pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text("Pemohon")),
                  pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text(requesterName))
                ]),
                pw.TableRow(children: [
                  pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text("Nama Pasien")),
                  pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text(namaPasien))
                ]),
                pw.TableRow(children: [
                  pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text("Usia Pasien")),
                  pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text(umurPasien))
                ]),
                pw.TableRow(children: [
                  pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text("Rumah Sakit")),
                  pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text(rumahSakit))
                ]),
                pw.TableRow(children: [
                  pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text("Golongan Darah")),
                  pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text(golonganDarah))
                ]),
                pw.TableRow(children: [
                  pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text("Komponen Darah")),
                  pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text(komponenDarah))
                ]),
                pw.TableRow(children: [
                  pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text("Jumlah Kantong")),
                  pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text(jumlahKantong))
                ]),
                pw.TableRow(children: [
                  pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text("Urgensi")),
                  pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text(urgensi))
                ]),
                pw.TableRow(children: [
                  pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text("Kontak")),
                  pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text(kontak))
                ]),
                pw.TableRow(children: [
                  pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text("Surat Dokter")),
                  pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text(suratUrl))
                ]),
              ],
            ),
          ];
        },
      ),
    );

    await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Permintaan Darah Aktif"),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection("users")
            .doc(FirebaseAuth.instance.currentUser?.uid)
            .snapshots(),
        builder: (context, userSnapshot) {
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
                    child: Text("Terjadi kesalahan saat memuat data"));
              }

              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final allRequests = snapshot.data?.docs ?? [];
              final donorUid = FirebaseAuth.instance.currentUser?.uid;

              // Filter permintaan yang BELUM dikontak oleh user saat ini
              final requests = allRequests.where((doc) {
                final data = doc.data();
                final List<dynamic> helpers = data['helpers'] ?? [];
                return !helpers.contains(donorUid);
              }).toList();

              if (requests.isEmpty) {
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.done_all, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text("Tidak ada permintaan baru untuk Anda"),
                    ],
                  ),
                );
              }

              return Column(
                children: [
                  if (viewerStatus == null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      color: Colors.orange.shade100,
                      child: const Text(
                        "Harap isi kuesioner terlebih dahulu di halaman Profil untuk melihat kriteria atau status di halaman ini.",
                        style: TextStyle(
                            color: Colors.brown,
                            fontWeight: FontWeight.bold,
                            fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: requests.length,
                      itemBuilder: (context, index) {
                        final doc = requests[index];
                        final request = doc.data();

                        final String golonganDarah =
                            request["golongan_darah"]?.toString() ?? "-";
                        final String namaPasien =
                            request["nama_pasien"]?.toString() ?? "-";
                        final String umurPasien =
                            request["umur_pasien"]?.toString() ?? "-";
                        final String rumahSakit =
                            request["rumah_sakit"]?.toString() ?? "-";
                        final String komponenDarah =
                            request["komponen_darah"]?.toString() ?? "-";
                        final String jumlahKantong =
                            request["jumlah_kantong"]?.toString() ?? "0";
                        final String urgensi =
                            request["urgensi"]?.toString() ?? "-";
                        final String kontak =
                            request["kontak"]?.toString() ?? "-";

                        Widget trailingWidget = const SizedBox.shrink();

                        if (viewerStatus != null) {
                          if (viewerStatus == 'Lolos') {
                            trailingWidget = ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                              ),
                              onPressed: _processingIds.contains(doc.id)
                                  ? null
                                  : () => _handleDonorAction(doc.id, request),
                              child: _processingIds.contains(doc.id)
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          color: Colors.white, strokeWidth: 2))
                                  : const Text("Siap Donor"),
                            );
                          } else if (viewerStatus ==
                              'Menunggu Konfirmasi PMI') {
                            // Status Tunda — menunggu keputusan Admin
                            trailingWidget = Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                  color: Colors.orange.shade50,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.orange)),
                              child: const Text("Menunggu\nkonfirmasi PMI",
                                  style: TextStyle(
                                      color: Colors.orange,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold),
                                  textAlign: TextAlign.center),
                            );
                          } else if (viewerStatus == 'Ditolak') {
                            trailingWidget = Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.red)),
                              child: const Text("Belum Layak",
                                  style: TextStyle(
                                      color: Colors.red,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold)),
                            );
                          } else {
                            // Status lain (misal belum isi atau status tidak dikenal)
                            trailingWidget = Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.grey)),
                              child: const Text("Tidak Layak",
                                  style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold)),
                            );
                          }
                        }

                        return Card(
                          margin: const EdgeInsets.all(10),
                          elevation: 3,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                vertical: 8, horizontal: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: CircleAvatar(
                                    backgroundColor: Colors.red,
                                    child: Text(golonganDarah,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold)),
                                  ),
                                  title: Text(namaPasien,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold)),
                                  subtitle: Text("RS: $rumahSakit"),
                                ),
                                const SizedBox(height: 8),
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
                                        icon: const Icon(Icons.picture_as_pdf,
                                            color: Colors.red),
                                        label: const Text("PDF"),
                                        onPressed: () =>
                                            _generateAndPrintRequestPdf(
                                                request),
                                        style: OutlinedButton.styleFrom(
                                          side: const BorderSide(
                                              color: Colors.red),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    if (viewerStatus == 'Lolos')
                                      Expanded(
                                        child: ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.green,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 12),
                                          ),
                                          onPressed:
                                              _processingIds.contains(doc.id)
                                                  ? null
                                                  : () => _handleDonorAction(
                                                      doc.id, request),
                                          child: _processingIds.contains(doc.id)
                                              ? const SizedBox(
                                                  width: 20,
                                                  height: 20,
                                                  child:
                                                      CircularProgressIndicator(
                                                          color: Colors.white,
                                                          strokeWidth: 2))
                                              : const Text("Siap Donor"),
                                        ),
                                      )
                                    else if (viewerStatus != null)
                                      Expanded(child: trailingWidget),
                                  ],
                                ),
                              ],
                            ),
                          ),
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
