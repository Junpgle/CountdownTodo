import 'package:http/http.dart' as http;

import '../models/cloud_challenge.dart';

class CloudChallengeService {
  static const String catalogUrl =
      'https://raw.githubusercontent.com/Junpgle/CountdownTodo/master/challenge_catalog.json';

  final http.Client _client;

  CloudChallengeService({http.Client? client})
      : _client = client ?? http.Client();

  Future<CloudChallengeCatalog> fetchCatalog() async {
    final response = await _client.get(
      Uri.parse(catalogUrl),
      headers: const {
        'Accept': 'application/json',
        'Cache-Control': 'no-cache',
      },
    ).timeout(const Duration(seconds: 12));
    return CloudChallengeCatalog.fromResponse(response);
  }

  void dispose() => _client.close();
}
