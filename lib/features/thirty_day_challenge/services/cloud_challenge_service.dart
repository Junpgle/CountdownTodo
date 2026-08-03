import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/cloud_challenge.dart';

class CachedCloudChallengeCatalog {
  final CloudChallengeCatalog catalog;
  final DateTime cachedAt;

  const CachedCloudChallengeCatalog({
    required this.catalog,
    required this.cachedAt,
  });
}

class CloudChallengeService {
  static const String catalogUrl =
      'https://raw.githubusercontent.com/Junpgle/CountdownTodo/master/challenge_catalog.json';
  static const String _cacheKey = 'thirty_day_cloud_challenge_catalog_v1';
  static const Duration cacheLifetime = Duration(days: 1);

  final http.Client _client;

  CloudChallengeService({http.Client? client})
      : _client = client ?? http.Client();

  Future<CachedCloudChallengeCatalog?> readCachedCatalog() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    if (raw == null || raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final cachedAt =
          DateTime.tryParse(decoded['cached_at']?.toString() ?? '');
      final rawCatalog = decoded['catalog'];
      if (cachedAt == null || rawCatalog is! Map) return null;

      return CachedCloudChallengeCatalog(
        catalog: CloudChallengeCatalog.fromJson(
          Map<String, dynamic>.from(rawCatalog),
        ),
        cachedAt: cachedAt.toUtc(),
      );
    } catch (_) {
      // 损坏的缓存不影响从网络获取最新清单。
      return null;
    }
  }

  bool isCacheFresh(
    CachedCloudChallengeCatalog cached, {
    DateTime? now,
  }) {
    final age = (now ?? DateTime.now()).toUtc().difference(cached.cachedAt);
    return age < cacheLifetime;
  }

  Future<CloudChallengeCatalog> fetchCatalog() async {
    final response = await _client.get(
      Uri.parse(catalogUrl),
      headers: const {
        'Accept': 'application/json',
        'Cache-Control': 'no-cache',
      },
    ).timeout(const Duration(seconds: 12));
    final catalog = CloudChallengeCatalog.fromResponse(response);
    try {
      await _saveCache(catalog);
    } catch (_) {
      // 缓存写入失败不应阻断本次已经成功获取的云端内容。
    }
    return catalog;
  }

  Future<void> _saveCache(CloudChallengeCatalog catalog) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _cacheKey,
      jsonEncode({
        'cached_at': DateTime.now().toUtc().toIso8601String(),
        'catalog': catalog.toJson(),
      }),
    );
  }

  void dispose() => _client.close();
}
