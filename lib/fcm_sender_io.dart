import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:googleapis_auth/auth_io.dart' as auth;
import 'package:flutter/foundation.dart';

Future<bool> sendFcmBroadcast({
  required String projectId,
  required Map<String, dynamic> serviceAccountJson,
  required String title,
  required String body,
  Map<String, String>? data,
}) async {
  try {
    final credentials = auth.ServiceAccountCredentials.fromJson(serviceAccountJson);
    final scopes = ["https://www.googleapis.com/auth/firebase.messaging"];
    final client = await auth.clientViaServiceAccount(credentials, scopes);
    final String token = client.credentials.accessToken.data;
    client.close();

    final String url = "https://fcm.googleapis.com/v1/projects/$projectId/messages:send";

    final response = await http.post(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
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

    if (response.statusCode == 200) {
      debugPrint("FcmService: Broadcast berhasil dikirim ke topik 'blood_requests'");
      return true;
    } else {
      debugPrint("FcmService: Gagal kirim broadcast: ${response.body}");
      return false;
    }
  } catch (e) {
    debugPrint("FcmService: Error mengirim broadcast: $e");
    return false;
  }
}
