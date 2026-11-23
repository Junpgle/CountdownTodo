import 'package:countdown_todo/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StorageService.onDataChangedHook（小组件数据刷新钩子）', () {
    test('triggerRefresh 防抖后回调一次', () async {
      var called = 0;
      StorageService.onDataChangedHook = () => called++;

      StorageService.triggerRefresh();
      StorageService.triggerRefresh();
      StorageService.triggerRefresh();

      await Future.delayed(const Duration(milliseconds: 200));
      expect(called, 1);

      StorageService.onDataChangedHook = null;
    });

    test('未注册钩子时 triggerRefresh 不抛错', () async {
      StorageService.onDataChangedHook = null;
      StorageService.triggerRefresh();
      await Future.delayed(const Duration(milliseconds: 150));
    });
  });
}
