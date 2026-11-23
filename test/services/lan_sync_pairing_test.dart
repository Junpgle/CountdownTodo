import 'dart:convert';
import 'dart:io';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/services/lan_mdns_codec.dart';
import 'package:countdown_todo/services/lan_sync_pairing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LanPairingPayload', () {
    test('round-trips cdt-lan://sync URI and detects expiry', () {
      final token = LanPairingPayload.generateOneTimeToken();
      expect(token.length, 32);

      final payload = LanPairingPayload(
        deviceId: 'dev-123',
        userId: 'alice',
        deviceName: 'MacBook Pro',
        ip: '192.168.1.42',
        port: 54322,
        token: token,
        expiresAt: 2000000,
      );

      final uriString = payload.toUriString();
      expect(uriString, startsWith('cdt-lan://sync?'));

      final parsed = LanPairingPayload.tryParse(uriString);
      expect(parsed, isNotNull);
      expect(parsed!.deviceId, 'dev-123');
      expect(parsed.userId, 'alice');
      expect(parsed.deviceName, 'MacBook Pro');
      expect(parsed.ip, '192.168.1.42');
      expect(parsed.port, 54322);
      expect(parsed.token, token);
      expect(parsed.isExpired(nowMs: 1999999), isFalse);
      expect(parsed.isExpired(nowMs: 2000001), isTrue);
    });

    test('parses JSON fallback and rejects invalid inputs', () {
      final parsed = LanPairingPayload.tryParse(
        '{"ip":"10.0.0.5","port":54323,"token":"abc","deviceId":"d1"}',
      );
      expect(parsed, isNotNull);
      expect(parsed!.ip, '10.0.0.5');
      expect(parsed.port, 54323);
      expect(parsed.token, 'abc');

      expect(LanPairingPayload.tryParse(''), isNull);
      expect(LanPairingPayload.tryParse('https://example.com'), isNull);
      expect(LanPairingPayload.tryParse('cdt-lan://sync?ip=1.2.3.4'), isNull);
    });
  });

  group('LanSyncLww', () {
    test('uses updatedAt as primary order and version as tie-breaker', () {
      final olderTimeHigherVersion = TodoItem(
        id: 't1',
        title: 'old',
        updatedAt: 1000,
        version: 99,
      );
      final newerTimeLowerVersion = TodoItem(
        id: 't1',
        title: 'new',
        updatedAt: 2000,
        version: 1,
      );

      expect(
        LanSyncLww.isTodoWinner(newerTimeLowerVersion, olderTimeHigherVersion),
        isTrue,
      );
      expect(
        LanSyncLww.isTodoWinner(olderTimeHigherVersion, newerTimeLowerVersion),
        isFalse,
      );

      final sameTimeHigherVersion = TodoItem(
        id: 't1',
        title: 'tie-win',
        updatedAt: 2000,
        version: 2,
      );
      expect(
        LanSyncLww.isTodoWinner(sameTimeHigherVersion, newerTimeLowerVersion),
        isTrue,
      );
    });
  });

  group('LanMdnsCodec', () {
    test('builds query packet recognized by isQueryForService', () {
      final query = LanMdnsCodec.buildQuery();
      expect(LanMdnsCodec.isQueryForService(query), isTrue);
      expect(
        LanMdnsCodec.parseAnnouncement(query, fallbackIp: '192.168.1.1'),
        isNull,
      );
    });

    test('round-trips mDNS announcement with PTR/SRV/TXT/A records', () {
      final packet = LanMdnsCodec.buildAnnouncement(
        deviceId: 'mac-office-01',
        userId: 'junpgle',
        deviceName: 'Junpgle Mac',
        ip: '192.168.31.88',
        port: 54322,
        autoSync: true,
      );

      expect(LanMdnsCodec.isQueryForService(packet), isFalse);

      final peer = LanMdnsCodec.parseAnnouncement(
        packet,
        fallbackIp: '192.168.31.1',
      );
      expect(peer, isNotNull);
      expect(peer!.deviceId, 'mac-office-01');
      expect(peer.userId, 'junpgle');
      expect(peer.deviceName, 'Junpgle Mac');
      expect(peer.ip, '192.168.31.88');
      expect(peer.port, 54322);
      expect(peer.autoSync, isTrue);
    });
  });

  group('LAN HTTP /discover loopback round-trip', () {
    test('parses /discover JSON payload from loopback HttpServer', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));

      server.listen((HttpRequest req) async {
        if (req.uri.path == '/discover') {
          req.response.headers.contentType = ContentType.json;
          req.response.write(
            jsonEncode({
              'deviceId': 'peer-dev-1',
              'userId': 'Alice',
              'deviceName': 'Test Desktop',
              'port': server.port,
            }),
          );
        } else {
          req.response.statusCode = HttpStatus.notFound;
        }
        await req.response.close();
      });

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final req = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/discover'),
      );
      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();
      final decoded = jsonDecode(body) as Map<String, dynamic>;

      expect(decoded['deviceId'], 'peer-dev-1');
      expect(decoded['userId'], 'Alice');
      expect(decoded['deviceName'], 'Test Desktop');
      expect(decoded['port'], server.port);
    });
  });

  group('LanDiscoveryIdentity', () {
    test('hashes userId irreversibly and matches across case/whitespace', () {
      final h1 = LanDiscoveryIdentity.hashUserId('Alice@Example.com');
      final h2 = LanDiscoveryIdentity.hashUserId('  alice@example.com ');
      expect(h1, startsWith('u1:'));
      expect(h1, equals(h2));
      expect(h1.contains('alice'), isFalse);

      expect(LanDiscoveryIdentity.isSameUser(h1, 'alice@example.com'), isTrue);
      expect(
        LanDiscoveryIdentity.isSameUser(
          LanDiscoveryIdentity.hashUserId('bob@example.com'),
          'alice@example.com',
        ),
        isFalse,
      );
      // Legacy plaintext compatibility
      expect(
        LanDiscoveryIdentity.isSameUser(
          'Alice@Example.com',
          'alice@example.com',
        ),
        isTrue,
      );

      expect(
        LanDiscoveryIdentity.isDirectSameAccount(
          'Alice@Example.com',
          'alice@example.com',
        ),
        isTrue,
      );
      expect(
        LanDiscoveryIdentity.isDirectSameAccount(h1, 'alice@example.com'),
        isFalse,
      );
      expect(
        LanDiscoveryIdentity.isDirectSameAccount('local', 'local'),
        isFalse,
      );
    });
  });
}
