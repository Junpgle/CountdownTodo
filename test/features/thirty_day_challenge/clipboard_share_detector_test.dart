import 'package:flutter_test/flutter_test.dart';

import 'package:countdown_todo/features/thirty_day_challenge/models/thirty_day_challenge.dart';
import 'package:countdown_todo/features/thirty_day_challenge/services/challenge_share_codec.dart';
import 'package:countdown_todo/features/thirty_day_challenge/services/clipboard_share_detector.dart';

void main() {
  test('识别自定义挑战分享内容', () {
    const draft = ChallengeDraft(title: '早起挑战', taskTitles: ['七点前起床']);

    final payload = ClipboardSharePayload.tryDecode(
      ChallengeShareCodec.encode(draft),
    );

    expect(payload?.kind, ClipboardShareKind.challenge);
    expect(payload?.challenge?.title, '早起挑战');
  });

  test('识别团队邀请并提取邀请码和团队名称', () {
    final payload = ClipboardSharePayload.tryDecode(
      '邀请您加入「一起学习」团队进行协作。复制此消息后打开App即可自动申请加入。\n\n邀请码：[abc123]',
    );

    expect(payload?.kind, ClipboardShareKind.teamInvite);
    expect(payload?.inviteCode, 'abc123');
    expect(payload?.teamName, '一起学习');
  });

  test('普通剪贴板文本不会触发首页分享提示', () {
    expect(ClipboardSharePayload.tryDecode('今天买牛奶'), isNull);
  });
}
