enum AiContextMode {
  functionCalling,
  smartContextInjection;

  String get label => switch (this) {
    functionCalling => '工具查询',
    smartContextInjection => '智能注入',
  };

  String get description => switch (this) {
    functionCalling => 'Function Calling：模型按需选择工具和查询范围，App 返回数据后继续回答。',
    smartContextInjection => 'App 根据当前问题匹配关键词，提前注入相关业务数据。',
  };

  static AiContextMode fromStorage(String? value) => values.firstWhere(
    (mode) => mode.name == value,
    orElse: () => functionCalling,
  );
}
