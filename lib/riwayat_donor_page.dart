import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class RiwayatDonorPage extends StatefulWidget {
  const RiwayatDonorPage({super.key});

  @override
  State<RiwayatDonorPage> createState() => _RiwayatDonorPageState();
}

class _RiwayatDonorPageState extends State<RiwayatDonorPage> {
  final Set<String> _processingIds = {};

  Future<void> _showDonorConfirmationDialog({
    required String requestId,
  }) async {
    final TextEditingController lokasiPmiController = TextEditingController();
    DateTime? selectedDate;

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("Konfirmasi Donor"),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "Isi data donor sebenarnya setelah Anda selesai donor.",
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: lokasiPmiController,
                      decoration: InputDecoration(
                        labelText: "Lokasi PMI",
                        hintText: "Contoh: PMI Kota Semarang",
                        prefixIcon: const Icon(Icons.location_on),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.calendar_month),
                        label: Text(
                          selectedDate == null
                              ? "Pilih tanggal donor"
                              : DateFormat("dd MMMM yyyy", "id_ID")
                                  .format(selectedDate!),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () async {
                          final pickedDate = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now(),
                            firstDate: DateTime.now().subtract(
                              const Duration(days: 30),
                            ),
                            lastDate: DateTime.now().add(
                              const Duration(days: 60),
                            ),
                          );

                          if (pickedDate != null) {
                            setDialogState(() {
                              selectedDate = pickedDate;
                            });
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text("Batal"),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    final String lokasiPmi = lokasiPmiController.text.trim();

                    if (lokasiPmi.isEmpty || selectedDate == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            "Lokasi PMI dan tanggal donor wajib diisi",
                          ),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }

                    Navigator.pop(dialogContext);

                    await _konfirmasiDonor(
                      requestId: requestId,
                      isDonor: true,
                      tanggalDonor: selectedDate,
                      lokasiPmi: lokasiPmi,
                    );
                  },
                  child: const Text("Simpan"),
                ),
              ],
            );
          },
        );
      },
    );

    lokasiPmiController.dispose();
  }

  Future<void> _konfirmasiDonor({
    required String requestId,
    required bool isDonor,
    DateTime? tanggalDonor,
    String? lokasiPmi,
  }) async {
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
      final docRef = FirebaseFirestore.instance
          .collection("permintaan_darah")
          .doc(requestId);

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final snapshot = await transaction.get(docRef);

        if (!snapshot.exists) {
          throw "Data permintaan tidak ditemukan";
        }

        final data = snapshot.data() as Map<String, dynamic>;

        final String requesterUid = data["requester_uid"]?.toString() ?? "";
        final String donorUid = data["donor_uid"]?.toString() ?? "";

        if (isDonor && currentUser.uid != donorUid) {
          throw "Hanya pendonor yang bisa menekan tombol ini";
        }

        if (!isDonor && currentUser.uid != requesterUid) {
          throw "Hanya pencari darah yang bisa menekan tombol ini";
        }

        final bool donorConfirmed =
            data["donor_confirmed"] == true || isDonor;
        final bool requesterConfirmed =
            data["requester_confirmed"] == true || !isDonor;

        final Map<String, dynamic> updateData = {
          "updated_at": FieldValue.serverTimestamp(),
        };

        if (isDonor) {
          if (tanggalDonor == null ||
              lokasiPmi == null ||
              lokasiPmi.trim().isEmpty) {
            throw "Tanggal donor dan lokasi PMI wajib diisi";
          }

          updateData["donor_confirmed"] = true;
          updateData["donor_confirmed_at"] = FieldValue.serverTimestamp();
          updateData["tanggal_donor"] = Timestamp.fromDate(tanggalDonor);
          updateData["lokasi_pmi"] = lokasiPmi.trim();
        } else {
          updateData["requester_confirmed"] = true;
          updateData["requester_confirmed_at"] = FieldValue.serverTimestamp();
        }

        if (donorConfirmed && requesterConfirmed) {
          updateData["status"] = "Donor berhasil";
          updateData["donor_completed_at"] = FieldValue.serverTimestamp();
        } else {
          updateData["status"] = "Menunggu konfirmasi";
        }

        transaction.update(docRef, updateData);
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isDonor
                ? "Data donor berhasil disimpan"
                : "Konfirmasi donor diterima berhasil dikirim",
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Gagal konfirmasi: $e"),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _processingIds.remove(requestId));
      }
    }
  }

  String _formatDate(dynamic value) {
    if (value == null) return "-";

    if (value is Timestamp) {
      return DateFormat("dd MMMM yyyy", "id_ID").format(value.toDate());
    }

    if (value is DateTime) {
      return DateFormat("dd MMMM yyyy", "id_ID").format(value);
    }

    return value.toString();
  }

  Color _statusColor(String status) {
    if (status == "Donor berhasil" || status == "Selesai") {
      return Colors.green;
    }

    if (status == "Menunggu konfirmasi") {
      return Colors.orange;
    }

    return Colors.grey;
  }

  Widget _infoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.red),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(color: Colors.black87, fontSize: 14),
                children: [
                  TextSpan(
                    text: "$label: ",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  TextSpan(text: value),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 76, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text(
              "Belum ada riwayat donor",
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Riwayat donor akan muncul setelah pendonor dan pencari darah sama-sama melakukan konfirmasi.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfirmationBox({
    required bool donorConfirmed,
    required bool requesterConfirmed,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Status Konfirmasi",
            style: TextStyle(
              color: Colors.brown,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                donorConfirmed
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                color: donorConfirmed ? Colors.green : Colors.orange,
                size: 18,
              ),
              const SizedBox(width: 6),
              Text(
                donorConfirmed
                    ? "Pendonor sudah konfirmasi"
                    : "Pendonor belum konfirmasi",
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                requesterConfirmed
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                color: requesterConfirmed ? Colors.green : Colors.orange,
                size: 18,
              ),
              const SizedBox(width: 6),
              Text(
                requesterConfirmed
                    ? "Pencari darah sudah konfirmasi"
                    : "Pencari darah belum konfirmasi",
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCard({
    required QueryDocumentSnapshot<Map<String, dynamic>> doc,
    required String currentUid,
  }) {
    final data = doc.data();

    final String requesterUid = data["requester_uid"]?.toString() ?? "";
    final String donorUid = data["donor_uid"]?.toString() ?? "";

    final bool isRequester = requesterUid == currentUid;
    final bool isDonor = donorUid == currentUid;

    final String namaPencari =
        data["requester_name"]?.toString().trim().isNotEmpty == true
            ? data["requester_name"].toString()
            : "-";

    final String namaPendonor =
        data["donor_name"]?.toString().trim().isNotEmpty == true
            ? data["donor_name"].toString()
            : "-";

    final String golonganDarah = data["golongan_darah"]?.toString() ?? "-";
    final String komponenDarah = data["komponen_darah"]?.toString() ?? "-";
    final String lokasiPmi =
        data["lokasi_pmi"]?.toString().trim().isNotEmpty == true
            ? data["lokasi_pmi"].toString()
            : "-";

    final String status = data["status"]?.toString() ?? "-";

    final bool donorConfirmed = data["donor_confirmed"] == true;
    final bool requesterConfirmed = data["requester_confirmed"] == true;

    final bool isFinished = status == "Donor berhasil" || status == "Selesai";
    final bool isProcessing = _processingIds.contains(doc.id);

    final dynamic tanggalDonor = data["tanggal_donor"];

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
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
                namaPendonor == "-" ? "Proses Donor" : namaPendonor,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text("Pencari darah: $namaPencari"),
              trailing: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _statusColor(status).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _statusColor(status)),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    color: _statusColor(status),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const Divider(height: 24),
            _infoRow(
              icon: Icons.person_search,
              label: "Nama pencari darah",
              value: namaPencari,
            ),
            _infoRow(
              icon: Icons.volunteer_activism,
              label: "Nama pendonor",
              value: namaPendonor,
            ),
            _infoRow(
              icon: Icons.bloodtype,
              label: "Golongan darah",
              value: golonganDarah,
            ),
            _infoRow(
              icon: Icons.medical_services,
              label: "Komponen darah",
              value: komponenDarah,
            ),
            _infoRow(
              icon: Icons.location_on,
              label: "Lokasi PMI",
              value: lokasiPmi,
            ),
            _infoRow(
              icon: Icons.calendar_month,
              label: "Tanggal donor",
              value: _formatDate(tanggalDonor),
            ),
            _infoRow(
              icon: Icons.verified,
              label: "Status donor",
              value: status,
            ),
            if (!isFinished) ...[
              const SizedBox(height: 8),
              _buildConfirmationBox(
                donorConfirmed: donorConfirmed,
                requesterConfirmed: requesterConfirmed,
              ),
            ],
            if (!isFinished && isDonor && !donorConfirmed) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: isProcessing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.check_circle),
                  label: const Text("Saya sudah donor"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: isProcessing
                      ? null
                      : () => _showDonorConfirmationDialog(
                            requestId: doc.id,
                          ),
                ),
              ),
            ],
            if (!isFinished && isRequester && !requesterConfirmed) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: isProcessing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.done_all),
                  label: const Text("Konfirmasi donor diterima"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: isProcessing
                      ? null
                      : () => _konfirmasiDonor(
                            requestId: doc.id,
                            isDonor: false,
                          ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text("Riwayat Donor"),
          backgroundColor: Colors.red,
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: Text("Silakan login terlebih dahulu"),
        ),
      );
    }

    final String currentUid = currentUser.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Riwayat Donor"),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
      ),
      backgroundColor: const Color(0xFFF6F6F6),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection("permintaan_darah")
            .orderBy("created_at", descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text("Terjadi kesalahan saat memuat riwayat donor"),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final allDocs = snapshot.data?.docs ?? [];

          final docs = allDocs.where((doc) {
            final data = doc.data();

            final String requesterUid =
                data["requester_uid"]?.toString() ?? "";
            final String donorUid = data["donor_uid"]?.toString() ?? "";
            final String status = data["status"]?.toString() ?? "";

            final bool relatedToCurrentUser =
                requesterUid == currentUid || donorUid == currentUid;

            final bool masukRiwayat =
                status == "Donor berhasil" || status == "Selesai";

            final bool butuhKonfirmasi =
                status == "Menunggu konfirmasi" &&
                    donorUid.isNotEmpty &&
                    (data["donor_confirmed"] != true ||
                        data["requester_confirmed"] != true);

            return relatedToCurrentUser && (masukRiwayat || butuhKonfirmasi);
          }).toList();

          if (docs.isEmpty) {
            return _emptyState();
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              return _buildCard(
                doc: docs[index],
                currentUid: currentUid,
              );
            },
          );
        },
      ),
    );
  }
}