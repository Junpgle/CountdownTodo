import 'dart:async';

class ClipboardConfig {
  ClipboardConfig._();

  static const Duration pollInterval = Duration(seconds: 1);
  static const int maxUrlLength = 2048;
  static const int maxDisplayLength = 30;
  static const Set<String> allowedSchemes = {'http', 'https', 'ftp'};
}

class ClipboardService {
  static final ClipboardService _instance = ClipboardService._internal();

  factory ClipboardService() => _instance;

  ClipboardService._internal();

  final _urlController = StreamController<String>.broadcast();

  Stream<String> get onUrlCopied => _urlController.stream;

  bool get isListening => false;

  bool get isInitialized => true;

  void startListening() {}

  void stopListening() {}

  void resetLastContent() {}

  void dispose() {
    if (!_urlController.isClosed) {
      _urlController.close();
    }
  }
}
