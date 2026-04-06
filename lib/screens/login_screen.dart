import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../services/api_service.dart';
import '../storage_service.dart';
import '../widgets/privacy_policy_dialog.dart';
import 'home_dashboard.dart';
import '../utils/page_transitions.dart';

// ─────────────────────────────────────────────
//  Adaptive color tokens
//  Usage: final t = _T(context);  t.bg / t.primary / …
// ─────────────────────────────────────────────
class _T {
  _T(BuildContext context)
      : _dark = Theme.of(context).brightness == Brightness.dark;

  final bool _dark;

  // ── Scaffolding ──
  Color get bg => _dark ? const Color(0xFF0D0D1C) : const Color(0xFFF2F2FA);
  Color get surface =>
      _dark ? const Color(0xFF13131F) : const Color(0xFFFFFFFF);
  Color get card => _dark ? const Color(0xFF1A1A2A) : const Color(0xFFFFFFFF);

  // ── Borders ──
  Color get border => _dark ? const Color(0x1AFFFFFF) : const Color(0x22000000);
  Color get borderFocus => const Color(0x806C63FF);

  // ── Brand (same in both modes) ──
  static const primary = Color(0xFF6C63FF);
  static const primaryLt = Color(0xFF8B85FF);
  static const accent = Color(0xFFFF6B9D);
  static const success = Color(0xFF4CAF50);

  // ── Text ──
  Color get textPri =>
      _dark ? const Color(0xFFFFFFFF) : const Color(0xFF1A1A2E);
  Color get textSec =>
      _dark ? const Color(0x99FFFFFF) : const Color(0xFF5A5A7A);
  Color get textHint =>
      _dark ? const Color(0x55FFFFFF) : const Color(0xFFAAAAAA);

  // ── Inputs ──
  Color get inputBg =>
      _dark ? const Color(0x0DFFFFFF) : const Color(0xFFF8F8FF);
  Color get inputBgF =>
      _dark ? const Color(0x126C63FF) : const Color(0xFFEEECFF);
  Color get inputBd =>
      _dark ? const Color(0x1AFFFFFF) : const Color(0xFFDDDDEE);

  // ── Amber / legacy banner ──
  Color get amber => _dark ? const Color(0xFFFFB74D) : const Color(0xFF7A5200);
  Color get amberBg =>
      _dark ? const Color(0x1AFFB74D) : const Color(0xFFFFF8E1);
  Color get amberBd =>
      _dark ? const Color(0x40FFB74D) : const Color(0xFFFFCC80);
  Color get amberEm =>
      _dark ? const Color(0xFFFFE082) : const Color(0xFF9A6500);

  // ── Wide-left panel ──
  List<Color> get leftGrad => _dark
      ? const [Color(0xFF140E38), Color(0xFF0F0A2E)]
      : const [Color(0xFF6C63FF), Color(0xFF9C8FFF)];
  Color get leftTextSec =>
      _dark ? const Color(0x99FFFFFF) : const Color(0xCCFFFFFF);
  Color get leftFeatureBg =>
      _dark ? const Color(0x286C63FF) : const Color(0x33FFFFFF);
  Color get leftFeatureBd =>
      _dark ? const Color(0x446C63FF) : const Color(0x55FFFFFF);

  // ── Tab switcher ──
  Color get tabActiveBg =>
      _dark ? const Color(0x406C63FF) : const Color(0xFFEEECFF);
  Color get tabActiveBd =>
      _dark ? const Color(0x666C63FF) : const Color(0xFF6C63FF);
  Color get tabActiveText =>
      _dark ? const Color(0xFFB8B3FF) : const Color(0xFF4A43D4);

  // ── Misc ──
  Color get otpBg => _dark ? const Color(0x126C63FF) : const Color(0xFFEEECFF);
  Color get verifyIconBg =>
      _dark ? const Color(0x286C63FF) : const Color(0xFFEEECFF);
  Color get verifyIconBd =>
      _dark ? const Color(0x446C63FF) : const Color(0xFF9C8FFF);
  Color get dropdownBg =>
      _dark ? const Color(0xFF1A1A2A) : const Color(0xFFFFFFFF);
}

// ─────────────────────────────────────────────
//  Background orb painter  (repaints on theme switch)
// ─────────────────────────────────────────────
class _OrbPainter extends CustomPainter {
  const _OrbPainter({required this.dark});
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final a1 = dark ? 0.20 : 0.10;
    final a2 = dark ? 0.12 : 0.07;

    canvas.drawCircle(
      Offset(size.width * 0.88, size.height * 0.10),
      240,
      Paint()
        ..shader = RadialGradient(
          colors: [_T.primary.withOpacity(a1), Colors.transparent],
        ).createShader(Rect.fromCircle(
            center: Offset(size.width * 0.88, size.height * 0.10),
            radius: 240)),
    );

    canvas.drawCircle(
      Offset(size.width * 0.08, size.height * 0.80),
      200,
      Paint()
        ..shader = RadialGradient(
          colors: [_T.accent.withOpacity(a2), Colors.transparent],
        ).createShader(Rect.fromCircle(
            center: Offset(size.width * 0.08, size.height * 0.80),
            radius: 200)),
    );
  }

  @override
  bool shouldRepaint(_OrbPainter old) => old.dark != dark;
}

// ─────────────────────────────────────────────
//  Reusable labelled text field
// ─────────────────────────────────────────────
class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.obscure = false,
    this.enabled = true,
    this.keyboardType,
    this.textAlign,
    this.style,
    this.maxLength,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final bool obscure;
  final bool enabled;
  final TextInputType? keyboardType;
  final TextAlign? textAlign;
  final TextStyle? style;
  final int? maxLength;

  @override
  Widget build(BuildContext context) {
    final t = _T(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.9,
            color: t.textHint,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: obscure,
          enabled: enabled,
          keyboardType: keyboardType,
          textAlign: textAlign ?? TextAlign.start,
          style: style ??
              TextStyle(
                fontSize: 15,
                color: t.textPri,
                fontWeight: FontWeight.w400,
              ),
          maxLength: maxLength,
          buildCounter: maxLength != null
              ? (_, {required currentLength, required isFocused, maxLength}) =>
                  null
              : null,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: t.textHint, fontSize: 15),
            prefixIcon: Icon(icon, size: 18, color: t.textHint),
            filled: true,
            fillColor: t.inputBg,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: t.inputBd, width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: t.borderFocus, width: 1.5),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide:
                  BorderSide(color: t.border.withOpacity(0.4), width: 1),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
//  Primary gradient button
// ─────────────────────────────────────────────
class _PrimaryBtn extends StatelessWidget {
  const _PrimaryBtn({
    required this.label,
    required this.onPressed,
    this.isAccent = false,
  });
  final String label;
  final VoidCallback onPressed;
  final bool isAccent;

  @override
  Widget build(BuildContext context) {
    final colors = isAccent
        ? [_T.accent, const Color(0xFFFF8F6B)]
        : [_T.primary, _T.primaryLt];
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: colors,
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: colors.first.withOpacity(0.35),
              blurRadius: 18,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.white,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Brand logo
// ─────────────────────────────────────────────
class _BrandLogo extends StatelessWidget {
  const _BrandLogo({this.size = 52});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_T.primary, _T.accent],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(size * 0.28),
        boxShadow: [
          BoxShadow(
            color: _T.primary.withOpacity(0.38),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Icon(Icons.bolt_rounded, color: Colors.white, size: size * 0.52),
    );
  }
}

// ─────────────────────────────────────────────
//  Tab switcher  (登录 / 注册)
// ─────────────────────────────────────────────
class _TabSwitcher extends StatelessWidget {
  const _TabSwitcher({required this.isRegister, required this.onToggle});
  final bool isRegister;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final t = _T(context);
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: t.inputBg,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: t.border, width: 1),
      ),
      child: Row(children: [
        _tab(context, t, '登录', !isRegister),
        _tab(context, t, '注册', isRegister),
      ]),
    );
  }

  Widget _tab(BuildContext context, _T t, String label, bool active) {
    return Expanded(
      child: GestureDetector(
        onTap: active ? null : onToggle,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          decoration: BoxDecoration(
            color: active ? t.tabActiveBg : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: active ? Border.all(color: t.tabActiveBd, width: 1) : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
              color: active ? t.tabActiveText : t.textHint,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Server selector
// ─────────────────────────────────────────────
class _ServerSelector extends StatelessWidget {
  const _ServerSelector({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = _T(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration:
              const BoxDecoration(color: _T.success, shape: BoxShape.circle),
        ),
        const SizedBox(width: 7),
        Text('服务器：', style: TextStyle(fontSize: 12, color: t.textHint)),
        DropdownButton<String>(
          value: value,
          underline: const SizedBox(),
          dropdownColor: t.dropdownBg,
          icon: Icon(Icons.keyboard_arrow_down_rounded,
              size: 16, color: t.textHint),
          style: const TextStyle(
              color: _T.primaryLt, fontSize: 12, fontWeight: FontWeight.w500),
          items: [
            DropdownMenuItem(
                value: 'cloudflare',
                child: Text('Cloudflare（推荐）',
                    style: TextStyle(color: _T.primaryLt))),
            DropdownMenuItem(
                value: 'aliyun',
                child: Text('阿里云 ECS', style: TextStyle(color: t.textSec))),
          ],
          onChanged: onChanged,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
//  Legacy-data migration banner
// ─────────────────────────────────────────────
class _LegacyBanner extends StatelessWidget {
  const _LegacyBanner({required this.username});
  final String username;

  @override
  Widget build(BuildContext context) {
    final t = _T(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: t.amberBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.amberBd, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 3),
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: t.amber, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(fontSize: 12.5, color: t.amber, height: 1.55),
                children: [
                  const TextSpan(text: '检测到本地存档 '),
                  TextSpan(
                    text: username,
                    style: TextStyle(
                        fontWeight: FontWeight.w600, color: t.amberEm),
                  ),
                  const TextSpan(text: '，注册后将自动迁移数据至云端'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  6-digit OTP input with per-digit scale bounce
// ─────────────────────────────────────────────
class _OtpInput extends StatefulWidget {
  const _OtpInput({required this.controller});
  final TextEditingController controller;

  @override
  State<_OtpInput> createState() => _OtpInputState();
}

class _OtpInputState extends State<_OtpInput> with TickerProviderStateMixin {
  String _prevText = '';
  final Map<int, AnimationController> _controllers = {};
  final Map<int, Animation<double>> _animations = {};

  @override
  void initState() {
    super.initState();
    _prevText = widget.controller.text;
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _onTextChanged() {
    final current = widget.controller.text;
    if (current.length != _prevText.length) {
      if (current.length > _prevText.length) {
        final idx = current.length - 1;
        if (!_controllers.containsKey(idx)) {
          final ctrl = AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 300),
          );
          _controllers[idx] = ctrl;
          _animations[idx] = CurvedAnimation(
            parent: ctrl,
            curve: Curves.easeOutBack,
          );
        }
        _controllers[idx]!.forward(from: 0.0);
      }
    }
    _prevText = current;
  }

  @override
  Widget build(BuildContext context) {
    final t = _T(context);
    return TextField(
      controller: widget.controller,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      maxLength: 6,
      style: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w600,
        color: t.textPri,
        letterSpacing: 12,
      ),
      buildCounter:
          (_, {required currentLength, required isFocused, maxLength}) => null,
      decoration: InputDecoration(
        hintText: '——————',
        hintStyle:
            TextStyle(fontSize: 20, color: t.textHint, letterSpacing: 10),
        filled: true,
        fillColor: t.otpBg,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: t.borderFocus, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: _T.primaryLt, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Wide-screen left decorative panel
// ─────────────────────────────────────────────
class _WideLeftPanel extends StatelessWidget {
  const _WideLeftPanel();

  @override
  Widget build(BuildContext context) {
    final t = _T(context);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: t.leftGrad,
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
      ),
      padding: const EdgeInsets.all(48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _BrandLogo(size: 56),
          const SizedBox(height: 36),
          const Text(
            '专注你的\n每一天',
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '待办、倒计时、番茄钟，\n多端实时同步，让效率触手可及。',
            style: TextStyle(
              fontSize: 14,
              color: t.leftTextSec,
              height: 1.7,
            ),
          ),
          const Spacer(),
          ...[
            (Icons.timer_outlined, '番茄钟跨设备实时感知'),
            (Icons.event_outlined, '倒计时 & 重要日提醒'),
            (Icons.cloud_sync_outlined, '增量同步，流量低消耗'),
          ].map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: t.leftFeatureBg,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: t.leftFeatureBd, width: 1),
                    ),
                    child: Icon(e.$1, size: 16, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Text(e.$2,
                      style: TextStyle(fontSize: 13.5, color: t.leftTextSec)),
                ]),
              )),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Shared loading spinner
// ─────────────────────────────────────────────
class _Spinner extends StatelessWidget {
  const _Spinner();
  @override
  Widget build(BuildContext context) => const Center(
        child: SizedBox(
          width: 32,
          height: 32,
          child:
              CircularProgressIndicator(strokeWidth: 2.5, color: _T.primaryLt),
        ),
      );
}

// ─────────────────────────────────────────────
//  LoginScreen
// ─────────────────────────────────────────────
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final _userCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();

  bool _isLoading = false;
  bool _isRegisterMode = false;
  bool _awaitingVerification = false;
  String? _legacyLocalUser;
  String _serverChoice = 'cloudflare';
  bool _privacyAgreed = false;
  int _forgotPasswordStep = 0;
  final _resetEmailCtrl = TextEditingController();
  final _resetCodeCtrl = TextEditingController();
  final _newPassCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();
  int _resetCodeCooldown = 0;
  Timer? _cooldownTimer;

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;
  late final AnimationController _slideCtrl;
  late final Animation<Offset> _slideAnim;

  // ── Lifecycle ────────────────────────────────

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 480));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _slideCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 480));
    _slideAnim = Tween<Offset>(
      begin: const Offset(0.15, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));
    _fadeCtrl.forward();
    _slideCtrl.forward();
    _checkLocalLegacyAccount();
    _loadServerChoice();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _fadeCtrl.dispose();
    _slideCtrl.dispose();
    _userCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _codeCtrl.dispose();
    _resetEmailCtrl.dispose();
    _resetCodeCtrl.dispose();
    _newPassCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }

  // ── Persistence helpers ──────────────────────

  void _loadServerChoice() async {
    final choice = await StorageService.getServerChoice();
    if (mounted) setState(() => _serverChoice = choice);
  }

  void _onServerChoiceChanged(String? val) async {
    if (val == null) return;
    setState(() => _serverChoice = val);
    ApiService.setServerChoice(val);
    await StorageService.saveServerChoice(val);
  }

  void _checkLocalLegacyAccount() async {
    final prefs = await SharedPreferences.getInstance();
    final legacyUser = prefs.getString('login_session');
    if (legacyUser != null && legacyUser.isNotEmpty) {
      setState(() {
        _legacyLocalUser = legacyUser;
        _userCtrl.text = legacyUser;
        _isRegisterMode = true;
      });
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('检测到本地存档，注册后自动同步数据')));
      }
    }
  }

  // ── Data migration ───────────────────────────

  Future<void> _syncLocalDataToCloud(
      int targetUserId, String currentUsername) async {
    final sourceUsername = _legacyLocalUser ?? currentUsername;
    try {
      final prefs = await SharedPreferences.getInstance();
      final deviceId = prefs.getString('app_device_uuid') ?? const Uuid().v4();

      final localScore = prefs.getInt('${sourceUsername}_best_score') ?? 0;
      final localDuration =
          prefs.getInt('${sourceUsername}_best_duration') ?? 0;
      if (localScore > 0) {
        await ApiService.uploadScore(
          userId: targetUserId,
          username: currentUsername,
          score: localScore,
          duration: localDuration > 0 ? localDuration : 60,
        );
      }

      List<Map<String, dynamic>> dirtyTodos = [];
      List<Map<String, dynamic>> dirtyCountdowns = [];

      final todosJson =
          prefs.getString('todos_$sourceUsername') ?? prefs.getString('todos');
      if (todosJson != null) {
        try {
          for (var item in jsonDecode(todosJson) as List) {
            final content = (item['title'] ?? item['content'] ?? '') as String;
            final isDone =
                (item['isDone'] ?? item['isCompleted'] ?? false) as bool;
            if (content.isNotEmpty && !isDone) {
              final nowMs = DateTime.now().millisecondsSinceEpoch;
              dirtyTodos.add({
                'id': const Uuid().v4(),
                'content': content,
                'is_completed': 0,
                'is_deleted': 0,
                'version': 1,
                'updated_at': nowMs,
                'created_at': nowMs,
                'device_id': deviceId,
              });
            }
          }
        } catch (_) {}
      }

      final countdownsJson = prefs.getString('countdowns_$sourceUsername') ??
          prefs.getString('countdowns');
      if (countdownsJson != null) {
        try {
          for (var item in jsonDecode(countdownsJson) as List) {
            final title = (item['title'] ?? '') as String;
            final dateStr =
                (item['date'] ?? item['targetTime'] ?? '') as String;
            if (title.isNotEmpty && dateStr.isNotEmpty) {
              final targetTime = DateTime.tryParse(dateStr);
              if (targetTime != null && targetTime.isAfter(DateTime.now())) {
                final nowMs = DateTime.now().millisecondsSinceEpoch;
                dirtyCountdowns.add({
                  'id': const Uuid().v4(),
                  'title': title,
                  'target_time': targetTime.millisecondsSinceEpoch,
                  'is_deleted': 0,
                  'version': 1,
                  'updated_at': nowMs,
                  'created_at': nowMs,
                  'device_id': deviceId,
                });
              }
            }
          }
        } catch (_) {}
      }

      if (dirtyTodos.isNotEmpty || dirtyCountdowns.isNotEmpty) {
        await ApiService.postDeltaSync(
          userId: targetUserId,
          lastSyncTime: 0,
          deviceId: deviceId,
          todosChanges: dirtyTodos,
          countdownsChanges: dirtyCountdowns,
        );
      }
    } catch (e) {
      debugPrint('老数据迁移错误: $e');
    }
  }

  // ── Auth actions ─────────────────────────────

  void _handleLogin() async {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text.trim();
    if (email.isEmpty || pass.isEmpty) {
      _snack('请输入邮箱和密码');
      return;
    }
    if (!_privacyAgreed) {
      _snack('请先阅读并同意隐私政策');
      return;
    }

    setState(() => _isLoading = true);
    final result = await ApiService.login(email, pass);
    if (!mounted) return;

    if (result['success'] == true) {
      final user = result['user'] as Map<String, dynamic>;
      final token = (result['token'] ?? '') as String;
      await StorageService.saveLoginSession(user['username'] as String,
          token: token);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('current_user_id', user['id'] as int);
      if (_legacyLocalUser != null) {
        await _syncLocalDataToCloud(
            user['id'] as int, user['username'] as String);
      }
      _finalizeLoginAndNavigate(user['username'] as String);
    } else {
      setState(() => _isLoading = false);
      _snack('登录失败：${result['message']}');
    }
  }

  void _handleRegister() async {
    if (!_awaitingVerification) {
      if (_userCtrl.text.trim().isEmpty ||
          _emailCtrl.text.trim().isEmpty ||
          _passCtrl.text.trim().isEmpty) {
        _snack('请填写完整注册信息');
        return;
      }
    } else {
      if (_codeCtrl.text.trim().isEmpty) {
        _snack('请输入邮箱收到的验证码');
        return;
      }
    }
    if (!_privacyAgreed) {
      _snack('请先阅读并同意隐私政策');
      return;
    }

    setState(() => _isLoading = true);
    final regResult = await ApiService.register(
      _userCtrl.text.trim(),
      _emailCtrl.text.trim(),
      _passCtrl.text.trim(),
      code: _awaitingVerification ? _codeCtrl.text.trim() : null,
    );
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (regResult['success'] == true) {
      if (regResult['require_verify'] == true) {
        setState(() => _awaitingVerification = true);
        _snack('验证码已发送至邮箱，请查收并输入');
      } else {
        _performAutoLoginAfterRegister(
          _emailCtrl.text.trim(),
          _passCtrl.text.trim(),
          _userCtrl.text.trim(),
        );
      }
    } else {
      _snack(regResult['message'] ?? '操作失败');
    }
  }

  void _performAutoLoginAfterRegister(
      String email, String pass, String username) async {
    await StorageService.setPrivacyPolicyAgreed(true,
        date: StorageService.PRIVACY_CURRENT_DATE);
    setState(() => _isLoading = true);
    final loginResult = await ApiService.login(email, pass);
    if (!mounted) return;

    if (loginResult['success'] == true) {
      final userInfo = loginResult['user'] as Map<String, dynamic>;
      final token = (loginResult['token'] ?? '') as String;
      _snack('注册成功，正在同步数据…');
      await StorageService.saveLoginSession(username, token: token);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('current_user_id', userInfo['id'] as int);
      await _syncLocalDataToCloud(userInfo['id'] as int, username);
      _finalizeLoginAndNavigate(username);
    } else {
      setState(() {
        _isLoading = false;
        _awaitingVerification = false;
        _isRegisterMode = false;
      });
      _snack('注册成功，请手动登录');
    }
  }

  void _finalizeLoginAndNavigate(String username) {
    if (!mounted) return;
    if (_privacyAgreed) {
      StorageService.setPrivacyPolicyAgreed(true,
          date: StorageService.PRIVACY_CURRENT_DATE);
    }
    setState(() => _isLoading = false);
    Navigator.pushReplacement(
      context,
      PageTransitions.fadeThrough(HomeDashboard(username: username)),
    );
  }

  void _toggleMode() {
    _fadeCtrl
      ..reset()
      ..forward();
    _slideCtrl
      ..reset()
      ..forward();
    setState(() {
      _isRegisterMode = !_isRegisterMode;
      _awaitingVerification = false;
      _codeCtrl.clear();
    });
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _showPrivacyDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => PrivacyPolicyDialog(
        isUpdate: false,
        onAgree: () {
          Navigator.pop(dialogContext);
          setState(() => _privacyAgreed = true);
        },
        onDisagree: () {
          Navigator.pop(dialogContext);
          setState(() => _privacyAgreed = false);
        },
      ),
    );
  }

  void _openForgotPassword() {
    _resetEmailCtrl.text = _emailCtrl.text.trim();
    _resetCodeCtrl.clear();
    _newPassCtrl.clear();
    _confirmPassCtrl.clear();
    setState(() => _forgotPasswordStep = 1);
  }

  void _handleSendResetCode() async {
    if (_resetCodeCooldown > 0) return;
    final email = _resetEmailCtrl.text.trim();
    if (email.isEmpty) {
      _snack('请输入邮箱地址');
      return;
    }
    setState(() {
      _isLoading = true;
      _resetCodeCooldown = 60;
    });
    final result = await ApiService.forgotPassword(email);
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (result['success'] == true) {
      _snack(result['message']);
      setState(() => _forgotPasswordStep = 2);
      _cooldownTimer?.cancel();
      _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_resetCodeCooldown <= 0) {
          timer.cancel();
          return;
        }
        setState(() => _resetCodeCooldown--);
      });
    } else {
      _snack(result['message']);
      setState(() => _resetCodeCooldown = 0);
    }
  }

  void _handleResetPassword() async {
    final email = _resetEmailCtrl.text.trim();
    final code = _resetCodeCtrl.text.trim();
    final newPass = _newPassCtrl.text;
    final confirmPass = _confirmPassCtrl.text;

    if (code.isEmpty) {
      _snack('请输入验证码');
      return;
    }
    if (newPass.isEmpty || confirmPass.isEmpty) {
      _snack('请输入新密码并确认');
      return;
    }
    if (newPass.length < 6) {
      _snack('密码长度不能少于 6 位');
      return;
    }
    if (newPass != confirmPass) {
      _snack('两次输入的密码不一致');
      return;
    }

    setState(() => _isLoading = true);
    final result = await ApiService.resetPassword(email, code, newPass);
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (result['success'] == true) {
      _snack(result['message']);
      setState(() {
        _forgotPasswordStep = 0;
        _emailCtrl.text = email;
      });
    } else {
      _snack(result['message']);
    }
  }

  // ── Build ────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = _T(context);
    return Scaffold(
      backgroundColor: t.bg,
      body: Stack(children: [
        Positioned.fill(
          child: CustomPaint(painter: _OrbPainter(dark: t._dark)),
        ),
        SafeArea(
          child: LayoutBuilder(builder: (ctx, constraints) {
            return constraints.maxWidth >= 768
                ? _buildWideLayout()
                : _buildNarrowLayout();
          }),
        ),
      ]),
    );
  }

  Widget _buildWideLayout() {
    return Row(children: [
      const Expanded(child: _WideLeftPanel()),
      Expanded(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 56, vertical: 40),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: SlideTransition(
                position: _slideAnim,
                child: FadeTransition(
                    opacity: _fadeAnim, child: _buildFormContent()),
              ),
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _buildNarrowLayout() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: SlideTransition(
        position: _slideAnim,
        child: FadeTransition(
          opacity: _fadeAnim,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              const _BrandLogo(),
              const SizedBox(height: 28),
              _buildFormContent(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFormContent() {
    if (_forgotPasswordStep > 0) return _buildForgotPasswordView();
    return _awaitingVerification ? _buildVerifyView() : _buildMainForm();
  }

  // ── Main form ────────────────────────────────

  Widget _buildMainForm() {
    final t = _T(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _isRegisterMode ? '账号升级' : '欢迎回来',
          style: TextStyle(
              fontSize: 26, fontWeight: FontWeight.w700, color: t.textPri),
        ),
        const SizedBox(height: 6),
        Text(
          _isRegisterMode ? '注册云账号，解锁多端同步' : '登录以同步你的全部数据',
          style: TextStyle(fontSize: 14, color: t.textSec),
        ),
        const SizedBox(height: 28),
        if (_legacyLocalUser != null && _isRegisterMode) ...[
          _LegacyBanner(username: _legacyLocalUser!),
          const SizedBox(height: 20),
        ],
        _TabSwitcher(isRegister: _isRegisterMode, onToggle: _toggleMode),
        const SizedBox(height: 24),
        if (_isRegisterMode) ...[
          _Field(
            controller: _userCtrl,
            label: '用户名',
            hint: '设置你的用户名',
            icon: Icons.person_outline_rounded,
          ),
          const SizedBox(height: 16),
        ],
        _Field(
          controller: _emailCtrl,
          label: '邮箱',
          hint: '输入邮箱地址',
          icon: Icons.mail_outline_rounded,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 16),
        _Field(
          controller: _passCtrl,
          label: '密码',
          hint: _isRegisterMode ? '设置密码' : '输入密码',
          icon: Icons.lock_outline_rounded,
          obscure: true,
        ),
        if (!_isRegisterMode)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _openForgotPassword,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                '忘记密码？',
                style: TextStyle(
                  fontSize: 12.5,
                  color: _T.primaryLt,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        const SizedBox(height: 28),
        Row(
          children: [
            Checkbox(
              value: _privacyAgreed,
              onChanged: (val) => setState(() => _privacyAgreed = val ?? false),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4)),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            Expanded(
              child: GestureDetector(
                onTap: () => _showPrivacyDialog(context),
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(
                        fontSize: 12.5, color: t.textSec, height: 1.4),
                    children: [
                      const TextSpan(text: '我已阅读并同意'),
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: TextButton(
                          onPressed: () => _showPrivacyDialog(context),
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text(
                            '《隐私政策》',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: _T.primaryLt,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_isLoading)
          const _Spinner()
        else
          _PrimaryBtn(
            label: _isRegisterMode ? '获取验证码' : '登录',
            onPressed: _isRegisterMode ? _handleRegister : _handleLogin,
            isAccent: _isRegisterMode,
          ),
        const SizedBox(height: 28),
        _ServerSelector(
            value: _serverChoice, onChanged: _onServerChoiceChanged),
      ],
    );
  }

  // ── Verify view (6-digit OTP) ────────────────

  Widget _buildVerifyView() {
    final t = _T(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: t.verifyIconBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: t.verifyIconBd, width: 1),
          ),
          child: const Icon(Icons.mark_email_read_outlined,
              color: _T.primaryLt, size: 26),
        ),
        const SizedBox(height: 20),
        Text(
          '验证邮箱',
          style: TextStyle(
              fontSize: 26, fontWeight: FontWeight.w700, color: t.textPri),
        ),
        const SizedBox(height: 8),
        Text(
          '验证码已发送至你的邮箱，\n请在下方输入 6 位验证码',
          style: TextStyle(fontSize: 14, color: t.textSec, height: 1.6),
        ),
        const SizedBox(height: 32),
        _OtpInput(controller: _codeCtrl),
        const SizedBox(height: 28),
        if (_isLoading)
          const _Spinner()
        else
          _PrimaryBtn(
            label: '验证并完成注册',
            onPressed: _handleRegister,
          ),
        const SizedBox(height: 18),
        Center(
          child: TextButton(
            onPressed: () => setState(() => _awaitingVerification = false),
            child: const Text(
              '← 返回修改邮箱',
              style: TextStyle(
                  fontSize: 13,
                  color: _T.primaryLt,
                  fontWeight: FontWeight.w500),
            ),
          ),
        ),
      ],
    );
  }

  // ── Forgot password view ───────────────

  Widget _buildForgotPasswordView() {
    final t = _T(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: t.verifyIconBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: t.verifyIconBd, width: 1),
          ),
          child: const Icon(Icons.lock_reset_outlined,
              color: _T.primaryLt, size: 26),
        ),
        const SizedBox(height: 20),
        Text(
          '重置密码',
          style: TextStyle(
              fontSize: 26, fontWeight: FontWeight.w700, color: t.textPri),
        ),
        const SizedBox(height: 8),
        Text(
          _forgotPasswordStep == 1
              ? '输入注册时使用的邮箱，\n我们将发送验证码到你的邮箱'
              : '输入验证码并设置新密码',
          style: TextStyle(fontSize: 14, color: t.textSec, height: 1.6),
        ),
        const SizedBox(height: 28),
        if (_forgotPasswordStep == 1) ...[
          _Field(
            controller: _resetEmailCtrl,
            label: '邮箱',
            hint: '输入注册邮箱',
            icon: Icons.mail_outline_rounded,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 28),
          if (_isLoading)
            const _Spinner()
          else if (_resetCodeCooldown > 0)
            SizedBox(
              width: double.infinity,
              height: 52,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: t.textHint.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Text(
                    '$_resetCodeCooldown 秒后可重新发送',
                    style: TextStyle(
                      fontSize: 14,
                      color: t.textHint,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            )
          else
            _PrimaryBtn(
              label: '发送验证码',
              onPressed: _handleSendResetCode,
            ),
        ] else ...[
          _Field(
            controller: _resetEmailCtrl,
            label: '邮箱',
            hint: '注册邮箱',
            icon: Icons.mail_outline_rounded,
            keyboardType: TextInputType.emailAddress,
            enabled: false,
          ),
          const SizedBox(height: 16),
          _OtpInput(controller: _resetCodeCtrl),
          const SizedBox(height: 16),
          _Field(
            controller: _newPassCtrl,
            label: '新密码',
            hint: '设置新密码（至少6位）',
            icon: Icons.lock_outline_rounded,
            obscure: true,
          ),
          const SizedBox(height: 16),
          _Field(
            controller: _confirmPassCtrl,
            label: '确认密码',
            hint: '再次输入新密码',
            icon: Icons.lock_outline_rounded,
            obscure: true,
          ),
          const SizedBox(height: 28),
          if (_isLoading)
            const _Spinner()
          else
            _PrimaryBtn(
              label: '重置密码',
              onPressed: _handleResetPassword,
              isAccent: true,
            ),
        ],
        const SizedBox(height: 18),
        Center(
          child: TextButton(
            onPressed: () => setState(() => _forgotPasswordStep = 0),
            child: const Text(
              '← 返回登录',
              style: TextStyle(
                  fontSize: 13,
                  color: _T.primaryLt,
                  fontWeight: FontWeight.w500),
            ),
          ),
        ),
      ],
    );
  }
}
