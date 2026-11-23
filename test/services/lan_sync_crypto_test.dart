import 'dart:convert';
import 'dart:typed_data';

import 'package:countdown_todo/services/lan_sync_crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';

void main() {
  group('LanSyncCrypto', () {
    test('ECDH key exchange derives identical 32-byte shared keys', () {
      final alice = LanSyncCrypto.generateEphemeralKeyPair();
      final bob = LanSyncCrypto.generateEphemeralKeyPair();
      final eve = LanSyncCrypto.generateEphemeralKeyPair();

      final aliceShared = LanSyncCrypto.deriveSharedKey(
        alice.privateKey,
        bob.publicKeyBase64,
      );
      final bobShared = LanSyncCrypto.deriveSharedKey(
        bob.privateKey,
        alice.publicKeyBase64,
      );
      final eveShared = LanSyncCrypto.deriveSharedKey(
        eve.privateKey,
        alice.publicKeyBase64,
      );

      expect(aliceShared.length, 32);
      expect(aliceShared, orderedEquals(bobShared));
      expect(eveShared, isNot(orderedEquals(aliceShared)));
    });

    test(
      'AES-256-GCM string round-trip uses fresh nonce and detects tampering',
      () {
        final alice = LanSyncCrypto.generateEphemeralKeyPair();
        final bob = LanSyncCrypto.generateEphemeralKeyPair();
        final key = LanSyncCrypto.deriveSharedKey(
          alice.privateKey,
          bob.publicKeyBase64,
        );

        const plaintext = '{"todos":[{"id":1,"title":"测试待办"}]}';
        final cipher1 = LanSyncCrypto.encryptString(key, plaintext);
        final cipher2 = LanSyncCrypto.encryptString(key, plaintext);

        expect(cipher1, isNot(equals(cipher2)));
        expect(LanSyncCrypto.decryptString(key, cipher1), plaintext);
        expect(LanSyncCrypto.decryptString(key, cipher2), plaintext);

        final bytes = LanSyncCrypto.encryptBytes(
          key,
          Uint8List.fromList(plaintext.codeUnits),
        );
        bytes[bytes.length - 1] ^= 0x01;
        expect(
          () => LanSyncCrypto.decryptBytes(key, bytes),
          throwsA(isA<InvalidCipherTextException>()),
        );
      },
    );

    test('file frame encryption binds chunk index via AAD', () {
      final alice = LanSyncCrypto.generateEphemeralKeyPair();
      final bob = LanSyncCrypto.generateEphemeralKeyPair();
      final key = LanSyncCrypto.deriveSharedKey(
        alice.privateKey,
        bob.publicKeyBase64,
      );

      final chunk = Uint8List.fromList(
        List<int>.generate(1024, (i) => i % 251),
      );
      final frame = LanSyncCrypto.encodeFileFrame(key, 0, chunk);
      final frameLen = ByteData.sublistView(frame, 0, 4).getUint32(0);
      final payload = Uint8List.sublistView(frame, 4, 4 + frameLen);

      expect(
        LanSyncCrypto.decodeFileFramePayload(key, 0, payload),
        orderedEquals(chunk),
      );
      expect(
        () => LanSyncCrypto.decodeFileFramePayload(key, 1, payload),
        throwsA(isA<InvalidCipherTextException>()),
      );
    });

    test(
      'async crypto handles small payloads below offload threshold',
      () async {
        final alice = LanSyncCrypto.generateEphemeralKeyPair();
        final bob = LanSyncCrypto.generateEphemeralKeyPair();
        final key = LanSyncCrypto.deriveSharedKey(
          alice.privateKey,
          bob.publicKeyBase64,
        );

        const plaintext = '{"ack":true}';
        final cipher = await LanSyncCrypto.encryptStringAsync(key, plaintext);
        expect(await LanSyncCrypto.decryptStringAsync(key, cipher), plaintext);

        final raw = Uint8List.fromList(utf8.encode(plaintext));
        final sealed = await LanSyncCrypto.encryptBytesAsync(key, raw);
        expect(
          await LanSyncCrypto.decryptBytesAsync(key, sealed),
          orderedEquals(raw),
        );
      },
    );

    test('async isolate offload handles large JSON payloads and sublistView file frames', () async {
      final alice = LanSyncCrypto.generateEphemeralKeyPair();
      final bob = LanSyncCrypto.generateEphemeralKeyPair();
      final key = LanSyncCrypto.deriveSharedKey(
        alice.privateKey,
        bob.publicKeyBase64,
      );

      final largeString = List.filled(70 * 1024, 'A').join();
      final cipher = await LanSyncCrypto.encryptStringAsync(key, largeString);
      expect(await LanSyncCrypto.decryptStringAsync(key, cipher), largeString);
      expect(LanSyncCrypto.decryptString(key, cipher), largeString);

      // Create a non-zero offset sublistView slice of a 256 KiB chunk to
      // verify compact copy handling across isolate boundaries.
      const chunkSize = LanSyncCrypto.maxFileChunkSize;
      final backing = Uint8List.fromList(
        List<int>.generate(chunkSize + 64, (i) => i % 251),
      );
      final chunkSlice = Uint8List.sublistView(backing, 32, 32 + chunkSize);

      final frame = await LanSyncCrypto.encodeFileFrameAsync(
        key,
        7,
        chunkSlice,
      );
      final frameLen = ByteData.sublistView(frame, 0, 4).getUint32(0);
      final payloadView = Uint8List.sublistView(frame, 4, 4 + frameLen);

      final decoded = await LanSyncCrypto.decodeFileFramePayloadAsync(
        key,
        7,
        payloadView,
      );
      expect(decoded, orderedEquals(chunkSlice));

      await expectLater(
        LanSyncCrypto.decodeFileFramePayloadAsync(key, 8, payloadView),
        throwsA(isA<InvalidCipherTextException>()),
      );
    });
  });
}
