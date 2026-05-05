import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'cloudinary_config.dart';
import 'dart:convert';
import 'login_page.dart';
import 'kuesioner_page.dart';

class ProfilPage extends StatefulWidget {
  const ProfilPage({super.key});

  @override
  State<ProfilPage> createState() => _ProfilPageState();
}

class _ProfilPageState extends State<ProfilPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _isEditing = false;
  bool _isLoading = false;
  bool _isSaving = false;
  bool _isUploadingPic = false;

  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  String? _selectedBloodType;
  String? _profilePicUrl;
  String _userName = "Nama Pengguna";
  String _userEmail = "-";
  String? _kuesionerStatus;
  DateTime? _kuesionerUpdatedAt;
  bool _canFillKuesioner = true;

  final List<String> _bloodTypes = ['A', 'B', 'AB', 'O', 'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _fetchUserData() async {
    setState(() => _isLoading = true);
    try {
      final user = _auth.currentUser;
      if (user != null) {
        final doc = await _firestore.collection('users').doc(user.uid).get();
        if (doc.exists && doc.data() != null) {
          final data = doc.data()!;
          final firstName = data['firstName']?.toString() ?? "";
          final lastName = data['lastName']?.toString() ?? "";
          
          setState(() {
            _userName = "$firstName $lastName".trim().isEmpty ? "User" : "$firstName $lastName".trim();
            _userEmail = data['email']?.toString() ?? user.email ?? "-";
            _phoneController.text = data['nomorTelepon']?.toString() ?? "";
            _addressController.text = data['alamat']?.toString() ?? data['location']?.toString() ?? "";
            _profilePicUrl = data['profilePicture']?.toString();
            _selectedBloodType = data['golonganDarah']?.toString();
            _kuesionerStatus = data['kuesioner_status']?.toString();
            
            // Cek kapan terakhir isi kuesioner
            final timestamp = data['kuesioner_updated_at'];
            if (timestamp != null && timestamp is Timestamp) {
              _kuesionerUpdatedAt = timestamp.toDate();
              final now = DateTime.now();
              final difference = now.difference(_kuesionerUpdatedAt!).inDays;
              _canFillKuesioner = difference >= 30;
            } else {
              _canFillKuesioner = true;
            }

            // Validasi agar blood type ada di list
            if (_selectedBloodType != null && !_bloodTypes.contains(_selectedBloodType)) {
              _selectedBloodType = null;
            }
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching user data: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isLoading = true);
    try {
      Position position = await Geolocator.getCurrentPosition();
      
      final url = Uri.parse(
          "https://nominatim.openstreetmap.org/reverse?format=json&lat=${position.latitude}&lon=${position.longitude}&zoom=18&addressdetails=1");
      final response = await http.get(url, headers: {'User-Agent': 'BloodifyApp/1.0'});

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final displayName = data['display_name'] ?? "";
        final parts = displayName.split(',');
        String address = displayName;
        if (parts.length > 2) {
          address = "${parts[0].trim()}, ${parts[1].trim()}";
        }
        
        setState(() {
          _addressController.text = address;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Gagal mengambil lokasi: $e")),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pickAndUploadImage() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final picker = ImagePicker();
    // Beri pilihan ke user untuk Kamera atau Galeri
    final source = await showDialog<ImageSource>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Pilih Sumber Foto"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, ImageSource.camera),
            child: const Text("Kamera"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ImageSource.gallery),
            child: const Text("Galeri"),
          ),
        ],
      ),
    );

    if (source == null) return;

    final pickedFile = await picker.pickImage(source: source, imageQuality: 70);
    if (pickedFile == null) return;

    setState(() => _isUploadingPic = true);

    try {
      final bytes = await pickedFile.readAsBytes();
      
      var request = http.MultipartRequest(
        'POST', 
        Uri.parse('https://api.cloudinary.com/v1_1/${CloudinaryConfig.cloudName}/upload')
      );
      request.fields['upload_preset'] = CloudinaryConfig.uploadPreset;
      request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: pickedFile.name));

      var response = await request.send();
      
      if (response.statusCode == 200) {
        final respStr = await response.stream.bytesToString();
        final jsonResponse = json.decode(respStr);
        final downloadUrl = jsonResponse['secure_url'];

        // Update ke Firestore
        await _firestore.collection('users').doc(user.uid).update({
          'profilePicture': downloadUrl,
        });

        setState(() {
          _profilePicUrl = downloadUrl;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Foto profil berhasil diperbarui!")));
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal upload foto ke Cloudinary. Status: ${response.statusCode}")));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal upload foto: $e")));
      }
    } finally {
      setState(() => _isUploadingPic = false);
    }
  }

  Future<void> _saveData() async {
    setState(() => _isSaving = true);
    try {
      final user = _auth.currentUser;
      if (user != null) {
        await _firestore.collection('users').doc(user.uid).update({
          'nomorTelepon': _phoneController.text,
          'alamat': _addressController.text,
          'location': _addressController.text, // Sync dengan Dashboard
          'golonganDarah': _selectedBloodType,
          'lastUpdate': FieldValue.serverTimestamp(),
        });

        setState(() => _isEditing = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Profil berhasil diperbarui!")),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Gagal menyimpan data: $e")),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _logout() async {
    await _auth.signOut();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFDF7F7),
      appBar: AppBar(
        backgroundColor: const Color(0xFFD32F2F),
        elevation: 0,
        title: const Text("Profil Saya", style: TextStyle(color: Colors.white)),
        centerTitle: true,
        actions: [
          if (!_isEditing)
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.white),
              onPressed: () => setState(() => _isEditing = true),
            )
          else
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () {
                _fetchUserData(); // Reset data
                setState(() => _isEditing = false);
              },
            ),
        ],
      ),
      body: _isLoading && !_isEditing
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _isEditing ? _pickAndUploadImage : null,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CircleAvatar(
                          radius: 50,
                          backgroundColor: const Color(0xFFD32F2F),
                          backgroundImage: _profilePicUrl != null && _profilePicUrl!.isNotEmpty
                              ? NetworkImage(_profilePicUrl!)
                              : null,
                          child: _profilePicUrl == null || _profilePicUrl!.isEmpty
                              ? const Icon(Icons.person, color: Colors.white, size: 60)
                              : null,
                        ),
                        if (_isEditing)
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: CircleAvatar(
                              radius: 16,
                              backgroundColor: Colors.white,
                              child: Icon(Icons.camera_alt, size: 18, color: Colors.grey[800]),
                            ),
                          ),
                        if (_isUploadingPic)
                          const Positioned(
                            child: CircularProgressIndicator(color: Colors.white),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(_userName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  Text(_userEmail, style: const TextStyle(color: Colors.grey)),
                  const SizedBox(height: 30),
                  Card(
                    elevation: 3,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          _buildProfileItem(
                            icon: Icons.bloodtype_rounded,
                            label: "Golongan Darah",
                            child: _isEditing
                                ? DropdownButton<String>(
                                    value: _selectedBloodType,
                                    isExpanded: true,
                                    hint: const Text("Pilih Golongan Darah"),
                                    items: _bloodTypes.map((type) {
                                      return DropdownMenuItem(value: type, child: Text(type));
                                    }).toList(),
                                    onChanged: (val) => setState(() => _selectedBloodType = val),
                                  )
                                : Text(_selectedBloodType ?? "-", style: const TextStyle(fontWeight: FontWeight.bold)),
                          ),
                          const Divider(),
                          _buildProfileItem(
                            icon: Icons.phone_rounded,
                            label: "Nomor Telepon",
                            child: _isEditing
                                ? TextField(
                                    controller: _phoneController,
                                    keyboardType: TextInputType.phone,
                                    decoration: const InputDecoration(hintText: "Masukkan nomor telepon"),
                                  )
                                : Text(_phoneController.text.isEmpty ? "-" : _phoneController.text),
                          ),
                          const Divider(),
                          _buildProfileItem(
                            icon: Icons.location_on_rounded,
                            label: "Alamat",
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                if (_isEditing) ...[
                                  TextField(
                                    controller: _addressController,
                                    maxLines: 2,
                                    decoration: const InputDecoration(hintText: "Masukkan alamat"),
                                  ),
                                  TextButton.icon(
                                    onPressed: _isLoading ? null : _getCurrentLocation,
                                    icon: _isLoading 
                                      ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                                      : const Icon(Icons.my_location, size: 14),
                                    label: const Text("Gunakan lokasi saya sekarang", style: TextStyle(fontSize: 12)),
                                  ),
                                ] else
                                  Text(_addressController.text.isEmpty ? "-" : _addressController.text, textAlign: TextAlign.end),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                    const SizedBox(height: 20),
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      color: Colors.white,
                      child: ListTile(
                        leading: Icon(
                          Icons.assignment_turned_in,
                          color: _kuesionerStatus == 'Lolos'
                              ? Colors.green
                              : (_kuesionerStatus == 'Menunggu Konfirmasi PMI'
                                  ? Colors.orange
                                  : (_kuesionerStatus == 'Tunda'
                                      ? Colors.orange
                                      : Colors.red)),
                        ),
                        title: const Text("Kuesioner Kelayakan",
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(_kuesionerStatus != null
                            ? "Status: $_kuesionerStatus"
                            : "Kuesioner belum diisi"),
                        trailing: _canFillKuesioner
                            ? ElevatedButton(
                                onPressed: () async {
                                  final result = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (context) =>
                                            const KuesionerPage()),
                                  );
                                  if (result != null &&
                                      result is Map<String, dynamic>) {
                                    final user = _auth.currentUser;
                                    if (user != null) {
                                      String finalStatus = result['status'];
                                      // Jika hasil kuesioner Tunda, maka ubah label agar Admin Konfirmasi
                                      if (finalStatus == 'Tunda') {
                                        finalStatus = 'Menunggu Konfirmasi PMI';
                                      }

                                      await _firestore
                                          .collection('users')
                                          .doc(user.uid)
                                          .update({
                                        'kuesioner_status': finalStatus,
                                        'kuesioner_lolos': result['lolosCount'],
                                        'kuesioner_tunda': result['tundaCount'],
                                        'kuesioner_tolak': result['tolakCount'],
                                        'detail_kuesioner': result['jawaban'],
                                        'kuesioner_updated_at':
                                            FieldValue.serverTimestamp(),
                                      });
                                      _fetchUserData(); // Refresh
                                    }
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blueGrey,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                ),
                                child: const Text("Isi Kuesioner"),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                    const SizedBox(height: 32),
                    if (_isEditing)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isSaving ? null : _saveData,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: _isSaving 
                            ? const CircularProgressIndicator(color: Colors.white)
                            : const Text("Simpan Perubahan"),
                        ),
                      )
                    else
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _logout,
                          icon: const Icon(Icons.logout),
                          label: const Text("Logout"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFD32F2F),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                ],
              ),
            ),
    );
  }

  Widget _buildProfileItem({required IconData icon, required String label, required Widget child}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: _isEditing && label == "Alamat" ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.red),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(color: Colors.black54)),
          const SizedBox(width: 12),
          Expanded(child: Align(alignment: Alignment.centerRight, child: child)),
        ],
      ),
    );
  }
}