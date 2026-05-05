import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'permintaan_aktif_page.dart';
import 'daftar_pendonor_page.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  String _userName = "User";
  String? _profilePicUrl;
  String _locationText = "Mencari Lokasi...";
  bool _isMapLoading = false;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  StreamSubscription<DocumentSnapshot>? _userSubscription;

  final PageController _pageController = PageController();
  int _currentPage = 0;
  Timer? _carouselTimer;

  @override
  void initState() {
    super.initState();
    _listenToUserData();
    _startCarouselTimer();
    _getCurrentLocation();
  }

  @override
  void dispose() {
    _userSubscription?.cancel();
    _carouselTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _startCarouselTimer() {
    _carouselTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (_pageController.hasClients) {
        _pageController.nextPage(
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isMapLoading = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _locationText = "Layanan lokasi nonaktif";
          _isMapLoading = false;
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _locationText = "Izin lokasi ditolak";
            _isMapLoading = false;
          });
          return;
        }
      }

      Position position = await Geolocator.getCurrentPosition();

      // Reverse Geocoding pakai Nominatim (OpenStreetMap) - Gratis & No API Key
      final url = Uri.parse(
          "https://nominatim.openstreetmap.org/reverse?format=json&lat=${position.latitude}&lon=${position.longitude}&zoom=18&addressdetails=1");

      final response =
          await http.get(url, headers: {'User-Agent': 'BloodifyApp/1.0'});

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final displayName = data['display_name'] ?? "Lokasi tidak diketahui";

        // Simpan ke Firestore agar bisa dicari pendonor lain
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          await _firestore.collection('users').doc(user.uid).update({
            'location': displayName,
            'latitude': position.latitude,
            'longitude': position.longitude,
            'lastUpdate': FieldValue.serverTimestamp(),
          });
        }

        if (mounted) {
          setState(() {
            _locationText = displayName;
            _isMapLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint("Error Get Location: $e");
      if (mounted) {
        setState(() {
          _locationText = "Gagal mengambil lokasi";
          _isMapLoading = false;
        });
      }
    }
  }

  void _listenToUserData() {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        _userSubscription = _firestore
            .collection('users')
            .doc(user.uid)
            .snapshots()
            .listen((doc) {
          if (doc.exists && doc.data() != null) {
            final data = doc.data()!;
            final firstName = data['firstName']?.toString() ?? "";
            final lastName = data['lastName']?.toString() ?? "";
            final fullName = "$firstName $lastName".trim();
            final profilePic = data['profilePicture']?.toString();

            if (mounted) {
              setState(() {
                _userName = fullName.isNotEmpty ? fullName : "User";
                _profilePicUrl = profilePic;
              });
            }
          }
        });
      }
    } catch (e) {
      debugPrint("Error listening to user data: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F6),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Halo, $_userName!",
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    _locationSection(),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _eventCarousel(),
              const SizedBox(height: 24),
              StreamBuilder<QuerySnapshot>(
                stream: _firestore
                    .collection('permintaan_darah')
                    .where('status', isEqualTo: 'aktif')
                    .snapshots(),
                builder: (context, snapshot) {
                  final allDocs = snapshot.data?.docs ?? [];
                  final currentUser = FirebaseAuth.instance.currentUser;

                  // Filter agar counter di dashboard sinkron dengan halaman list
                  final count = allDocs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>? ?? {};
                    final List<dynamic> helpers = data['helpers'] ?? [];
                    return !helpers.contains(currentUser?.uid);
                  }).length;

                  return _infoCard(
                    context: context,
                    icon: Icons.bloodtype,
                    title: "Permintaan Aktif",
                    value: count.toString(),
                    color: Colors.red,
                    page: const PermintaanAktifPage(),
                  );
                },
              ),
              // Stream untuk Pendonor Online (Semua User Terdaftar)
              StreamBuilder<QuerySnapshot>(
                stream: _firestore.collection('users').snapshots(),
                builder: (context, snapshot) {
                  final allDocs = snapshot.data?.docs ?? [];
                  // Hitung jumlah user selain admin yang sudah Lolos verifikasi
                  final count = allDocs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>? ?? {};
                    final email = data['email']?.toString().toLowerCase() ?? '';
                    final status = data['kuesioner_status']?.toString() ?? '';
                    
                    return email != 'admin@bloodify.com' && status == 'Lolos';
                  }).length;
                  return _infoCard(
                    context: context,
                    icon: Icons.people,
                    title: "Pendonor Online",
                    value: count.toString(),
                    color: Colors.green,
                    page: const DaftarPendonorPage(),
                  );
                },
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _locationSection() {
    return Row(
      children: [
        const Icon(Icons.location_on, color: Colors.red, size: 18),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            _locationText,
            style: const TextStyle(color: Colors.grey, fontSize: 13),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        TextButton(
          onPressed: _isMapLoading ? null : _getCurrentLocation,
          child: _isMapLoading
              ? const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text("Gunakan Lokasi Sekarang",
                  style: TextStyle(color: Colors.red, fontSize: 12)),
        ),
      ],
    );
  }

  Widget _eventCarousel() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('events')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return SizedBox(
            height: 200,
            child: Center(
              child: Text(
                "Error loading events: ${snapshot.error}",
                style: const TextStyle(fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const SizedBox(
              height: 200, child: Center(child: CircularProgressIndicator()));
        }
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return const SizedBox.shrink();

        return Column(
          children: [
            SizedBox(
              height: 200,
              child: PageView.builder(
                controller: _pageController,
                scrollDirection: Axis.horizontal,
                onPageChanged: (index) {
                  setState(() => _currentPage = index % docs.length);
                },
                itemBuilder: (context, index) {
                  final realIndex = index % docs.length;
                  final data = docs[realIndex].data() as Map<String, dynamic>;
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      image: DecorationImage(
                        image: NetworkImage(data['imageUrl'] ?? ''),
                        fit: BoxFit.cover,
                        colorFilter: ColorFilter.mode(
                            Colors.black.withValues(alpha: 0.3),
                            BlendMode.darken),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            data['title'] ?? 'Event Bloodify',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "${data['date'] ?? ''} • ${data['time'] ?? ''}",
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 13),
                          ),
                          if (data['description'] != null &&
                              data['description'].toString().isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              data['description'],
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 12),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(docs.length, (index) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  height: 8,
                  width: _currentPage == index ? 24 : 8,
                  decoration: BoxDecoration(
                    color: _currentPage == index
                        ? Colors.red
                        : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
          ],
        );
      },
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Icon(Icons.water_drop, color: Colors.red, size: 28),
          const SizedBox(width: 8),
          const Text(
            "Bloodify",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          CircleAvatar(
            radius: 18,
            backgroundColor: Colors.red,
            backgroundImage:
                _profilePicUrl != null && _profilePicUrl!.isNotEmpty
                    ? NetworkImage(_profilePicUrl!)
                    : null,
            child: _profilePicUrl == null || _profilePicUrl!.isEmpty
                ? const Icon(
                    Icons.person,
                    color: Colors.white,
                    size: 20,
                  )
                : null,
          ),
        ],
      ),
    );
  }

  Widget _infoCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String value,
    required Color color,
    required Widget page,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => page,
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: color.withValues(alpha: 0.15),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                value,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
