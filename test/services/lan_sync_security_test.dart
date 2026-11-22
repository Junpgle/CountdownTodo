import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:countdown_todo/services/lan_sync_crypto.dart';
import 'package:countdown_todo/services/lan_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _AllowLoopbackHttpOverrides extends HttpOverrides {}

Future<({String sessionId, Uint8List key})> _handshake(
  HttpClient client,
  int port,
) async {
  final keys = LanSyncCrypto.generateEphemeralKeyPair();
  final req = await client.postUrl(
    Uri.parse('http://127.0.0.1:$port/handshake'),
  );
  req.headers.contentType = ContentType.json;
  req.write(
    jsonEncode({
      'v': LanSyncCrypto.protocolVersion,
      'clientPublicKey': keys.publicKeyBase64,
    }),
  );
  final resp = await req.close();
  final body = await resp.transform(utf8.decoder).join();
  final decoded = jsonDecode(body) as Map<String, dynamic>;
  return (
    sessionId: decoded['sessionId'].toString(),
    key: LanSyncCrypto.deriveSharedKey(
      keys.privateKey,
      decoded['serverPublicKey'].toString(),
    ),
  );
}

Future<({int statusCode, Map<String, dynamic> body})> _postSync(
  HttpClient client,
  int port,
  Map<String, dynamic> payload,
) async {
  final session = await _handshake(client, port);
  final req = await client.postUrl(Uri.parse('http://127.0.0.1:$port/sync'));
  req.headers.contentType = ContentType.json;
  req.write(
    jsonEncode({
      'v': LanSyncCrypto.protocolVersion,
      'encrypted': true,
      'sessionId': session.sessionId,
      'payload': LanSyncCrypto.encryptString(session.key, jsonEncode(payload)),
    }),
  );
  final resp = await req.close();
  final raw = await resp.transform(utf8.decoder).join();
  final outer = jsonDecode(raw) as Map<String, dynamic>;
  if (outer['encrypted'] == true) {
    final inner = jsonDecode(
      LanSyncCrypto.decryptString(session.key, outer['payload'].toString()),
    ) as Map<String, dynamic>;
    return (statusCode: resp.statusCode, body: inner);
  }
  return (statusCode: resp.statusCode, body: outer);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() async {
    LanSyncService.instance.powerSaveModeOverrideForTesting = null;
    await LanSyncService.instance.stop();
  });

  test('LanSyncService blocks request-to-confirm bypass, hash auto_sync, secret leakage, and unauthenticated /file', () async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'alice',
      'app_device_uuid': 'dev-receiver',
      'device_friendly_name': 'Receiver',
      'llm_provider_key_deepseek': 'sk-top-secret-key',
    });

    final service = LanSyncService.instance;
    service.powerSaveModeOverrideForTesting = true;
    await service.initFromPreferences();
    await service.setAutoSyncEnabled(true);
    await service.setSyncSecretsEnabled(false);
    await service.start();
    final port = service.serverPort;
    expect(port, isNotNull);

    await HttpOverrides.runWithHttpOverrides(() async {
      final client = HttpClient();
      addTearDown(() => client.close(force: true));

      // Discover exposes public userId hash.
      final discReq = await client.getUrl(
        Uri.parse('http://127.0.0.1:$port/discover'),
      );
      final discResp = await discReq.close();
      final discJson = jsonDecode(
        await discResp.transform(utf8.decoder).join(),
      ) as Map<String, dynamic>;
      final discoveryHash = discJson['userId'] as String;
      expect(discoveryHash, startsWith('u1:'));

      // 1. Self-confirm bypass after action: 'request' must be rejected.
      final reqRes = await _postSync(client, port!, {
        'deviceId': 'attacker-dev',
        'userId': discoveryHash,
        'deviceName': 'Attacker',
        'port': 55555,
        'action': 'request',
      });
      expect(reqRes.statusCode, HttpStatus.ok);
      expect(reqRes.body['pending'], isTrue);
      final leakedToken = reqRes.body['token'] as String;

      final confirmRes = await _postSync(client, port, {
        'deviceId': 'attacker-dev',
        'userId': discoveryHash,
        'deviceName': 'Attacker',
        'port': 55555,
        'action': 'confirm',
        'token': leakedToken,
        'config': {
          'todos': false,
          'countdowns': false,
          'timeLogs': false,
          'pomodoroTags': false,
          'pomodoroRecords': false,
          'courses': false,
          'secrets': true,
          'settings': false,
        },
      });
      expect(confirmRes.statusCode, HttpStatus.forbidden);
      expect(confirmRes.body['error'], isNotNull);

      // 2. auto_sync with public discovery hash must be rejected.
      final autoSyncRes = await _postSync(client, port, {
        'deviceId': 'attacker-dev',
        'userId': discoveryHash,
        'deviceName': 'Attacker',
        'port': 55555,
        'action': 'auto_sync',
        'config': {
          'todos': false,
          'countdowns': false,
          'timeLogs': false,
          'pomodoroTags': false,
          'pomodoroRecords': false,
          'courses': false,
          'secrets': true,
          'settings': false,
        },
      });
      expect(autoSyncRes.statusCode, HttpStatus.forbidden);
      expect(autoSyncRes.body['error'], isNotNull);

      // 3. quick_pair clamps secrets to local syncSecretsEnabled=false.
      final pairing = await service.startQuickPairSession();
      expect(pairing, isNotNull);
      final quickPairRes = await _postSync(client, port, {
        'deviceId': 'trusted-peer',
        'userId': 'bob',
        'deviceName': 'Bob Phone',
        'port': 55556,
        'action': 'quick_pair',
        'token': pairing!.token,
        'config': {
          'todos': false,
          'countdowns': false,
          'timeLogs': false,
          'pomodoroTags': false,
          'pomodoroRecords': false,
          'courses': false,
          'secrets': true,
          'settings': false,
        },
      });
      expect(quickPairRes.statusCode, HttpStatus.ok);
      expect(quickPairRes.body['success'], isTrue);
      expect(quickPairRes.body.containsKey('secrets'), isFalse);

      // 4. Unauthenticated POST /file (handshake only) must return 403.
      final fileSession = await _handshake(client, port);
      final fileReq = await client.postUrl(
        Uri.parse('http://127.0.0.1:$port/file?name=evil.txt'),
      );
      fileReq.headers.set('X-Lan-Session', fileSession.sessionId);
      fileReq.headers.set('X-Lan-Encrypted', 'v2');
      fileReq.headers.set('X-Lan-Device-Id', 'stranger-dev');
      fileReq.headers.set('X-Lan-User-Id', discoveryHash);
      final fileResp = await fileReq.close();
      expect(fileResp.statusCode, HttpStatus.forbidden);
    }, _AllowLoopbackHttpOverrides());
  });
}
