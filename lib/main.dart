import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/date_symbol_data_local.dart';

import 'firebase_options.dart';
import 'welcome_page.dart';
import 'dashboard_page.dart';
import 'permintaan_page.dart';
import 'chat_list_page.dart';
import 'chat_page.dart';
import 'profil_page.dart';
import 'permintaan_aktif_page.dart';
import 'admin_page.dart';
import 'riwayat_donor_page.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  debugPrint("Handling a background message: ${message.messageId}");
}

const AndroidNotificationChannel channel = AndroidNotificationChannel(
  'blood_requests_channel',
  'Blood Requests Notifications',
  description: 'This channel is used for blood request broadcasts.',
  importance: Importance.high,
);

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await initializeDateFormatting('id_ID', null);

  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    await FirebaseMessaging.instance.subscribeToTopic("blood_requests");

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _handleNotificationClick(message);
    });

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      RemoteNotification? notification = message.notification;
      AndroidNotification? android = message.notification?.android;

      if (notification != null && android != null) {
        flutterLocalNotificationsPlugin.show(
          notification.hashCode,
          notification.title,
          notification.body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              channel.id,
              channel.name,
              channelDescription: channel.description,
              icon: android.smallIcon,
              importance: channel.importance,
              priority: Priority.high,
            ),
          ),
        );
      }
    });

    RemoteMessage? initialMessage =
        await FirebaseMessaging.instance.getInitialMessage();

    if (initialMessage != null) {
      Future.delayed(const Duration(seconds: 1), () {
        _handleNotificationClick(initialMessage);
      });
    }
  }

  runApp(const MyApp());
}

void _handleNotificationClick(RemoteMessage message) {
  navigatorKey.currentState?.push(
    MaterialPageRoute(
      builder: (context) => const PermintaanAktifPage(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  static const String adminEmail = 'admin@bloodify.com';

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, authSnapshot) {
          if (authSnapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          if (!authSnapshot.hasData) {
            return const WelcomePage();
          }

          final user = authSnapshot.data!;

          if (user.email == adminEmail) {
            return const AdminPage();
          }

          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .snapshots(),
            builder: (context, userSnapshot) {
              if (userSnapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }

              final userData = userSnapshot.data?.data();
              final bool isBanned = userData?['isBanned'] == true;
              final String role = userData?['role']?.toString() ?? 'user';

              if (role == 'admin') {
                return const AdminPage();
              }

              if (isBanned) {
                return const BannedPage();
              }

              return const MainPage();
            },
          );
        },
      ),
    );
  }
}

class BannedPage extends StatelessWidget {
  const BannedPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Akun Diblokir'),
        backgroundColor: Colors.red.shade800,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(
              Icons.block,
              size: 72,
              color: Colors.red,
            ),
            const SizedBox(height: 24),
            const Text(
              'Akun Anda telah diblokir oleh admin.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Silakan hubungi admin jika Anda ingin mengajukan banding atau mendapatkan informasi lebih lanjut.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade800,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                await FirebaseAuth.instance.signOut();

                if (!context.mounted) return;

                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
                    builder: (_) => const WelcomePage(),
                  ),
                  (route) => false,
                );
              },
              child: const Text('Keluar'),
            ),
          ],
        ),
      ),
    );
  }
}

class MainPage extends StatefulWidget {
  final int initialIndex;
  final String? forcePushChatId;
  final String? forcePushChatTitle;

  const MainPage({
    super.key,
    this.initialIndex = 0,
    this.forcePushChatId,
    this.forcePushChatTitle,
  });

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  late int _currentIndex;

  final List<Widget> _pages = [
    const DashboardPage(),
    const PermintaanPage(),
    const ChatListPage(),
    const RiwayatDonorPage(),
    const ProfilPage(),
  ];

  @override
  void initState() {
    super.initState();

    if (widget.initialIndex < 0 || widget.initialIndex >= _pages.length) {
      _currentIndex = 0;
    } else {
      _currentIndex = widget.initialIndex;
    }

    if (widget.forcePushChatId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final currentUser = FirebaseAuth.instance.currentUser;

        if (currentUser != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ChatPage(
                chatId: widget.forcePushChatId!,
                currentUserId: currentUser.uid,
                chatTitle: widget.forcePushChatTitle,
              ),
            ),
          );
        }
      });
    }
  }

  void _changePage(int index) {
    if (index < 0 || index >= _pages.length) return;

    setState(() {
      _currentIndex = index;
    });
  }

  Widget _buildChatIcon() {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      return const Icon(Icons.chat);
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('chats')
          .where('participants', arrayContains: currentUser.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Icon(Icons.chat);
        }

        int total = 0;

        for (var doc in snapshot.data!.docs) {
          final data = doc.data();

          if (data['unreadCount'] != null &&
              data['unreadCount'][currentUser.uid] != null) {
            total += data['unreadCount'][currentUser.uid] as int;
          }
        }

        if (total > 0) {
          return Badge(
            label: Text(total.toString()),
            child: const Icon(Icons.chat),
          );
        }

        return const Icon(Icons.chat);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _changePage,
        selectedItemColor: Colors.red,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: "Beranda",
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.bloodtype),
            label: "Permintaan",
          ),
          BottomNavigationBarItem(
            icon: _buildChatIcon(),
            label: "Chat",
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.history),
            label: "Riwayat",
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: "Profil",
          ),
        ],
      ),
    );
  }
}