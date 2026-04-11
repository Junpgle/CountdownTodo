import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

/// 适配请求二级界面 - 经过美化重构
class CourseAdaptationScreen extends StatefulWidget {
  const CourseAdaptationScreen({Key? key}) : super(key: key);

  @override
  State<CourseAdaptationScreen> createState() => _CourseAdaptationScreenState();
}

class _CourseAdaptationScreenState extends State<CourseAdaptationScreen> {
  late VideoPlayerController _controller;
  bool _isError = false;

  @override
  void initState() {
    super.initState();
    _controller =
        VideoPlayerController.asset('assets/guide_media/course_import.mp4')
          ..initialize().then((_) {
            setState(() {});
            _controller.setLooping(true);
            _controller.play();
          }).catchError((error) {
            debugPrint("视频加载失败: $error");
            setState(() => _isError = true);
          });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _launchQQ() async {
    const qqUrl = "mqqwpa://im/chat?chat_type=wpa&uin=674155783";
    if (await canLaunchUrl(Uri.parse(qqUrl))) {
      await launchUrl(Uri.parse(qqUrl));
    } else {
      await Clipboard.setData(const ClipboardData(text: "674155783"));
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('QQ号已复制到剪贴板')));
      }
    }
  }

  Future<void> _launchEmail() async {
    final Uri emailLaunchUri = Uri(
      scheme: 'mailto',
      path: 'junpgle@qq.com',
      queryParameters: {
        'subject': '课表适配申请',
        'body': '学校名称：\n所在城市：\n附件请添加保存好的 mhtml 文件。'
      },
    );
    if (await canLaunchUrl(emailLaunchUri)) {
      await launchUrl(emailLaunchUri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title:
            const Text('学校适配申请', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          children: [
            // 顶部横幅
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
              color: colorScheme.primary.withOpacity(0.05),
              child: Column(
                children: [
                  const Icon(Icons.school_rounded,
                      size: 48, color: Colors.blueAccent),
                  const SizedBox(height: 12),
                  const Text('让你的校园生活更高效',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('只需 1 分钟，为全校同学谋福利',
                      style: TextStyle(color: colorScheme.onSurfaceVariant)),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 新增置顶方法：移动端快捷适配
                  _buildSectionHeader(Icons.flash_on_rounded, '方案一：自动嗅探 (推荐)'),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          colorScheme.primary.withOpacity(0.1),
                          colorScheme.primary.withOpacity(0.05)
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border:
                          Border.all(color: colorScheme.primary.withOpacity(0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '可以先使用 App 内“网页登录”尝试导入。',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.lightbulb_outline_rounded,
                                size: 18, color: Colors.orange[700]),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                '失败后，请将手机“文件管理/Download”目录下的 course_debug.html 发送给开发者。',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.black87,
                                    height: 1.4),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  // 步骤标题
                  _buildSectionHeader(Icons.computer_rounded, '方案二：手动导出 (电脑端)'),
                  const SizedBox(height: 16),

                  // 步骤时间轴
                  _buildStepTile(1, '登录教务系统', '在电脑浏览器中进入课表查询页面。',
                      isFirst: true),
                  _buildStepTile(2, '右键另存为', '点击页面空白处，选择“另存为”。'),
                  _buildStepTile(3, '选择格式', '保存类型选“网页，单个文件 (*.mhtml)”。'),
                  _buildStepTile(4, '发送文件', '通过下方联系方式将文件发给开发者。',
                      isLast: true),

                  const SizedBox(height: 32),

                  // 视频部分
                  _buildSectionHeader(Icons.play_circle_fill_rounded, '操作演示'),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 15,
                            offset: const Offset(0, 8))
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _isError
                        ? const SizedBox(
                            height: 200,
                            child: Center(
                                child: Text('视频无法加载',
                                    style: TextStyle(color: Colors.white70))))
                        : _controller.value.isInitialized
                            ? Center(
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                      maxHeight:
                                          MediaQuery.of(context).size.height *
                                              0.45),
                                  child: AspectRatio(
                                    aspectRatio: _controller.value.aspectRatio,
                                    child: GestureDetector(
                                      onTap: () => setState(() =>
                                          _controller.value.isPlaying
                                              ? _controller.pause()
                                              : _controller.play()),
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          VideoPlayer(_controller),
                                          if (!_controller.value.isPlaying)
                                            Container(
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                  color: Colors.black38,
                                                  shape: BoxShape.circle),
                                              child: const Icon(
                                                  Icons.play_arrow_rounded,
                                                  color: Colors.white,
                                                  size: 48),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              )
                            : const SizedBox(
                                height: 200,
                                child:
                                    Center(child: CircularProgressIndicator())),
                  ),

                  const SizedBox(height: 40),

                  // 联系部分
                  _buildSectionHeader(Icons.contact_support, '提交申请'),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _buildContactCard(
                          'QQ 邮箱',
                          'junpgle@qq.com',
                          Icons.alternate_email_rounded,
                          Colors.blue,
                          _launchEmail),
                      const SizedBox(width: 16),
                      _buildContactCard('开发者 QQ', '674155783',
                          Icons.chat_bubble_rounded, Colors.indigo, _launchQQ),
                    ],
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.blueAccent),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1)),
      ],
    );
  }

  Widget _buildStepTile(int step, String title, String desc,
      {bool isFirst = false, bool isLast = false}) {
    final colorScheme = Theme.of(context).colorScheme;
    return IntrinsicHeight(
      child: Row(
        children: [
          Column(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                child: Center(
                    child: Text('$step',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold))),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: colorScheme.primary.withOpacity(0.2),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 4),
                Text(desc,
                    style: TextStyle(
                        color: colorScheme.onSurfaceVariant, fontSize: 13)),
                if (!isLast) const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactCard(String title, String value, IconData icon,
      Color color, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.2)),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 12),
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 4),
              Text(value,
                  style:
                      TextStyle(fontSize: 11, color: color.withOpacity(0.8))),
            ],
          ),
        ),
      ),
    );
  }
}
