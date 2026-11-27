import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../services/lan_sync_pairing.dart';
import '../../utils/app_dialogs.dart';

/// 局域网面对面同步二维码扫描页。
class LanQrScannerScreen extends StatefulWidget {
  const LanQrScannerScreen({super.key});

  @override
  State<LanQrScannerScreen> createState() => _LanQrScannerScreenState();
}

class _LanQrScannerScreenState extends State<LanQrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );
  bool _handled = false;
  bool _invalidHintShown = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue?.trim();
      if (raw == null || raw.isEmpty) continue;
      if (LanPairingPayload.tryParse(raw) != null) {
        _handled = true;
        Navigator.of(context).pop(raw);
        return;
      }
    }
    if (!_invalidHintShown && mounted) {
      _invalidHintShown = true;
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(
          content: Text('未识别到有效的局域网同步二维码'),
          duration: Duration(seconds: 2),
        ),
      );
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) _invalidHintShown = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('扫码互同步'),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            tooltip: '闪光灯',
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.cameraswitch),
            tooltip: '切换摄像头',
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.videocam_off_outlined,
                        size: 56,
                        color: colorScheme.error,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '无法打开摄像头（${error.errorCode.name}）',
                        style: Theme.of(context).textTheme.titleMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '请检查相机权限，或返回使用“输入配对码”连接。',
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: colorScheme.onSurfaceVariant),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('返回'),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: colorScheme.primary, width: 2.5),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 36,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.surface.withValues(alpha: 0.88),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Text(
                  '将对方屏幕上的面对面同步二维码放入框内',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
