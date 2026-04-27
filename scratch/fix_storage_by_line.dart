import 'dart:io';

void main() {
  final file = File('d:/Codes/Android/math_quiz_app/lib/storage_service.dart');
  final lines = file.readAsLinesSync();
  
  void fix(int lineNum, String content) {
    if (lineNum <= lines.length) {
      lines[lineNum - 1] = content;
    }
  }

  fix(954, '          debugPrint("✅ 老数据增量迁移完成。");');
  fix(1612, '          debugPrint("⏳ [同步] 距离上次同步仅过去 \${diff.inSeconds}s，忽略本次触发");');
  fix(1656, '      debugPrint("🚀 [同步引擎] 正在为 \$username 启动全量增量合并...");');
  fix(1665, '      debugPrint("⚠️ 同步中断: 用户名或 DeviceID 为空");');
  fix(1737, '          debugPrint("🚀 [增量提交] 发现 \${dirtyTodos.length + dirtyGroups.length + dirtyCountdowns.length + dirtyTimeLogs.length + dirtyPomodoros.length + dirtyTags.length} 条本地变更，正在上报...");');
  fix(1780, "        debugPrint('⏳ [全量同步] 命中服务端防抖空响应，3.2s 后自动重试一次');");
  fix(1875, '        debugPrint("🛡️ 数据合并逻辑 (Table: \$table)");');
  fix(2497, '      debugPrint("✅ 隐私政策版本提取成功: \$version");');
  
  file.writeAsStringSync(lines.join('\n'));
}
