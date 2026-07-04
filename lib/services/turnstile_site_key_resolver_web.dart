import 'package:web/web.dart' as web;

String resolveTurnstileSiteKey({
  required bool isTest,
  required String testSiteKey,
  required String productionSiteKey,
  required bool useProductionOnLocalWeb,
}) {
  if (isTest || (!useProductionOnLocalWeb && _isLocalWebHost)) {
    return testSiteKey;
  }
  return productionSiteKey;
}

bool get _isLocalWebHost {
  final location = web.window.location;
  final protocol = location.protocol.toLowerCase();
  final host = location.hostname.toLowerCase();

  return protocol == 'file:' ||
      host.isEmpty ||
      host == 'localhost' ||
      host == '127.0.0.1' ||
      host == '0.0.0.0' ||
      host == '::1' ||
      host.endsWith('.localhost');
}
