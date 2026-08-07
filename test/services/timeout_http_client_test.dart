import 'dart:async';

import 'package:countdown_todo/services/timeout_http_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class _StallingClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return Completer<http.StreamedResponse>().future;
  }

  @override
  void close() {}
}

void main() {
  test('shared API client bounds a stalled request', () async {
    final client = TimeoutHttpClient(
      _StallingClient(),
      timeout: const Duration(milliseconds: 1),
    );

    expect(
      client.get(Uri.parse('https://example.com')),
      throwsA(isA<TimeoutException>()),
    );
    client.close();
  });
}
