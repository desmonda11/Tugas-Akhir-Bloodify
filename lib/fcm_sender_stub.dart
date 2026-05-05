Future<bool> sendFcmBroadcast({
  required String projectId,
  required Map<String, dynamic> serviceAccountJson,
  required String title,
  required String body,
  Map<String, String>? data,
}) async {
  // Return false on stub/web as it's not supported via Service Account
  return false;
}
