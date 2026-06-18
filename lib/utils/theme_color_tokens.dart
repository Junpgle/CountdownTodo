import 'package:flutter/material.dart';

extension CdtColorTokens on ColorScheme {
  Color get cdtSuccess => tertiary;
  Color get cdtSuccessContainer => tertiaryContainer;
  Color get cdtOnSuccessContainer => onTertiaryContainer;

  Color get cdtWarning => secondary;
  Color get cdtWarningContainer => secondaryContainer;
  Color get cdtOnWarningContainer => onSecondaryContainer;

  Color get cdtInfo => primary;
  Color get cdtInfoContainer => primaryContainer;
  Color get cdtOnInfoContainer => onPrimaryContainer;

  Color get cdtFocus => error;
  Color get cdtFocusContainer => errorContainer;

  Color get cdtDisabled => onSurface.withValues(alpha: 0.45);
  Color get cdtDivider => outlineVariant.withValues(alpha: 0.65);
}
