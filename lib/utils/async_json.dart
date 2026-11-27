import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Payloads at or above 16 KB are decoded in a background isolate so
/// background sync and history loads do not stall the UI thread.
const int kAsyncJsonOffloadThresholdBytes = 16 * 1024;
const int kAsyncJsonEncodeOffloadMinItems = 64;

dynamic _decodeJsonTopLevel(String source) => jsonDecode(source);
String _encodeJsonTopLevel(Object? value) => jsonEncode(value);

Future<dynamic> decodeJsonOffload(String source) async {
  if (kIsWeb || source.length < kAsyncJsonOffloadThresholdBytes) {
    return jsonDecode(source);
  }
  return compute(_decodeJsonTopLevel, source);
}

Future<String> encodeJsonOffload(
  Object? value, {
  int? estimatedItemCount,
}) async {
  if (kIsWeb ||
      estimatedItemCount == null ||
      estimatedItemCount < kAsyncJsonEncodeOffloadMinItems) {
    return jsonEncode(value);
  }
  return compute(_encodeJsonTopLevel, value);
}
