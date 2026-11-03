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
  });

  test('formatDurationHMin formats duration as xhxmin / xh / xmin / xs / 0min', () {
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
  });
}
