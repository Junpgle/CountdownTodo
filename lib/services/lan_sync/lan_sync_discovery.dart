part of '../lan_sync_service_io.dart';

List<String> _buildSubnetHosts(String localIp) {
  final parts = localIp.split('.');
  if (parts.length != 4) return const <String>[];
  final subnet = '${parts[0]}.${parts[1]}.${parts[2]}';
  final hosts = <String>[];
  for (int host = 1; host < 255; host++) {
    final ip = '$subnet.$host';
    if (ip == localIp) continue;
    hosts.add(ip);
  }
  return hosts;
}

Future<List<Map<String, Object?>>> _probeLanSubnetHosts({
  required List<String> targetIps,
  required String localIp,
  required int port,
  required String? currentDeviceId,
  required int batchSize,
  required int connectionTimeoutMs,
  required int responseTimeoutMs,
}) async {
  final client = HttpClient();
  client.connectionTimeout = Duration(milliseconds: connectionTimeoutMs);
  final connectionTimeout = Duration(milliseconds: connectionTimeoutMs);
  final responseTimeout = Duration(milliseconds: responseTimeoutMs);
  final discovered = <Map<String, Object?>>[];
  try {
    final step = batchSize > 0 ? batchSize : 24;
    for (int i = 0; i < targetIps.length; i += step) {
      final end = (i + step).clamp(0, targetIps.length);
      final futures = <Future<void>>[];
      for (int idx = i; idx < end; idx++) {
        final ip = targetIps[idx];
        if (ip == localIp) continue;
        futures.add(() async {
          try {
            final request = await client
                .getUrl(Uri.parse('http://$ip:$port/discover'))
                .timeout(connectionTimeout);
            final response = await request.close().timeout(responseTimeout);
            final body = await response.transform(utf8.decoder).join();
            final data = jsonDecode(body) as Map<String, dynamic>;
            final remoteDeviceId = data['deviceId']?.toString();
            if (remoteDeviceId != null && remoteDeviceId != currentDeviceId) {
              discovered.add(<String, Object?>{
                'ip': ip,
                'port': (data['port'] as num?)?.toInt() ?? port,
                'deviceId': remoteDeviceId,
                'userId': data['userId']?.toString(),
                'deviceName': data['deviceName']?.toString() ?? '未知设备',
              });
            }
          } catch (_) {}
        }());
      }
      await Future.wait(futures);
    }
  } finally {
    client.close(force: true);
  }
  return discovered;
}

/// Probes hosts in [localIp]'s `/24` subnet inside a background [Isolate]
/// so socket connect attempts do not contend with main-isolate UI frames.
@visibleForTesting
Future<List<Map<String, Object?>>> scanLanSubnetInIsolate({
  required String localIp,
  required int port,
  String? currentDeviceId,
  int batchSize = 24,
  Duration connectionTimeout = const Duration(milliseconds: 500),
  Duration responseTimeout = const Duration(milliseconds: 700),
  List<String>? targetIpsOverride,
}) {
  final ips = targetIpsOverride ?? _buildSubnetHosts(localIp);
  if (ips.isEmpty) {
    return Future<List<Map<String, Object?>>>.value(
      const <Map<String, Object?>>[],
    );
  }
  return Isolate.run(
    () => _probeLanSubnetHosts(
      targetIps: ips,
      localIp: localIp,
      port: port,
      currentDeviceId: currentDeviceId,
      batchSize: batchSize,
      connectionTimeoutMs: connectionTimeout.inMilliseconds,
      responseTimeoutMs: responseTimeout.inMilliseconds,
    ),
  );
}

mixin _LanSyncDiscoveryMixin on _LanSyncServiceBase {
  @override
  void triggerDiscovery() {
    if (_isRunning) {
      _broadcastDiscovery();
      _startTimedScan(force: true);
      _emitStatus('正在重新扫描...');
    }
  }

  void _startTimedScan({bool force = false}) {
    _fallbackScanTimer?.cancel();
    if (force) {
      unawaited(_scanAllInterfaces());
    } else {
      // Multicast discovery is cheap and normally answers immediately. Only
      // fan out across the /24 subnet when multicast did not find any peer.
      _fallbackScanTimer = Timer(const Duration(seconds: 2), () {
        if (_isRunning && _devices.isEmpty) {
          unawaited(_scanAllInterfaces());
        }
      });
    }
    Future.delayed(const Duration(seconds: 10), () {
      if (_isRunning) {
        _emitStatus('已启动（AES加密），发现 ${_devices.length} 台设备');
      }
    });
  }

  bool _isVirtualInterfaceName(String name) {
    final lower = name.toLowerCase();
    const prefixes = [
      'utun',
      'tun',
      'tap',
      'ppp',
      'wg',
      'docker',
      'veth',
      'vmnet',
      'vboxnet',
      'bridge',
      'awdl',
      'llw',
      'ap',
    ];
    return prefixes.any((prefix) => lower.startsWith(prefix));
  }

  Future<List<({NetworkInterface interface, InternetAddress address})>>
  _getLanIpv4Interfaces() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    final preferred =
        <({NetworkInterface interface, InternetAddress address})>[];
    final secondary =
        <({NetworkInterface interface, InternetAddress address})>[];
    final virtualFallback =
        <({NetworkInterface interface, InternetAddress address})>[];
    for (final interface in interfaces) {
      final isVirtual = _isVirtualInterfaceName(interface.name);
      for (final addr in interface.addresses) {
        if (addr.isLoopback || addr.type != InternetAddressType.IPv4) continue;
        final ip = addr.address;
        if (ip.startsWith('169.254.') || ip.startsWith('198.18.')) continue;
        final entry = (interface: interface, address: addr);
        if (isVirtual) {
          virtualFallback.add(entry);
          continue;
        }
        if (ip.startsWith('192.168.') || ip.startsWith('10.')) {
          preferred.add(entry);
        } else {
          secondary.add(entry);
        }
      }
    }
    final physical = [...preferred, ...secondary];
    return physical.isNotEmpty ? physical : virtualFallback;
  }

  Future<void> _joinMulticastOnLanInterfaces(
    RawDatagramSocket socket,
    InternetAddress group,
  ) async {
    bool joinedAny = false;
    try {
      final lanInterfaces = await _getLanIpv4Interfaces();
      for (final entry in lanInterfaces) {
        try {
          socket.joinMulticast(group, entry.interface);
          joinedAny = true;
        } catch (_) {}
      }
    } catch (_) {}
    if (!joinedAny) {
      try {
        socket.joinMulticast(group);
      } catch (_) {}
    }
  }

  Future<void> _scanAllInterfaces({bool ignoreRunningState = false}) async {
    if (_scanInProgress || (!ignoreRunningState && !_isRunning)) return;
    _scanInProgress = true;
    try {
      final lanInterfaces = await _getLanIpv4Interfaces();
      for (final entry in lanInterfaces) {
        await _scanSubnet(
          entry.address.address,
          ignoreRunningState: ignoreRunningState,
        );
      }
    } catch (_) {
    } finally {
      _scanInProgress = false;
    }
  }

  Future<void> _scanSubnet(
    String localIp, {
    bool ignoreRunningState = false,
  }) async {
    try {
      final parts = localIp.split('.');
      if (parts.length != 4) return;

      final subnet = '${parts[0]}.${parts[1]}.${parts[2]}';
      debugPrint(
        '[LanSync] Scanning HTTP subnet $subnet.1-254 (localIp=$localIp, user=$_currentUserId)',
      );
      final discovered = await scanLanSubnetInIsolate(
        localIp: localIp,
        port: _defaultHttpPort,
        currentDeviceId: _currentDeviceId,
      );
      if (!ignoreRunningState && !_isRunning) return;

      for (final peer in discovered) {
        final remoteDeviceId = peer['deviceId']?.toString();
        final remoteUserId = peer['userId']?.toString();
        final ip = peer['ip']?.toString() ?? '';
        if (remoteDeviceId == null || remoteDeviceId == _currentDeviceId) {
          continue;
        }
        if (_discoverAllDevices || _isSameUser(remoteUserId, _currentUserId)) {
          final device = LanDevice(
            deviceId: remoteDeviceId,
            userId: remoteUserId ?? '',
            deviceName: peer['deviceName']?.toString() ?? '未知设备',
            ip: ip,
            port: (peer['port'] as num?)?.toInt() ?? _defaultHttpPort,
            lastSeen: DateTime.now().millisecondsSinceEpoch,
          );
          _devices[device.deviceId] = device;
          debugPrint(
            '[LanSync] HTTP discovered peer ${device.deviceName} ($ip:${device.port}, user=${device.userId})',
          );
        } else {
          debugPrint(
            '[LanSync] HTTP peer $ip ignored due to userId mismatch: remote=$remoteUserId, local=$_currentUserId',
          );
        }
      }

      _emitDevices();
    } catch (e) {
      debugPrint('[LanSync] _scanSubnet error: $e');
    }
  }

  @override
  Future<String?> _getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      String? fallback;
      String? classB;
      String? classA;
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (addr.isLoopback || addr.type != InternetAddressType.IPv4) {
            continue;
          }
          final ip = addr.address;
          if (ip.startsWith('169.254.')) continue;
          if (ip.startsWith('192.168.')) return ip;
          if (ip.startsWith('10.')) {
            classA ??= ip;
            continue;
          }
          final parts = ip.split('.');
          final second = parts.length == 4 ? int.tryParse(parts[1]) : null;
          if (parts[0] == '172' &&
              second != null &&
              second >= 16 &&
              second <= 31) {
            classB ??= ip;
            continue;
          }
          fallback ??= ip;
        }
      }
      return classA ?? classB ?? fallback;
    } catch (_) {}
    return null;
  }

  Future<void> _startUdpDiscovery() async {
    try {
      _udpSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _discoveryPort,
        reuseAddress: true,
      );
      _udpSocket!.broadcastEnabled = true;
      await _joinMulticastOnLanInterfaces(
        _udpSocket!,
        InternetAddress(_multicastGroup),
      );

      _udpSubscription = _udpSocket!.listen((event) {
        if (event != RawSocketEvent.read) return;
        Datagram? datagram;
        while ((datagram = _udpSocket?.receive()) != null) {
          _processDiscoveryDatagram(datagram);
        }
      }, onError: (_) {});
    } catch (_) {}
  }

  void _processDiscoveryDatagram(Datagram? datagram) {
    if (datagram == null) return;
    try {
      final data =
          jsonDecode(utf8.decode(datagram.data)) as Map<String, dynamic>;
      final type = data['type']?.toString();
      if (type == 'discovery_probe') {
        if (data['deviceId'] != _currentDeviceId && _udpSocket != null) {
          final reply = jsonEncode({
            'type': 'discovery',
            'deviceId': _currentDeviceId,
            'userId': _hashedDiscoveryUserId,
            'deviceName': _currentDeviceName,
            'port': _serverPort,
          });
          _udpSocket!.send(utf8.encode(reply), datagram.address, datagram.port);
        }
        return;
      }
      if (type == 'discovery' &&
          data['deviceId'] != _currentDeviceId &&
          (_discoverAllDevices ||
              _isSameUser(data['userId']?.toString(), _currentUserId))) {
        final device = LanDevice(
          deviceId: data['deviceId'],
          userId: data['userId'],
          deviceName: data['deviceName'],
          ip: datagram.address.address,
          port: data['port'] ?? _defaultHttpPort,
          lastSeen: DateTime.now().millisecondsSinceEpoch,
        );
        final isNew = !_devices.containsKey(device.deviceId);
        _devices[device.deviceId] = device;
        _emitDevices();
        if (isNew && _udpSocket != null && _serverPort != null) {
          final reply = jsonEncode({
            'type': 'discovery',
            'deviceId': _currentDeviceId,
            'userId': _hashedDiscoveryUserId,
            'deviceName': _currentDeviceName,
            'port': _serverPort,
          });
          _udpSocket!.send(
            utf8.encode(reply),
            datagram.address,
            _discoveryPort,
          );
        }
        _maybeAutoSync(device);
      }
    } catch (_) {}
  }

  Future<void> _startMdnsDiscovery() async {
    try {
      final useReusePort =
          Platform.isMacOS || Platform.isIOS || Platform.isLinux;
      try {
        _mdnsSocket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          LanMdnsCodec.mdnsPort,
          reuseAddress: true,
          reusePort: useReusePort,
        );
      } catch (_) {
        _mdnsSocket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          LanMdnsCodec.mdnsPort,
          reuseAddress: true,
        );
      }
      await _joinMulticastOnLanInterfaces(
        _mdnsSocket!,
        InternetAddress(LanMdnsCodec.multicastAddress),
      );
      _mdnsSubscription = _mdnsSocket!.listen((event) {
        if (event != RawSocketEvent.read) return;
        Datagram? datagram;
        while ((datagram = _mdnsSocket?.receive()) != null) {
          _processMdnsDatagram(datagram);
        }
      }, onError: (_) {});
      if (!_isPowerSaveMode) {
        _mdnsSocket!.send(
          LanMdnsCodec.buildQuery(),
          InternetAddress(LanMdnsCodec.multicastAddress),
          LanMdnsCodec.mdnsPort,
        );
      }
    } catch (_) {
      // 部分平台或受限网络可能禁止绑定 5353，保留已有 UDP 组播与子网扫描兜底。
    }
  }

  void _processMdnsDatagram(Datagram? datagram) {
    if (datagram == null || !_isRunning) return;
    final packet = datagram.data;
    if (LanMdnsCodec.isQueryForService(packet)) {
      _broadcastMdnsAnnouncement();
      return;
    }
    final peer = LanMdnsCodec.parseAnnouncement(
      packet,
      fallbackIp: datagram.address.address,
    );
    if (peer == null || peer.deviceId == _currentDeviceId) return;
    if (!_discoverAllDevices && !_isSameUser(peer.userId, _currentUserId)) {
      return;
    }

    final device = LanDevice(
      deviceId: peer.deviceId,
      userId: peer.userId,
      deviceName: peer.deviceName,
      ip: peer.ip,
      port: peer.port,
      lastSeen: DateTime.now().millisecondsSinceEpoch,
    );
    _devices[device.deviceId] = device;
    _emitDevices();

    if (peer.autoSync) {
      _maybeAutoSync(device);
    }
  }

  void _broadcastMdnsAnnouncement() {
    if (_mdnsSocket == null || !_isRunning || _serverPort == null) return;
    final ip = _localIp;
    if (ip == null || ip.isEmpty) return;
    try {
      final packet = LanMdnsCodec.buildAnnouncement(
        deviceId: _currentDeviceId ?? '',
        userId: _hashedDiscoveryUserId,
        deviceName: _currentDeviceName ?? '未知设备',
        ip: ip,
        port: _serverPort!,
        autoSync: _autoSyncEnabled,
      );
      _mdnsSocket!.send(
        packet,
        InternetAddress(LanMdnsCodec.multicastAddress),
        LanMdnsCodec.mdnsPort,
      );
    } catch (_) {}
  }

  void _maybeAutoSync(LanDevice device) {
    if (!_autoSyncEnabled || _isSyncing) return;
    if (!_isSameUser(device.userId, _currentUserId)) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = _lastAutoSyncAt[device.deviceId] ?? 0;
    if (AppSettingsStorage.offlineModeNotifier.value &&
        _cachedOfflineSyncIntervalMinutes != null) {
      final interval = _cachedOfflineSyncIntervalMinutes!;
      if (interval <= 0 && last > 0) return;
      if (interval > 0 && now - last < interval * 60 * 1000) return;
    } else if (now - last < _autoSyncCooldownMs) {
      return;
    }
    _lastAutoSyncAt[device.deviceId] = now;
    unawaited(_autoSyncWithDevice(device));
  }

  void _startDiscoveryBroadcast() {
    _discoveryTimer?.cancel();
    _broadcastDiscovery();
    _discoveryTimer = Timer.periodic(
      _discoveryInterval,
      (_) => _broadcastDiscovery(),
    );
  }

  void _broadcastDiscovery() {
    if (!_isRunning) return;
    if (_currentUserId == null || _currentUserId == 'local') {
      unawaited(_ensureIdentity());
    }
    if (_udpSocket != null) {
      try {
        final message = utf8.encode(
          jsonEncode({
            'type': 'discovery',
            'deviceId': _currentDeviceId,
            'userId': _hashedDiscoveryUserId,
            'deviceName': _currentDeviceName,
            'port': _serverPort,
          }),
        );
        _udpSocket!.send(
          message,
          InternetAddress(_multicastGroup),
          _discoveryPort,
        );
        _udpSocket!.send(
          message,
          InternetAddress('255.255.255.255'),
          _discoveryPort,
        );
        unawaited(_sendSubnetBroadcasts(_udpSocket!, message));
      } catch (_) {}
    }
    _broadcastMdnsAnnouncement();
  }

  Future<void> _sendSubnetBroadcasts(
    RawDatagramSocket socket,
    List<int> payload,
  ) async {
    try {
      final lanInterfaces = await _getLanIpv4Interfaces();
      for (final entry in lanInterfaces) {
        final parts = entry.address.address.split('.');
        if (parts.length == 4) {
          final bcast = '${parts[0]}.${parts[1]}.${parts[2]}.255';
          try {
            socket.send(payload, InternetAddress(bcast), _discoveryPort);
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  void _handlePowerSaveModeChanged() {
    if (_isPowerSaveMode) {
      _discoveryTimer?.cancel();
      _discoveryTimer = null;
      _fallbackScanTimer?.cancel();
      _fallbackScanTimer = null;
      if (_isRunning) {
        _emitStatus('省电模式已暂停自动探测');
      }
      return;
    }

    if (_isRunning) {
      _startDiscoveryBroadcast();
      _startTimedScan();
      _emitStatus(_isDaemonMode ? '常驻服务运行中（mDNS）' : '正在扫描设备...');
    } else if (_initialized) {
      unawaited(initFromPreferences());
    }
  }

  Future<bool> _shouldAllowBackgroundAutoSync({required bool isStartup}) async {
    final isOffline = await AppSettingsStorage.isOfflineModeEnabled();
    if (!isOffline) return true;

    final intervalMinutes = await StorageService.getSyncInterval();
    _cachedOfflineSyncIntervalMinutes = intervalMinutes;
    if (intervalMinutes <= 0) {
      return isStartup && !_hasRunStartupBackgroundSync;
    }
    final lastSync = _lastOfflineBackgroundSyncAt;
    if (lastSync != null &&
        DateTime.now().difference(lastSync).inMinutes < intervalMinutes) {
      return false;
    }
    return true;
  }

  /// 应用启动或切回前台时，按配置执行一次轻量局域网无感发现并双向合并。
  Future<void> triggerBackgroundAutoSync({bool isStartup = false}) async {
    if (_backgroundAutoSyncInProgress || _isSyncing || _isPowerSaveMode) {
      return;
    }
    _backgroundAutoSyncInProgress = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final isOffline = await AppSettingsStorage.isOfflineModeEnabled();
      final autoEnabled = prefs.getBool(_prefAutoSyncEnabled) ?? isOffline;
      _autoSyncEnabled = autoEnabled;
      if (!autoEnabled) return;
      if (!await _shouldAllowBackgroundAutoSync(isStartup: isStartup)) return;

      final loggedInUser = (await UserSessionStorage.getCurrentUsername())
          ?.trim();
      if (loggedInUser == null || loggedInUser.isEmpty) return;

      _hasRunStartupBackgroundSync = true;
      _lastOfflineBackgroundSyncAt = DateTime.now();
      await _ensureIdentity();

      if (!_isRunning) {
        final isDesktop =
            Platform.isWindows || Platform.isMacOS || Platform.isLinux;
        final desktopDaemon =
            isDesktop &&
            (prefs.getBool(_prefDesktopDaemonEnabled) ?? isOffline);
        await start(daemonMode: desktopDaemon);
      } else {
        _broadcastDiscovery();
      }

      await Future.delayed(const Duration(milliseconds: 1200));
      if (!_devices.values.any((d) => _isSameUser(d.userId, _currentUserId))) {
        await _scanAllInterfaces(ignoreRunningState: true);
      }

      for (final device in _devices.values.toList()) {
        _maybeAutoSync(device);
      }
    } catch (e) {
      debugPrint('[LanSync] triggerBackgroundAutoSync error: $e');
    } finally {
      _backgroundAutoSyncInProgress = false;
    }
  }

  /// 触发一次轻量局域网设备扫描（供手动同步弹窗实时检测在线设备）。
  Future<void> scanForPeersOnce() async {
    await _ensureIdentity();
    if (!_isRunning) {
      final prefs = await SharedPreferences.getInstance();
      final isOffline = await AppSettingsStorage.isOfflineModeEnabled();
      final isDesktop =
          Platform.isWindows || Platform.isMacOS || Platform.isLinux;
      final desktopDaemon =
          isDesktop && (prefs.getBool(_prefDesktopDaemonEnabled) ?? isOffline);
      await start(daemonMode: desktopDaemon);
    } else {
      _broadcastDiscovery();
    }
    await Future.delayed(const Duration(milliseconds: 1000));
    if (!_devices.values.any((d) => _isSameUser(d.userId, _currentUserId))) {
      await _scanAllInterfaces(ignoreRunningState: true);
    }
    _emitDevices();
  }

  @override
  Future<void> _discoverOnce({
    Duration duration = const Duration(seconds: 3),
  }) async {
    RawDatagramSocket? tempMdnsSocket;
    RawDatagramSocket? tempUdpSocket;
    StreamSubscription<RawSocketEvent>? mdnsSub;
    StreamSubscription<RawSocketEvent>? udpSub;

    try {
      Future<void> bindTempMdns() async {
        try {
          final useReusePort =
              Platform.isMacOS || Platform.isIOS || Platform.isLinux;
          try {
            tempMdnsSocket = await RawDatagramSocket.bind(
              InternetAddress.anyIPv4,
              LanMdnsCodec.mdnsPort,
              reuseAddress: true,
              reusePort: useReusePort,
            );
          } catch (_) {
            tempMdnsSocket = await RawDatagramSocket.bind(
              InternetAddress.anyIPv4,
              LanMdnsCodec.mdnsPort,
              reuseAddress: true,
            );
          }
          await _joinMulticastOnLanInterfaces(
            tempMdnsSocket!,
            InternetAddress(LanMdnsCodec.multicastAddress),
          );
          mdnsSub = tempMdnsSocket!.listen((event) {
            if (event != RawSocketEvent.read) return;
            Datagram? datagram;
            while ((datagram = tempMdnsSocket?.receive()) != null) {
              final peer = LanMdnsCodec.parseAnnouncement(
                datagram!.data,
                fallbackIp: datagram.address.address,
              );
              if (peer == null ||
                  peer.deviceId == _currentDeviceId ||
                  !_isSameUser(peer.userId, _currentUserId)) {
                continue;
              }
              _devices[peer.deviceId] = LanDevice(
                deviceId: peer.deviceId,
                userId: peer.userId,
                deviceName: peer.deviceName,
                ip: peer.ip,
                port: peer.port,
                lastSeen: DateTime.now().millisecondsSinceEpoch,
              );
              _emitDevices();
            }
          }, onError: (_) {});
          tempMdnsSocket!.send(
            LanMdnsCodec.buildQuery(),
            InternetAddress(LanMdnsCodec.multicastAddress),
            LanMdnsCodec.mdnsPort,
          );
        } catch (_) {}
      }

      Future<void> bindTempUdp() async {
        try {
          tempUdpSocket = await RawDatagramSocket.bind(
            InternetAddress.anyIPv4,
            0,
          );
          tempUdpSocket!.broadcastEnabled = true;
          await _joinMulticastOnLanInterfaces(
            tempUdpSocket!,
            InternetAddress(_multicastGroup),
          );
          udpSub = tempUdpSocket!.listen((event) {
            if (event != RawSocketEvent.read) return;
            Datagram? datagram;
            while ((datagram = tempUdpSocket?.receive()) != null) {
              try {
                final data = jsonDecode(
                  utf8.decode(datagram!.data),
                ) as Map<String, dynamic>;
                if (data['type'] == 'discovery' &&
                    data['deviceId'] != _currentDeviceId &&
                    _isSameUser(data['userId']?.toString(), _currentUserId)) {
                  final device = LanDevice(
                    deviceId: data['deviceId'],
                    userId: data['userId'],
                    deviceName: data['deviceName'],
                    ip: datagram.address.address,
                    port: data['port'] ?? _defaultHttpPort,
                    lastSeen: DateTime.now().millisecondsSinceEpoch,
                  );
                  _devices[device.deviceId] = device;
                  _emitDevices();
                }
              } catch (_) {}
            }
          }, onError: (_) {});

          final probe = utf8.encode(
            jsonEncode({
              'type': 'discovery_probe',
              'deviceId': _currentDeviceId,
              'userId': _hashedDiscoveryUserId,
              'deviceName': _currentDeviceName,
            }),
          );
          tempUdpSocket!.send(
            probe,
            InternetAddress(_multicastGroup),
            _discoveryPort,
          );
          tempUdpSocket!.send(
            probe,
            InternetAddress('255.255.255.255'),
            _discoveryPort,
          );
          await _sendSubnetBroadcasts(tempUdpSocket!, probe);
        } catch (_) {}
      }

      await Future.wait([bindTempMdns(), bindTempUdp()]);
      await Future.delayed(duration);
      if (!_devices.values.any((d) => _isSameUser(d.userId, _currentUserId))) {
        await _scanAllInterfaces(ignoreRunningState: true);
      }
      _emitDevices();
    } finally {
      await mdnsSub?.cancel();
      await udpSub?.cancel();
      tempMdnsSocket?.close();
      tempUdpSocket?.close();
    }
  }
}
