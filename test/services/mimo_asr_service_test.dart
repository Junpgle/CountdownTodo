import 'dart:convert';
import 'dart:typed_data';

import 'package:countdown_todo/services/ai_chat_service.dart';
import 'package:countdown_todo/services/mimo_asr_service.dart';
import 'package:countdown_todo/services/quick_voice_recorder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Uint8List audio() => encodePcmWav(Uint8List(32000), sampleRate: 16000);
http.Response response(Object data, [int status = 200]) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  test(
    'WAV metadata matches actual sample rate, channels and aligned data',
    () {
      final wav = encodePcmWav(
        Uint8List.fromList([1, 2, 3, 4, 5]),
        sampleRate: 48000,
        channels: 2,
      );
      final header = ByteData.sublistView(wav);
      expect(ascii.decode(wav.sublist(0, 4)), 'RIFF');
      expect(ascii.decode(wav.sublist(8, 12)), 'WAVE');
      expect(header.getUint32(4, Endian.little), wav.length - 8);
      expect(header.getUint16(22, Endian.little), 2);
      expect(header.getUint32(24, Endian.little), 48000);
      expect(header.getUint32(28, Endian.little), 192000);
      expect(header.getUint16(34, Endian.little), 16);
      expect(header.getUint32(40, Endian.little), 4);
      expect(wav.sublist(44), [1, 2, 3, 4]);
    },
  );

  test(
    'normal MiMo credentials are independent of chat provider and Token Plan',
    () {
      String select(String saved, String provider, String url) =>
          MimoAsrService.selectApiKey(
            savedMimoKey: saved,
            provider: provider,
            apiUrl: url,
            apiKey: 'chat-key',
          );
      expect(
        select(' saved-key ', 'deepseek', 'https://api.deepseek.com'),
        'saved-key',
      );
      expect(select('', 'mimo', AiChatService.mimoApiBaseUrl), 'chat-key');
      expect(select('', 'custom', AiChatService.mimoApiBaseUrl), 'chat-key');
      expect(select('', 'deepseek', 'https://api.deepseek.com'), isEmpty);
      expect(
        select('', 'mimo_token_plan', AiChatService.mimoTokenPlanOpenAiBaseUrl),
        isEmpty,
      );
      expect(
        select('', 'mimo', AiChatService.mimoTokenPlanOpenAiBaseUrl),
        isEmpty,
      );
      expect(
        select('', 'custom', 'https://api.xiaomimimo.com.example/v1'),
        isEmpty,
      );
      expect(select('', 'mimo', 'https://aggregator.example/v1'), isEmpty);
    },
  );

  test('official ASR request preserves transcript and seconds usage', () async {
    AiTokenUsage? usage;
    final bytes = audio();
    final service = MimoAsrService(
      authorize: () async => true,
      recordUsage: (value) async {
        usage = value;
        return null;
      },
      client: MockClient((request) async {
        expect(
          request.url.toString(),
          'https://api.xiaomimimo.com/v1/chat/completions',
        );
        expect(request.headers['api-key'], 'test-key');
        final body = jsonDecode(request.body) as Map;
        expect(body['model'], 'mimo-v2.5-asr');
        expect(body['stream'], false);
        expect(body['asr_options'], {'language': 'auto'});
        expect(body.containsKey('tools'), false);
        final content = body['messages'][0]['content'] as List;
        expect(content, hasLength(1));
        expect(content.first['type'], 'input_audio');
        final input = content.first['input_audio'];
        expect(input['format'], 'wav');
        expect(base64Decode((input['data'] as String).split(',').last), bytes);
        return response({
          'choices': [
            {
              'message': {'content': ' 明天九点提醒我交报告。 '},
            },
          ],
          'usage': {
            'prompt_tokens': 10,
            'completion_tokens': 8,
            'total_tokens': 18,
            'seconds': 1,
          },
        });
      }),
    );
    addTearDown(service.dispose);
    expect(
      await service.transcribe(wavBytes: bytes, apiKey: ' test-key '),
      '明天九点提醒我交报告。',
    );
    expect(usage?.audioSeconds, 1);
    expect(usage?.totalTokens, 18);
  });

  test(
    'authorization denial and invalid input never make a network request',
    () async {
      var requests = 0;
      final service = MimoAsrService(
        authorize: () async => false,
        client: MockClient((_) async {
          requests++;
          return response({});
        }),
      );
      addTearDown(service.dispose);
      await expectLater(
        service.transcribe(wavBytes: audio(), apiKey: 'key'),
        throwsException,
      );
      await expectLater(
        service.transcribe(wavBytes: audio(), apiKey: ''),
        throwsFormatException,
      );
      await expectLater(
        service.transcribe(wavBytes: Uint8List(44), apiKey: 'key'),
        throwsFormatException,
      );
      await expectLater(
        service.transcribe(
          wavBytes: Uint8List(MimoAsrService.maxAudioBytes + 1),
          apiKey: 'key',
        ),
        throwsFormatException,
      );
      expect(requests, 0);
    },
  );

  for (final status in [401, 402, 403, 429, 500]) {
    test(
      'HTTP $status produces a useful error without response secrets',
      () async {
        final service = MimoAsrService(
          authorize: () async => true,
          client: MockClient(
            (_) async => response({'error': 'secret-key-and-audio'}, status),
          ),
        );
        addTearDown(service.dispose);
        await expectLater(
          service.transcribe(wavBytes: audio(), apiKey: 'key'),
          throwsA(
            predicate(
              (Object e) =>
                  e.toString().contains('MiMo') &&
                  !e.toString().contains('secret-key-and-audio'),
            ),
          ),
        );
      },
    );
  }

  for (final data in <Object>[
    [],
    {},
    {'choices': []},
    {
      'choices': [1],
    },
    {
      'choices': [
        {
          'message': {'content': ''},
        },
      ],
    },
    {
      'choices': [
        {
          'message': {'content': []},
        },
      ],
    },
  ]) {
    test('rejects malformed or silent transcript: $data', () async {
      final service = MimoAsrService(
        authorize: () async => true,
        recordUsage: (_) async => null,
        client: MockClient((_) async => response(data)),
      );
      addTearDown(service.dispose);
      await expectLater(
        service.transcribe(wavBytes: audio(), apiKey: 'key'),
        throwsFormatException,
      );
    });
  }

  test('usage storage failure cannot lose recognized words', () async {
    final service = MimoAsrService(
      authorize: () async => true,
      recordUsage: (_) async => throw StateError('storage busy'),
      client: MockClient(
        (_) async => response({
          'choices': [
            {
              'message': {'content': '然后改到周五'},
            },
          ],
        }),
      ),
    );
    addTearDown(service.dispose);
    expect(
      await service.transcribe(wavBytes: audio(), apiKey: 'key'),
      '然后改到周五',
    );
  });
}
