import 'package:countdown_todo/models/chat_message.dart';
import 'package:countdown_todo/services/chat_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'loading a long history preserves every message and its content',
    () async {
      const sessionId = 'long-history-session';
      final original = List<ChatMessage>.generate(512, (index) {
        final role = index.isEven ? ChatRole.user : ChatRole.assistant;
        return ChatMessage(
          id: 'message-$index',
          role: role,
          content: 'content-$index-${'c' * 512}',
          rawContent: 'raw-$index-${'r' * 512}',
          reasoningContent: 'reasoning-$index-${'d' * 512}',
          timestamp: DateTime.fromMillisecondsSinceEpoch(index * 1000),
        );
      });

      await ChatStorageService.saveHistory(original, sessionId);
      final loaded = await ChatStorageService.loadHistory(sessionId);

      expect(loaded, hasLength(original.length));
      for (var index = 0; index < original.length; index++) {
        expect(loaded[index].id, original[index].id);
        expect(loaded[index].role, original[index].role);
        expect(loaded[index].content, original[index].content);
        expect(loaded[index].rawContent, original[index].rawContent);
        expect(
          loaded[index].reasoningContent,
          original[index].reasoningContent,
        );
        expect(loaded[index].timestamp, original[index].timestamp);
      }
    },
  );
}
