import 'package:countdown_todo/services/api_service.dart';
import 'package:countdown_todo/services/storage/user_session_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
}
