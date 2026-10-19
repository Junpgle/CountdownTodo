import 'package:countdown_todo/models/ai_todo_action.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AI待办操作草稿与来源清单的嵌套数据隔离', () {
    final source = AiTodoAction(
      type: AiTodoActionType.createTodo,
      title: '原始标题',
      tagUuids: ['read'],
      quickValues: [1, 2],
      metadata: {
        'draft': {'priority': 2},
      },
    );
    final draft = source.copy();

    draft.title = '修改中的标题';
    draft.tagUuids.add('work');
    draft.quickValues[0] = 9;
    (draft.metadata['draft'] as Map<String, dynamic>)['priority'] = 5;

    expect(source.title, '原始标题');
    expect(source.tagUuids, ['read']);
    expect(source.quickValues, [1, 2]);
    expect((source.metadata['draft'] as Map<String, dynamic>)['priority'], 2);
  });
}
