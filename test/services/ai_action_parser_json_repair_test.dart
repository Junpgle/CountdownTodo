import 'dart:convert';

import 'package:countdown_todo/services/ai_action_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AI action JSON repair', () {
    for (final title in [
      'Review JSON {schema',
      'List [draft',
      'Review {schema with "quoted" text',
    ]) {
      test('keeps delimiters in string: $title', () {
        final payload = jsonEncode({
          'action': 'create_todo',
          'todos': [
            {'title': title},
          ],
        });
        final actions = AiActionParser.extractTodoActions(
          '[ACTION_START]$payload[ACTION_END]',
          originalText: '创建待办',
        );

        expect(actions, hasLength(1));
        expect(actions.single.title, title);
      });
    }

    test('closes nested truncated JSON in stack order', () {
      const response =
          '[ACTION_START]{"action":"create_todo","todos":[{"title":"Recovered","metadata":{"items":[{"value":"kept"'
          '[ACTION_END]';

      final actions = AiActionParser.extractTodoActions(
        response,
        originalText: '创建待办',
      );

      expect(actions, hasLength(1));
      expect(actions.single.title, 'Recovered');
    });
  });
}
