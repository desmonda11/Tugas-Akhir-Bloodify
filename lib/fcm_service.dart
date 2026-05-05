import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'fcm_sender_stub.dart'
    // ignore: uri_does_not_exist
    if (dart.library.io) 'fcm_sender_io.dart'
    // ignore: uri_does_not_exist
    if (dart.library.html) 'fcm_sender_web.dart';

class FcmService {
  // Data Service Account (FCM V1)
  static final Map<String, dynamic> _serviceAccountJson = {
    "type": "service_account",
    "project_id": "blood-donation-8367a",
    "private_key_id": "27c85cb1c93ef44535d8dd606be4dc25d3a3f885",
    "private_key": """-----BEGIN PRIVATE KEY-----
MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQDsZL6HOTtI0luk
UD7CG8xiNOPZA5Q3oXx6iNbq9Go3YIKP9IrimGSBq2iEt7clXni3s/0i40YdUnRv
RBX3Apnpdr5SxQWO3rST4mlA9+S0Pp2DVVE3oxn19Wa5WjxVIE7ctlYkoWVfNc0C
L8D+btE1itk6SMY1x4cFipzQH8J6a0v8os1qTSw5oiczzJFEJcaLjaEBbHNp9ak6
oY+PlSNoIrVot2OU8X+NzfnNS+M+7gm3cwrm6B1xrDTTBGddDbALztGOE8cxIFIY
2o/4bK2UgYgQREPuD4XJ+Q3BhYgmTYrSLp1yPzEKFbQ3dBdeHlglsTkdiwNXJaQw
AUnXBVspAgMBAAECggEAMf6HdflCYr8MXxaSg0JWShHF+0RAwTgvp4mPrG6nFRGd
4zyUb+JLZUofR2xEOUy+ypkwCMQYtMRWuB5l59DexKuWilI9P+81MQ6B9JnIvl78
uIUfcV0W9TficwJUvqsfyplsZABXPFjYQ+VeE2FT8RctpGA2PTL2yRL84Z5J5tIo
zu7WHMT1h3i04phkHB5JZTKvy/h/tZZvDcVV9I549pzqtqblBDAiYFEWsJyVm6dG
ga02nNhgG5iggcYiNAQ9O0ch3kCpbDabwX79Ic1MLpSTiIf2IVsCUKXluGKB364P
9SdNVfK4Nno7BSss24RiVzKdY4vWD8PHCGNtrh695QKBgQD8ysk8Bqi6+kkc2w48
lUVHoyBjdO8klz6jvk+ZOVctkb/5z9R3Erj84+dXTfNJEK/NxZ4K+cND8+58ei5h
HDKBLCPwFngGwRM0tAI1+QI0Iq5EZR4N59Hfw817jnV3YxabBqDlJn6LSS2ljCrr
n+1rvCtwyRJZuqvjvAoybfRvzQKBgQDvZK+lBV6ly873H3n7qpbT2iSpjef+DnL7
+EGogYTOexEx+IEJ3YeJwKI1JEBOMLhiE7h3om7DWvUkbmD4frasIgTpFDrERJct
5R/kn8r/1dFJMsehyW9J0YuFYEJsi9LxFYRRnuYy5MfydThj67ckw052iW4eZnxj
MvcOz8skzQKBgBtPLP43GfNZJpzfbWJOHfXnQZB9CXjCfhnibWb4MtrRbBPox+M1
OpbXaB6eZTH3g4aPWsuEv/uPVqxL5sbG7Q3XXuqJAt537UM8TyDVjc9kD7+DzQNj
j+DEnmZCtZ34LnEA/lDDH9icRzojMl/SHywMYAUHM9xNtlQb9F4OUuHhAoGBAKtd
FsJ4+oySPR/3HznAnmEeWXoqA7SAIV0vE8kMlcW8oM11huFJ+9jm1PZXcdTG2WYT
mcvBsaoT9UFT5gRbqGXFoGA8Q+j09Ic86bydihHivAK63953NDvSTR53jnTnDmPX
NDW9Gim6TUrJEEmulRYy3HrL29DVKhtUgzfOFSvNAoGAfI14qJpwI1l/H9bjgiFC
NiEkOagCuo3ubItEOJbv2se15gNwSeh03ZznfV7aCbUOYcUe550oeh+3qp4e8BRI
e5W3o2bbIhg9dv2mIKtE5yp1JAi/MQkEVLjBzRtvK6qI42dBoFoU+jc9ywLaYkun
gmQj8/4M1V6FCsp2cJs2su8=
-----END PRIVATE KEY-----
""",
    "client_email":
        "firebase-adminsdk-fbsvc@blood-donation-8367a.iam.gserviceaccount.com",
    "client_id": "117318307241074001021",
    "auth_uri": "https://accounts.google.com/o/oauth2/auth",
    "token_uri": "https://oauth2.googleapis.com/token",
    "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
    "client_x509_cert_url":
        "https://www.googleapis.com/robot/v1/metadata/x509/firebase-adminsdk-fbsvc%40blood-donation-8367a.iam.gserviceaccount.com",
    "universe_domain": "googleapis.com"
  };

  static Future<bool> sendBroadcast({
    required String title,
    required String body,
    Map<String, String>? data,
  }) async {
    return await sendFcmBroadcast(
      projectId: _serviceAccountJson["project_id"],
      serviceAccountJson: _serviceAccountJson,
      title: title,
      body: body,
      data: data,
    );
  }

  static Future<bool> sendTemplatedBroadcast({
    required String requesterName,
    required String bloodType,
    required String componentType,
  }) async {
    try {
      // 1. Ambil Template dari Firestore
      final doc = await FirebaseFirestore.instance
          .collection('settings')
          .doc('notification_template')
          .get();

      String titleTemplate = "🔴 [NAMA] Membutuhkan Darah";
      String bodyTemplate =
          "[NAMA] sedang membutuhkan [KOMPONEN] golongan darah [GOL] untuk membantu kebutuhannya. Yuk, segera lihat permintaannya!";

      if (doc.exists) {
        titleTemplate = doc.data()?['request_title_template'] ?? titleTemplate;
        bodyTemplate = doc.data()?['request_body_template'] ?? bodyTemplate;
      }

      // 2. Ganti Placeholder
      final finalTitle = titleTemplate
          .replaceAll('[NAMA]', requesterName)
          .replaceAll('[GOL]', bloodType)
          .replaceAll('[KOMPONEN]', componentType);
      final finalBody = bodyTemplate
          .replaceAll('[NAMA]', requesterName)
          .replaceAll('[GOL]', bloodType)
          .replaceAll('[KOMPONEN]', componentType);

      // 3. Kirim via FCM
      final success = await sendBroadcast(
        title: finalTitle,
        body: finalBody,
        data: {
          'type': 'blood_request',
          'sender': requesterName,
          'blood_type': bloodType,
          'component_type': componentType,
        },
      );

      if (success) {
        // 4. Simpan ke Firestore untuk riwayat (Jangan biarkan error tulis merusak aliran)
        try {
          await FirebaseFirestore.instance.collection('notifications').add({
            'title': finalTitle,
            'body': finalBody,
            'sentAt': FieldValue.serverTimestamp(),
            'type': 'automated_request',
            'requesterName': requesterName,
            'bloodType': bloodType,
            'componentType': componentType,
          });
        } catch (dbError) {
          debugPrint("FcmService: Gagal mencatat log ke Firestore: $dbError");
        }
      }

      return success;
    } catch (e) {
      debugPrint("FcmService: Error mengirim templated broadcast: $e");
      return false;
    }
  }
}
