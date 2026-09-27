import 'package:flutter/material.dart';

import '../services/finance_expression_calculator.dart';

Widget _plainButtonLayerBuilder(
  BuildContext context,
  Set<WidgetState> states,
  Widget? child,
) {
  return child ?? const SizedBox.shrink();
}

ThemeData _calculatorTheme(ThemeData base) {
  final colors = base.colorScheme;
  final buttonShape = WidgetStatePropertyAll<OutlinedBorder>(
    RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  );
  final noSide = WidgetStatePropertyAll<BorderSide?>(BorderSide.none);
  final overlayColor = WidgetStateProperty.resolveWith<Color?>((states) {
    if (states.contains(WidgetState.pressed)) {
      return colors.onSurface.withValues(alpha: 0.1);
    }
    if (states.contains(WidgetState.hovered) ||
        states.contains(WidgetState.focused)) {
      return colors.onSurface.withValues(alpha: 0.06);
    }
    return Colors.transparent;
  });

  final filledButtonStyle = ButtonStyle(
    backgroundBuilder: _plainButtonLayerBuilder,
    backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
      if (states.contains(WidgetState.disabled)) {
        return colors.surfaceContainerHighest;
      }
      return colors.primary;
    }),
    foregroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
      if (states.contains(WidgetState.disabled)) {
        return colors.onSurfaceVariant;
      }
      return colors.onPrimary;
    }),
    overlayColor: overlayColor,
    side: noSide,
    shape: buttonShape,
    elevation: const WidgetStatePropertyAll(0.0),
    shadowColor: const WidgetStatePropertyAll(Colors.transparent),
    surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
    animationDuration: const Duration(milliseconds: 90),
  );
  final textButtonStyle = ButtonStyle(
    backgroundBuilder: _plainButtonLayerBuilder,
    backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
    foregroundColor: WidgetStatePropertyAll(colors.primary),
    overlayColor: overlayColor,
    side: noSide,
    shape: WidgetStatePropertyAll<OutlinedBorder>(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    elevation: const WidgetStatePropertyAll(0.0),
    shadowColor: const WidgetStatePropertyAll(Colors.transparent),
    surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
    animationDuration: const Duration(milliseconds: 90),
  );
  final iconButtonStyle = ButtonStyle(
    backgroundBuilder: _plainButtonLayerBuilder,
    backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
    foregroundColor: WidgetStatePropertyAll(colors.onSurfaceVariant),
    overlayColor: overlayColor,
    side: noSide,
    shape: const WidgetStatePropertyAll<OutlinedBorder>(CircleBorder()),
    elevation: const WidgetStatePropertyAll(0.0),
    shadowColor: const WidgetStatePropertyAll(Colors.transparent),
    surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
    animationDuration: const Duration(milliseconds: 90),
  );

  return base.copyWith(
    filledButtonTheme: FilledButtonThemeData(style: filledButtonStyle),
    textButtonTheme: TextButtonThemeData(style: textButtonStyle),
    iconButtonTheme: IconButtonThemeData(style: iconButtonStyle),
  );
}

/// The amount and the expression that produced it when the calculator closes.
class FinanceAmountCalculation {
  final String expression;
  final String amount;

  const FinanceAmountCalculation({
    required this.expression,
    required this.amount,
  });
}

/// Opens the keypad used to calculate a transaction amount without invoking
/// the platform input method.
Future<FinanceAmountCalculation?> showFinanceAmountCalculator(
  BuildContext context, {
  String initialExpression = '',
}) {
  final colors = Theme.of(context).colorScheme;
  return showModalBottomSheet<FinanceAmountCalculation>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    requestFocus: false,
    backgroundColor: colors.surface,
    barrierColor: colors.scrim.withValues(alpha: 0.48),
    elevation: 0,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    clipBehavior: Clip.antiAlias,
    sheetAnimationStyle: const AnimationStyle(
      duration: Duration(milliseconds: 190),
      reverseDuration: Duration(milliseconds: 150),
    ),
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.86,
    ),
    builder: (_) => FinanceAmountCalculatorSheet(
      initialExpression: initialExpression,
    ),
  );
}

class FinanceAmountCalculatorSheet extends StatefulWidget {
  final String initialExpression;

  const FinanceAmountCalculatorSheet({
    super.key,
    this.initialExpression = '',
  });

  @override
  State<FinanceAmountCalculatorSheet> createState() =>
      _FinanceAmountCalculatorSheetState();
}

class _FinanceAmountCalculatorSheetState
    extends State<FinanceAmountCalculatorSheet> {
  late final TextEditingController _expressionController;
  late final FocusNode _expressionFocusNode;
  FinanceExpressionValue? _result;
  String? _error;
  bool _showValidationError = false;

  bool get _canUseResult {
    final result = _result;
    if (result == null) return false;
    return FinanceExpressionCalculator.roundToCents(result) > BigInt.zero;
  }

  String? get _formattedResult {
    final result = _result;
    if (result == null) return null;
    return FinanceExpressionCalculator.formatResult(result);
  }

  @override
  void initState() {
    super.initState();
    _expressionController = TextEditingController(
      text: widget.initialExpression.replaceAll(',', '').trim(),
    );
    _expressionFocusNode = FocusNode();
    _recalculate();
  }

  @override
  void dispose() {
    _expressionController.dispose();
    _expressionFocusNode.dispose();
    super.dispose();
  }

  void _recalculate() {
    final expression = _expressionController.text.trim();
    if (expression.isEmpty) {
      _result = null;
      _error = null;
      return;
    }
    try {
      final value = FinanceExpressionCalculator.evaluate(expression);
      _result = value;
      _error = _showValidationError &&
              FinanceExpressionCalculator.roundToCents(value) <= BigInt.zero
          ? '结果必须大于 0'
          : null;
    } on FinanceExpressionException catch (error) {
      _result = null;
      _error = error.message;
    }
  }

  TextSelection _safeSelection() {
    final text = _expressionController.text;
    final selection = _expressionController.selection;
    if (!selection.isValid ||
        selection.start < 0 ||
        selection.end > text.length) {
      return TextSelection.collapsed(offset: text.length);
    }
    return selection;
  }

  void _replaceSelection(String value) {
    final text = _expressionController.text;
    final selection = _safeSelection();
    final start = selection.start;
    final end = selection.end;
    final nextText = text.replaceRange(start, end, value);
    final nextOffset = start + value.length;
    _expressionController.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextOffset),
    );
    _showValidationError = false;
    _recalculate();
    setState(() {});
  }

  void _deleteBackward() {
    final text = _expressionController.text;
    final selection = _safeSelection();
    if (selection.start == 0 && selection.isCollapsed) return;
    final start = selection.isCollapsed ? selection.start - 1 : selection.start;
    final nextText = text.replaceRange(start, selection.end, '');
    _expressionController.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: start),
    );
    _showValidationError = false;
    _recalculate();
    setState(() {});
  }

  void _clear() {
    if (_expressionController.text.isEmpty) return;
    _expressionController.clear();
    _showValidationError = false;
    _recalculate();
    setState(() {});
  }

  void _evaluate() {
    _showValidationError = true;
    _recalculate();
    setState(() {});
  }

  void _useResult() {
    _showValidationError = true;
    _recalculate();
    final result = _result;
    if (result == null || !_canUseResult) {
      setState(() {});
      return;
    }
    Navigator.of(context).pop(
      FinanceAmountCalculation(
        expression: _expressionController.text.trim(),
        amount: FinanceExpressionCalculator.formatResult(result),
      ),
    );
  }

  Widget _buildKeyRow(List<Widget> children) {
    return Row(
      children: [
        for (final child in children) Expanded(child: child),
      ],
    );
  }

  Widget _buildTextKey({
    required String keyName,
    required String label,
    required String value,
    bool isOperator = false,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(4),
      child: SizedBox(
        height: 54,
        child: FilledButton(
          key: ValueKey('finance-calculator-key-$keyName'),
          style: FilledButton.styleFrom(
            backgroundColor: isOperator
                ? colors.secondaryContainer
                : colors.surfaceContainerHighest,
            foregroundColor:
                isOperator ? colors.onSecondaryContainer : colors.onSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          onPressed: () => _replaceSelection(value),
          child: Text(
            label,
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }

  Widget _buildIconKey({
    required String keyName,
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(4),
      child: SizedBox(
        height: 54,
        child: FilledButton(
          key: ValueKey('finance-calculator-key-$keyName'),
          style: FilledButton.styleFrom(
            backgroundColor: colors.surfaceContainerHighest,
            foregroundColor: colors.onSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          onPressed: onPressed,
          child: Tooltip(message: tooltip, child: Icon(icon)),
        ),
      ),
    );
  }

  Widget _buildActionKey({
    required String keyName,
    required String label,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(4),
      child: SizedBox(
        height: 54,
        child: FilledButton(
          key: ValueKey('finance-calculator-key-$keyName'),
          style: FilledButton.styleFrom(
            backgroundColor: colors.surfaceContainerHighest,
            foregroundColor: colors.onSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          onPressed: onPressed,
          child: Tooltip(
            message: tooltip,
            child: Text(
              label,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEqualsKey() {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(4),
      child: SizedBox(
        height: 54,
        child: FilledButton(
          key: const ValueKey('finance-calculator-key-equals'),
          style: FilledButton.styleFrom(
            backgroundColor: colors.primary,
            foregroundColor: colors.onPrimary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          onPressed: _evaluate,
          child: const Text(
            '=',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final result = _formattedResult;
    final helperText = _showValidationError && _error != null
        ? null
        : '支持 +、−、×、÷ 和括号；点击计算过程可移动光标';

    return RepaintBoundary(
      child: Theme(
        data: _calculatorTheme(theme),
        child: Material(
          color: colors.surface,
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 24,
                    child: Center(
                      child: Container(
                        width: 38,
                        height: 4,
                        decoration: BoxDecoration(
                          color:
                              colors.onSurfaceVariant.withValues(alpha: 0.72),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                    child: Row(
                      children: [
                        Icon(Icons.calculate_outlined, color: colors.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '金额计算器',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        TextButton(
                          key: const ValueKey('finance-calculator-clear'),
                          onPressed: _clear,
                          child: const Text('清空'),
                        ),
                      ],
                    ),
                  ),
                  TextField(
                    key: const ValueKey('finance-calculator-expression'),
                    controller: _expressionController,
                    focusNode: _expressionFocusNode,
                    readOnly: true,
                    showCursor: true,
                    enableInteractiveSelection: true,
                    maxLines: 2,
                    textAlign: TextAlign.end,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colors.onSurface,
                    ),
                    decoration: InputDecoration(
                      labelText: '计算过程（可编辑）',
                      hintText: '输入数字和运算符',
                      helperText: helperText,
                      helperMaxLines: 2,
                      errorText: _showValidationError && _error != null
                          ? _error
                          : null,
                      prefixIcon:
                          Icon(Icons.edit_outlined, color: colors.primary),
                      suffixIcon: IconButton(
                        tooltip: '删除一位',
                        onPressed: _deleteBackward,
                        icon: const Icon(Icons.backspace_outlined),
                      ),
                      filled: true,
                      fillColor: colors.surfaceContainerLow,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                  if (result != null) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text.rich(
                        TextSpan(
                          text: '= ',
                          style: TextStyle(color: colors.onSurfaceVariant),
                          children: [
                            TextSpan(
                              text: result,
                              style: TextStyle(
                                color: _canUseResult
                                    ? colors.primary
                                    : colors.error,
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  _buildKeyRow([
                    _buildTextKey(
                      keyName: 'left-parenthesis',
                      label: '(',
                      value: '(',
                      isOperator: true,
                    ),
                    _buildTextKey(
                      keyName: 'right-parenthesis',
                      label: ')',
                      value: ')',
                      isOperator: true,
                    ),
                    _buildIconKey(
                      keyName: 'backspace',
                      icon: Icons.backspace_outlined,
                      tooltip: '删除一位',
                      onPressed: _deleteBackward,
                    ),
                    _buildActionKey(
                      keyName: 'clear',
                      label: '清除',
                      tooltip: '清除全部',
                      onPressed: _clear,
                    ),
                  ]),
                  _buildKeyRow([
                    _buildTextKey(keyName: '7', label: '7', value: '7'),
                    _buildTextKey(keyName: '8', label: '8', value: '8'),
                    _buildTextKey(keyName: '9', label: '9', value: '9'),
                    _buildTextKey(
                      keyName: 'divide',
                      label: '÷',
                      value: '/',
                      isOperator: true,
                    ),
                  ]),
                  _buildKeyRow([
                    _buildTextKey(keyName: '4', label: '4', value: '4'),
                    _buildTextKey(keyName: '5', label: '5', value: '5'),
                    _buildTextKey(keyName: '6', label: '6', value: '6'),
                    _buildTextKey(
                      keyName: 'multiply',
                      label: '×',
                      value: '*',
                      isOperator: true,
                    ),
                  ]),
                  _buildKeyRow([
                    _buildTextKey(keyName: '1', label: '1', value: '1'),
                    _buildTextKey(keyName: '2', label: '2', value: '2'),
                    _buildTextKey(keyName: '3', label: '3', value: '3'),
                    _buildTextKey(
                      keyName: 'subtract',
                      label: '−',
                      value: '-',
                      isOperator: true,
                    ),
                  ]),
                  _buildKeyRow([
                    _buildTextKey(keyName: '0', label: '0', value: '0'),
                    _buildTextKey(keyName: 'decimal', label: '.', value: '.'),
                    _buildTextKey(
                      keyName: 'add',
                      label: '+',
                      value: '+',
                      isOperator: true,
                    ),
                    _buildEqualsKey(),
                  ]),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    key: const ValueKey('finance-calculator-use-result'),
                    onPressed: _canUseResult ? _useResult : null,
                    icon: const Icon(Icons.done_rounded),
                    label: Text(
                      result == null ? '先完成计算' : '使用结果 ¥$result',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
