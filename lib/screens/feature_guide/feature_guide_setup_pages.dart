part of '../feature_guide_screen.dart';

extension _FeatureGuideSetupPages on _FeatureGuideScreenState {
  Widget _buildTaiSetupPage() {
    return _buildPageContainer(
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 16),
          _buildStepHeader(
            icon: Icons.folder_special_outlined,
            iconColor: Colors.teal,
            title: '配置 Tai 数据库路径',
            subtitle:
                '如果要启用 Windows 的时常追踪聚合（可选），请指定已安装的 Tai 软件数据文件路径 (data.db)。',
          ),
          const SizedBox(height: 32),
          OptionalLiquidGlassCard(
            padding: const EdgeInsets.all(16),
            width: double.infinity,
            borderRadius: 12,
            highContrast: true,
            fallbackDecoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '当数据库文件路径:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  _taiDbPath.isNotEmpty ? _taiDbPath : '未设置，功能无法生效',
                  style: TextStyle(
                    color: _taiDbPath.isNotEmpty
                        ? Theme.of(context).colorScheme.primary
                        : Colors.red,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.folder_open),
                    label: const Text('手动选择 data.db 文件'),
                    onPressed: () async {
                      final pickedFile = await FilePicker.pickFile(
                        type: FileType.custom,
                        allowedExtensions: ['db'],
                        dialogTitle: '选择 Tai 的 data.db 文件',
                      );
                      if (!mounted) return;
                      if (pickedFile?.path != null) {
                        String path = pickedFile!.path!;
                        bool isValid = await TaiService.validateDb(path);
                        if (!mounted) return;
                        if (isValid) {
                          await TaiService.saveDbPath(path);
                          _mutateState(() => _taiDbPath = path);
                        } else {
                          if (!mounted) return;
                          AppSnackBars.showSnackBar(
                            context,
                            const SnackBar(content: Text('⚠️ 选定的文件无效Tai数据库')),
                          );
                        }
                      }
                    },
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    icon: const Icon(Icons.flash_auto),
                    label: const Text('尝试自动检测默认安装路径'),
                    onPressed: () async {
                      final path = await TaiService.detectDefaultPath();
                      if (!mounted) return;
                      if (path != null) {
                        await TaiService.saveDbPath(path);
                        if (!mounted) return;
                        _mutateState(() => _taiDbPath = path);
                        AppSnackBars.showSnackBar(
                          context,
                          const SnackBar(content: Text('✅ 自动检测并绑定成功！')),
                        );
                      } else {
                        if (!mounted) return;
                        AppSnackBars.showSnackBar(
                          context,
                          const SnackBar(
                            content: Text('⚠️ 未能找到默认路径，请确认是否安装或手动选择。'),
                          ),
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 全局通用配置引导 ──────────────────────────────

  Widget _buildGlobalCourseSetupPage() {
    final scheme = Theme.of(context).colorScheme;
    final isWeb = AppPlatform.isWeb;
    return _buildPageContainer(
      content: Column(
        children: [
          const SizedBox(height: 16),
          _buildStepHeader(
            icon: Icons.calendar_month_outlined,
            iconColor: Colors.teal,
            title: '课表导入与学期同步',
            subtitle: isWeb
                ? '网页版支持浏览器文件导入、云端课表同步和学期进度设置。\n受浏览器限制，教务 WebView 导入和系统本地路径能力会降级。'
                : '全平台均支持智能课表解析。你可以在首页设置中导入本地课表，或直接从云端同步。\n设置开学与放假日期，以开启学期进度条。',
          ),
          const SizedBox(height: 24),
          OptionalLiquidGlassCard(
            margin: EdgeInsets.zero,
            borderRadius: 12,
            highContrast: true,
            fallbackDecoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                children: [
                  LiquidGlassSwitchListTile(
                    secondary: const Icon(Icons.linear_scale),
                    title: const Text(
                      '首页学期进度条',
                      style: TextStyle(fontSize: 14),
                    ),
                    value: _semesterEnabled,
                    onChanged: (val) {
                      _mutateState(() => _semesterEnabled = val);
                      StorageService.saveAppSetting(
                        StorageService.keySemesterProgressEnabled,
                        val,
                      );
                    },
                  ),
                  const Divider(height: 1, indent: 56),
                  ListTile(
                    contentPadding: const EdgeInsets.only(left: 56, right: 16),
                    title: const Text('开学日期', style: TextStyle(fontSize: 14)),
                    trailing: Text(
                      _semesterStart == null
                          ? "未设置"
                          : AppTimeFormats.date(_semesterStart!),
                    ),
                    onTap: () => _pickSemesterDate(true),
                  ),
                  ListTile(
                    contentPadding: const EdgeInsets.only(left: 56, right: 16),
                    title: const Text('放假日期', style: TextStyle(fontSize: 14)),
                    trailing: Text(
                      _semesterEnd == null
                          ? "未设置"
                          : AppTimeFormats.date(_semesterEnd!),
                    ),
                    onTap: () => _pickSemesterDate(false),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.tips_and_updates_outlined,
                  color: scheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isWeb
                        ? '提示：网页版请使用浏览器文件选择或云端同步导入课表。'
                        : '提示：进入应用后，请前往 设置 > 课程设置 导入或同步您的课表！',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          if (_checkingCloudData) ...[
            const SizedBox(height: 16),
            const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ] else if (_hasCloudCourses || _hasCloudSemester) ...[
            const SizedBox(height: 20),
            Row(
              children: [
                Icon(
                  Icons.cloud_sync_rounded,
                  size: 16,
                  color: scheme.onSurface.withValues(alpha: 0.5),
                ),
                const SizedBox(width: 6),
                Text(
                  '检测到云端数据',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _buildCloudSyncActions(scheme),
          ],
        ],
      ),
    );
  }

  Widget _buildCloudSyncActions(ColorScheme scheme) {
    final courseAction = _hasCloudCourses
        ? _buildCloudSyncAction(
            accentColor: scheme.primary,
            icon: Icons.calendar_month_rounded,
            label: _importingCourses ? '正在导入...' : '从云端同步课表',
            loading: _importingCourses,
            onPressed: _importingCourses ? null : _importCloudCourses,
          )
        : null;
    final semesterAction = _hasCloudSemester
        ? _buildCloudSyncAction(
            accentColor: scheme.secondary,
            icon: Icons.date_range_rounded,
            label: _importingSemester ? '正在同步...' : '从云端同步开学/放假时间',
            loading: _importingSemester,
            onPressed: _importingSemester ? null : _importCloudSemester,
          )
        : null;
    final hasBothActions = courseAction != null && semesterAction != null;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 652),
        child: SizedBox(
          width: double.infinity,
          child: LayoutBuilder(
            builder: (context, constraints) {
              const gap = 12.0;
              const maxActionWidth = 320.0;
              final canFitSideBySide =
                  hasBothActions &&
                  constraints.maxWidth >= maxActionWidth * 2 + gap;

              if (canFitSideBySide) {
                return Row(
                  children: [
                    Expanded(child: courseAction),
                    const SizedBox(width: gap),
                    Expanded(child: semesterAction),
                  ],
                );
              }

              final actionWidth = constraints.maxWidth < maxActionWidth
                  ? constraints.maxWidth
                  : maxActionWidth;
              return Column(
                children: [
                  if (courseAction != null)
                    SizedBox(width: actionWidth, child: courseAction),
                  if (hasBothActions) const SizedBox(height: 10),
                  if (semesterAction != null)
                    SizedBox(width: actionWidth, child: semesterAction),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCloudSyncAction({
    required Color accentColor,
    required IconData icon,
    required String label,
    required bool loading,
    required VoidCallback? onPressed,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final isEnabled = onPressed != null;
    final iconColor = isEnabled || loading
        ? accentColor
        : scheme.onSurface.withValues(alpha: 0.38);
    final labelColor = isEnabled || loading
        ? scheme.onSurface.withValues(alpha: 0.88)
        : scheme.onSurface.withValues(alpha: 0.38);
    final borderRadius = BorderRadius.circular(26);

    return FloatingGlassControl(
      height: 52,
      borderRadius: 26,
      // Keep the glass material neutral and let the action color belong to the
      // icon. Passing accentColor as the glass tint makes sibling actions
      // sample as unrelated blue/gray surfaces on macOS.
      haloColor: scheme.shadow,
      haloOpacity: isEnabled ? 0.42 : 0.18,
      isDark: isDark,
      child: Semantics(
        button: true,
        enabled: isEnabled,
        label: label,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onPressed,
            borderRadius: borderRadius,
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (loading)
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: iconColor,
                          strokeWidth: 2,
                        ),
                      )
                    else
                      Icon(icon, size: 20, color: iconColor),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: labelColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickSemesterDate(bool isStart) async {
    final DateTime initDate = isStart
        ? (_semesterStart ?? DateTime.now())
        : (_semesterEnd ?? DateTime.now().add(const Duration(days: 120)));
    final DateTime? picked = await showAppDatePicker(
      context: context,
      initialDate: initDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      if (!mounted) return;
      _mutateState(() {
        if (isStart) {
          _semesterStart = picked;
        } else {
          _semesterEnd = picked;
        }
      });
      final prefs = await SharedPreferences.getInstance();
      if (isStart) {
        await prefs.setString(
          StorageService.keySemesterStart,
          picked.toIso8601String(),
        );
      } else {
        await prefs.setString(
          StorageService.keySemesterEnd,
          picked.toIso8601String(),
        );
      }
    }
  }

  Widget _buildGlobalThemeSetupPage() {
    final isWeb = AppPlatform.isWeb;
    final scheme = Theme.of(context).colorScheme;
    return _buildPageContainer(
      content: Column(
        children: [
          const SizedBox(height: 16),
          _buildStepHeader(
            icon: Icons.palette_outlined,
            iconColor: Colors.deepPurple,
            title: '个性化：模块排序与主题',
            subtitle: isWeb ? '你可以自由决定首页模块顺序，选择跟随系统、浅色或深色主题，还可以开启液态玻璃效果。' : '你可以自由决定首页上哪个模块显示在最上面。进入设置找到 "模块管理" 即可自由拖拽模块进行排序。\n开启深色模式让你在夜晚操作更舒适，也可以打开下方的液态玻璃效果。',
          ),
          const SizedBox(height: 24),
          const GuideAppearanceOptions(),
          if (isWeb) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.secondaryContainer.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: scheme.secondary.withValues(alpha: 0.22),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: scheme.secondary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '网页版的跟随系统会读取浏览器/操作系统的亮暗偏好，浏览器偏好变化后界面会随应用主题刷新。',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.45,
                        color: scheme.onSurface.withValues(alpha: 0.72),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDeviceCalendarReadSetupPage() {
    return _buildPageContainer(
      content: Column(
        children: [
          const SizedBox(height: 16),
          _buildStepHeader(
            icon: Icons.calendar_view_week_outlined,
            iconColor: Colors.teal,
            title: '可选：读取手机日历',
            subtitle: '把手机中的日程只读展示到首页、周视图和半月/月视图。默认关闭；不会写回系统日历、生成待办、上传或参与同步。',
          ),
          const SizedBox(height: 24),
          const GuideDeviceCalendarReadToggle(),
          const SizedBox(height: 12),
          Text(
            '不想现在开启也没关系，之后可在 设置 → 互联服务 → 读取手机日历 随时调整。',
            style: TextStyle(
              fontSize: 12,
              height: 1.45,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  // ── 辅助 UI 工具 ────────────────────────────────────────

  // ── 页面: Uni-Sync 4.0 迁移引导 (独立定义) ──────────────────

  Widget _buildUniSyncMigrationPage() {
    return _buildPageContainer(
      content: Column(
        children: [
          const SizedBox(height: 24),
          _buildStepHeader(
            icon: Icons.storage_rounded,
            iconColor: Colors.teal,
            title: 'Uni-Sync 4.0 存储主权',
            subtitle: '您的数据已平稳降落。我们已完成从传统 JSON 向工业级 SQLite 存储引擎的跨代迁移。',
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.teal.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.teal.withValues(alpha: 0.2)),
            ),
            child: const Column(
              children: [
                Icon(Icons.verified_user_rounded, color: Colors.teal, size: 48),
                SizedBox(height: 16),
                Text(
                  "本地数据迁移完成",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.teal,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  "单一事实来源 (SSoT) 架构已激活",
                  style: TextStyle(fontSize: 12, color: Colors.teal),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
          _buildMigrationPoint(
            Icons.bolt_rounded,
            "极致搜索性能",
            "基于 FTS5 全文索引，即便万条待办，检索只需毫秒。",
          ),
          const SizedBox(height: 20),
          _buildMigrationPoint(
            Icons.offline_pin_rounded,
            "离线操作拦截",
            "内置 Oplog 离线记录仪，断网改动自动入库，联网秒速对齐。",
          ),
          const SizedBox(height: 20),
          _buildMigrationPoint(
            Icons.security_rounded,
            "核心数据双活",
            "本地 SQL 与 Prefs 互为备份，最大限度抵御外部文件损毁风险。",
          ),
        ],
      ),
    );
  }

  Widget _buildMigrationPoint(IconData icon, String title, String desc) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Colors.teal, size: 24),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                desc,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[600],
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPermissionTile({
    required String title,
    required String subtitle,
    required bool isGranted,
    required VoidCallback onRequest,
    bool optional = false,
  }) {
    return OptionalLiquidGlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      borderRadius: 12,
      highContrast: true,
      tint: isGranted ? Colors.green.withValues(alpha: 0.16) : null,
      fallbackDecoration: BoxDecoration(
        color: isGranted
            ? Colors.green.withValues(alpha: 0.1)
            : Theme.of(context).colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isGranted
              ? Colors.green.withValues(alpha: 0.3)
              : Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    if (optional) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          '强烈推荐',
                          style: TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurface
                        .withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          if (isGranted)
            const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.green, size: 20),
                SizedBox(width: 4),
                Text(
                  '已授权',
                  style: TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ],
            )
          else
            FilledButton.tonal(
              onPressed: onRequest,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                visualDensity: VisualDensity.compact,
              ),
              child: const Text('去开启'),
            ),
        ],
      ),
    );
  }

  // ── 布局搭建 ──────────────────────────────────────────

  Widget _buildLiquidGlassAction({
    required VoidCallback onPressed,
    required IconData icon,
    required String label,
    required bool useGlass,
    double? width,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final foregroundColor = colorScheme.onSurface;
    final borderRadius = BorderRadius.circular(22);
    final isDark = colorScheme.brightness == Brightness.dark;

    final action = Semantics(
      button: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onPressed,
          borderRadius: borderRadius,
          child: SizedBox(
            width: width,
            height: 44,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 20, color: foregroundColor),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: foregroundColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (!useGlass) {
      return Material(
        color: colorScheme.surfaceContainerHighest.withValues(
          alpha: isDark ? 0.92 : 0.68,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: borderRadius,
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(
              alpha: isDark ? 0.7 : 0.8,
            ),
            width: 0.8,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: action,
      );
    }

    return FloatingGlassControl(
      height: 44,
      borderRadius: 22,
      haloColor: colorScheme.primary,
      isDark: colorScheme.brightness == Brightness.dark,
      child: action,
    );
  }
}
