import 'package:http/http.dart' as http;

/// Bounds requests made through the shared API client so one stalled socket
/// cannot keep a synchronization operation (and its UI lock) alive forever.
class TimeoutHttpClient extends http.BaseClient {
  TimeoutHttpClient(this._inner, {this.timeout = const Duration(seconds: 30)});

  final http.Client _inner;
  final Duration timeout;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _inner.send(request).timeout(timeout);
  }

  @override
  void close() => _inner.close();
}
