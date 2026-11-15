import 'dart:convert';
import 'dart:typed_data';

/// mDNS 解析出的局域网对端设备信息。
class LanMdnsPeer {
  const LanMdnsPeer({
    required this.deviceId,
    required this.userId,
    required this.deviceName,
    required this.ip,
    required this.port,
    required this.autoSync,
  });

  final String deviceId;
  final String userId;
  final String deviceName;
  final String ip;
  final int port;
  final bool autoSync;
}

/// 纯 Dart RFC 6762 mDNS 编解码器（`_cdtodo-lan._tcp.local`）。
class LanMdnsCodec {
  const LanMdnsCodec._();

  static const String multicastAddress = '224.0.0.251';
  static const int mdnsPort = 5353;
  static const String serviceType = '_cdtodo-lan._tcp.local';

  static const int _typeA = 1;
  static const int _typePtr = 12;
  static const int _typeTxt = 16;
  static const int _typeSrv = 33;
  static const int _classIn = 1;

  /// 构建 mDNS PTR 查询包，用于发现同局域网内的 CountdownTodo 节点。
  static Uint8List buildQuery() {
    final out = BytesBuilder();
    _writeUint16(out, 0); // Transaction ID = 0
    _writeUint16(out, 0); // Flags = standard query
    _writeUint16(out, 1); // QDCOUNT = 1
    _writeUint16(out, 0); // ANCOUNT = 0
    _writeUint16(out, 0); // NSCOUNT = 0
    _writeUint16(out, 0); // ARCOUNT = 0

    _writeDnsName(out, serviceType);
    _writeUint16(out, _typePtr);
    _writeUint16(out, _classIn);
    return out.toBytes();
  }

  /// 构建 mDNS 广播/响应包，公布本机服务实例、端口与设备元数据。
  static Uint8List buildAnnouncement({
    required String deviceId,
    required String userId,
    required String deviceName,
    required String ip,
    required int port,
    bool autoSync = true,
    int ttlSeconds = 120,
  }) {
    final safeId = _sanitizeLabel(deviceId);
    final instanceName = '$safeId.$serviceType';
    final hostName = '$safeId.local';
    final ipv4Bytes = _parseIpv4(ip);

    final out = BytesBuilder();
    _writeUint16(out, 0); // Transaction ID
    _writeUint16(out, 0x8400); // Response + Authoritative Answer
    _writeUint16(out, 0); // QDCOUNT
    _writeUint16(out, ipv4Bytes != null ? 4 : 3); // ANCOUNT
    _writeUint16(out, 0); // NSCOUNT
    _writeUint16(out, 0); // ARCOUNT

    // 1. PTR: _cdtodo-lan._tcp.local -> <instance>._cdtodo-lan._tcp.local
    final ptrRdata = BytesBuilder();
    _writeDnsName(ptrRdata, instanceName);
    _writeRecord(out, serviceType, _typePtr, ttlSeconds, ptrRdata.toBytes());

    // 2. SRV: <instance> -> port + hostName
    final srvRdata = BytesBuilder();
    _writeUint16(srvRdata, 0); // priority
    _writeUint16(srvRdata, 0); // weight
    _writeUint16(srvRdata, port);
    _writeDnsName(srvRdata, hostName);
    _writeRecord(out, instanceName, _typeSrv, ttlSeconds, srvRdata.toBytes());

    // 3. TXT: key=value pairs
    final txtRdata = BytesBuilder();
    final entries = <String>[
      'deviceId=$deviceId',
      'userId=$userId',
      'deviceName=$deviceName',
      'port=$port',
      'autoSync=${autoSync ? '1' : '0'}',
    ];
    for (final entry in entries) {
      final encoded = utf8.encode(entry);
      if (encoded.length <= 255) {
        txtRdata.addByte(encoded.length);
        txtRdata.add(encoded);
      }
    }
    _writeRecord(out, instanceName, _typeTxt, ttlSeconds, txtRdata.toBytes());

    // 4. A: <host>.local -> IPv4
    if (ipv4Bytes != null) {
      _writeRecord(out, hostName, _typeA, ttlSeconds, ipv4Bytes);
    }

    return out.toBytes();
  }

  /// 是否是查询 `_cdtodo-lan._tcp.local` 的 mDNS 请求包。
  static bool isQueryForService(Uint8List packet) {
    if (packet.length < 12) return false;
    final flags = _readUint16(packet, 2);
    if ((flags & 0x8000) != 0) return false; // 忽略响应包
    final qdCount = _readUint16(packet, 4);
    int offset = 12;
    for (int i = 0; i < qdCount; i++) {
      final decoded = _readDnsName(packet, offset);
      if (decoded == null) return false;
      offset = decoded.nextOffset;
      if (offset + 4 > packet.length) return false;
      final qtype = _readUint16(packet, offset);
      offset += 4;
      if (decoded.name.toLowerCase() == serviceType &&
          (qtype == _typePtr || qtype == 255)) {
        return true;
      }
    }
    return false;
  }

  /// 解析 mDNS 响应/广播包；非本服务包返回 `null`。
  static LanMdnsPeer? parseAnnouncement(
    Uint8List packet, {
    required String fallbackIp,
  }) {
    if (packet.length < 12) return null;
    final flags = _readUint16(packet, 2);
    if ((flags & 0x8000) == 0) return null; // 仅解析响应包

    final qdCount = _readUint16(packet, 4);
    final anCount = _readUint16(packet, 6);
    final nsCount = _readUint16(packet, 8);
    final arCount = _readUint16(packet, 10);
    int offset = 12;

    for (int i = 0; i < qdCount; i++) {
      final decoded = _readDnsName(packet, offset);
      if (decoded == null) return null;
      offset = decoded.nextOffset + 4;
      if (offset > packet.length) return null;
    }

    final totalRecords = anCount + nsCount + arCount;
    bool matchesService = false;
    int? srvPort;
    String? ipv4;
    final txtMap = <String, String>{};

    for (int i = 0; i < totalRecords; i++) {
      final nameRes = _readDnsName(packet, offset);
      if (nameRes == null) break;
      offset = nameRes.nextOffset;
      if (offset + 10 > packet.length) break;

      final type = _readUint16(packet, offset);
      final rdLength = _readUint16(packet, offset + 8);
      offset += 10;
      if (offset + rdLength > packet.length) break;

      final rdataStart = offset;
      final lowerName = nameRes.name.toLowerCase();

      if (type == _typePtr && lowerName == serviceType) {
        final target = _readDnsName(packet, rdataStart);
        if (target != null && target.name.toLowerCase().endsWith(serviceType)) {
          matchesService = true;
        }
      } else if (type == _typeSrv && lowerName.endsWith(serviceType)) {
        matchesService = true;
        if (rdLength >= 6) {
          srvPort = _readUint16(packet, rdataStart + 4);
        }
      } else if (type == _typeTxt && lowerName.endsWith(serviceType)) {
        matchesService = true;
        int pos = rdataStart;
        final end = rdataStart + rdLength;
        while (pos < end) {
          final len = packet[pos++];
          if (pos + len > end) break;
          final kv = utf8.decode(
            packet.sublist(pos, pos + len),
            allowMalformed: true,
          );
          final eq = kv.indexOf('=');
          if (eq > 0) {
            txtMap[kv.substring(0, eq)] = kv.substring(eq + 1);
          }
          pos += len;
        }
      } else if (type == _typeA && rdLength == 4) {
        ipv4 =
            '${packet[rdataStart]}.${packet[rdataStart + 1]}.${packet[rdataStart + 2]}.${packet[rdataStart + 3]}';
      }

      offset += rdLength;
    }

    if (!matchesService) return null;
    final deviceId = txtMap['deviceId'] ?? '';
    if (deviceId.isEmpty) return null;

    final port = srvPort ?? int.tryParse(txtMap['port'] ?? '') ?? 0;
    if (port <= 0) return null;

    return LanMdnsPeer(
      deviceId: deviceId,
      userId: txtMap['userId'] ?? '',
      deviceName: txtMap['deviceName'] ?? '未知设备',
      ip: ipv4 ?? fallbackIp,
      port: port,
      autoSync: txtMap['autoSync'] != '0',
    );
  }

  static void _writeRecord(
    BytesBuilder out,
    String name,
    int type,
    int ttlSeconds,
    List<int> rdata,
  ) {
    _writeDnsName(out, name);
    _writeUint16(out, type);
    _writeUint16(out, _classIn);
    _writeUint32(out, ttlSeconds);
    _writeUint16(out, rdata.length);
    out.add(rdata);
  }

  static void _writeDnsName(BytesBuilder out, String name) {
    for (final label in name.split('.')) {
      if (label.isEmpty) continue;
      final bytes = utf8.encode(label);
      final clamped = bytes.length > 63 ? bytes.sublist(0, 63) : bytes;
      out.addByte(clamped.length);
      out.add(clamped);
    }
    out.addByte(0);
  }

  static _DnsNameResult? _readDnsName(Uint8List packet, int offset) {
    final labels = <String>[];
    int cursor = offset;
    int? jumpedNextOffset;
    int jumps = 0;

    while (cursor < packet.length) {
      final len = packet[cursor];
      if (len == 0) {
        cursor++;
        break;
      }
      if ((len & 0xC0) == 0xC0) {
        if (cursor + 1 >= packet.length) return null;
        final ptr = ((len & 0x3F) << 8) | packet[cursor + 1];
        jumpedNextOffset ??= cursor + 2;
        cursor = ptr;
        jumps++;
        if (jumps > 16) return null;
        continue;
      }
      cursor++;
      if (cursor + len > packet.length) return null;
      labels.add(
        utf8.decode(packet.sublist(cursor, cursor + len), allowMalformed: true),
      );
      cursor += len;
    }

    return _DnsNameResult(
      name: labels.join('.'),
      nextOffset: jumpedNextOffset ?? cursor,
    );
  }

  static String _sanitizeLabel(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '');
    if (cleaned.isEmpty) return 'cdt-node';
    return cleaned.length > 48 ? cleaned.substring(0, 48) : cleaned;
  }

  static List<int>? _parseIpv4(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return null;
    final bytes = <int>[];
    for (final part in parts) {
      final v = int.tryParse(part);
      if (v == null || v < 0 || v > 255) return null;
      bytes.add(v);
    }
    return bytes;
  }

  static void _writeUint16(BytesBuilder out, int value) {
    out.addByte((value >> 8) & 0xFF);
    out.addByte(value & 0xFF);
  }

  static void _writeUint32(BytesBuilder out, int value) {
    out.addByte((value >> 24) & 0xFF);
    out.addByte((value >> 16) & 0xFF);
    out.addByte((value >> 8) & 0xFF);
    out.addByte(value & 0xFF);
  }

  static int _readUint16(Uint8List data, int offset) =>
      (data[offset] << 8) | data[offset + 1];
}

class _DnsNameResult {
  const _DnsNameResult({required this.name, required this.nextOffset});

  final String name;
  final int nextOffset;
}
