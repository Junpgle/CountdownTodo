import '../models/minor_mode_state.dart';

enum MinorModeAction {
  aiInteraction,
  llmConfiguration,
  dataImport,
  dataExport,
  updateSource,
  sensitive,
}

enum MinorModeAvailability {
  available,
  parentAuthentication,
  unavailable,
  systemManaged,
}

extension MinorModeAvailabilityLabel on MinorModeAvailability {
  String get label => switch (this) {
        MinorModeAvailability.available => '可用',
        MinorModeAvailability.parentAuthentication => '家长认证',
        MinorModeAvailability.unavailable => '不可用',
        MinorModeAvailability.systemManaged => '系统管理',
      };
}

class MinorModeCapabilityRow {
  final String label;
  final List<MinorModeAvailability> availability;

  const MinorModeCapabilityRow({
    required this.label,
    required this.availability,
  });
}

extension MinorModeActionLabel on MinorModeAction {
  String get label => switch (this) {
        MinorModeAction.aiInteraction => 'AI 功能',
        MinorModeAction.llmConfiguration => '大模型配置',
        MinorModeAction.dataImport => '数据导入',
        MinorModeAction.dataExport => '数据导出',
        MinorModeAction.updateSource => '更新源切换',
        MinorModeAction.sensitive => '此操作',
      };
}

class MinorModeAccessException implements Exception {
  final String message;

  const MinorModeAccessException(this.message);

  @override
  String toString() => message;
}

/// Central policy decisions for operations that may need parent approval.
///
/// The policy deliberately does not block ordinary productivity features or
/// APK updates. Unsupported parent-authentication APIs use a compatibility
/// fallback so users are not permanently locked out of their account.
class MinorModePolicy {
  const MinorModePolicy._();

  static const capabilityAgeBands = [
    MinorAgeBand.under3,
    MinorAgeBand.age3to7,
    MinorAgeBand.age8to11,
    MinorAgeBand.age12to15,
    MinorAgeBand.age16to17,
  ];

  /// The visible permission matrix for the minor-mode settings page.
  ///
  /// The order of each row follows [capabilityAgeBands]. Keep this matrix in
  /// sync with the policy checks below when adding a protected operation.
  static const capabilityRows = [
    MinorModeCapabilityRow(
      label: '基础待办、课程、倒计时、专注',
      availability: [
        MinorModeAvailability.available,
        MinorModeAvailability.available,
        MinorModeAvailability.available,
        MinorModeAvailability.available,
        MinorModeAvailability.available,
      ],
    ),
    MinorModeCapabilityRow(
      label: '提醒、同步、同步重试、时间记录恢复',
      availability: [
        MinorModeAvailability.available,
        MinorModeAvailability.available,
        MinorModeAvailability.available,
        MinorModeAvailability.available,
        MinorModeAvailability.available,
      ],
    ),
    MinorModeCapabilityRow(
      label: 'AI 对话与高级 AI',
      availability: [
        MinorModeAvailability.unavailable,
        MinorModeAvailability.unavailable,
        MinorModeAvailability.unavailable,
        MinorModeAvailability.unavailable,
        MinorModeAvailability.parentAuthentication,
      ],
    ),
    MinorModeCapabilityRow(
      label: '大模型配置与模型列表',
      availability: [
        MinorModeAvailability.parentAuthentication,
        MinorModeAvailability.parentAuthentication,
        MinorModeAvailability.parentAuthentication,
        MinorModeAvailability.parentAuthentication,
        MinorModeAvailability.parentAuthentication,
      ],
    ),
    MinorModeCapabilityRow(
      label: '数据导入',
      availability: [
        MinorModeAvailability.parentAuthentication,
        MinorModeAvailability.parentAuthentication,
        MinorModeAvailability.parentAuthentication,
        MinorModeAvailability.parentAuthentication,
        MinorModeAvailability.parentAuthentication,
      ],
    ),
    MinorModeCapabilityRow(
      label: '数据导出',
      availability: [
        MinorModeAvailability.parentAuthentication,
        MinorModeAvailability.parentAuthentication,
        MinorModeAvailability.parentAuthentication,
        MinorModeAvailability.parentAuthentication,
        MinorModeAvailability.parentAuthentication,
      ],
    ),
    MinorModeCapabilityRow(
      label: '更新源切换',
      availability: [
        MinorModeAvailability.parentAuthentication,
        MinorModeAvailability.parentAuthentication,
        MinorModeAvailability.parentAuthentication,
        MinorModeAvailability.parentAuthentication,
        MinorModeAvailability.parentAuthentication,
      ],
    ),
    MinorModeCapabilityRow(
      label: '敏感权限与设备控制',
      availability: [
        MinorModeAvailability.parentAuthentication,
        MinorModeAvailability.parentAuthentication,
        MinorModeAvailability.parentAuthentication,
        MinorModeAvailability.parentAuthentication,
        MinorModeAvailability.parentAuthentication,
      ],
    ),
    MinorModeCapabilityRow(
      label: '使用时长、休息提醒、应用安装限制',
      availability: [
        MinorModeAvailability.systemManaged,
        MinorModeAvailability.systemManaged,
        MinorModeAvailability.systemManaged,
        MinorModeAvailability.systemManaged,
        MinorModeAvailability.systemManaged,
      ],
    ),
  ];

  static bool isEffective(MinorModeState state) => state.effectiveMinorMode;

  static bool requiresParentAuthentication(MinorModeState state) =>
      state.effectiveMinorMode;

  static bool allowWhenParentAuthenticationUnavailable(
    MinorModeState state,
  ) =>
      state.effectiveMinorMode && !state.parentAuthenticationSupported;

  static bool isAllowedByAge(
    MinorModeState state,
    MinorModeAction action,
  ) {
    if (action != MinorModeAction.aiInteraction) return true;
    return allowsAdvancedAiInteraction(state);
  }

  static bool requiresParentAuthenticationFor(
    MinorModeState state,
    MinorModeAction action,
  ) {
    if (!state.effectiveMinorMode) return false;
    if (!isAllowedByAge(state, action)) return false;
    return true;
  }

  static String denialMessage(
    MinorModeState state,
    MinorModeAction action,
  ) {
    if (!isAllowedByAge(state, action)) {
      return '当前未成年人模式年龄段暂不允许使用高级 AI 功能';
    }
    return '未成年人模式下，${action.label}需要家长身份认证';
  }

  static bool allowsAdvancedAiInteraction(MinorModeState state) {
    if (!state.effectiveMinorMode) return true;
    return switch (state.ageBand) {
      MinorAgeBand.under13 ||
      MinorAgeBand.under3 ||
      MinorAgeBand.age3to7 ||
      MinorAgeBand.age8to11 ||
      MinorAgeBand.age13to15 ||
      MinorAgeBand.age12to15 =>
        false,
      MinorAgeBand.age16to17 || MinorAgeBand.adult => true,
      // An enabled minor mode with no usable age range must not silently
      // fall through to the adult/allowed branch.
      MinorAgeBand.unknown => false,
    };
  }
}
