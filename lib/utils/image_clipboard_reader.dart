import 'package:flutter/services.dart';

import 'image_input_data.dart';

const MethodChannel _clipboardImageChannel = MethodChannel(
  'countdown_todo/clipboard_image',
);

Future<ImageInputData?> readClipboardImage() async {
  try {
    final payload = await _clipboardImageChannel.invokeMapMethod<String, dynamic>(
      'readImage',
    );
    if (payload == null) return null;

    final rawBytes = payload['bytes'];
    final bytes = switch (rawBytes) {
      Uint8List value => value,
      List<int> value => Uint8List.fromList(value),
      _ => null,
    };
    final mimeType = payload['mimeType']?.toString() ?? '';
    if (bytes == null || bytes.isEmpty || !mimeType.startsWith('image/')) {
      return null;
    }

    return ImageInputData(
      bytes: bytes,
      mimeType: mimeType,
      displayName: payload['displayName']?.toString() ?? 'clipboard-image.png',
    );
  } on MissingPluginException {
    // Platforms without native image clipboard support can still paste text.
    return null;
  } on PlatformException {
    return null;
  }
}
