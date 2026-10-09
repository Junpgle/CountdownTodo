import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'timeout_http_client.dart';

http.Client createApiHttpClient() {
  final httpClient = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10)
    ..idleTimeout = const Duration(seconds: 30);
  return TimeoutHttpClient(
    IOClient(httpClient),
  );
}
