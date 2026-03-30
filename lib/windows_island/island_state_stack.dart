// Island State Stack - 栈式状态管理
// 所有状态操作通过此栈进行，确保状态可预测、可恢复

enum IslandState {
  idle,
  focusing,
  hoverWide,
  stackedCard,
  splitAlert,
  finishConfirm,
  abandonConfirm,
  finishFinal,
  reminderPopup,
  reminderSplit,
  reminderCapsule,
  copiedLink,
  // 系统控制状态
  quickControls,      // 快速控制面板
  musicPlayer,        // 音乐播放器
  volumeControl,      // 音量控制
  brightnessControl,  // 亮度控制
  cardCarousel,       // 卡片轮播
}

class _StackEntry {
  final IslandState state;
  final Map<String, dynamic>? data;

  _StackEntry(this.state, {this.data});

  @override
  String toString() => state.name;
}

/// 栈式状态管理器
/// - push: 入栈临时状态（confirm / copiedLink / hoverWide）
/// - pop: 出栈恢复下层状态
/// - replaceTop: 替换栈顶（reminderSplit 替换 focusing）
/// - replaceBase: 替换栈底（idle <-> focusing 切换）
/// - clearToIdle: 清空回 idle（完成/放弃后调用）
class IslandStateStack {
  final List<_StackEntry> _stack = [];

  /// 受保护状态集合 —— 外部 payload 无法覆盖
  static const protectedStates = {
    IslandState.finishConfirm,
    IslandState.abandonConfirm,
    IslandState.finishFinal,
    IslandState.copiedLink,
    IslandState.reminderPopup,
  };

  /// 当前显示的状态（栈顶）
  IslandState get current =>
      _stack.isEmpty ? IslandState.idle : _stack.last.state;

  /// 基础状态（栈底）—— 代表"背景状态"（idle 或 focusing）
  IslandState get base =>
      _stack.isNotEmpty ? _stack.first.state : IslandState.idle;

  /// 当前状态的数据
  Map<String, dynamic>? get currentData =>
      _stack.isEmpty ? null : _stack.last.data;

  /// 当前是否处于受保护状态
  bool get isProtected => protectedStates.contains(current);

  /// 栈大小
  int get length => _stack.length;

  /// 是否为空
  bool get isEmpty => _stack.isEmpty;

  /// 栈内容（调试用）
  List<IslandState> get states => _stack.map((e) => e.state).toList();

  /// 入栈：临时状态（confirm / copiedLink / hoverWide）
  void push(IslandState state, {Map<String, dynamic>? data}) {
    _stack.add(_StackEntry(state, data: data));
  }

  /// 出栈：恢复下层状态
  /// [expectedState] 用于防止错误 pop
  /// 返回 pop 后的新 current
  IslandState pop(IslandState expectedState) {
    if (_stack.isNotEmpty && _stack.last.state == expectedState) {
      _stack.removeLast();
    }
    return current;
  }

  /// 替换栈顶：reminderSplit 替换 focusing 时使用
  void replaceTop(IslandState state, {Map<String, dynamic>? data}) {
    if (_stack.isNotEmpty) {
      _stack[_stack.length - 1] = _StackEntry(state, data: data);
    } else {
      _stack.add(_StackEntry(state, data: data));
    }
  }

  /// 替换栈底（基础状态切换 idle <-> focusing）
  void replaceBase(IslandState state, {Map<String, dynamic>? data}) {
    if (_stack.isEmpty) {
      _stack.add(_StackEntry(state, data: data));
    } else {
      _stack[0] = _StackEntry(state, data: data);
    }
  }

  /// 清空回 idle（完成/放弃后调用）
  void clearToIdle() {
    _stack.clear();
    _stack.add(_StackEntry(IslandState.idle));
  }

  /// 弹出直到某个状态
  /// 例如：stackedCard -> finishConfirm 后取消，回到 stackedCard
  void popUntil(IslandState targetState) {
    while (_stack.length > 1 && _stack.last.state != targetState) {
      _stack.removeLast();
    }
  }

  /// 获取栈中指定状态的数据
  Map<String, dynamic>? getDataForState(IslandState targetState) {
    for (int i = _stack.length - 1; i >= 0; i--) {
      if (_stack[i].state == targetState) {
        return _stack[i].data;
      }
    }
    return null;
  }

  /// 检查栈中是否包含指定状态
  bool contains(IslandState state) {
    return _stack.any((e) => e.state == state);
  }

  /// 重置栈（用于测试）
  void reset() {
    _stack.clear();
    _stack.add(_StackEntry(IslandState.idle));
  }

  @override
  String toString() => '[${_stack.map((e) => e.state.name).join(' → ')}]';
}
