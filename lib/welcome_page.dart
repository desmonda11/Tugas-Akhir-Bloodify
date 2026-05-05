import 'package:flutter/material.dart';
import 'login_page.dart';
import 'daftar_page.dart'; // Pastikan nama file ini sesuai

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFD32F2F), // Merah background
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              
              // LOGO TENGAH (Hati dengan Tetesan Air)
              const Stack(
                alignment: Alignment.center,
                children: [
                  // Ikon Hati (Outline Putih)
                  Icon(
                    Icons.favorite_border_rounded, 
                    size: 120, 
                    color: Colors.white
                  ),
                  // Ikon Tetesan Air (Isi Putih) di tengah
                  Positioned(
                    top: 35, 
                    child: Icon(
                      Icons.water_drop, 
                      size: 50, 
                      color: Colors.white
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              
              const Text(
                "Bloodify",
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "Donate Blood, Save Lives",
                style: TextStyle(fontSize: 16, color: Colors.white70),
              ),

              const Spacer(),

              // TOMBOL LOGIN (PUTIH)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context, 
                      MaterialPageRoute(builder: (context) => const LoginPage())
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFFD32F2F),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  ),
                  child: const Text("Login", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
              
              const SizedBox(height: 16),

              // TOMBOL DAFTAR (MERAH GELAP)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    // Navigasi ke DaftarPage
                    Navigator.push(
                      context, 
                      MaterialPageRoute(builder: (context) => const DaftarPage())
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFB71C1C), // Merah lebih gelap
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  ),
                  child: const Text("Daftar", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),

              const SizedBox(height: 50),
            ],
          ),
        ),
      ),
    );
  }
}
