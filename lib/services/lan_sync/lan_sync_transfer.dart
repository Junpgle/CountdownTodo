part of '../lan_sync_service_io.dart';

mixin _LanSyncTransferMixin on _LanSyncServiceBase {
  /// 首页手动触发局域网同步：向同账号在线局域网设备发起一次双向合并。
  Future<LanSyncResult> syncManualWithPeers({LanSyncConfig? config}) async {
    if (_isSyncing) return LanSyncResult(success: false, message: '同步进行中');
    await _ensureIdentity();

    final sameAccountPeers = _devices.values
        .where((d) => _isSameUser(d.userId, _currentUserId))
        .toList();

    if (sameAccountPeers.isEmpty) {
      await _discoverOnce(duration: const Duration(milliseconds: 2000));
    }

    final peers = _devices.values
        .where((d) => _isSameUser(d.userId, _currentUserId))
        .toList();
    if (peers.isEmpty) {
      return LanSyncResult(
        success: false,
        message: '未发现同账号在线局域网设备，请确认另一台设备已开启局域网服务并处于同一 Wi-Fi',
      );
    }

    LanSyncResult? lastSuccess;
    LanSyncResult? lastFailure;
    for (final peer in peers) {
      final res = await _performDirectSync(
        ip: peer.ip,
        port: peer.port,
        deviceName: peer.deviceName,
        action: 'auto_sync',
        config: config ?? LanSyncConfig(),
        silent: false,
      );
      if (res.success) {
        lastSuccess = res;
      } else {
        lastFailure = res;
      }
    }
    return lastSuccess ??
        lastFailure ??
        LanSyncResult(success: false, message: '局域网同步失败');
  }

  /// 面对面扫码/配对码直连互同步（无需等待手动确认弹窗）。
  Future<LanSyncResult> syncWithPairingCode(
    String rawCode, {
    LanSyncConfig? config,
  }) async {
    if (_isSyncing) return LanSyncResult(success: false, message: '同步进行中');
    final pairing = LanPairingPayload.tryParse(rawCode);
    if (pairing == null) {
      return LanSyncResult(success: false, message: '无效的配对二维码或配对码');
    }
    if (pairing.isExpired()) {
      return LanSyncResult(success: false, message: '配对二维码已过期，请让对方重新生成');
    }

    await _ensureIdentity();
    if (pairing.deviceId.isNotEmpty && pairing.deviceId == _currentDeviceId) {
      return LanSyncResult(success: false, message: '不能与当前设备自身配对');
    }

    return _performDirectSync(
      ip: pairing.ip,
      port: pairing.port,
      deviceName: pairing.deviceName,
      peerDeviceId: pairing.deviceId,
      action: 'quick_pair',
      token: pairing.token,
      config:
          config ??
          LanSyncConfig(
            syncSecrets: _syncSecretsEnabled,
            syncSettings: _syncSettingsEnabled,
          ),
      silent: false,
    );
  }

  @override
  Future<LanSyncResult> _autoSyncWithDevice(LanDevice device) async {
    if (_isSyncing) return LanSyncResult(success: false, message: '同步进行中');
    return _performDirectSync(
      ip: device.ip,
      port: device.port,
      deviceName: device.deviceName,
      peerDeviceId: device.deviceId,
      action: 'auto_sync',
      config: LanSyncConfig(
        syncSecrets: _syncSecretsEnabled,
        syncSettings: _syncSettingsEnabled,
      ),
      silent: true,
    );
  }

  Future<LanSyncResult> _performDirectSync({
    required String ip,
    required int port,
    required String deviceName,
    String? peerDeviceId,
    required String action,
    String? token,
    required LanSyncConfig config,
    required bool silent,
  }) async {
    _isSyncing = true;
    if (!silent) _emitProgressValue(0.05);
    HttpClient? client;
    try {
      if (!silent) _emitProgress('正在连接 $deviceName...');
      final username = _currentUserId ?? 'local';
      final localData = await _gatherLocalData(username, config);

      final payload = <String, dynamic>{
        'deviceId': _currentDeviceId,
        'userId': username,
        'deviceName': _currentDeviceName,
        'port': _serverPort ?? 0,
        'action': action,
        'token': ?token,
        'config': config.toJson(),
        'todos': config.syncTodos ? localData['todos'] : [],
        'countdowns': config.syncCountdowns ? localData['countdowns'] : [],
        'timeLogs': config.syncTimeLogs ? localData['timeLogs'] : [],
        'pomodoroTags': config.syncPomodoroTags
            ? localData['pomodoroTags']
            : [],
        'pomodoroRecords': config.syncPomodoroRecords
            ? localData['pomodoroRecords']
            : [],
        'courses': config.syncCourses ? localData['courses'] : [],
        if (config.syncSecrets && localData['secrets'] != null)
          'secrets': localData['secrets'],
        if (config.syncSettings && localData['settings'] != null)
          'settings': localData['settings'],
      };

      if (!silent) {
        _emitProgress('正在交换加密数据...');
        _emitProgressValue(0.2);
      }

      client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      final responseData = await _postEncryptedSync(client, ip, port, payload);
      if (responseData['success'] != true) {
        return LanSyncResult(
          success: false,
          message: _localizePeerError(responseData['error']?.toString()),
        );
      }

      if (!silent) {
        _emitProgress('正在按 LWW 规则合并数据...');
        _emitProgressValue(0.6);
      }

      final counts = await _mergeSyncBundle(
        username: username,
        data: responseData,
        config: config,
        emitProgress: !silent,
      );

      if (action == 'quick_pair') {
        await _trustPeerDevice(peerDeviceId);
      }

      if (!silent) {
        _emitProgressValue(1.0);
        _emitProgress('同步完成');
      } else {
        _emitStatus('已与 $deviceName 自动同步');
      }

      final result = LanSyncResult(
        success: true,
        message: action == 'quick_pair'
            ? '面对面局域网同步成功（$deviceName）'
            : silent
            ? '局域网自动同步成功（$deviceName）'
            : '局域网同步成功（$deviceName）',
        todosSynced: counts.todos,
        countdownsSynced: counts.countdowns,
        timeLogsSynced: counts.timeLogs,
        pomodoroTagsSynced: counts.pomodoroTags,
        pomodoroRecordsSynced: counts.pomodoroRecords,
        coursesSynced: counts.courses,
        progress: 1.0,
      );
      if (!_syncCompletedCtrl.isClosed) {
        _syncCompletedCtrl.add(result);
      }
      return result;
    } catch (e) {
      return LanSyncResult(success: false, message: '连接失败: $e');
    } finally {
      client?.close(force: true);
      _isSyncing = false;
    }
  }

  Future<LanSyncResult> syncWithDevice(
    LanDevice device, {
    LanSyncConfig? config,
  }) async {
    if (_isSyncing) return LanSyncResult(success: false, message: '同步进行中');
    _isSyncing = true;
    _currentConfig = config ?? LanSyncConfig();
    // A retry must never inherit the previous request's confirmation token.
    _outgoingPendingRequests.remove(device.deviceId);
    _outgoingPendingTokens.remove(device.deviceId);
    _emitProgressValue(0);
    HttpClient? client;

    try {
      _emitProgress('正在请求连接 ${device.deviceName}...');

      client = HttpClient();

      final requestPayload = {
        'deviceId': _currentDeviceId,
        'userId': _currentUserId,
        'deviceName': _currentDeviceName,
        'port': _serverPort,
        'action': 'request',
      };

      final data = await _postEncryptedSync(
        client,
        device.ip,
        device.port,
        requestPayload,
      );

      String errorMsg = '连接被拒绝';
      if (data['pending'] == true) {
        final token = data['token']?.toString();
        if (token == null || token.isEmpty) {
          errorMsg = '连接失败: 对方返回的确认令牌无效';
        } else {
          // The receiver stores the incoming request under our device ID.
          // Mirror that pending state here so the receiver's later
          // `confirm` request can be accepted by this device's server.
          _outgoingPendingRequests[device.deviceId] = device.copyWith(
            pendingApproval: true,
          );
          _outgoingPendingTokens[device.deviceId] = (
            token: token,
            expiresAt:
                DateTime.now().millisecondsSinceEpoch + _pendingRequestTtlMs,
          );
          _emitProgress('等待对方确认...');
          return LanSyncResult(success: false, message: '等待对方确认');
        }
      }
      if (data['error'] != null) {
        errorMsg = _localizePeerError(
          data['error'].toString(),
          fallback: errorMsg,
        );
      }

      return LanSyncResult(success: false, message: errorMsg);
    } catch (e) {
      return LanSyncResult(success: false, message: '连接失败: $e');
    } finally {
      client?.close(force: true);
      _isSyncing = false;
    }
  }

  Future<LanSyncResult> confirmAndSync(
    LanDevice device, {
    LanSyncConfig? config,
  }) async {
    if (_isSyncing) return LanSyncResult(success: false, message: '同步进行中');
    final pendingEntry = _incomingPendingTokens[device.deviceId];
    final now = DateTime.now().millisecondsSinceEpoch;
    if (pendingEntry == null || now > pendingEntry.expiresAt) {
      _incomingPendingRequests.remove(device.deviceId);
      _incomingPendingTokens.remove(device.deviceId);
      return LanSyncResult(success: false, message: '确认令牌已失效，请重新发起同步');
    }
    _isSyncing = true;
    _currentConfig = config ?? LanSyncConfig();
    _currentPendingToken = pendingEntry.token;
    _emitProgressValue(0);
    HttpClient? client;

    try {
      _emitProgress('正在连接 ${device.deviceName}...');
      _emitProgressValue(0.05);

      final username = _currentUserId!;
      final localData = await _gatherLocalData(username, _currentConfig);

      final payload = {
        'deviceId': _currentDeviceId,
        'userId': _currentUserId,
        'deviceName': _currentDeviceName,
        'port': _serverPort,
        'action': 'confirm',
        'token': _currentPendingToken,
        'config': _currentConfig.toJson(),
        'todos': _currentConfig.syncTodos ? localData['todos'] : [],
        'countdowns': _currentConfig.syncCountdowns
            ? localData['countdowns']
            : [],
        'timeLogs': _currentConfig.syncTimeLogs ? localData['timeLogs'] : [],
        'pomodoroTags': _currentConfig.syncPomodoroTags
            ? localData['pomodoroTags']
            : [],
        'pomodoroRecords': _currentConfig.syncPomodoroRecords
            ? localData['pomodoroRecords']
            : [],
        'courses': _currentConfig.syncCourses ? localData['courses'] : [],
        if (_currentConfig.syncSecrets && localData['secrets'] != null)
          'secrets': localData['secrets'],
        if (_currentConfig.syncSettings && localData['settings'] != null)
          'settings': localData['settings'],
      };

      _emitProgress('正在发送加密数据...');
      _emitProgressValue(0.1);

      client = HttpClient();

      final responseData = await _postEncryptedSync(
        client,
        device.ip,
        device.port,
        payload,
      );

      if (responseData['success'] != true) {
        return LanSyncResult(
          success: false,
          message:
              '同步失败: ${_localizePeerError(responseData['error']?.toString())}',
        );
      }

      _emitProgress('正在合并远程数据...');
      _emitProgressValue(0.6);

      final remoteTodos =
          (responseData['todos'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          [];
      final remoteCountdowns =
          (responseData['countdowns'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          [];
      final remoteTimeLogs =
          (responseData['timeLogs'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          [];
      final remotePomodoroTags =
          (responseData['pomodoroTags'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          [];
      final remotePomodoroRecords =
          (responseData['pomodoroRecords'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          [];
      final remoteCourses =
          (responseData['courses'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          [];

      int todosSynced = 0,
          countdownsSynced = 0,
          timeLogsSynced = 0,
          pomodoroTagsSynced = 0,
          pomodoroRecordsSynced = 0,
          coursesSynced = 0;

      await _mergeTodos(username, remoteTodos, (count) => todosSynced = count);
      await _mergeCountdowns(
        username,
        remoteCountdowns,
        (count) => countdownsSynced = count,
      );
      await _mergeTimeLogs(
        username,
        remoteTimeLogs,
        (count) => timeLogsSynced = count,
      );
      await _mergePomodoroTags(
        remotePomodoroTags,
        (count) => pomodoroTagsSynced = count,
      );
      await _mergePomodoroRecords(
        remotePomodoroRecords,
        (count) => pomodoroRecordsSynced = count,
      );
      await _mergeCourses(
        username,
        remoteCourses,
        (count) => coursesSynced = count,
      );
      if (_currentConfig.syncSecrets && responseData['secrets'] is Map) {
        await LanSyncPrivateData.mergeSecrets(
          Map<String, dynamic>.from(responseData['secrets'] as Map),
        );
      }
      if (_currentConfig.syncSettings && responseData['settings'] is Map) {
        await LanSyncPrivateData.mergePortableSettings(
          Map<String, dynamic>.from(responseData['settings'] as Map),
        );
      }
      _emitProgressValue(1.0);
      _incomingPendingRequests.remove(device.deviceId);
      _incomingPendingTokens.remove(device.deviceId);
      await _trustPeerDevice(device.deviceId);

      return LanSyncResult(
        success: true,
        message: '同步成功（AES加密）',
        todosSynced: todosSynced,
        countdownsSynced: countdownsSynced,
        timeLogsSynced: timeLogsSynced,
        pomodoroTagsSynced: pomodoroTagsSynced,
        pomodoroRecordsSynced: pomodoroRecordsSynced,
        coursesSynced: coursesSynced,
        progress: 1.0,
      );
    } catch (e) {
      return LanSyncResult(success: false, message: '连接失败: $e');
    } finally {
      client?.close(force: true);
      _isSyncing = false;
    }
  }

  @override
  Future<void> _handleFileRequest(HttpRequest req) async {
    IOSink? sink;
    File? partialFile;
    try {
      final version = req.headers.value('x-lan-encrypted');
      final sessionId = req.headers.value('x-lan-session');
      final sessionKey = _getSessionKey(sessionId);
      if (version != 'v2' || sessionKey == null) {
        req.response.statusCode = HttpStatus.unauthorized;
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({'error': '需要 v2 加密会话，请升级应用版本'}));
        await req.response.close();
        return;
      }

      final senderDeviceId = req.headers.value('x-lan-device-id')?.trim() ?? '';
      final senderUserId = req.headers.value('x-lan-user-id')?.trim() ?? '';
      final isDirectAccount = LanDiscoveryIdentity.isDirectSameAccount(
        senderUserId,
        _currentUserId,
      );
      final isTrustedPeer =
          senderDeviceId.isNotEmpty &&
          _trustedPeerDeviceIds.contains(senderDeviceId);
      final isAllowedDiscoveryPeer =
          _discoverAllDevices &&
          senderDeviceId.isNotEmpty &&
          _devices.containsKey(senderDeviceId);
      if (!isDirectAccount && !isTrustedPeer && !isAllowedDiscoveryPeer) {
        await _writeEncryptedError(
          req,
          sessionKey,
          '未授权的文件传输请求',
          statusCode: HttpStatus.forbidden,
        );
        return;
      }

      if (req.contentLength > _maxReceiveFileBytes) {
        await _writeEncryptedError(
          req,
          sessionKey,
          '接收文件超过大小限制',
          statusCode: HttpStatus.requestEntityTooLarge,
        );
        return;
      }

      final rawName = req.uri.queryParameters['name'] ?? 'unknown_file';
      var fileName = p
          .basename(rawName)
          .replaceAll(_rxCached32_1, '_')
          .replaceFirst(_rxCached32_2, '');
      if (fileName.isEmpty || fileName == '.' || fileName == '..') {
        fileName = 'received_file';
      }

      final deviceName = req.uri.queryParameters['device'] ?? '未知设备';

      _emitProgress('正在接收来自 $deviceName 的加密文件: $fileName');
      _emitProgressValue(0.1);

      final tempDir = await getTemporaryDirectory();
      if (!await tempDir.exists()) {
        await tempDir.create(recursive: true);
      }
      final file = File(p.join(tempDir.path, fileName));
      if (!p.isWithin(tempDir.path, file.path)) {
        await _writeEncryptedError(
          req,
          sessionKey,
          '非法文件名',
          statusCode: HttpStatus.badRequest,
        );
        return;
      }
      partialFile = file;
      sink = file.openWrite();

      int received = 0;
      final total = req.contentLength;
      final buffer = BytesBuilder(copy: false);
      var bufferBytes = Uint8List(0);
      int offset = 0;
      int chunkIndex = 0;
      const maxFrameSize =
          LanSyncCrypto.maxFileChunkSize + LanSyncCrypto.nonceLength + 16;

      await for (final chunk in req) {
        received += chunk.length;
        if (received > _maxReceiveFileBytes) {
          throw const FormatException('File exceeds maximum allowed size');
        }
        if (total > 0) {
          _emitProgressValue(0.1 + (received / total) * 0.9);
        }

        if (offset < bufferBytes.length) {
          buffer.add(Uint8List.sublistView(bufferBytes, offset));
        }
        buffer.add(chunk);
        bufferBytes = buffer.takeBytes();
        offset = 0;

        while (bufferBytes.length - offset >= 4) {
          final frameLen = ByteData.sublistView(
            bufferBytes,
            offset,
            offset + 4,
          ).getUint32(0, Endian.big);
          if (frameLen == 0 || frameLen > maxFrameSize) {
            throw const FormatException('Invalid encrypted file frame length');
          }
          if (bufferBytes.length - offset < 4 + frameLen) {
            break;
          }
          final sealedPayload = Uint8List.sublistView(
            bufferBytes,
            offset + 4,
            offset + 4 + frameLen,
          );
          final plainChunk = await LanSyncCrypto.decodeFileFramePayloadAsync(
            sessionKey,
            chunkIndex++,
            sealedPayload,
          );
          sink.add(plainChunk);
          offset += 4 + frameLen;
        }
      }

      if (offset != bufferBytes.length) {
        throw const FormatException('Truncated encrypted file frame');
      }

      await sink.close();
      sink = null;
      partialFile = null;

      _emitProgress('加密文件接收完成: $fileName');
      _emitProgressValue(1.0);

      _fileReceivedCtrl.add({
        'name': fileName,
        'path': file.path,
        'from': deviceName,
      });

      await _writeEncryptedJson(req, sessionKey, {'success': true});
    } catch (e) {
      await sink?.close();
      try {
        if (partialFile != null && await partialFile.exists()) {
          await partialFile.delete();
        }
      } catch (_) {}
      // debugPrint('[LanSync] File receive error: $e');
      req.response.statusCode = HttpStatus.internalServerError;
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode({'error': e.toString()}));
      await req.response.close();
    }
  }

  Future<LanSyncResult> sendFilePath(LanDevice device, String path) {
    return sendFile(device, File(path));
  }

  Future<LanSyncResult> sendFile(LanDevice device, File file) async {
    if (_isSyncing) return LanSyncResult(success: false, message: '同步进行中');
    _isSyncing = true;
    _emitProgressValue(0);
    HttpClient? client;
    RandomAccessFile? raf;

    try {
      final fileName = p.basename(file.path);
      _emitProgress('正在建立加密通道并发送文件: $fileName');

      client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);

      final session = await _performHandshake(client, device.ip, device.port);

      final uri = Uri.parse('http://${device.ip}:${device.port}/file').replace(
        queryParameters: {
          'name': fileName,
          'device': _currentDeviceName ?? '未知设备',
        },
      );

      final request = await client.postUrl(uri);
      request.headers.set('X-Lan-Session', session.sessionId);
      request.headers.set('X-Lan-Encrypted', 'v2');
      request.headers.set('X-Lan-Device-Id', _currentDeviceId ?? '');
      request.headers.set('X-Lan-User-Id', _currentUserId ?? '');

      final total = await file.length();
      raf = await file.open();
      int sent = 0;
      int chunkIndex = 0;

      while (true) {
        final plainChunk = await raf.read(LanSyncCrypto.maxFileChunkSize);
        if (plainChunk.isEmpty) break;
        final frame = await LanSyncCrypto.encodeFileFrameAsync(
          session.key,
          chunkIndex++,
          plainChunk,
        );
        request.add(frame);
        sent += plainChunk.length;
        if (total > 0) {
          _emitProgressValue((sent / total) * 0.95);
        }
      }
      await raf.close();
      raf = null;

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode == HttpStatus.ok) {
        final respData = jsonDecode(body) as Map<String, dynamic>;
        if (respData['encrypted'] == true &&
            respData['v'] == LanSyncCrypto.protocolVersion) {
          final decrypted = jsonDecode(
            await LanSyncCrypto.decryptStringAsync(
              session.key,
              respData['payload'].toString(),
            ),
          ) as Map<String, dynamic>;
          if (decrypted['success'] == true) {
            _emitProgressValue(1.0);
            _emitProgress('文件发送成功（AES-GCM 加密）');
            return LanSyncResult(success: true, message: '文件发送成功');
          }
        }
        return LanSyncResult(success: false, message: '文件传输加密校验失败');
      } else {
        return LanSyncResult(
          success: false,
          message: '服务器响应错误: ${response.statusCode}',
        );
      }
    } catch (e) {
      return LanSyncResult(success: false, message: '发送失败: $e');
    } finally {
      await raf?.close();
      client?.close(force: true);
      _isSyncing = false;
    }
  }
}

// Cached RegExp patterns
final RegExp _rxCached32_1 = RegExp(r'[\\/:*?"<>|\x00-\x1F]');
final RegExp _rxCached32_2 = RegExp(r'^\.+');
