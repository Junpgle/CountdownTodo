import 'dart:async';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

abstract interface class QuickVoiceRecorder {
  Future<void> start();
  Future<Uint8List> stop();
  Future<void> dispose();
}

abstract interface class QuickVoiceLevelSource {
  ValueListenable<double> get level;
}

class MicrophoneAccessDenied implements Exception {
  @override
  String toString() => '请在系统设置中允许麦克风访问，然后重新录音';
}

/// Keeps a short PCM recording in memory on native platforms and web alike.
class RecordQuickVoiceRecorder
    implements QuickVoiceRecorder, QuickVoiceLevelSource {
  final ValueNotifier<double> _level = ValueNotifier(0);
  @override
  ValueListenable<double> get level => _level;
  final AudioRecorder _recorder = AudioRecorder();
  final BytesBuilder _pcm = BytesBuilder(copy: false);
  StreamSubscription<Uint8List>? _subscription;
  Object? _streamError;
  int _sampleRate = 16000;
  int _channels = 1;
  static const maxPcmBytes = 7 * 1024 * 1024 - 44;

  @override
  Future<void> start() async {
    if (!await _recorder.hasPermission()) throw MicrophoneAccessDenied();
    _pcm.clear();
    _streamError = null;
    _sampleRate = 16000;
    _channels = 1;
    await _recorder.setOnConfigChanged((config) {
      _sampleRate = config.sampleRate;
      _channels = config.numChannels;
    });
    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
    );
    _subscription = stream.listen((chunk) {
      final samples = ByteData.sublistView(chunk);
      var energy = 0.0;
      var count = 0;
      for (var offset = 0; offset + 1 < chunk.length; offset += 32) {
        final sample = samples.getInt16(offset, Endian.little) / 32768;
        energy += sample * sample;
        count++;
      }
      if (count > 0) {
        _level.value = (math.sqrt(energy / count) * 5).clamp(0.0, 1.0);
      }
      if (_pcm.length + chunk.length <= maxPcmBytes) {
        _pcm.add(chunk);
      } else {
        _streamError = const FormatException('录音过长，请重新录音');
      }
    }, onError: (Object error) => _streamError = error);
  }

  @override
  Future<Uint8List> stop() async {
    try {
      await _recorder.stop();
    } catch (_) {
      // AudioRecorder skips its stream cleanup when the platform stop call
      // throws. Cancel the native recording before allowing a retry.
      try {
        await _recorder.cancel();
      } catch (_) {}
      rethrow;
    } finally {
      final subscription = _subscription;
      _subscription = null;
      try {
        await subscription?.cancel();
      } catch (_) {}
      _level.value = 0;
    }
    if (_streamError != null) throw _streamError!;
    return encodePcmWav(
      _pcm.takeBytes(),
      sampleRate: _sampleRate,
      channels: _channels,
    );
  }

  @override
  Future<void> dispose() async {
    try {
      await _recorder.cancel();
    } finally {
      await _subscription?.cancel();
      _pcm.clear();
      await _recorder.dispose();
      _level.dispose();
    }
  }
}

Uint8List encodePcmWav(
  Uint8List pcm, {
  required int sampleRate,
  int channels = 1,
}) {
  final alignedLength = pcm.length - pcm.length % (channels * 2);
  final wav = Uint8List(44 + alignedLength);
  final header = ByteData.sublistView(wav);
  wav.setRange(0, 4, 'RIFF'.codeUnits);
  header.setUint32(4, 36 + alignedLength, Endian.little);
  wav.setRange(8, 12, 'WAVE'.codeUnits);
  wav.setRange(12, 16, 'fmt '.codeUnits);
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little);
  header.setUint16(22, channels, Endian.little);
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, sampleRate * channels * 2, Endian.little);
  header.setUint16(32, channels * 2, Endian.little);
  header.setUint16(34, 16, Endian.little);
  wav.setRange(36, 40, 'data'.codeUnits);
  header.setUint32(40, alignedLength, Endian.little);
  wav.setRange(44, wav.length, pcm);
  return wav;
}
