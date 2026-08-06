import 'dart:io';
import 'dart:typed_data';

import 'package:countdown_todo/services/android_delta_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('applies copy and data operations and verifies target hash', () async {
    final directory = await Directory.systemTemp.createTemp('cdt_delta_test');
    addTearDown(() => directory.delete(recursive: true));

    final baseBytes = Uint8List.fromList(
      List<int>.generate(128, (index) => index),
    );
    final targetBytes = Uint8List.fromList(<int>[
      ...baseBytes.sublist(0, 64),
      201,
      202,
      203,
      204,
      ...baseBytes.sublist(68),
    ]);
    final base = File('${directory.path}/base.apk')
      ..writeAsBytesSync(baseBytes);
    final patch = File('${directory.path}/update.patch')
      ..writeAsBytesSync(_buildPatch(baseBytes.length, targetBytes));
    final output = File('${directory.path}/target.apk');

    await AndroidDeltaService.applyPatch(
      baseApk: base,
      patchFile: patch,
      outputApk: output,
    );

    expect(output.readAsBytesSync(), targetBytes);
  });

  test('rejects a patch with the wrong base size', () async {
    final directory = await Directory.systemTemp.createTemp('cdt_delta_test');
    addTearDown(() => directory.delete(recursive: true));

    final base = File('${directory.path}/base.apk')..writeAsBytesSync([1, 2]);
    final patch = File('${directory.path}/update.patch')
      ..writeAsBytesSync(_buildPatch(3, Uint8List.fromList([4])));
    final output = File('${directory.path}/target.apk');

    expect(
      () => AndroidDeltaService.applyPatch(
        baseApk: base,
        patchFile: patch,
        outputApk: output,
      ),
      throwsA(isA<FormatException>()),
    );
  });
}

List<int> _buildPatch(int baseSize, Uint8List target) {
  final bytes = BytesBuilder();
  bytes.add('CDTDELTA'.codeUnits);
  _addUint32(bytes, 1);
  _addUint64(bytes, baseSize);
  _addUint64(bytes, target.length);
  _addUint32(bytes, 64 * 1024);
  _addUint32(bytes, 3);

  bytes.addByte(0);
  _addUint64(bytes, 0);
  _addUint32(bytes, 64);

  bytes.addByte(1);
  _addUint64(bytes, 0);
  _addUint32(bytes, 4);
  bytes.add(<int>[201, 202, 203, 204]);

  bytes.addByte(0);
  _addUint64(bytes, 68);
  _addUint32(bytes, 60);

  return bytes.takeBytes();
}

void _addUint32(BytesBuilder builder, int value) {
  builder.add(
      Uint8List(4)..buffer.asByteData().setUint32(0, value, Endian.little));
}

void _addUint64(BytesBuilder builder, int value) {
  builder.add(
      Uint8List(8)..buffer.asByteData().setUint64(0, value, Endian.little));
}
