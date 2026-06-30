import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../screens/personal_timeline_screen.dart';
import 'app_deep_link_service.dart';
import 'app_report_launch_visibility_stub.dart'
    if (dart.library.html) 'app_report_launch_visibility_web.dart';

class AppReportLaunchService {
  static const String _manifestUrl =
      'https://raw.githubusercontent.com/Junpgle/CountdownTodo/refs/heads/master/update_manifest.json';
  static const String _releasePageUrl =
      'https://github.com/Junpgle/CountdownTodo/releases';

  static Uri buildTimelineReportUri({
    required TimelineDimension dimension,
    required DateTime date,
  }) {
    return Uri(
      scheme: AppDeepLinkService.scheme,
      host: 'timeline',
      path: '/report',
      queryParameters: {
        'dimension': dimension.name,
        'date': DateFormat('yyyy-MM-dd').format(date),
      },
    );
  }

  static Future<void> openTimelineReportInApp({
    required TimelineDimension dimension,
    required DateTime date,
  }) async {
    final appUri = buildTimelineReportUri(dimension: dimension, date: date);
    try {
      await launchUrl(appUri, mode: LaunchMode.externalApplication);
    } catch (_) {}

    if (!kIsWeb) return;

    await Future<void>.delayed(const Duration(milliseconds: 1400));
    if (!isReportLaunchPageVisible) return;
    final downloadUrl = await _resolveDownloadUrlForCurrentVisitor();
    await launchUrl(
      Uri.parse(downloadUrl),
      mode: LaunchMode.externalApplication,
    );
  }

  static Future<String> _resolveDownloadUrlForCurrentVisitor() async {
    try {
      final response = await http.get(Uri.parse(_manifestUrl));
      if (response.statusCode == 200) {
        final data =
            jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        final info = (data['update_info'] as Map?) ?? const {};
        final pcUrl = info['PC_package_url']?.toString() ?? '';
        final macUrl = info['mac_package_url']?.toString() ?? '';
        final apkUrl = info['full_package_url']?.toString() ?? '';
        final archPackages =
            (info['android_arch_packages'] as Map?) ?? const {};
        final firstArchApk = archPackages.values
            .map((value) => value.toString())
            .where((value) => value.isNotEmpty)
            .cast<String?>()
            .firstWhere((value) => value != null, orElse: () => null);

        if (defaultTargetPlatform == TargetPlatform.android) {
          return firstArchApk ?? apkUrl.ifNotEmpty ?? _releasePageUrl;
        }
        if (defaultTargetPlatform == TargetPlatform.macOS) {
          return macUrl.ifNotEmpty ?? _releasePageUrl;
        }
        if (defaultTargetPlatform == TargetPlatform.windows) {
          return pcUrl.ifNotEmpty ?? _releasePageUrl;
        }
        return pcUrl.ifNotEmpty ?? apkUrl.ifNotEmpty ?? _releasePageUrl;
      }
    } catch (_) {}
    return _releasePageUrl;
  }
}

extension on String {
  String? get ifNotEmpty => isEmpty ? null : this;
}
