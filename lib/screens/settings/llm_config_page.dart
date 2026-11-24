import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../services/ai_chat_service.dart';
import '../../services/llm_service.dart';
import '../../services/minor_mode_policy.dart';
import '../../services/minor_mode_service.dart';
import '../../widgets/advanced_ai_tutorial_card.dart';
import '../../widgets/floating_glass_control.dart';
import '../../widgets/optional_liquid_glass_surface.dart';
import '../../utils/app_dialogs.dart';

part 'llm_config/llm_config_catalog.dart';
part 'llm_config/llm_config_logic.dart';
part 'llm_config/llm_config_steps.dart';
part 'llm_config/llm_config_dialogs.dart';

class TextModelInfo {
  final String id;
  final String name;
  final String description;
  final String context;
  final String maxOutput;
  final bool isPaid;
  final String provider;

  const TextModelInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.context,
    required this.maxOutput,
    this.isPaid = false,
    this.provider = 'zhipu',
  });
}

class VisionModelInfo {
  final String id;
  final String name;
  final String description;
  final String? context;
  final String? maxOutput;
  final bool isPaid;
  final String provider;

  const VisionModelInfo({
    required this.id,
    required this.name,
    required this.description,
    this.context,
    this.maxOutput,
    this.isPaid = false,
    this.provider = 'zhipu',
  });
}

enum _ModelSelectionTarget { text, vision }

class LLMConfigPage extends StatefulWidget {
  final bool isEmbedded;
  final int? initialStep;
  final String? initialTarget;
  const LLMConfigPage({
    super.key,
    this.isEmbedded = false,
    this.initialStep,
    this.initialTarget,
  });

  @override
  State<LLMConfigPage> createState() => _LLMConfigPageState();
}

class _LLMConfigPageState extends State<LLMConfigPage> {
  final _presetApiKeyCtrl = TextEditingController();
  final _textPromptCtrl = TextEditingController();
  final _visionPromptCtrl = TextEditingController();
  bool _isLoading = true;
  bool _accessDenied = false;
  bool _isTesting = false;
  String? _selectedTextModel;
  String? _selectedVisionModel;
  List<CustomTextModel> _customTextModels = [];
  List<CustomVisionModel> _customVisionModels = [];
  final Map<String, List<TextModelInfo>> _fetchedTextModelsByProvider = {};
  final Map<String, List<VisionModelInfo>> _fetchedVisionModelsByProvider = {};
  String _zhipuApiKey = '';
  String _mimoApiKey = '';
  String _mimoTokenPlanApiKey = '';
  String _deepseekApiKey = '';
  String _nvidiaNimApiKey = '';
  String _selectedTextModelProvider = 'zhipu';
  String _selectedVisionModelProvider = 'zhipu';
  int _currentStep = 0;
  final _uuid = const Uuid();

  void _mutateState(VoidCallback fn) => setState(fn);

  @override
  void initState() {
    super.initState();
    _authorizeAndLoadConfig();
  }

  @override
  void dispose() {
    _presetApiKeyCtrl.dispose();
    _textPromptCtrl.dispose();
    _visionPromptCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final standalone = !widget.isEmbedded;
    final content = _isLoading
        ? const Center(child: CircularProgressIndicator())
        : _accessDenied
        ? _buildAccessDeniedBody(context)
        : LayoutBuilder(
            builder: (context, constraints) {
              final wide = _useWideLayout(constraints.maxWidth);
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1180),
                  child: MediaQuery.removePadding(
                    context: context,
                    removeTop: true,
                    child: Stepper(
                      type: wide
                          ? StepperType.horizontal
                          : StepperType.vertical,
                      margin: wide
                          ? const EdgeInsets.fromLTRB(24, 12, 24, 24)
                          : null,
                      currentStep: _currentStep,
                      onStepContinue: () {
                        if (_currentStep < 2) {
                          setState(() => _currentStep++);
                        } else {
                          _saveConfig();
                        }
                      },
                      onStepCancel: () {
                        if (_currentStep > 0) {
                          setState(() => _currentStep--);
                        }
                      },
                      onStepTapped: (step) {
                        // 只允许点击已完成的步骤或当前步骤
                        if (step <= _currentStep) {
                          setState(() => _currentStep = step);
                        }
                      },
                      controlsBuilder: (context, details) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 20),
                          child: Row(
                            mainAxisAlignment: wide
                                ? MainAxisAlignment.end
                                : MainAxisAlignment.start,
                            children: [
                              if (_currentStep < 2)
                                FilledButton.icon(
                                  onPressed: details.onStepContinue,
                                  icon: const Icon(
                                    Icons.arrow_forward,
                                    size: 18,
                                  ),
                                  label: const Text('下一步'),
                                )
                              else
                                FilledButton.icon(
                                  onPressed: _isTesting
                                      ? null
                                      : details.onStepContinue,
                                  icon: const Icon(Icons.save, size: 18),
                                  label: const Text('保存配置'),
                                ),
                              if (_currentStep > 0) ...[
                                const SizedBox(width: 12),
                                OutlinedButton.icon(
                                  onPressed: details.onStepCancel,
                                  icon: const Icon(Icons.arrow_back, size: 18),
                                  label: const Text('上一步'),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                      steps: [
                        Step(
                          title: const Text('了解服务商'),
                          content: _buildStep1Provider(),
                          isActive: _currentStep >= 0,
                          state: _currentStep > 0
                              ? StepState.complete
                              : StepState.indexed,
                        ),
                        Step(
                          title: const Text('配置 API Key'),
                          content: _buildStep2ApiKey(),
                          isActive: _currentStep >= 1,
                          state: _currentStep > 1
                              ? StepState.complete
                              : _currentStep == 1
                              ? StepState.indexed
                              : StepState.disabled,
                        ),
                        Step(
                          title: const Text('选择模型'),
                          content: _buildStep3Models(),
                          isActive: _currentStep >= 2,
                          state: _currentStep == 2
                              ? StepState.indexed
                              : StepState.disabled,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );

    return Scaffold(
      extendBodyBehindAppBar: standalone,
      appBar: widget.isEmbedded
          ? null
          : FloatingGlassAppBar(
              flexibleSpace: const FloatingGlassTopBarBackground(),
              title: const Text('模型与 API 配置'),
              actions: _accessDenied
                  ? const []
                  : [
                      IconButton(
                        onPressed: () async {
                          final confirmed = await showAppDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('清除配置'),
                              content: const Text('确定要清除所有大模型配置吗？'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('取消'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: Colors.red,
                                  ),
                                  child: const Text('清除'),
                                ),
                              ],
                            ),
                          );
                          if (confirmed == true) {
                            if (!await _ensureLlmConfigurationAllowed()) {
                              return;
                            }
                            await LLMService.clearConfig();
                            if (context.mounted) {
                              Navigator.pop(context, true);
                              AppSnackBars.showSnackBar(
                                context,
                                const SnackBar(content: Text('已清除大模型配置')),
                              );
                            }
                          }
                        },
                        icon: const Icon(Icons.delete_outline),
                        tooltip: '清除配置',
                      ),
                    ],
            ),
      body: floatingGlassSettingsBody(
        context,
        standalone: standalone,
        child: standalone
            ? Padding(
                padding: EdgeInsets.only(
                  top: floatingGlassSettingsContentTopInset(context),
                ),
                child: content,
              )
            : content,
      ),
    );
  }

  Widget _buildChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, color: Colors.grey[700]),
      ),
    );
  }
}
