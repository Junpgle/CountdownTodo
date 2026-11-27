import 'package:flutter/foundation.dart';

import 'system_control_models.dart';

export 'system_control_models.dart';

class SystemControlService {
  SystemControlService._();

  static double _cachedVolume = 0.5;
  static double _cachedBrightness = 0.7;
  static const MediaInfo _mediaInfo = MediaInfo();
  static final ValueNotifier<MediaInfo> _mediaInfoNotifier =
      ValueNotifier<MediaInfo>(_mediaInfo);

  static double getVolumeSync() => _cachedVolume;

  static void initVolume() {}

  static void setVolume(double target) {
    _cachedVolume = target.clamp(0.0, 1.0);
  }

  static void commitVolume(double target) {
    setVolume(target);
  }

  static bool isMuted() => _cachedVolume <= 0.01;

  static void toggleMute() {
    _cachedVolume = isMuted() ? 0.5 : 0;
  }

  static void initBrightness() {}

  static double getBrightness() => _cachedBrightness;

  static void setBrightness(double value) {
    _cachedBrightness = value.clamp(0.0, 1.0);
  }

  static void disposeBrightness() {}

  static void disposeGamma() {}

  static MediaInfo getMediaInfo() => _mediaInfo;

  static ValueListenable<MediaInfo> get mediaInfoListenable =>
      _mediaInfoNotifier;

  static void startMediaPolling({int intervalMs = 2000}) {}

  static void stopMediaPolling() {}

  static void dispose() {}
}
