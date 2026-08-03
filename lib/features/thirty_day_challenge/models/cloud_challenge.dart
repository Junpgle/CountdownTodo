import 'dart:convert';

import 'package:http/http.dart' as http;

import 'thirty_day_challenge.dart';

/// GitHub 根目录 challenge_catalog.json 中的一份挑战模板。
class CloudChallengeTemplate {
  final String id;
  final String title;
  final String description;
  final List<String> tags;
  final List<String> tasks;

  const CloudChallengeTemplate({
    required this.id,
    required this.title,
    this.description = '',
    this.tags = const [],
    required this.tasks,
  });

  factory CloudChallengeTemplate.fromJson(Map<String, dynamic> json) {
    final rawId = json['id']?.toString().trim() ?? '';
    final rawTitle = json['title']?.toString().trim() ?? '';
    final rawDescription = json['description']?.toString().trim() ?? '';
    final rawTags = json['tags'];
    final rawTasks = json['tasks'];

    final tags = rawTags is List
        ? rawTags
            .map((tag) => tag.toString().trim())
            .where((tag) => tag.isNotEmpty)
            .toList(growable: false)
        : const <String>[];
    final tasks = rawTasks is List
        ? rawTasks
            .map((task) => task.toString().trim())
            .where((task) => task.isNotEmpty)
            .toList(growable: false)
        : const <String>[];

    if (rawId.isEmpty || rawTitle.isEmpty || tasks.isEmpty) {
      throw const FormatException('云端挑战缺少 id、title 或 tasks');
    }

    return CloudChallengeTemplate(
      id: rawId,
      title: rawTitle,
      description: rawDescription,
      tags: tags,
      tasks: tasks,
    );
  }

  ChallengeDraft toDraft() => ChallengeDraft(
        title: title,
        taskTitles: tasks,
      );
}

class CloudChallengeCatalog {
  final int version;
  final String updatedAt;
  final List<CloudChallengeTemplate> challenges;

  const CloudChallengeCatalog({
    required this.version,
    required this.updatedAt,
    required this.challenges,
  });

  factory CloudChallengeCatalog.fromJson(Map<String, dynamic> json) {
    final rawChallenges = json['challenges'];
    if (rawChallenges is! List) {
      throw const FormatException('云端挑战清单缺少 challenges 数组');
    }

    final challenges = <CloudChallengeTemplate>[];
    for (final rawChallenge in rawChallenges) {
      if (rawChallenge is! Map) continue;
      try {
        challenges.add(
          CloudChallengeTemplate.fromJson(
            Map<String, dynamic>.from(rawChallenge),
          ),
        );
      } on FormatException {
        // 允许清单中某一条损坏时，其余挑战仍然可以使用。
      }
    }
    if (challenges.isEmpty) {
      throw const FormatException('云端挑战清单没有可用挑战');
    }

    return CloudChallengeCatalog(
      version: _parseVersion(json['version']),
      updatedAt: json['updated_at']?.toString().trim() ?? '',
      challenges: challenges,
    );
  }

  static int _parseVersion(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 1;
  }

  static CloudChallengeCatalog fromResponse(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw FormatException('云端挑战请求失败（HTTP ${response.statusCode}）');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map) {
      throw const FormatException('云端挑战文档不是 JSON 对象');
    }
    return CloudChallengeCatalog.fromJson(
      Map<String, dynamic>.from(decoded),
    );
  }
}
