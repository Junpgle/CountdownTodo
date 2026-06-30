import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../handlers/permission_handler.dart' as handlers;
import '../widgets/permission_section.dart';

class PermissionSettingsPage extends StatefulWidget {
  final String? initialTarget;
  final bool isEmbedded;
  const PermissionSettingsPage(
      {super.key, this.initialTarget, this.isEmbedded = false});

  @override
  State<PermissionSettingsPage> createState() => _PermissionSettingsPageState();
}

class _PermissionSettingsPageState extends State<PermissionSettingsPage> {
  static const platform =
      MethodChannel('com.math_quiz.junpgle.com.math_quiz_app/notifications');

  final Map<String, GlobalKey> _itemKeys = {
    'permissions': GlobalKey(),
  };

  String? _highlightTarget;
  late handlers.PermissionHandler _permissionHandler;
  bool _isCheckingPermissions = false;
  final Map<String, PermissionStatus?> _permissionStatuses = {};

  @override
  void initState() {
    super.initState();
    _permissionHandler = handlers.PermissionHandler(
      context: context,
      platform: platform,
      onUpdateChecking: (val) {
        if (mounted) setState(() => _isCheckingPermissions = val);
      },
      onUpdateStatuses: (results) {
        if (mounted) {
          setState(() {
            for (final entry in results.entries) {
              _permissionStatuses[entry.key] = entry.value;
            }
          });
        }
      },
    );
    _permissionHandler.checkAllPermissions();

    if (widget.initialTarget != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToTarget(widget.initialTarget!);
      });
    }
  }

  void _scrollToTarget(String target) {
    final key = _itemKeys[target];
    if (key?.currentContext != null) {
      setState(() => _highlightTarget = target);
      Scrollable.ensureVisible(
        key!.currentContext!,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
        alignment: 0.15,
      );
      Future.delayed(const Duration(milliseconds: 3000), () {
        if (mounted) setState(() => _highlightTarget = null);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.isEmbedded
          ? null
          : AppBar(
              title: const Text('权限管理'),
            ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Container(
          key: _itemKeys['permissions'],
          child: PermissionSection(
            permissionDefs: handlers.PermissionHandler.permissionDefs,
            permissionStatuses: _permissionStatuses,
            isCheckingPermissions: _isCheckingPermissions,
            onCheckAllPermissions: _permissionHandler.checkAllPermissions,
            onRequestOrOpenPermission:
                _permissionHandler.requestOrOpenPermission,
          ),
        ),
      ),
    );
  }
}
