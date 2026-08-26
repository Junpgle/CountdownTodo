import 'package:flutter_test/flutter_test.dart';

import 'package:countdown_todo/services/sidebar_menu_service.dart';

void main() {
  test('normalizes sidebar order and appends new entries', () {
    final pair = SidebarMenuService.normalizePair(
      features: ['journal', 'unknown', 'journal'],
      utilities: ['update', 'journal'],
    );

    expect(pair.features, contains('journal'));
    expect(pair.features, isNot(contains('unknown')));
    expect(pair.features.where((key) => key == 'journal'), hasLength(1));
    expect(pair.utilities, ['update', 'changelog']);
    expect(
        pair.features,
        containsAll(<String>[
          'teams',
          'aiAssistant',
          'timeline',
          'screenTime',
          'planCenter',
          'habits',
          'challengeCenter',
        ]));
  });

  test('visibility defaults to true and ignores unknown keys', () {
    final visibility = SidebarMenuService.normalizeVisibility({
      'journal': false,
      'unknown': false,
    });

    expect(visibility['journal'], isFalse);
    expect(visibility['teams'], isTrue);
    expect(visibility.containsKey('unknown'), isFalse);
  });

  test('sidebar preference keys are recognized as user-scoped backup keys', () {
    expect(
      SidebarMenuService.isUserSpecificKey('sidebar_menu_order_features'),
      isTrue,
    );
    expect(
      SidebarMenuService.isUserSpecificKey('sidebar_menu_order_utilities'),
      isTrue,
    );
    expect(
      SidebarMenuService.isUserSpecificKey('sidebar_menu_visibility'),
      isTrue,
    );
    expect(SidebarMenuService.isUserSpecificKey('theme_mode'), isFalse);
  });
}
