import 'package:web/web.dart' as web;

String getUrlHash() {
  final hash = web.window.location.hash;
  if (hash.isNotEmpty) return hash;
  // release 模式下 hash 可能为空，从 href 中提取
  final href = web.window.location.href;
  final idx = href.indexOf('#');
  if (idx != -1) return href.substring(idx);
  return '';
}
