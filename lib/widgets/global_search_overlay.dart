import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models.dart';
import '../services/search_service.dart';
import 'dart:async';

// ──────────────────────────────────────────────────────────────────────────────
// 类型元数据：名称、图标、颜色
// ──────────────────────────────────────────────────────────────────────────────
class _TypeMeta {
  final String label;
  final IconData icon;
  final Color color;
  const _TypeMeta(this.label, this.icon, this.color);
}

class _SearchSectionLayoutItem {
  final Widget widget;
  final double estimatedHeight;

  const _SearchSectionLayoutItem({
    required this.widget,
    required this.estimatedHeight,
  });
}

class _TextMatch {
  final int start;
  final int end;
  const _TextMatch(this.start, this.end);
}

const _typeMeta = <SearchResultType, _TypeMeta>{
  SearchResultType.todo:      _TypeMeta('待办事项',  Icons.check_circle_outline,   Color(0xFF007AFF)),
  SearchResultType.todoGroup: _TypeMeta('待办文件夹', Icons.folder_rounded,          Color(0xFFFF9500)),
  SearchResultType.course:    _TypeMeta('课程',      Icons.school_rounded,          Color(0xFF34C759)),
  SearchResultType.countdown: _TypeMeta('倒计时',    Icons.timer_outlined,          Color(0xFFFF3B30)),
  SearchResultType.tag:       _TypeMeta('专注标签',   Icons.label_rounded,           Color(0xFFE84C88)),
  SearchResultType.app:       _TypeMeta('屏幕使用',   Icons.smartphone_rounded,      Color(0xFF5B6BE8)),
  SearchResultType.log:       _TypeMeta('时间日志',  Icons.history_edu_rounded,     Color(0xFF00C7BE)),
  SearchResultType.setting:   _TypeMeta('设置',      Icons.settings_rounded,        Color(0xFFFF9500)),
  SearchResultType.action:    _TypeMeta('快捷操作',  Icons.bolt_rounded,            Color(0xFFAF52DE)),
  SearchResultType.recommend: _TypeMeta('猜你想搜',  Icons.auto_awesome_outlined,   Color(0xFFFF2D55)),
  SearchResultType.history:   _TypeMeta('搜索历史',  Icons.history_rounded,         Colors.grey),
};

// 分组显示顺序
const _groupOrder = [
  SearchResultType.recommend,
  SearchResultType.history,
  SearchResultType.todo,
  SearchResultType.todoGroup,
  SearchResultType.countdown,
  SearchResultType.course,
  SearchResultType.tag,
  SearchResultType.app,
  SearchResultType.log,
  SearchResultType.setting,
  SearchResultType.action,
];

// ──────────────────────────────────────────────────────────────────────────────
// 主 Widget
// ──────────────────────────────────────────────────────────────────────────────
class GlobalSearchOverlay extends StatefulWidget {
  const GlobalSearchOverlay({super.key});

  @override
  State<GlobalSearchOverlay> createState() => _GlobalSearchOverlayState();
}

class _GlobalSearchOverlayState extends State<GlobalSearchOverlay>
    with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  List<SearchResult> _results = [];
  bool _isSearching = false;
  String _currentQuery = '';
  Timer? _debounce;

  // 记录每个类型是否已展开（默认只显示前 3 条）
  final Map<SearchResultType, bool> _expanded = {};

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scaleAnimation =
        CurvedAnimation(parent: _animController, curve: Curves.easeOutBack);
    _fadeAnimation =
        CurvedAnimation(parent: _animController, curve: Curves.easeIn);
    _animController.forward();

    Future.delayed(const Duration(milliseconds: 50), () {
      _inputFocusNode.requestFocus();
      _onQueryChanged(''); // 🚀 初始化触发“猜你想搜”
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _inputFocusNode.dispose();
    _debounce?.cancel();
    _animController.dispose();
    super.dispose();
  }

  // ────────────────────────────────── 搜索 ──────────────────────────────────

  void _onQueryChanged(String query) {
    _currentQuery = query;
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    
    // 如果是空字符串，立即执行（不防抖），让建议秒出
    if (query.trim().isEmpty) {
      _executeSearch('');
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 300), () => _executeSearch(query));
  }

  Future<void> _executeSearch(String query) async {
    setState(() => _isSearching = true);
    final results = await SearchService.instance.search(query);
    if (mounted && query == _currentQuery) {
      setState(() {
        _results = results.cast<SearchResult>();
        _isSearching = false;
        _expanded.clear();
      });
    }
  }

  // ────────────────────────────────── 交互 ──────────────────────────────────

  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _close();
    }
  }

  void _close() {
    FocusManager.instance.primaryFocus?.unfocus();
    _animController.reverse().then((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  void _handleResultClick(SearchResult result) {
    final data = result.extraData;
    final action = data?['action'] as String?;

    // 🚀 特殊处理：如果是应用查询建议，不关闭蒙层，而是更新搜索框
    if (action == 'apply_query' || action == 'ai_query') {
      final q = data?['query'] as String?;
      if (q != null) {
        _controller.text = q;
        _controller.selection = TextSelection.fromPosition(
          TextPosition(offset: q.length),
        );
        _onQueryChanged(q);
        return;
      }
    }

    FocusManager.instance.primaryFocus?.unfocus();
    final navigator = Navigator.of(context);
    _animController.reverse().then((_) {
      if (mounted) {
        navigator.pop(); // 关闭搜索蒙层
        SearchNavigationHandler.handle(navigator.context, result); // 用父级 context 导航
      }
    });
  }

  // ────────────────────────────────── 分组 ──────────────────────────────────

  /// 将扁平结果按 type 分组，保留 _groupOrder 顺序
  Map<SearchResultType, List<SearchResult>> _groupResults() {
    final map = <SearchResultType, List<SearchResult>>{};
    for (var r in _results) {
      map.putIfAbsent(r.type, () => []).add(r);
    }
    // 按 _groupOrder 排序
    final ordered = <SearchResultType, List<SearchResult>>{};
    for (var t in _groupOrder) {
      if (map.containsKey(t)) ordered[t] = map[t]!;
    }
    // 追加未知类型
    for (var entry in map.entries) {
      if (!ordered.containsKey(entry.key)) ordered[entry.key] = entry.value;
    }
    return ordered;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Build
  // ──────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isCompact = size.shortestSide < 600;

    // 🚀 电脑端（非 Compact）面板使用全不透明色
    final panelColor = isDark
        ? Color.fromRGBO(28, 28, 30, isCompact ? 0.96 : 1.0)
        : Color.fromRGBO(255, 255, 255, isCompact ? 0.98 : 1.0);

    // 🚀 背景色：电脑端使用更深的遮罩和更强的模糊，产生“悬浮感”但又不会透出背景细节
    final backdropColor = isCompact
        ? (isDark
            ? const Color.fromRGBO(0, 0, 0, 0.26)
            : const Color.fromRGBO(255, 255, 255, 0.16))
        : (isDark
            ? Colors.black.withValues(alpha: 0.75)
            : Colors.black.withValues(alpha: 0.35));

    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: false,
      body: KeyboardListener(
        focusNode: FocusNode(),
        onKeyEvent: _handleKeyEvent,
        child: Stack(
          children: [
            // ── 背景遮罩 ──
            GestureDetector(
              onTap: _close,
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: isCompact ? 15 : 30,
                  sigmaY: isCompact ? 15 : 30,
                ),
                child: Container(
                  color: backdropColor,
                ),
              ),
            ),
            // ── 内容 ──
            SafeArea(
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: isCompact ? size.width : 1180),
                      child: Container(
                        margin: const EdgeInsets.fromLTRB(20, 60, 20, 20),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: panelColor,
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            color: isDark ? Colors.white12 : Colors.black12,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Color.fromRGBO(0, 0, 0, isDark ? 0.25 : 0.12),
                              blurRadius: 36,
                              offset: const Offset(0, 18),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildSearchInput(colorScheme, isDark),
                            const SizedBox(height: 8),
                            _buildSearchScopeHint(colorScheme, isDark),
                            const SizedBox(height: 12),
                            if (_results.isNotEmpty || _isSearching)
                              _buildResultsPanel(colorScheme, isDark, size),
                          ],
                        ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 搜索框
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildSearchInput(ColorScheme colorScheme, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color.fromRGBO(0, 0, 0, 0.15),
            blurRadius: 30,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: TextField(
        controller: _controller,
        focusNode: _inputFocusNode,
        onChanged: _onQueryChanged,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white : Colors.black87,
        ),
        decoration: InputDecoration(
          hintText: '多关键词搜全应用',
          hintStyle: TextStyle(color: isDark ? Colors.white54 : Colors.black38),
          prefixIcon:
              Icon(Icons.search_rounded, color: colorScheme.primary, size: 24),
          suffixIcon: _isSearching
              ? Container(
                  padding: const EdgeInsets.all(14),
                  width: 20,
                  height: 20,
                  child: const CircularProgressIndicator(strokeWidth: 2),
                )
              : IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () {
                    _controller.clear();
                    _onQueryChanged('');
                  },
                ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 20),
        ),
      ),
    );
  }

  Widget _buildSearchScopeHint(ColorScheme colorScheme, bool isDark) {
    final items = ['待办', '倒计时', '番茄钟', '时间日志', '屏幕时间', '团队', '设置'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Icon(Icons.tips_and_updates_outlined,
              size: 15, color: isDark ? Colors.white54 : Colors.black45),
          Text(
            '支持搜索：',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white54 : Colors.black54,
              fontWeight: FontWeight.w600,
            ),
          ),
          for (final item in items)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: isDark ? 0.14 : 0.08),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                item,
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 结果面板（分组）
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildResultsPanel(ColorScheme colorScheme, bool isDark, Size screenSize) {
    if (_results.isEmpty && _isSearching) {
      return _buildSearchSkeleton(isDark, screenSize);
    }
    if (_results.isEmpty && !_isSearching) {
      return _buildEmptyState(colorScheme, isDark);
    }

    final dateQueryHint = _extractDateQueryHint();

    final groups = _groupResults();
    final sections = <_SearchSectionLayoutItem>[];

    for (var entry in groups.entries) {
      final type = entry.key;
      final items = entry.value;
      final meta = _typeMeta[type] ??
          const _TypeMeta('其他', Icons.help_outline, Colors.grey);
      final isExpanded = _expanded[type] ?? false;
      final displayItems = isExpanded ? items : items.take(3).toList();
      final hasMore = items.length > 3 && !isExpanded;
      final estimatedHeight = 58 + (displayItems.length * 86.0) + (hasMore ? 38 : 0);

      sections.add(_SearchSectionLayoutItem(
        widget: _buildSection(
          type: type,
          meta: meta,
          items: displayItems,
          hasMore: hasMore,
          totalCount: items.length,
          colorScheme: colorScheme,
          isDark: isDark,
        ),
        estimatedHeight: estimatedHeight,
      ));
    }

    final isCompact = screenSize.shortestSide < 600;
    final maxHeight = screenSize.height * (isCompact ? 0.55 : 0.68);

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final banner = dateQueryHint == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF2C2C2E)
                          : colorScheme.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: colorScheme.primary.withValues(alpha: isDark ? 0.18 : 0.12),
                      ),
                    ),
                    child: Text(
                      dateQueryHint,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : colorScheme.primary,
                      ),
                    ),
                  ),
                );

          final useTwoColumns = !isCompact && constraints.maxWidth >= 960;
          if (!useTwoColumns) {
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  banner,
                  ...sections.map((section) => section.widget),
                ],
              ),
            );
          }

          final gutter = 12.0;
          final columnWidth = (constraints.maxWidth - gutter) / 2;
          final leftColumn = <Widget>[];
          final rightColumn = <Widget>[];
          double leftHeight = 0;
          double rightHeight = 0;

          for (final section in sections) {
            final wrapped = SizedBox(width: columnWidth, child: section.widget);
            if (leftHeight <= rightHeight) {
              leftColumn.add(wrapped);
              leftHeight += section.estimatedHeight;
            } else {
              rightColumn.add(wrapped);
              rightHeight += section.estimatedHeight;
            }
          }

          Widget buildColumn(List<Widget> children) {
            if (children.isEmpty) return const SizedBox.shrink();
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  children[i],
                  if (i != children.length - 1) const SizedBox(height: 12),
                ],
              ],
            );
          }

          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                banner,
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: columnWidth, child: buildColumn(leftColumn)),
                    const SizedBox(width: 12),
                    SizedBox(width: columnWidth, child: buildColumn(rightColumn)),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String? _extractDateQueryHint() {
    for (final result in _results) {
      final hint = result.extraData?['date_query_hint']?.toString().trim();
      if (hint != null && hint.isNotEmpty) return hint;
    }
    return null;
  }


  // ──────────────────────────────────────────────────────────────────────────
  // 分类区块
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildSection({
    required SearchResultType type,
    required _TypeMeta meta,
    required List<SearchResult> items,
    required bool hasMore,
    required int totalCount,
    required ColorScheme colorScheme,
    required bool isDark,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: const Color.fromRGBO(0, 0, 0, 0.08), blurRadius: 16),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── 分类标题栏 ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: meta.color.withValues(alpha: isDark ? 0.15 : 0.06),
              ),
              child: Row(
                children: [
                  Icon(meta.icon, color: meta.color, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    meta.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: meta.color,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: meta.color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$totalCount',
                      style: TextStyle(
                          fontSize: 11, color: meta.color, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            // ── 条目列表 ──
            ...items.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (index > 0)
                    Divider(
                      height: 1,
                      indent: 16,
                      endIndent: 16,
                                              color: isDark ? Colors.white10 : const Color(0x0F000000),
                    ),
                  _buildResultTile(item, meta.color, colorScheme, isDark),
                ],
              );
            }),
            // ── 展开更多 ──
            if (hasMore)
              InkWell(
                onTap: () => setState(() => _expanded[type] = true),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: isDark ? Colors.white10 : const Color(0x0F000000),
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.expand_more_rounded, size: 16, color: meta.color),
                      const SizedBox(width: 4),
                      Text(
                        '查看全部 $totalCount 项',
                        style: TextStyle(
                          fontSize: 12,
                          color: meta.color,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 单条搜索结果 Tile
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildResultTile(
    SearchResult item,
    Color typeColor,
    ColorScheme colorScheme,
    bool isDark,
  ) {
    final isCompleted = item.extraData?['is_completed'] == 1;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _handleResultClick(item),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── 图标 ──
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: typeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  item.icon,
                  color: isCompleted ? Colors.grey : typeColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              // ── 文本 ──
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 标题
                    Row(
                      children: [
                        Expanded(
                          child: _highlightText(
                            item.title,
                            _currentQuery,
                            TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: isCompleted
                                  ? Colors.grey
                                  : (isDark ? Colors.white : Colors.black87),
                              decoration: isCompleted
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                        ),
                        // 面包屑（设置项）
                        if (item.breadcrumb != null)
                          Container(
                            margin: const EdgeInsets.only(left: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: typeColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              item.breadcrumb!,
                              style: TextStyle(
                                fontSize: 10,
                                color: typeColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                    // 副标题
                    if (item.subtitle != null && item.subtitle!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: _highlightText(
                          item.subtitle!,
                          _currentQuery,
                          TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white54 : Colors.black45,
                          ),
                        ),
                      ),
                    // 待办额外信息标签
                    if (item.type == SearchResultType.todo)
                      _buildTodoTags(item, typeColor, isDark),
                  ],
                ),
              ),
              // ── 右侧箭头 ──
              const SizedBox(width: 8),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 13,
                color: isDark ? Colors.white24 : Colors.black26,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 待办专属的小标签行（已完成、团队、截止等）
  Widget _buildTodoTags(SearchResult item, Color typeColor, bool isDark) {
    final tags = <Widget>[];
    final data = item.extraData ?? {};

    if (data['is_completed'] == 1) {
      tags.add(_chip('已完成', Colors.green, isDark));
    }
    if (data['team_name'] != null &&
        (data['team_name'] as String).isNotEmpty) {
      tags.add(_chip('📌 ${data['team_name']}', Colors.blueAccent, isDark));
    }

    if (tags.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Wrap(spacing: 6, children: tags),
    );
  }

  Widget _chip(String label, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 关键词高亮
  // ──────────────────────────────────────────────────────────────────────────

  Widget _highlightText(String text, String query, TextStyle style) {
    final terms = query
        .split(RegExp(r'[\s,，;；]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    if (terms.isEmpty) {
      return Text(text, style: style, maxLines: 2, overflow: TextOverflow.ellipsis);
    }

    final lower = text.toLowerCase();
    final matches = <_TextMatch>[];
    for (final term in terms) {
      final lowerTerm = term.toLowerCase();
      var start = 0;
      while (true) {
        final idx = lower.indexOf(lowerTerm, start);
        if (idx == -1) break;
        matches.add(_TextMatch(idx, idx + lowerTerm.length));
        start = idx + lowerTerm.length;
      }
    }

    if (matches.isEmpty) {
      return Text(text, style: style, maxLines: 2, overflow: TextOverflow.ellipsis);
    }

    matches.sort((a, b) => a.start.compareTo(b.start));
    final merged = <_TextMatch>[];
    for (final m in matches) {
      if (merged.isEmpty || m.start > merged.last.end) {
        merged.add(m);
      } else if (m.end > merged.last.end) {
        merged[merged.length - 1] = _TextMatch(merged.last.start, m.end);
      }
    }

    final List<TextSpan> spans = [];
    int start = 0;
    for (final m in merged) {
      if (m.start > start) {
        spans.add(TextSpan(text: text.substring(start, m.start), style: style));
      }
      spans.add(TextSpan(
        text: text.substring(m.start, m.end),
        style: style.copyWith(
          color: const Color(0xFF007AFF),
          fontWeight: FontWeight.w900,
          backgroundColor: const Color(0xFF007AFF).withValues(alpha: 0.1),
        ),
      ));
      start = m.end;
    }
    if (start < text.length) spans.add(TextSpan(text: text.substring(start), style: style));
    return RichText(
      text: TextSpan(children: spans, style: style),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }


  // ──────────────────────────────────────────────────────────────────────────
  // 空状态
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildEmptyState(ColorScheme colorScheme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Icon(Icons.search_off_rounded, size: 50, color: colorScheme.outline),
          const SizedBox(height: 16),
          Text(
            '没找到相关内容',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 17,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '旅行者，你将去往何方？',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isDark ? Colors.white54 : Colors.black45,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
  // 🚀 搜索结果骨架屏
  Widget _buildSearchSkeleton(bool isDark, Size screenSize) {
    final baseColor =
        isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05);

    return Column(
      children: List.generate(
          4,
          (i) => Container(
                height: 70,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: baseColor,
                  borderRadius: BorderRadius.circular(20),
                ),
              )),
    );
  }
}
