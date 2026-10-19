import 'package:countdown_todo/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

int _localSortKey(DateTime value) => int.parse(
  '${value.year.toString().padLeft(4, '0')}'
  '${value.month.toString().padLeft(2, '0')}'
  '${value.day.toString().padLeft(2, '0')}'
  '${value.hour.toString().padLeft(2, '0')}'
  '${value.minute.toString().padLeft(2, '0')}'
  '${value.second.toString().padLeft(2, '0')}',
);

void main() {
  group('公告时间排序键', () {
    test('支持日期、分钟和秒级公告 ID', () {
      expect(
        UpdateService.parseAnnouncementSortKey('ann_20260608_001'),
        20260608000000,
      );
      expect(
        UpdateService.parseAnnouncementSortKey('ann_202606081230'),
        20260608123000,
      );
      expect(
        UpdateService.parseAnnouncementSortKey('ann_20260608090908'),
        20260608090908,
      );
    });

    test('空 ID 或不含有效时间片段时返回零', () {
      expect(UpdateService.parseAnnouncementSortKey(''), 0);
      expect(UpdateService.parseAnnouncementSortKey('announcement-latest'), 0);
    });

    test('支持毫秒和秒级 Unix 时间戳', () {
      final milliseconds = DateTime.fromMillisecondsSinceEpoch(
        1720000000000,
        isUtc: true,
      ).toLocal();
      final seconds = DateTime.fromMillisecondsSinceEpoch(
        1720000000 * 1000,
        isUtc: true,
      ).toLocal();

      expect(
        UpdateService.parseAnnouncementSortKey('ann_1720000000000'),
        _localSortKey(milliseconds),
      );
      expect(
        UpdateService.parseAnnouncementSortKey('ann_1720000000'),
        _localSortKey(seconds),
      );
    });
  });
}
