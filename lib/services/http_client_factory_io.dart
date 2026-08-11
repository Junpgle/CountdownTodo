import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'timeout_http_client.dart';

http.Client createApiHttpClient() {
  final httpClient = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10)
    ..idleTimeout = const Duration(seconds: 30);
  httpClient.badCertificateCallback =
      (X509Certificate cert, String host, int port) => true;
  return TimeoutHttpClient(
    IOClient(httpClient),
  );
}
