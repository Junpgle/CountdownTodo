import 'package:flutter_test/flutter_test.dart';

import 'package:countdown_todo/features/thirty_day_challenge/models/thirty_day_challenge.dart';
import 'package:countdown_todo/features/thirty_day_challenge/services/challenge_share_codec.dart';

void main() {
  test('分享内容可以保留标题和任务并被识别', () {
    const draft = ChallengeDraft(title: '七天阅读', taskTitles: ['读第一章', '写下三点感受']);

    final shared = ChallengeShareCodec.encode(draft);
    final restored = ChallengeShareCodec.tryDecode(shared);

    expect(restored?.title, '七天阅读');
    expect(restored?.taskTitles, ['读第一章', '写下三点感受']);
  });

  test('可以识别聊天中常见的 JSON 代码块', () {
    const shared = '''```json
{
  "format": "countdowntodo.challenge",
  "version": 1,
  "title": "三天整理",
  "tasks": ["整理桌面", "清理下载目录"]
}
```''';

    final restored = ChallengeShareCodec.tryDecode(shared);

    expect(restored?.title, '三天整理');
    expect(restored?.taskTitles, ['整理桌面', '清理下载目录']);
  });

  test('普通文本不会被误识别为结构化挑战', () {
    expect(ChallengeShareCodec.tryDecode('读一本书\n跑步 3 公里'), isNull);
  });
}
