part of 'api_service.dart';

Future<List<dynamic>> _apiTeamFetchTeams() async {
  final result = await ApiService.fetchTeamsWithStatus();
  return result.teams;
}

Future<({bool succeeded, List<dynamic> teams})> _apiTeamFetchTeamsWithStatus({
  http.Client? client,
}) async {
  try {
    final response = await ApiService._request(
      'GET',
      '/api/teams',
      client: client,
    );
    if (response.statusCode != 200) {
      return (succeeded: false, teams: const <dynamic>[]);
    }

    final data = jsonDecode(response.body);
    if (data is! Map || data['success'] == false) {
      return (succeeded: false, teams: const <dynamic>[]);
    }
    final rawTeams = data['teams'];
    if (rawTeams == null) return (succeeded: true, teams: const <dynamic>[]);
    if (rawTeams is! List) {
      return (succeeded: false, teams: const <dynamic>[]);
    }
    return (succeeded: true, teams: List<dynamic>.from(rawTeams));
  } catch (_) {
    return (succeeded: false, teams: const <dynamic>[]);
  }
}

Future<Map<String, dynamic>> _apiTeamCreateTeam(String name) async {
  try {
    final response = await ApiService._request(
      'POST',
      '/api/teams/create',
      body: {'name': name},
    );
    return jsonDecode(response.body);
  } catch (e) {
    return {'success': false, 'error': e.toString()};
  }
}

Future<Map<String, dynamic>> _apiTeamGenerateInviteCode(String teamUuid) async {
  try {
    final response = await ApiService._request(
      'POST',
      '/api/teams/invite',
      body: {'team_uuid': teamUuid},
    );
    return jsonDecode(response.body);
  } catch (e) {
    return {'success': false, 'error': e.toString()};
  }
}

Future<Map<String, dynamic>> _apiTeamAddTeamMemberByEmail(
  String teamUuid,
  String email,
) async {
  try {
    final response = await ApiService._request(
      'POST',
      '/api/teams/members/add',
      body: {'team_uuid': teamUuid, 'email': email},
    );
    return jsonDecode(response.body);
  } catch (e) {
    return {'success': false, 'error': e.toString()};
  }
}

Future<Map<String, dynamic>> _apiTeamJoinTeamByCode(String code) async {
  try {
    final response = await ApiService._request(
      'POST',
      '/api/teams/join',
      body: {'code': code},
    );
    return jsonDecode(response.body);
  } catch (e) {
    return {'success': false, 'error': e.toString()};
  }
}

Future<Map<String, dynamic>> _apiTeamDeleteTeam(String teamUuid) async {
  try {
    final response = await ApiService._request(
      'POST',
      '/api/teams/delete',
      body: {'team_uuid': teamUuid},
    );
    return jsonDecode(response.body);
  } catch (e) {
    return {'success': false, 'error': e.toString()};
  }
}

Future<Map<String, dynamic>> _apiTeamSelfCompleteTodo(String todoUuid) async {
  try {
    final response = await ApiService._request(
      'POST',
      '/api/teams/self_complete_todo',
      body: {'todo_uuid': todoUuid},
    );
    return jsonDecode(response.body);
  } catch (e) {
    return {'success': false, 'error': e.toString()};
  }
}

Future<Map<String, dynamic>> _apiTeamSelfResetTodo(String todoUuid) async {
  try {
    final response = await ApiService._request(
      'POST',
      '/api/teams/self_reset_todo',
      body: {'todo_uuid': todoUuid},
    );
    return jsonDecode(response.body);
  } catch (e) {
    return {'success': false, 'error': e.toString()};
  }
}

Future<Map<String, dynamic>> _apiTeamGetTodoStatus(String todoUuid) async {
  try {
    final response = await ApiService._request(
      'GET',
      '/api/teams/todo_status?todo_uuid=$todoUuid',
    );
    return jsonDecode(response.body);
  } catch (e) {
    return {'success': false, 'error': e.toString()};
  }
}

Future<Map<String, dynamic>> _apiTeamLeaveTeam(String teamUuid) async {
  try {
    final response = await ApiService._request(
      'POST',
      '/api/teams/leave',
      body: {'team_uuid': teamUuid},
    );
    return jsonDecode(response.body);
  } catch (e) {
    return {'success': false, 'error': e.toString()};
  }
}

Future<List<dynamic>> _apiTeamFetchTeamMembers(String teamUuid) async {
  try {
    final response = await ApiService._request(
      'GET',
      '/api/teams/members?team_uuid=$teamUuid',
    );
    final data = jsonDecode(response.body);
    return data['members'] ?? [];
  } catch (e) {
    return [];
  }
}

Future<Map<String, dynamic>> _apiTeamRemoveTeamMember(
  String teamUuid,
  int targetUserId,
) async {
  try {
    final response = await ApiService._request(
      'POST',
      '/api/teams/members/remove',
      body: {'team_uuid': teamUuid, 'target_user_id': targetUserId},
    );
    return jsonDecode(response.body);
  } catch (e) {
    return {'success': false, 'error': e.toString()};
  }
}

Future<Map<String, dynamic>> _apiTeamGetPoWChallenge() async {
  try {
    final response = await ApiService._request(
      'GET',
      '/api/auth/pow_challenge',
    );
    return jsonDecode(response.body);
  } catch (e) {
    return {'success': false, 'error': e.toString()};
  }
}

String? _apiTeamCalculatePoW(String challenge, int difficulty) {
  String prefix = '0' * difficulty;
  int nonce = 0;
  while (true) {
    String content = challenge + nonce.toString();
    String hash = sha256.convert(utf8.encode(content)).toString();
    if (hash.startsWith(prefix)) return nonce.toString();
    nonce++;
    if (nonce > 1000000) return null; // 安全限制，防止死循环
  }
}

Future<Map<String, dynamic>> _apiTeamRequestJoinTeam(
  String code, {
  String message = '',
}) async {
  try {
    final normalizedCode = code.trim().toUpperCase();
    if (normalizedCode.isEmpty) {
      return {'success': false, 'error': '邀请码不能为空'};
    }

    // 1. 获取挑战
    final challengeRes = await ApiService.getPoWChallenge();
    if (challengeRes['success'] != true) return challengeRes;

    final challenge = challengeRes['challenge'];
    final difficulty = challengeRes['difficulty'] ?? 4;

    // 2. 计算 PoW
    final nonce = _apiTeamCalculatePoW(challenge, difficulty);
    if (nonce == null) return {'success': false, 'error': '算力验证失败'};

    // 3. 提交申请
    final response = await ApiService._request(
      'POST',
      '/api/teams/request_join',
      body: {
        'invite_code': normalizedCode,
        'message': message,
        'pow_challenge': challenge,
        'pow_nonce': nonce,
      },
    );
    return jsonDecode(response.body);
  } catch (e) {
    return {'success': false, 'error': e.toString()};
  }
}

Future<List<dynamic>> _apiTeamFetchPendingRequests(String teamUuid) async {
  try {
    final response = await ApiService._request(
      'GET',
      '/api/teams/pending_requests?team_uuid=$teamUuid',
    );
    final data = jsonDecode(response.body);
    return data['requests'] ?? [];
  } catch (e) {
    return [];
  }
}

Future<Map<String, dynamic>> _apiTeamProcessJoinRequest(
  String teamUuid,
  int targetUserId,
  String action,
) async {
  try {
    const allowedActions = {'approve', 'reject'};
    if (!allowedActions.contains(action)) {
      return {'success': false, 'error': '无效操作: $action'};
    }

    final response = await ApiService._request(
      'POST',
      '/api/teams/process_request',
      body: {
        'team_uuid': teamUuid,
        'target_user_id': targetUserId,
        'action': action,
      },
    );
    return jsonDecode(response.body);
  } catch (e) {
    return {'success': false, 'error': e.toString()};
  }
}

Future<List<dynamic>> _apiTeamFetchMyInvitations() async {
  try {
    final response = await ApiService._request('GET', '/api/teams/invitations');
    final data = jsonDecode(response.body);
    return data['invitations'] ?? [];
  } catch (e) {
    return [];
  }
}

Future<Map<String, dynamic>> _apiTeamRespondToInvitation(
  String teamUuid,
  String action,
) async {
  try {
    const allowedActions = {'accept', 'decline'};
    if (!allowedActions.contains(action)) {
      return {'success': false, 'error': '无效操作: $action'};
    }

    final response = await ApiService._request(
      'POST',
      '/api/teams/respond_invitation',
      body: {'team_uuid': teamUuid, 'action': action},
    );
    return jsonDecode(response.body);
  } catch (e) {
    return {'success': false, 'error': e.toString()};
  }
}

Future<Map<String, dynamic>> _apiTeamFetchTeamSystemMessages(
  String teamUuid, {
  int? limit,
  int? offset,
}) async {
  try {
    final paging = [
      if (limit != null) 'limit=$limit',
      if (offset != null) 'offset=$offset',
    ].join('&');
    final response = await ApiService._request(
      'GET',
      '/api/teams/system_messages?team_uuid=$teamUuid${paging.isEmpty ? '' : '&$paging'}',
    );
    return jsonDecode(response.body);
  } catch (e) {
    return {'success': false, 'error': e.toString()};
  }
}

Future<Map<String, dynamic>> _apiTeamCreateTeamAnnouncement(
  String teamUuid,
  String title,
  String content, {
  bool isPriority = false,
  int? expiresAt,
}) async {
  try {
    final response = await ApiService._request(
      'POST',
      '/api/teams/announcements/create',
      body: {
        'team_uuid': teamUuid,
        'title': title,
        'content': content,
        'is_priority': isPriority ? 1 : 0,
        'expires_at': expiresAt,
      },
    );
    return jsonDecode(response.body);
  } catch (e) {
    return {'success': false, 'error': e.toString()};
  }
}

Future<Map<String, dynamic>> _apiTeamDeleteTeamAnnouncement(
  String announcementUuid, {
  String? teamUuid,
}) async {
  try {
    final response = await ApiService._request(
      'POST',
      '/api/teams/announcements/delete',
      body: {
        'uuid': announcementUuid,
        'announcement_uuid': announcementUuid,
        if (teamUuid != null && teamUuid.isNotEmpty) 'team_uuid': teamUuid,
      },
    );
    return jsonDecode(response.body);
  } catch (e) {
    return {'success': false, 'error': e.toString()};
  }
}

Future<List<dynamic>> _apiTeamFetchTeamAnnouncements(String teamUuid) async {
  try {
    final response = await ApiService._request(
      'GET',
      '/api/teams/announcements?team_uuid=$teamUuid',
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['announcements'] ?? [];
    }
    return [];
  } catch (e) {
    return [];
  }
}

Future<Map<String, dynamic>> _apiTeamMarkAnnouncementAsRead(
  String announcementUuid,
) async {
  try {
    final response = await ApiService._request(
      'POST',
      '/api/teams/announcements/read',
      body: {'uuid': announcementUuid, 'announcement_uuid': announcementUuid},
    );
    return jsonDecode(response.body);
  } catch (e) {
    return {'success': false, 'error': e.toString()};
  }
}

Future<Map<String, dynamic>> _apiTeamFetchAnnouncementStats(
  String announcementUuid,
) async {
  try {
    final response = await ApiService._request(
      'GET',
      '/api/teams/announcements/stats?announcement_uuid=$announcementUuid',
    );
    return jsonDecode(response.body);
  } catch (e) {
    return {'success': false, 'error': e.toString()};
  }
}

Future<List<dynamic>> _apiTeamFetchUnreadPriorityAnnouncements() async {
  try {
    final response = await ApiService._request(
      'GET',
      '/api/teams/announcements/unread_priority',
    );
    final data = jsonDecode(response.body);
    return data['announcements'] ?? [];
  } catch (e) {
    return [];
  }
}

Future<Map<String, dynamic>> _apiTeamCreateTeamShare({
  required String teamUuid,
  String? title,
  String? description,
  bool shareTodos = true,
  bool shareSchedules = true,
  bool shareCountdowns = true,
  bool shareAnnouncements = true,
  String? password,
  int? expiresHours,
}) async {
  try {
    final body = <String, dynamic>{
      'team_uuid': teamUuid,
      'share_todos': shareTodos,
      'share_schedules': shareSchedules,
      'share_countdowns': shareCountdowns,
      'share_announcements': shareAnnouncements,
    };
    if (title != null) body['title'] = title;
    if (description != null) body['description'] = description;
    if (password != null && password.isNotEmpty) body['password'] = password;
    if (expiresHours != null) body['expires_hours'] = expiresHours;

    final response = await ApiService._request(
      'POST',
      '/api/teams/shares/create',
      body: body,
    );
    return jsonDecode(response.body);
  } catch (e) {
    return {'success': false, 'error': e.toString()};
  }
}

Future<List<dynamic>> _apiTeamFetchTeamShares(String teamUuid) async {
  try {
    final response = await ApiService._request(
      'GET',
      '/api/teams/shares?team_uuid=$teamUuid',
    );
    final data = jsonDecode(response.body);
    return data['shares'] ?? [];
  } catch (e) {
    return [];
  }
}

Future<Map<String, dynamic>> _apiTeamDeleteTeamShare(String shareCode) async {
  try {
    final response = await ApiService._request(
      'POST',
      '/api/teams/shares/delete',
      body: {'share_code': shareCode},
    );
    return jsonDecode(response.body);
  } catch (e) {
    return {'success': false, 'error': e.toString()};
  }
}

Future<Map<String, dynamic>> _apiTeamUpdateTeamShare({
  required String shareCode,
  required bool isActive,
}) async {
  try {
    final response = await ApiService._request(
      'POST',
      '/api/teams/shares/update',
      body: {'share_code': shareCode, 'is_active': isActive},
    );
    return jsonDecode(response.body);
  } catch (e) {
    return {'success': false, 'error': e.toString()};
  }
}

Future<Map<String, dynamic>> _apiTeamVerifyShareCode(
  String code,
  String? password,
) async {
  try {
    final body = <String, dynamic>{};
    if (password != null && password.isNotEmpty) body['password'] = password;

    final response = await ApiService._request(
      'POST',
      '/api/shares/$code/verify',
      body: body,
      includeAuth: false,
    );
    return jsonDecode(response.body);
  } catch (e) {
    return {'success': false, 'error': e.toString()};
  }
}

Future<Map<String, dynamic>> _apiTeamFetchShareData(
  String code, {
  String? token,
  bool includeHistory = false,
}) async {
  try {
    final tzOffsetMinutes = -DateTime.now().timeZoneOffset.inMinutes;
    final params = <String, String>{
      'tz_offset': tzOffsetMinutes.toString(),
      if (token != null && token.isNotEmpty) 'token': token,
      if (includeHistory) 'include_history': '1',
    };
    final query = Uri(queryParameters: params).query;
    final url = '${ApiService._effectiveBaseUrl}/api/shares/$code/data?$query';
    final response = await ApiService._request('GET', url, includeAuth: false);
    return jsonDecode(response.body);
  } catch (e) {
    return {'success': false, 'error': e.toString()};
  }
}

Future<Map<String, dynamic>> _apiTeamRequestJoinViaShare({
  required String shareCode,
  required String email,
  String? message,
  String? accessToken,
}) async {
  try {
    final response = await ApiService._request(
      'POST',
      '/api/shares/${Uri.encodeComponent(shareCode)}/request_join',
      body: {
        'email': email,
        if (message != null && message.isNotEmpty) 'message': message,
        if (accessToken != null && accessToken.isNotEmpty) 'token': accessToken,
      },
      includeAuth: false,
    );
    return jsonDecode(response.body);
  } catch (e) {
    return {'success': false, 'error': e.toString()};
  }
}

Future<List<dynamic>> _apiTeamFetchItemHistory(
  String uuid,
  String table,
) async {
  List<dynamic> combinedHistory = [];

  // 1. 尝试获取云端历史
  try {
    final response = await ApiService._request(
      'GET',
      '/api/sync/history?uuid=$uuid&table=$table',
      timeout: const Duration(seconds: 3),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      combinedHistory.addAll(data['history'] ?? []);
    } else if (response.statusCode == 403 || response.statusCode == 404) {
      // 后端权限收紧后，这两种状态是业务态，不当作网络异常
      //         debugPrint("🔒 云端历史访问受限(status=${response.statusCode})，继续展示本地历史");
    } else {
      //         debugPrint("⚠️ 云端历史接口异常(status=${response.statusCode})");
    }
  } catch (e) {
    //       debugPrint("🌐 云端历史不可用，切换至纯本地模式: $e");
  }

  // 2. 获取本地历史并合并
  try {
    final localLogs = await DatabaseHelper.instance.getLocalAuditLogs(
      uuid,
      table,
    );
    for (var log in localLogs) {
      // 转换本地格式为 UI 统一格式
      combinedHistory.add({
        'id': log['id'], // 注意：本地 ID 可能是 int
        'is_local': true, // 标记为本地记录
        'op_type': log['op_type'],
        'before_data': log['before_data'] != null
            ? jsonDecode(log['before_data'])
            : null,
        'after_data': log['after_data'] != null
            ? jsonDecode(log['after_data'])
            : null,
        'timestamp': log['timestamp'],
        'operator_name': log['operator_name'] ?? '本地修改',
      });
    }
  } catch (e) {
    //       debugPrint("⚠️ 获取本地历史失败: $e");
  }

  // 3. 排序：按时间倒序
  combinedHistory.sort(
    (a, b) => (b['timestamp'] as int).compareTo(a['timestamp'] as int),
  );
  return combinedHistory;
}

Future<Map<String, dynamic>> _apiTeamRollbackItem(
  dynamic logId, {
  bool isLocal = false,
  String? table,
  String? username,
}) async {
  // 🚀 如果是本地记录或处于离线状态，执行本地强力回滚（含缓存刷新）
  if (isLocal) {
    if (table == null || username == null) {
      return {'success': false, 'error': '缺少回滚上下文'};
    }
    final success = await StorageService.rollbackLocalItem(
      table,
      logId as int,
      username,
    );
    return {'success': success, 'message': success ? '本地回滚成功' : '本地回滚失败'};
  }

  try {
    final response = await ApiService._request(
      'POST',
      '/api/sync/rollback',
      body: {'log_id': logId},
    );

    final Map<String, dynamic> data = jsonDecode(response.body);
    if (response.statusCode == 403 || response.statusCode == 404) {
      return {'success': false, 'error': data['error'] ?? '无权限或记录不存在，无法回滚'};
    }
    return data;
  } catch (e) {
    return {'success': false, 'error': "网络错误，无法执行云端回滚"};
  }
}

Future<Map<String, dynamic>> _apiTeamResolveConflict({
  required String uuid,
  required String table,
  required String resolution, // 'keep_local' or 'accept_server'
  int? bumpedVersion,
  Map<String, dynamic>? data,
}) async {
  try {
    final body = <String, dynamic>{
      'uuid': uuid,
      'table': table,
      'resolution': resolution,
    };
    if (bumpedVersion != null) body['version'] = bumpedVersion;
    if (data != null) body['data'] = data;

    final response = await ApiService._request(
      'POST',
      '/api/sync/resolve_conflict',
      body: body,
      timeout: const Duration(seconds: 5),
    );

    final result = jsonDecode(response.body);
    if (response.statusCode == 200 && result['success'] == true) {
      return {'success': true};
    }
    return {'success': false, 'error': result['error'] ?? '请求失败'};
  } catch (e) {
    return {'success': false, 'error': "网络错误: $e"};
  }
}

Future<bool> _apiTeamMarkNotificationsRead(List<int> ids) async {
  if (ids.isEmpty) return true;
  try {
    final response = await ApiService._request(
      'POST',
      '/api/notifications/mark_read',
      body: {'ids': ids},
      timeout: const Duration(seconds: 5),
    );
    final data = jsonDecode(response.body);
    return response.statusCode == 200 && data['success'] == true;
  } catch (_) {
    return false;
  }
}
