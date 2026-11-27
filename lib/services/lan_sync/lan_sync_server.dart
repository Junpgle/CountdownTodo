part of '../lan_sync_service_io.dart';

mixin _LanSyncServerMixin on _LanSyncServiceBase {
  void _pruneExpiredSessions() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _cryptoSessions.removeWhere((_, session) => session.expiresAt < now);
  }

  ({String sessionId, String serverPublicKeyBase64}) _createCryptoSession(
    String clientPublicKeyBase64,
  ) {
    _pruneExpiredSessions();
    if (_cryptoSessions.length >= _maxCryptoSessions) {
      _cryptoSessions.remove(_cryptoSessions.keys.first);
    }

    final serverKeys = LanSyncCrypto.generateEphemeralKeyPair();
    final sharedKey = LanSyncCrypto.deriveSharedKey(
      serverKeys.privateKey,
      clientPublicKeyBase64,
    );

    final rng = Random.secure();
    final idBytes = List<int>.generate(16, (_) => rng.nextInt(256));
    final sessionId = idBytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();

    _cryptoSessions[sessionId] = (
      key: sharedKey,
      expiresAt: DateTime.now().add(_sessionTtl).millisecondsSinceEpoch,
    );
    return (
      sessionId: sessionId,
      serverPublicKeyBase64: serverKeys.publicKeyBase64,
    );
  }

  @override
  Uint8List? _getSessionKey(String? sessionId) {
    if (sessionId == null || sessionId.isEmpty) return null;
    _pruneExpiredSessions();
    return _cryptoSessions[sessionId]?.key;
  }

  @override
  Future<({String sessionId, Uint8List key})> _performHandshake(
    HttpClient client,
    String ip,
    int port,
  ) async {
    final clientKeys = LanSyncCrypto.generateEphemeralKeyPair();
    final req = await client.postUrl(Uri.parse('http://$ip:$port/handshake'));
    req.headers.contentType = ContentType.json;
    req.write(
      jsonEncode({
        'v': LanSyncCrypto.protocolVersion,
        'clientPublicKey': clientKeys.publicKeyBase64,
      }),
    );
    final resp = await req.close().timeout(const Duration(seconds: 8));
    final body = await resp.transform(utf8.decoder).join();
    if (resp.statusCode != HttpStatus.ok) {
      throw StateError('加密握手失败 (${resp.statusCode}): $body');
    }
    final data = jsonDecode(body) as Map<String, dynamic>;
    if (data['v'] != LanSyncCrypto.protocolVersion) {
      throw StateError('不支持的加密协议版本: ${data['v']}');
    }
    final sessionId = data['sessionId']?.toString() ?? '';
    final serverPub = data['serverPublicKey']?.toString() ?? '';
    if (sessionId.isEmpty || serverPub.isEmpty) {
      throw const FormatException('握手响应缺少会话参数');
    }
    final key = LanSyncCrypto.deriveSharedKey(clientKeys.privateKey, serverPub);
    return (sessionId: sessionId, key: key);
  }

  @override
  Future<Map<String, dynamic>> _postEncryptedSync(
    HttpClient client,
    String ip,
    int port,
    Map<String, dynamic> payload, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final session = await _performHandshake(client, ip, port);
    final request = await client.postUrl(Uri.parse('http://$ip:$port/sync'));
    request.headers.contentType = ContentType.json;
    request.write(
      jsonEncode({
        'v': LanSyncCrypto.protocolVersion,
        'encrypted': true,
        'sessionId': session.sessionId,
        'payload': await LanSyncCrypto.encryptStringAsync(
          session.key,
          jsonEncode(payload),
        ),
      }),
    );
    final response = await request.close().timeout(timeout);
    final encryptedBody = await response.transform(utf8.decoder).join();
    final encryptedResponseData =
        jsonDecode(encryptedBody) as Map<String, dynamic>;

    if (encryptedResponseData['encrypted'] != true ||
        encryptedResponseData['v'] != LanSyncCrypto.protocolVersion) {
      final rawErr = encryptedResponseData['error']?.toString();
      return {
        'success': false,
        'error':
            '响应未加密或版本不匹配 (${_localizePeerError(rawErr, fallback: '未知错误')})',
      };
    }

    final decryptedBody = await LanSyncCrypto.decryptStringAsync(
      session.key,
      encryptedResponseData['payload'].toString(),
    );
    return jsonDecode(decryptedBody) as Map<String, dynamic>;
  }

  Future<void> _startHttpServer() async {
    int port = _defaultHttpPort;
    for (int attempt = 0; attempt < 10; attempt++) {
      try {
        _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
        _serverPort = port;
        // debugPrint('[LanSync] HTTP server started on port $port');
        break;
      } catch (e) {
        port = _defaultHttpPort + attempt + 1;
      }
    }
    if (_server == null) throw Exception('无法启动HTTP服务器');

    _server!.listen(_handleRequest);
  }

  Future<void> _handleRequest(HttpRequest req) async {
    try {
      final path = req.uri.path;
      if (path == '/handshake' && req.method == 'POST') {
        await _handleHandshakeRequest(req);
      } else if (path == '/sync' && req.method == 'POST') {
        await _handleSyncRequest(req);
      } else if (path == '/file' && req.method == 'POST') {
        await _handleFileRequest(req);
      } else if (path == '/discover' && req.method == 'GET') {
        await _handleDiscoverRequest(req);
      } else {
        req.response.statusCode = HttpStatus.notFound;
        req.response.write(jsonEncode({'error': '请求路径不存在'}));
        await req.response.close();
      }
    } catch (e) {
      // debugPrint('[LanSync] Handle request error: $e');
      try {
        req.response.statusCode = HttpStatus.internalServerError;
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({'error': e.toString()}));
        await req.response.close();
      } catch (_) {}
    }
  }

  Future<void> _handleHandshakeRequest(HttpRequest req) async {
    final body = await utf8.decoder.bind(req).join();
    final data = jsonDecode(body) as Map<String, dynamic>;
    if (data['v'] != LanSyncCrypto.protocolVersion) {
      req.response.statusCode = HttpStatus.badRequest;
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode({'error': '不支持的加密协议版本: ${data['v']}'}));
      await req.response.close();
      return;
    }

    final clientPub = data['clientPublicKey']?.toString() ?? '';
    if (clientPub.isEmpty) {
      req.response.statusCode = HttpStatus.badRequest;
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode({'error': '握手请求缺少客户端公钥'}));
      await req.response.close();
      return;
    }

    final session = _createCryptoSession(clientPub);
    req.response.headers.contentType = ContentType.json;
    req.response.write(
      jsonEncode({
        'v': LanSyncCrypto.protocolVersion,
        'sessionId': session.sessionId,
        'serverPublicKey': session.serverPublicKeyBase64,
      }),
    );
    await req.response.close();
  }

  Future<void> _handleDiscoverRequest(HttpRequest req) async {
    if (_currentUserId == null || _currentUserId == 'local') {
      await _ensureIdentity();
    }
    final response = {
      'deviceId': _currentDeviceId,
      'userId': _hashedDiscoveryUserId,
      'deviceName': _currentDeviceName,
      'port': _serverPort,
    };
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode(response));
    await req.response.close();
  }

  Future<void> _handleSyncRequest(HttpRequest req) async {
    final encryptedBody = await utf8.decoder.bind(req).join();
    final encryptedData = jsonDecode(encryptedBody) as Map<String, dynamic>;

    if (encryptedData['encrypted'] != true ||
        encryptedData['v'] != LanSyncCrypto.protocolVersion) {
      req.response.statusCode = HttpStatus.badRequest;
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode({'error': '需要 v2 加密会话，请升级应用版本'}));
      await req.response.close();
      return;
    }

    final sessionId = encryptedData['sessionId']?.toString();
    final sessionKey = _getSessionKey(sessionId);
    if (sessionKey == null) {
      req.response.statusCode = HttpStatus.unauthorized;
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode({'error': '加密会话无效或已过期，请重试'}));
      await req.response.close();
      return;
    }

    final decryptedBody = await LanSyncCrypto.decryptStringAsync(
      sessionKey,
      encryptedData['payload'].toString(),
    );
    final data = jsonDecode(decryptedBody) as Map<String, dynamic>;

    final remoteDeviceId = data['deviceId'] ?? '';
    final remoteUserId = data['userId'] ?? '';
    final remoteDeviceName = data['deviceName'] ?? '';
    final action = data['action'] ?? 'request';

    // quick_pair 使用一次性二维码令牌授权，允许跨账号或离线 local 账号直接互传。
    if (action != 'quick_pair' &&
        !_isSameUser(remoteUserId, _currentUserId) &&
        !_discoverAllDevices) {
      await _writeEncryptedError(
        req,
        sessionKey,
        '对方设备账号不匹配，请确认双方登录同一账号或开启“所有设备”',
        statusCode: HttpStatus.forbidden,
      );
      return;
    }

    if (action == 'request') {
      final ip = req.connectionInfo?.remoteAddress.address ?? '';
      final port = data['port'] ?? 54322;

      final token = LanPairingPayload.generateOneTimeToken();
      final now = DateTime.now().millisecondsSinceEpoch;
      final device = LanDevice(
        deviceId: remoteDeviceId,
        userId: remoteUserId,
        deviceName: remoteDeviceName,
        ip: ip,
        port: port,
        lastSeen: now,
      );

      _incomingPendingRequests[remoteDeviceId] = device;
      _incomingPendingTokens[remoteDeviceId] = (
        token: token,
        expiresAt: now + _pendingRequestTtlMs,
      );

      _incomingRequestCtrl.add(device);

      await _writeEncryptedJson(req, sessionKey, {
        'pending': true,
        'token': token,
      });
      return;
    }

    if (action == 'confirm' ||
        action == 'quick_pair' ||
        action == 'auto_sync') {
      if (action == 'confirm') {
        final pendingDevice = _outgoingPendingRequests[remoteDeviceId];
        final pendingEntry = _outgoingPendingTokens[remoteDeviceId];
        final receivedToken = data['token']?.toString() ?? '';
        final now = DateTime.now().millisecondsSinceEpoch;

        if (pendingDevice == null ||
            pendingEntry == null ||
            now > pendingEntry.expiresAt ||
            receivedToken.isEmpty ||
            !_constantTimeTokenEquals(receivedToken, pendingEntry.token)) {
          await _writeEncryptedError(
            req,
            sessionKey,
            '对方没有待处理的同步请求，请重新发起',
            statusCode: HttpStatus.forbidden,
          );
          return;
        }
        _outgoingPendingRequests.remove(remoteDeviceId);
        _outgoingPendingTokens.remove(remoteDeviceId);
      } else if (action == 'quick_pair') {
        final receivedToken = data['token']?.toString() ?? '';
        final now = DateTime.now().millisecondsSinceEpoch;
        if (_activeQuickPairToken == null ||
            receivedToken.isEmpty ||
            !_constantTimeTokenEquals(receivedToken, _activeQuickPairToken!) ||
            now > _activeQuickPairExpiresAt) {
          await _writeEncryptedError(
            req,
            sessionKey,
            '配对二维码已过期或失效，请重新生成',
            statusCode: HttpStatus.unauthorized,
          );
          return;
        }
        // 一次性令牌用完即销毁，防止重放。
        cancelQuickPairSession();
      } else if (action == 'auto_sync') {
        final isDirectAccount = LanDiscoveryIdentity.isDirectSameAccount(
          remoteUserId,
          _currentUserId,
        );
        final isTrustedPeer =
            remoteDeviceId.isNotEmpty &&
            _trustedPeerDeviceIds.contains(remoteDeviceId);
        if (!_autoSyncEnabled || (!isDirectAccount && !isTrustedPeer)) {
          await _writeEncryptedError(
            req,
            sessionKey,
            '对方设备未开启自动同步，请在对方“局域网同步”设置中开启“自动同步”',
            statusCode: HttpStatus.forbidden,
          );
          return;
        }
      }

      if (action == 'confirm' || action == 'quick_pair') {
        await _trustPeerDevice(remoteDeviceId);
      }

      final isSilent = action == 'auto_sync';
      if (!isSilent) {
        _emitProgress('正在接收数据...');
        _emitProgressValue(0.1);
      }

      final requestedConfig = _parseSyncConfig(data['config']);
      final syncConfig = action == 'confirm'
          ? LanSyncConfig(
              syncTodos: requestedConfig.syncTodos && _currentConfig.syncTodos,
              syncCountdowns:
                  requestedConfig.syncCountdowns &&
                  _currentConfig.syncCountdowns,
              syncTimeLogs:
                  requestedConfig.syncTimeLogs && _currentConfig.syncTimeLogs,
              syncPomodoroTags:
                  requestedConfig.syncPomodoroTags &&
                  _currentConfig.syncPomodoroTags,
              syncPomodoroRecords:
                  requestedConfig.syncPomodoroRecords &&
                  _currentConfig.syncPomodoroRecords,
              syncCourses:
                  requestedConfig.syncCourses && _currentConfig.syncCourses,
              syncSecrets:
                  requestedConfig.syncSecrets && _currentConfig.syncSecrets,
              syncSettings:
                  requestedConfig.syncSettings && _currentConfig.syncSettings,
            )
          : LanSyncConfig(
              syncTodos: requestedConfig.syncTodos,
              syncCountdowns: requestedConfig.syncCountdowns,
              syncTimeLogs: requestedConfig.syncTimeLogs,
              syncPomodoroTags: requestedConfig.syncPomodoroTags,
              syncPomodoroRecords: requestedConfig.syncPomodoroRecords,
              syncCourses: requestedConfig.syncCourses,
              syncSecrets: requestedConfig.syncSecrets && _syncSecretsEnabled,
              syncSettings:
                  requestedConfig.syncSettings && _syncSettingsEnabled,
            );
      final username = _currentUserId ?? 'local';
      final mergeCounts = await _mergeSyncBundle(
        username: username,
        data: data,
        config: syncConfig,
        emitProgress: !isSilent,
      );

      final localData = await _gatherLocalData(username, syncConfig);
      await _writeEncryptedJson(req, sessionKey, {
        'success': true,
        'todos': syncConfig.syncTodos ? localData['todos'] : [],
        'countdowns': syncConfig.syncCountdowns ? localData['countdowns'] : [],
        'timeLogs': syncConfig.syncTimeLogs ? localData['timeLogs'] : [],
        'pomodoroTags': syncConfig.syncPomodoroTags
            ? localData['pomodoroTags']
            : [],
        'pomodoroRecords': syncConfig.syncPomodoroRecords
            ? localData['pomodoroRecords']
            : [],
        'courses': syncConfig.syncCourses ? localData['courses'] : [],
        if (syncConfig.syncSecrets && localData['secrets'] != null)
          'secrets': localData['secrets'],
        if (syncConfig.syncSettings && localData['settings'] != null)
          'settings': localData['settings'],
      });

      final result = LanSyncResult(
        success: true,
        message: action == 'quick_pair'
            ? '面对面同步成功（$remoteDeviceName）'
            : action == 'auto_sync'
            ? '局域网自动同步完成（$remoteDeviceName）'
            : '局域网同步完成（$remoteDeviceName）',
        todosSynced: mergeCounts.todos,
        countdownsSynced: mergeCounts.countdowns,
        timeLogsSynced: mergeCounts.timeLogs,
        pomodoroTagsSynced: mergeCounts.pomodoroTags,
        pomodoroRecordsSynced: mergeCounts.pomodoroRecords,
        coursesSynced: mergeCounts.courses,
        progress: 1.0,
      );
      if (action == 'quick_pair' && !_quickPairCompletedCtrl.isClosed) {
        _quickPairCompletedCtrl.add(result);
      }
      if (!_syncCompletedCtrl.isClosed) {
        _syncCompletedCtrl.add(result);
      }

      if (!isSilent) {
        _emitProgressValue(1.0);
        _emitProgress('同步完成');
      }
      return;
    }
  }

  @override
  Future<void> _writeEncryptedJson(
    HttpRequest req,
    Uint8List sessionKey,
    Map<String, dynamic> body, {
    int statusCode = HttpStatus.ok,
  }) async {
    req.response.statusCode = statusCode;
    req.response.headers.contentType = ContentType.json;
    req.response.write(
      jsonEncode({
        'v': LanSyncCrypto.protocolVersion,
        'encrypted': true,
        'payload': await LanSyncCrypto.encryptStringAsync(
          sessionKey,
          jsonEncode(body),
        ),
      }),
    );
    await req.response.close();
  }

  @override
  Future<void> _writeEncryptedError(
    HttpRequest req,
    Uint8List sessionKey,
    String message, {
    int statusCode = HttpStatus.ok,
  }) async {
    await _writeEncryptedJson(req, sessionKey, {
      'error': message,
    }, statusCode: statusCode);
  }

  LanSyncConfig _parseSyncConfig(dynamic raw) {
    if (raw is! Map) return LanSyncConfig();
    return LanSyncConfig(
      syncTodos: raw['todos'] ?? true,
      syncCountdowns: raw['countdowns'] ?? true,
      syncTimeLogs: raw['timeLogs'] ?? true,
      syncPomodoroTags: raw['pomodoroTags'] ?? true,
      syncPomodoroRecords: raw['pomodoroRecords'] ?? true,
      syncCourses: raw['courses'] ?? true,
      syncSecrets: raw['secrets'] ?? true,
      syncSettings: raw['settings'] ?? false,
    );
  }
}
