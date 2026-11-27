part of '../add_todo_screen.dart';

extension _AddTodoAiTabExt on _AddTodoScreenState {
  // ================= AI 识别界面 (保持卡片风格) =================
  Widget _buildAIRecognitionTab({Key? key, double topPadding = 0}) {
    return SingleChildScrollView(
      key: key,
      padding: EdgeInsets.fromLTRB(16, topPadding + 8, 16, 8),
      child: Column(
        children: [
          // 🚀 待确认的图片识别事项入口
          if (_pendingTodoConfirm != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AiWaterRippleBorder(
                isLight: Theme.of(context).brightness == Brightness.light,
                child: _buildPendingTodoCard(),
              ),
            ),
          OptionalLiquidGlassCard(
            padding: const EdgeInsets.all(16),
            borderRadius: 16,
            highContrast: true,
            fallbackDecoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 10,
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.auto_awesome,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      "用自然语言描述你的计划",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TextField(
                    controller: _aiInputCtrl,
                    maxLines: 4,
                    minLines: 3,
                    decoration: const InputDecoration(
                      hintText: "例如：明天下午3点开会\n每周一早上9点做周报\n每天早上8点喝水，下午2点开会",
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.all(12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isParsing ? null : _doSmartParse,
                        icon: const Icon(Icons.bolt, size: 18),
                        label: _isParsing
                            ? _buildBouncingDots()
                            : const Text("本地速认"),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AiWaterRippleBorder(
                        isLight:
                            Theme.of(context).brightness == Brightness.light,
                        child: FilledButton.icon(
                          onPressed: _isParsing ? null : _doLLMParse,
                          icon: const Icon(Icons.memory, size: 18),
                          label: _isParsing
                              ? _buildBouncingDots()
                              : const Text("大模型深思"),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          if (_parsedResults.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: AiWaterRippleBorder(
                enabled: _parsedWithAi,
                isLight: Theme.of(context).brightness == Brightness.light,
                child: OptionalLiquidGlassCard(
                  padding: const EdgeInsets.all(16),
                  borderRadius: 16,
                  highContrast: true,
                  fallbackDecoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.02),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "解析结果 (${_currentParseIndex + 1}/${_parsedResults.length})",
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(
                                  Icons.arrow_back_ios,
                                  size: 16,
                                ),
                                onPressed: _currentParseIndex > 0
                                    ? () {
                                        _mutateState(
                                          () => _currentParseIndex--,
                                        );
                                        _applyParsedResult(
                                          _parsedResults[_currentParseIndex],
                                        );
                                      }
                                    : null,
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.arrow_forward_ios,
                                  size: 16,
                                ),
                                onPressed:
                                    _currentParseIndex <
                                        _parsedResults.length - 1
                                    ? () {
                                        _mutateState(
                                          () => _currentParseIndex++,
                                        );
                                        _applyParsedResult(
                                          _parsedResults[_currentParseIndex],
                                        );
                                      }
                                    : null,
                              ),
                            ],
                          ),
                        ],
                      ),
                      const Divider(),
                      _buildParseResultRow(
                        '类型',
                        _parsedKindLabel(_parsedResults[_currentParseIndex]),
                      ),
                      _buildParseResultRow(
                        '内容',
                        _parsedResults[_currentParseIndex].title,
                      ),
                      if (_parsedResults[_currentParseIndex].location
                              ?.trim()
                              .isNotEmpty ==
                          true)
                        _buildParseResultRow(
                          '地点',
                          _parsedResults[_currentParseIndex].location!.trim(),
                        ),
                      if (_parsedResults[_currentParseIndex].remark
                              ?.trim()
                              .isNotEmpty ==
                          true)
                        _buildParseResultRow(
                          '备注',
                          _parsedResults[_currentParseIndex].remark!.trim(),
                        ),
                      _buildParseResultRow(
                        '时间',
                        _parsedTimeLabel(_parsedResults[_currentParseIndex]),
                      ),
                      _buildParseResultRow(
                        "重复",
                        _getRecurrenceLabel(
                          _parsedResults[_currentParseIndex].recurrence,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildParseResultRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(label, style: const TextStyle(color: Colors.grey)),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBouncingDots() {
    final dotColor = Theme.of(context).colorScheme.primary;
    return RepaintBoundary(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(3, (index) {
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            child: AnimatedBuilder(
              animation: _dotsController,
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              builder: (context, child) {
                final double value = _dotsController.value;
                final double delay = index * 0.2;
                final double animationValue = (value + delay) % 1.0;
                final double scale =
                    0.5 + 0.5 * (1.0 - (animationValue - 0.5).abs() * 2.0);
                return Transform.scale(scale: scale, child: child);
              },
            ),
          );
        }),
      ),
    );
  }

  void _startParsingAnimation() {
    if (_dotsController.isAnimating) return;
    _dotsController.repeat();
  }

  void _stopParsingAnimation() {
    _dotsController
      ..stop()
      ..reset();
  }
}
