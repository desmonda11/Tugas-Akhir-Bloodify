import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'cloudinary_config.dart';
import 'fcm_service.dart';

class PermintaanPage extends StatefulWidget {
  const PermintaanPage({super.key});

  @override
  State<PermintaanPage> createState() => _PermintaanPageState();
}

class _PermintaanPageState extends State<PermintaanPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final TextEditingController namaPasienController = TextEditingController();
  final TextEditingController usiaPasienController = TextEditingController();
  final TextEditingController rumahSakitController = TextEditingController();
  final TextEditingController jumlahKantongController = TextEditingController();
  final TextEditingController kontakController = TextEditingController();

  String golonganDarah = "O+";
  String jenisKomponenDarah = "WB";
  String tingkatUrgensi = "Tinggi";
  bool _isLoading = false;
  bool _isUploadingSurat = false;
  String? _dokterSuratUrl;
  String? _dokterSuratName;
  String? _kuesionerStatus;
  bool _isCheckingStatus = true;

  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _fetchUserStatus();
  }

  Future<void> _fetchUserStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final doc = await firestore.collection("users").doc(user.uid).get();
        if (doc.exists) {
          setState(() {
            _kuesionerStatus = doc.data()?['kuesioner_status']?.toString();
          });
        }
      } catch (e) {
        debugPrint("Error fetching status: $e");
      }
    }
    setState(() {
      _isCheckingStatus = false;
    });
  }

  Future<void> kirimPermintaan() async {
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("User belum login"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final userDoc = await firestore.collection("users").doc(user.uid).get();

      final userData = userDoc.data() ?? {};
      final String firstName = userData["firstName"]?.toString() ?? "";
      final String lastName = userData["lastName"]?.toString() ?? "";
      final String requesterName = "$firstName $lastName".trim().isEmpty
          ? "User"
          : "$firstName $lastName".trim();

      final newRequest = {
        "nama_pasien": namaPasienController.text.trim(),
        "umur_pasien": int.parse(usiaPasienController.text.trim()),
        "rumah_sakit": rumahSakitController.text.trim(),
        "golongan_darah": golonganDarah,
        "komponen_darah": jenisKomponenDarah,
        "jumlah_kantong": int.parse(jumlahKantongController.text.trim()),
        "urgensi": tingkatUrgensi,
        "kontak": kontakController.text.trim(),
        "created_at": FieldValue.serverTimestamp(),
        "requester_uid": user.uid,
        "requester_name": requesterName,
        "requester_email": user.email,
        "status": "aktif",
      };

      if (_dokterSuratUrl != null) {
        newRequest["dokter_surat_url"] = _dokterSuratUrl;
      }

      await firestore.collection("permintaan_darah").add(newRequest);

      // Kirim Notifikasi Broadcast via FCM Topics
      await _sendBroadcastNotification(
          requesterName, golonganDarah, jenisKomponenDarah);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Permintaan darah berhasil dikirim"),
          backgroundColor: Colors.green,
        ),
      );

      namaPasienController.clear();
      usiaPasienController.clear();
      rumahSakitController.clear();
      jumlahKantongController.clear();
      kontakController.clear();
      _dokterSuratUrl = null;
      _dokterSuratName = null;

      setState(() {
        golonganDarah = "O+";
        jenisKomponenDarah = "WB";
        tingkatUrgensi = "Tinggi";
      });
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Gagal mengirim data: $e"),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _sendBroadcastNotification(
      String requesterName, String bloodType, String componentType) async {
    await FcmService.sendTemplatedBroadcast(
      requesterName: requesterName,
      bloodType: bloodType,
      componentType: componentType,
    );
  }

  @override
  void dispose() {
    namaPasienController.dispose();
    usiaPasienController.dispose();
    rumahSakitController.dispose();
    jumlahKantongController.dispose();
    kontakController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Buat Permintaan Darah"),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
      ),
      backgroundColor: const Color(0xFFF6F6F6),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: _isCheckingStatus
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_kuesionerStatus == null) _warningBanner(),
                    _inputField(
                      label: "Nama Pasien",
                      controller: namaPasienController,
                      hint: "Masukkan nama pasien",
                      enabled: _kuesionerStatus != null,
                    ),
                    _inputField(
                      label: "Usia Pasien",
                      controller: usiaPasienController,
                      hint: "Contoh: 25",
                      keyboardType: TextInputType.number,
                      enabled: _kuesionerStatus != null,
                    ),
                    _inputField(
                      label: "Rumah Sakit",
                      controller: rumahSakitController,
                      hint: "Contoh: RS Sentosa",
                      enabled: _kuesionerStatus != null,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      "Golongan Darah",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    _golonganDarahSelector(),
                    const SizedBox(height: 16),
                    _inputField(
                      label: "Jumlah Kantong Darah",
                      controller: jumlahKantongController,
                      hint: "Contoh: 2",
                      keyboardType: TextInputType.number,
                      enabled: _kuesionerStatus != null,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      "Jenis Komponen Darah",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    _komponenDarahSelector(),
                    const SizedBox(height: 16),
                    const Text(
                      "Tingkat Urgensi",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    _urgensiSelector(),
                    const SizedBox(height: 16),
                    _inputField(
                      label: "Kontak yang Bisa Dihubungi",
                      controller: kontakController,
                      hint: "08xxxxxxxxxx",
                      keyboardType: TextInputType.phone,
                      enabled: _kuesionerStatus != null,
                    ),
                    const SizedBox(height: 16),
                    _uploadSuratDokterSection(),
                    const SizedBox(height: 16),
                    _downloadPdfButton(),
                    const SizedBox(height: 16),
                    _submitButton(),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _warningBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              "Anda belum mengisi kuesioner kelayakan. Harap isi kuesioner di halaman Profil sebelum dapat membuat permintaan darah.",
              style: TextStyle(
                  color: Colors.red, fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _inputField({
    required String label,
    required TextEditingController controller,
    required String hint,
    TextInputType keyboardType = TextInputType.text,
    bool enabled = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
              fontWeight: FontWeight.bold,
              color: enabled ? Colors.black : Colors.grey),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          enabled: enabled,
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return "$label tidak boleh kosong";
            }

            if (label == "Jumlah Kantong Darah") {
              final jumlah = int.tryParse(value.trim());
              if (jumlah == null || jumlah <= 0) {
                return "Jumlah kantong harus berupa angka lebih dari 0";
              }
            }

            if (label == "Usia Pasien") {
              final usia = int.tryParse(value.trim());
              if (usia == null || usia <= 0) {
                return "Usia pasien harus berupa angka lebih dari 0";
              }
            }

            return null;
          },
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _golonganDarahSelector() {
    final List<String> golonganList = [
      "O+",
      "O-",
      "A+",
      "A-",
      "B+",
      "B-",
      "AB+",
      "AB-"
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: golonganList.map((gd) {
        return ChoiceChip(
          label: Text(gd),
          selected: golonganDarah == gd,
          selectedColor: Colors.red,
          labelStyle: TextStyle(
            color: golonganDarah == gd ? Colors.white : Colors.black,
          ),
          onSelected: _kuesionerStatus == null
              ? null
              : (_) {
                  setState(() {
                    golonganDarah = gd;
                  });
                },
        );
      }).toList(),
    );
  }

  Widget _urgensiSelector() {
    final List<String> urgensiList = ["Rendah", "Sedang", "Tinggi"];

    return RadioGroup<String>(
      groupValue: tingkatUrgensi,
      onChanged: _kuesionerStatus == null
          ? (_) {} // Dummy function to disable interaction
          : (value) {
              if (value == null) return;
              setState(() {
                tingkatUrgensi = value;
              });
            },
      child: Column(
        children: urgensiList.map((urgensi) {
          return RadioListTile<String>(
            value: urgensi,
            activeColor: Colors.red,
            contentPadding: EdgeInsets.zero,
            title: Text(urgensi),
          );
        }).toList(),
      ),
    );
  }

  Widget _komponenDarahSelector() {
    final List<String> componentOptions = [
      "WB",
      "PRC",
      "WRC",
      "TC",
      "FFP",
      "AHF",
      "LP",
      "BC",
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: componentOptions.map((option) {
        return ChoiceChip(
          label: Text(option),
          selected: jenisKomponenDarah == option,
          selectedColor: Colors.red,
          labelStyle: TextStyle(
            color: jenisKomponenDarah == option ? Colors.white : Colors.black,
          ),
          onSelected: _kuesionerStatus == null
              ? null
              : (_) {
                  setState(() {
                    jenisKomponenDarah = option;
                  });
                },
        );
      }).toList(),
    );
  }

  Widget _uploadSuratDokterSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Upload Surat Dokter (opsional)",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _kuesionerStatus == null || _isUploadingSurat
                    ? null
                    : _pickAndUploadSuratDokter,
                icon: const Icon(Icons.upload_file),
                label: Text(_dokterSuratName == null
                    ? 'Pilih Surat Dokter'
                    : 'Ubah Surat Dokter'),
              ),
            ),
            if (_isUploadingSurat) ...[
              const SizedBox(width: 12),
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.red,
                ),
              ),
            ]
          ],
        ),
        if (_dokterSuratName != null) ...[
          const SizedBox(height: 8),
          Text(
            "File terpilih: $_dokterSuratName",
            style: const TextStyle(fontSize: 13, color: Colors.black87),
          ),
        ],
      ],
    );
  }

  Future<void> _pickAndUploadSuratDokter() async {
    final ImagePicker picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile == null) return;

    setState(() {
      _isUploadingSurat = true;
    });

    try {
      final bytes = await pickedFile.readAsBytes();
      final uri = Uri.parse(
          'https://api.cloudinary.com/v1_1/${CloudinaryConfig.cloudName}/upload');
      final request = http.MultipartRequest('POST', uri);
      request.fields['upload_preset'] = CloudinaryConfig.uploadPreset;
      request.files.add(http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: pickedFile.name,
      ));

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception(
            'Gagal mengunggah surat dokter. Status: ${response.statusCode}');
      }

      final body = jsonDecode(responseBody);
      final secureUrl = body['secure_url']?.toString();
      if (secureUrl == null || secureUrl.isEmpty) {
        throw Exception('URL hasil upload tidak valid');
      }

      setState(() {
        _dokterSuratUrl = secureUrl;
        _dokterSuratName = pickedFile.name;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Surat dokter berhasil diunggah'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal mengunggah surat dokter: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingSurat = false;
        });
      }
    }
  }

  Widget _downloadPdfButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton.icon(
        icon: const Icon(Icons.picture_as_pdf, color: Colors.red),
        label: const Text(
          "Download PDF Permintaan",
          style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red),
        ),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Colors.red),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        onPressed: _kuesionerStatus == null ? null : _generateRequestPdf,
      ),
    );
  }

  Future<void> _generateRequestPdf() async {
    final String namaPasien = namaPasienController.text.trim().isEmpty
        ? "-"
        : namaPasienController.text.trim();
    final String usiaPasien = usiaPasienController.text.trim().isEmpty
        ? "-"
        : usiaPasienController.text.trim();
    final String rumahSakit = rumahSakitController.text.trim().isEmpty
        ? "-"
        : rumahSakitController.text.trim();
    final String jumlahKantong = jumlahKantongController.text.trim().isEmpty
        ? "-"
        : jumlahKantongController.text.trim();
    final String kontak = kontakController.text.trim().isEmpty
        ? "-"
        : kontakController.text.trim();
    final String suratDokter = _dokterSuratUrl == null ? "Tidak ada" : "Ada";

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
                  pw.Text("Permintaan Darah Bloodify",
                      style: pw.TextStyle(
                          fontSize: 18, fontWeight: pw.FontWeight.bold)),
                  pw.Text(
                      DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())),
                ],
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Text("Detail Permintaan:",
                style:
                    pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 10),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300),
              children: [
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
                      child: pw.Text(usiaPasien))
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
                      child: pw.Text(jenisKomponenDarah))
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
                      child: pw.Text(tingkatUrgensi))
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
                      child: pw.Text(suratDokter))
                ]),
              ],
            ),
            if (_dokterSuratUrl != null) ...[
              pw.SizedBox(height: 10),
              pw.Text("Surat dokter tersedia: $_dokterSuratUrl",
                  style: pw.TextStyle(fontSize: 12)),
            ],
          ];
        },
      ),
    );

    await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save());
  }

  Widget _submitButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.red,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.grey.shade400,
          disabledForegroundColor: Colors.white70,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        onPressed: (_isLoading || _isUploadingSurat || _kuesionerStatus == null)
            ? null
            : kirimPermintaan,
        child: _isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              )
            : const Text(
                "KIRIM PERMINTAAN",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }
}
