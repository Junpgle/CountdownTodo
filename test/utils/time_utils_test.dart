import 'package:countdown_todo/utils/time_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en_US');
    await initializeDateFormatting('zh_CN');
  });

  test('date format cache follows the active locale', () {
    final originalLocale = Intl.defaultLocale;
    addTearDown(() => Intl.defaultLocale = originalLocale);
    final date = DateTime(2026, 3, 4, 13, 45);

    Intl.defaultLocale = 'en_US';
    final english = AppTimeFormats.format(date, 'EEEE');
    expect(english, DateFormat('EEEE', 'en_US').format(date));

    Intl.defaultLocale = 'zh_CN';
    final chinese = AppTimeFormats.format(date, 'EEEE');
    expect(chinese, DateFormat('EEEE', 'zh_CN').format(date));
    expect(chinese, isNot(english));
  });

  test('date formatter cache reuses instances per locale', () {
    final originalLocale = Intl.defaultLocale;
    addTearDown(() => Intl.defaultLocale = originalLocale);

    Intl.defaultLocale = 'en_US';
    final english = AppTimeFormats.dateFormatter('EEEE');
    expect(AppTimeFormats.dateFormatter('EEEE'), same(english));

    Intl.defaultLocale = 'zh_CN';
    final chinese = AppTimeFormats.dateFormatter('EEEE');
    expect(chinese, isNot(same(english)));
    expect(AppTimeFormats.dateFormatter('EEEE'), same(chinese));

    final explicitEn = AppTimeFormats.dateFormatter('MMMM', locale: 'en_US');
    final explicitZh = AppTimeFormats.dateFormatter('MMMM', locale: 'zh_CN');
    expect(
      AppTimeFormats.dateFormatter('MMMM', locale: 'en_US'),
      same(explicitEn),
    );
    expect(explicitZh, isNot(same(explicitEn)));
  });

  test('date formatter cache retains at least 48 distinct patterns without eviction', () {
    final originalLocale = Intl.defaultLocale;
    addTearDown(() => Intl.defaultLocale = originalLocale);
    Intl.defaultLocale = 'en_US';

    final formatters = [
      for (var i = 0; i < 48; i++)
        AppTimeFormats.dateFormatter("yyyy-MM-dd 'tag$i'"),
    ];
    for (var i = 0; i < 48; i++) {
      expect(
        AppTimeFormats.dateFormatter("yyyy-MM-dd 'tag$i'"),
        same(formatters[i]),
      );
    }
  });

  test(
    'formatDurationHMin formats duration as xhxmin / xh / xmin / xs / 0min',
    () {
      expect(formatDurationHMin(0), '0min');
      expect(formatDurationHMin(-10), '0min');
      expect(formatDurationHMin(15), '15s');
      expect(formatDurationHMin(59), '59s');
      expect(formatDurationHMin(60), '1min');
      expect(formatDurationHMin(1500), '25min');
      expect(formatDurationHMin(3600), '1h');
      expect(formatDurationHMin(3660), '1h1min');
      expect(formatDurationHMin(5400), '1h30min');
      expect(formatDurationHMin(7200), '2h');
      expect(formatDurationHMin(7500), '2h5min');
    },
  );

  test(
    'weekday helpers and timestamp/hourMinute helpers format accurately',
    () {
      expect(AppTimeFormats.weekdayShortLabelsZh, [
        '一',
        '二',
        '三',
        '四',
        '五',
        '六',
        '日',
      ]);
      expect(AppTimeFormats.weekdayLabelsZh, [
        '周一',
        '周二',
        '周三',
        '周四',
        '周五',
        '周六',
        '周日',
      ]);
      expect(AppTimeFormats.weekdayShortZh(1), '一');
      expect(AppTimeFormats.weekdayShortZh(7), '日');
      expect(AppTimeFormats.weekdayShortZh(0), '一');
      expect(AppTimeFormats.weekdayShortZh(99), '日');

      expect(AppTimeFormats.weekdayZh(1), '周一');
      expect(AppTimeFormats.weekdayZh(5), '周五');
      expect(AppTimeFormats.weekdayZh(0), '周一');
      expect(AppTimeFormats.weekdayZh(8), '周日');

      // 2026-11-25 is Wednesday (weekday == 3)
      final dt = DateTime(2026, 11, 25, 8, 5, 9);
      expect(AppTimeFormats.weekdayLabel(dt), '周三');
      expect(AppTimeFormats.fileTimestamp(dt), '20261125_080509');
      expect(AppTimeFormats.hourMinute(8, 5), '08:05');
      expect(AppTimeFormats.hourMinute(19, 42), '19:42');
      expect(AppTimeFormats.minuteOfDay(0), '00:00');
      expect(AppTimeFormats.minuteOfDay(485), '08:05');
      expect(AppTimeFormats.minuteOfDay(1440), '24:00');
      final utcInstant = DateTime.utc(2026, 11, 25, 8, 5, 9);
      expect(
        AppTimeFormats.toServerTimestamp(utcInstant.toLocal()),
        utcInstant.millisecondsSinceEpoch,
      );
      expect(AppTimeFormats.toNullableServerTimestamp(null), isNull);
      expect(
        AppTimeFormats.toNullableServerTimestamp(utcInstant.toLocal()),
        utcInstant.millisecondsSinceEpoch,
      );
    },
  );

  test('fast-path fixed patterns and dayStart match intl output and preserve local midnight', () {
    final originalLocale = Intl.defaultLocale;
    addTearDown(() => Intl.defaultLocale = originalLocale);
    Intl.defaultLocale = 'zh_CN';

    final singleDigit = DateTime(2026, 3, 5, 7, 4, 2);
    expect(AppTimeFormats.dayKey(singleDigit), '20260305');
    expect(AppTimeFormats.date(singleDigit), '2026-03-05');
    expect(AppTimeFormats.dateCn(singleDigit), '2026年03月05日');
    expect(AppTimeFormats.monthDayCn(singleDigit), '03月05日');
    expect(AppTimeFormats.monthDaySlash(singleDigit), '03/05');
    expect(AppTimeFormats.compactDateTime(singleDigit), '03-05 07:04');
    expect(AppTimeFormats.fullDateTime(singleDigit), '2026-03-05 07:04');
    expect(AppTimeFormats.clock(singleDigit), '07:04');
    expect(AppTimeFormats.fileTimestamp(singleDigit), '20260305_070402');

    final doubleDigit = DateTime(2026, 11, 26, 19, 48, 25);
    for (final pattern in const [
      'yyyyMMdd',
      'yyyy-MM-dd',
      'yyyy年MM月dd日',
      'MM月dd日',
      'MM/dd',
      'MM-dd HH:mm',
      'yyyy-MM-dd HH:mm',
      'HH:mm',
      'yyyyMMdd_HHmmss',
    ]) {
      expect(
        AppTimeFormats.format(singleDigit, pattern),
        DateFormat(pattern, 'zh_CN').format(singleDigit),
      );
      expect(
        AppTimeFormats.format(doubleDigit, pattern),
        DateFormat(pattern, 'zh_CN').format(doubleDigit),
      );
    }

    final localMidnight = DateTime(2026, 11, 26);
    expect(
      identical(AppTimeFormats.dayStart(localMidnight), localMidnight),
      isTrue,
    );
    expect(
      identical(
        AppTimeFormats.localDayStartOffset(localMidnight, 0),
        localMidnight,
      ),
      isTrue,
    );
    expect(AppTimeFormats.dayStart(doubleDigit), DateTime(2026, 11, 26));
    final utcMidnight = DateTime.utc(2026, 11, 26);
    expect(
      identical(AppTimeFormats.dayStart(utcMidnight), utcMidnight),
      isFalse,
    );
    expect(AppTimeFormats.dayStart(utcMidnight), DateTime(2026, 11, 26));
  });
}
