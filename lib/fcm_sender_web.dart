import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

Future<bool> sendFcmBroadcast({
  required String projectId,
  required Map<String, dynamic> serviceAccountJson,
  required String title,
  required String body,
  Map<String, String>? data,
}) async {
  try {
    // 1. Buat JWT untuk OAuth2 token exchange
    final now = DateTime.now().toUtc();
    final expiry = now.add(const Duration(hours: 1));

    final jwt = JWT(
      {
        'iss': serviceAccountJson['client_email'],
        'sub': serviceAccountJson['client_email'],
        'scope': 'https://www.googleapis.com/auth/firebase.messaging',
        'aud': 'https://oauth2.googleapis.com/token',
        'iat': now.millisecondsSinceEpoch ~/ 1000,
        'exp': expiry.millisecondsSinceEpoch ~/ 1000,
      },
    );

    // 2. Sign JWT dengan RSA private key dari service account
    final privateKeyStr = serviceAccountJson['private_key'] as String;
    final signedToken = jwt.sign(
      RSAPrivateKey(privateKeyStr),
      algorithm: JWTAlgorithm.RS256,
    );

    // 3. Tukar JWT ke Google OAuth2 Access Token
    final tokenResponse = await http.post(
      Uri.parse('https://oauth2.googleapis.com/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        'assertion': signedToken,
      },
    );

    if (tokenResponse.statusCode != 200) {
      debugPrint(
          'FcmServiceWeb: Gagal mendapatkan access token: ${tokenResponse.body}');
      return false;
    }

    final tokenData = jsonDecode(tokenResponse.body);
    final accessToken = tokenData['access_token'] as String?;

    if (accessToken == null) {
      debugPrint('FcmServiceWeb: access_token null dari response Google');
      return false;
    }

    // 4. Kirim FCM Broadcast ke Topic
    final fcmUrl =
        'https://fcm.googleapis.com/v1/projects/$projectId/messages:send';

    final fcmResponse = await http.post(
      Uri.parse(fcmUrl),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode({
        'message': {
          'topic': 'blood_requests',
          'notification': {
            'title': title,
            'body': body,
          },
          'android': {
            'notification': {
              'color': '#FF0000',
              'click_action': 'FLUTTER_NOTIFICATION_CLICK',
              'channel_id': 'blood_requests_channel',
            },
          },
          if (data != null) 'data': data,
        },
      }),
    );

    if (fcmResponse.statusCode == 200) {
      debugPrint(
          "FcmServiceWeb: Broadcast berhasil dikirim ke topik 'blood_requests'");
      return true;
    } else {
      debugPrint('FcmServiceWeb: Gagal kirim broadcast: ${fcmResponse.body}');
      return false;
    }
  } catch (e) {
    debugPrint('FcmServiceWeb: Error saat mengirim broadcast: $e');
    return false;
  }
}
