import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:pointycastle/export.dart';

Uint8List _encryptBytesIsolate(
  ({Uint8List key, Uint8List plaintext, Uint8List? aad}) args,
) => LanSyncCrypto.encryptBytes(args.key, args.plaintext, aad: args.aad);

Uint8List _decryptBytesIsolate(
  ({Uint8List key, Uint8List sealed, Uint8List? aad}) args,
) => LanSyncCrypto.decryptBytes(args.key, args.sealed, aad: args.aad);

String _encryptStringIsolate(({Uint8List key, String plaintext}) args) =>
    LanSyncCrypto.encryptString(args.key, args.plaintext);

String _decryptStringIsolate(({Uint8List key, String sealedBase64}) args) =>
    LanSyncCrypto.decryptString(args.key, args.sealedBase64);

Uint8List _encodeFileFrameIsolate(
  ({Uint8List key, int chunkIndex, Uint8List plainChunk}) args,
) => LanSyncCrypto.encodeFileFrame(args.key, args.chunkIndex, args.plainChunk);

Uint8List _decodeFileFramePayloadIsolate(
  ({Uint8List key, int chunkIndex, Uint8List sealedPayload}) args,
) => LanSyncCrypto.decodeFileFramePayload(
  args.key,
  args.chunkIndex,
  args.sealedPayload,
);

/// Ephemeral ECDH (secp256r1) + AES-256-GCM helpers for LAN sync.
class LanSyncCrypto {
  LanSyncCrypto._();

  static const int protocolVersion = 2;
  static const int nonceLength = 12;
  static const int macBitLength = 128;
  static const int maxFileChunkSize = 256 * 1024; // 256 KiB plaintext per frame
  static const int isolateOffloadThresholdBytes = 16 * 1024; // 16 KiB
  static const String _kdfContext = 'cdt-lan-sync-v2-aes256gcm';

  static final ECDomainParameters _domainParams = ECDomainParameters(
    'secp256r1',
  );

  static FortunaRandom _createSecureRandom() {
    final rng = Random.secure();
    final seed = Uint8List(32);
    for (var i = 0; i < seed.length; i++) {
      seed[i] = rng.nextInt(256);
    }
    return FortunaRandom()..seed(KeyParameter(seed));
  }

  /// Generates an ephemeral P-256 key pair and returns `(privateKey, publicKeyBase64)`.
  static ({ECPrivateKey privateKey, String publicKeyBase64})
  generateEphemeralKeyPair() {
    final generator = ECKeyGenerator()
      ..init(
        ParametersWithRandom(
          ECKeyGeneratorParameters(_domainParams),
          _createSecureRandom(),
        ),
      );
    final pair = generator.generateKeyPair();
    final privateKey = pair.privateKey as ECPrivateKey;
    final publicKey = pair.publicKey as ECPublicKey;
    final encodedPub = publicKey.Q!.getEncoded(false);
    return (privateKey: privateKey, publicKeyBase64: base64Encode(encodedPub));
  }

  /// Derives a 32-byte AES-256 key from [privateKey] and [peerPublicKeyBase64].
  static Uint8List deriveSharedKey(
    ECPrivateKey privateKey,
    String peerPublicKeyBase64,
  ) {
    final peerBytes = base64Decode(peerPublicKeyBase64);
    final peerPoint = _domainParams.curve.decodePoint(peerBytes);
    if (peerPoint == null || peerPoint.isInfinity) {
      throw const FormatException('Invalid ECDH peer public key');
    }
    final peerPublicKey = ECPublicKey(peerPoint, _domainParams);
    final agreement = ECDHBasicAgreement()..init(privateKey);
    final sharedBigInt = agreement.calculateAgreement(peerPublicKey);
    final sharedBytes = _bigIntToFixedBytes(sharedBigInt, 32);

    final digest = sha256.convert(<int>[
      ...utf8.encode(_kdfContext),
      ...sharedBytes,
    ]);
    return Uint8List.fromList(digest.bytes);
  }

  /// Encrypts [plaintext] using AES-256-GCM with a fresh random 12-byte nonce.
  ///
  /// Output format: `[12-byte nonce][ciphertext + 16-byte GCM tag]`.
  static Uint8List encryptBytes(
    Uint8List key,
    Uint8List plaintext, {
    Uint8List? aad,
  }) {
    final rng = Random.secure();
    final nonce = Uint8List(nonceLength);
    for (var i = 0; i < nonce.length; i++) {
      nonce[i] = rng.nextInt(256);
    }

    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(
          KeyParameter(key),
          macBitLength,
          nonce,
          aad ?? Uint8List(0),
        ),
      );

    final encrypted = cipher.process(plaintext);
    final result = Uint8List(nonceLength + encrypted.length);
    result.setRange(0, nonceLength, nonce);
    result.setRange(nonceLength, result.length, encrypted);
    return result;
  }

  /// Decrypts and authenticates [sealed] produced by [encryptBytes].
  static Uint8List decryptBytes(
    Uint8List key,
    Uint8List sealed, {
    Uint8List? aad,
  }) {
    if (sealed.length < nonceLength + (macBitLength ~/ 8)) {
      throw const FormatException('Encrypted payload too short');
    }
    final nonce = Uint8List.sublistView(sealed, 0, nonceLength);
    final ciphertext = Uint8List.sublistView(sealed, nonceLength);

    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        false,
        AEADParameters(
          KeyParameter(key),
          macBitLength,
          nonce,
          aad ?? Uint8List(0),
        ),
      );

    return cipher.process(ciphertext);
  }

  static String encryptString(Uint8List key, String plaintext) {
    final sealed = encryptBytes(
      key,
      Uint8List.fromList(utf8.encode(plaintext)),
    );
    return base64Encode(sealed);
  }

  static String decryptString(Uint8List key, String sealedBase64) {
    final sealed = base64Decode(sealedBase64);
    final plainBytes = decryptBytes(key, sealed);
    return utf8.decode(plainBytes);
  }

  /// Encodes an encrypted file chunk as `[4-byte uint32 length][sealed chunk]`.
  static Uint8List encodeFileFrame(
    Uint8List key,
    int chunkIndex,
    Uint8List plainChunk,
  ) {
    final aad = _chunkIndexAad(chunkIndex);
    final sealed = encryptBytes(key, plainChunk, aad: aad);
    final frame = Uint8List(4 + sealed.length);
    ByteData.sublistView(frame, 0, 4).setUint32(0, sealed.length, Endian.big);
    frame.setRange(4, frame.length, sealed);
    return frame;
  }

  /// Decrypts a single file frame payload using [chunkIndex] as AAD.
  static Uint8List decodeFileFramePayload(
    Uint8List key,
    int chunkIndex,
    Uint8List sealedPayload,
  ) {
    return decryptBytes(key, sealedPayload, aad: _chunkIndexAad(chunkIndex));
  }

  /// Encrypts [plaintext] using AES-256-GCM, offloading payloads at or above
  /// [isolateOffloadThresholdBytes] to a background isolate.
  static Future<Uint8List> encryptBytesAsync(
    Uint8List key,
    Uint8List plaintext, {
    Uint8List? aad,
  }) {
    if (plaintext.length < isolateOffloadThresholdBytes) {
      return Future<Uint8List>.value(encryptBytes(key, plaintext, aad: aad));
    }
    return compute(_encryptBytesIsolate, (
      key: _compactBytes(key),
      plaintext: _compactBytes(plaintext),
      aad: aad == null ? null : _compactBytes(aad),
    ));
  }

  /// Decrypts and authenticates [sealed], offloading payloads at or above
  /// [isolateOffloadThresholdBytes] to a background isolate.
  static Future<Uint8List> decryptBytesAsync(
    Uint8List key,
    Uint8List sealed, {
    Uint8List? aad,
  }) {
    if (sealed.length < isolateOffloadThresholdBytes) {
      return Future<Uint8List>.value(decryptBytes(key, sealed, aad: aad));
    }
    return compute(_decryptBytesIsolate, (
      key: _compactBytes(key),
      sealed: _compactBytes(sealed),
      aad: aad == null ? null : _compactBytes(aad),
    ));
  }

  /// Encrypts [plaintext], offloading payloads at or above
  /// [isolateOffloadThresholdBytes] to a background isolate.
  static Future<String> encryptStringAsync(Uint8List key, String plaintext) {
    if (plaintext.length < isolateOffloadThresholdBytes) {
      return Future<String>.value(encryptString(key, plaintext));
    }
    return compute(_encryptStringIsolate, (
      key: _compactBytes(key),
      plaintext: plaintext,
    ));
  }

  /// Decrypts [sealedBase64], offloading payloads at or above
  /// [isolateOffloadThresholdBytes] to a background isolate.
  static Future<String> decryptStringAsync(Uint8List key, String sealedBase64) {
    if (sealedBase64.length < isolateOffloadThresholdBytes) {
      return Future<String>.value(decryptString(key, sealedBase64));
    }
    return compute(_decryptStringIsolate, (
      key: _compactBytes(key),
      sealedBase64: sealedBase64,
    ));
  }

  /// Encodes an encrypted file frame, offloading chunks at or above
  /// [isolateOffloadThresholdBytes] to a background isolate.
  static Future<Uint8List> encodeFileFrameAsync(
    Uint8List key,
    int chunkIndex,
    Uint8List plainChunk,
  ) {
    if (plainChunk.length < isolateOffloadThresholdBytes) {
      return Future<Uint8List>.value(
        encodeFileFrame(key, chunkIndex, plainChunk),
      );
    }
    return compute(_encodeFileFrameIsolate, (
      key: _compactBytes(key),
      chunkIndex: chunkIndex,
      plainChunk: _compactBytes(plainChunk),
    ));
  }

  /// Decrypts a single file frame payload, offloading frames at or above
  /// [isolateOffloadThresholdBytes] to a background isolate.
  static Future<Uint8List> decodeFileFramePayloadAsync(
    Uint8List key,
    int chunkIndex,
    Uint8List sealedPayload,
  ) {
    if (sealedPayload.length < isolateOffloadThresholdBytes) {
      return Future<Uint8List>.value(
        decodeFileFramePayload(key, chunkIndex, sealedPayload),
      );
    }
    return compute(_decodeFileFramePayloadIsolate, (
      key: _compactBytes(key),
      chunkIndex: chunkIndex,
      sealedPayload: _compactBytes(sealedPayload),
    ));
  }

  static Uint8List _compactBytes(Uint8List bytes) {
    if (bytes.offsetInBytes == 0 &&
        bytes.lengthInBytes == bytes.buffer.lengthInBytes) {
      return bytes;
    }
    return Uint8List.fromList(bytes);
  }

  static Uint8List _chunkIndexAad(int chunkIndex) {
    final aad = Uint8List(8);
    ByteData.sublistView(aad).setUint64(0, chunkIndex, Endian.big);
    return aad;
  }

  static Uint8List _bigIntToFixedBytes(BigInt value, int length) {
    final out = Uint8List(length);
    var v = value;
    for (var i = length - 1; i >= 0; i--) {
      out[i] = (v & BigInt.from(0xff)).toInt();
      v >>= 8;
    }
    return out;
  }
}
