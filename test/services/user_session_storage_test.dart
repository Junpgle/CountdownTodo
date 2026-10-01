import 'package:countdown_todo/services/api_service.dart';
import 'package:countdown_todo/services/storage/user_session_storage.dart';
import 'package:countdown_todo/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('切换活动会话时同时更新认证令牌和用户 ID', () {
    final previousToken = ApiService.getToken();
    final previousUserId = ApiService.currentUserId;
    addTearDown(() {
      ApiService.setToken(previousToken ?? '');
      ApiService.currentUserId = previousUserId;
    });

    ApiService.currentUserId = 15;
    ApiService.setToken('old-server-token');
    ApiService.setSession(token: 'new-server-token', userId: 42);

    expect(ApiService.getToken(), 'new-server-token');
    expect(ApiService.currentUserId, 42);
  });

  test('restores the authenticated user id after a cold start', () async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'alice',
      'auth_session_token': 'token',
      'current_user_id': 42,
    });
    ApiService.currentUserId = 0;
    ApiService.setToken('');

    expect(await UserSessionStorage.getLoginSession(), 'alice');
    expect(ApiService.getToken(), 'token');
    expect(ApiService.currentUserId, 42);
  });

  test('does not restore an orphaned user id without an active session',
      () async {
    SharedPreferences.setMockInitialValues({
      'auth_session_token': 'stale-token',
      'current_user_id': 42,
    });
    ApiService.currentUserId = 99;

    expect(await UserSessionStorage.getLoginSession(), isNull);
    expect(ApiService.currentUserId, 0);
  });

  test('clearLoginSession clears identity and auth state together', () async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'alice',
      'auth_session_token': 'token',
      'current_user_id': 42,
      'last_screen_time_sync_alice': 123,
    });
    ApiService.currentUserId = 42;
    ApiService.setToken('token');

    await UserSessionStorage.clearLoginSession();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('current_login_user'), isNull);
    expect(prefs.getString('auth_session_token'), isNull);
    expect(prefs.getInt('current_user_id'), isNull);
    expect(prefs.getInt('last_screen_time_sync_alice'), isNull);
    expect(ApiService.getToken(), isEmpty);
    expect(ApiService.currentUserId, 0);
  });

  test(
      'legacy semester date is migrated once and not exposed to another account',
      () async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'alice',
      'semester_start_date': '2026-09-07T00:00:00.000',
    });

    final start = await StorageService.getSemesterStart();

    final prefs = await SharedPreferences.getInstance();
    expect(start, DateTime(2026, 9, 7));
    expect(prefs.getString('semester_start_date_alice'), isNotNull);
    expect(prefs.getString('semester_start_date'), isNull);

    await prefs.setString('current_login_user', 'bob');
    expect(await StorageService.getSemesterStart(), isNull);
  });

  test('captured session becomes invalid after an account switch', () async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'alice',
      'current_user_id': 42,
    });

    final snapshot = await UserSessionStorage.captureSession('alice');
    expect(snapshot, isNotNull);
    expect(await UserSessionStorage.isCurrentSession(snapshot!), isTrue);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('current_login_user', 'bob');
    await prefs.setInt('current_user_id', 43);

    expect(await UserSessionStorage.isCurrentSession(snapshot), isFalse);
    await expectLater(
      UserSessionStorage.ensureCurrentSession(snapshot),
      throwsA(isA<StateError>()),
    );
  });
}
