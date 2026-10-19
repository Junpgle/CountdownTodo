import '../models.dart';

/// Resolves model/user supplied team names against the teams already loaded by
/// the app. An alias is accepted only when it maps to one local team. If the
/// supplied name and UUID point to different teams, the binding is ambiguous.
abstract final class AiTeamBindingResolver {
  static final RegExp _teamStatement = RegExp(
    r'(?:团队|小组)\s*(?:是|为|改成|改为|换成|绑定到|归到|设为|[:：])\s*([^\s，。；！？,;]{1,40})',
  );
  static final RegExp _teamAction = RegExp(
    r'(?:绑定|关联|属于|归属|归到|放到|放入|同步到|分配到|指定为|设为)'
    r'\s*(?:(?:到|为|至)\s*)?(?:团队|小组)?\s*[:：]?\s*'
    r'([^\s，。；！？,;]{1,40})',
  );
  static final RegExp _collectiveTeamBinding = RegExp(
    r'(?:这些|它们|全部|所有|每个|每条)(?:倒计时|事项)?(?:都)?(?:是|属于)(.{1,32}?)的',
  );
  static final RegExp _positiveBindingIntent = RegExp(
    r'绑定|关联|属于|归属|归到|放到|放入|同步到|分配到|指定为|设为|'
    r'(?:团队|小组)\s*(?:是|为|改成|改为|换成|绑定到|归到|设为|[:：])|'
    r'(?:这些|它们|全部|所有|每个|每条)(?:倒计时|事项)?(?:都)?(?:是|属于).{1,32}的',
  );
  static final RegExp _negativeBindingIntent = RegExp(
    r'(?:不要|别|不必|无需|不用|取消|不再|不想|不需要|不|没|未)'
    r'(?:再|继续)?(?:绑定|关联|指定|分配|归属)',
  );

  static bool hasExplicitBindingIntent(String text) =>
      _bindingClauses(text)
          .any((clause) => _positiveBindingIntent.hasMatch(clause));

  static String? requestedTeamName(String text, {List<Team> teams = const []}) {
    final orderedTeams =
        teams.where((team) => team.name.trim().isNotEmpty).toList()
          ..sort((a, b) => b.name.length.compareTo(a.name.length));
    for (final clause in _bindingClauses(text)) {
      if (!_positiveBindingIntent.hasMatch(clause)) continue;
      for (final team in orderedTeams) {
        if (clause.contains(team.name.trim())) return team.name.trim();
      }

      for (final pattern in [
        _teamStatement,
        _teamAction,
        _collectiveTeamBinding,
      ]) {
        final captured = pattern.firstMatch(clause)?.group(1)?.trim();
        if (captured == null || captured.isEmpty) continue;
        final candidate = captured.replaceFirst(RegExp(r'^(?:团队|小组)\s*'), '');
        if (candidate.isNotEmpty) return candidate;
      }
    }
    return null;
  }

  static List<String> _bindingClauses(String text) => text
      .split(RegExp(r'[，。；！？,;]|然后|同时|但是|但'))
      .map((clause) => clause.trim())
      .where(
        (clause) =>
            clause.isNotEmpty && !_negativeBindingIntent.hasMatch(clause),
      )
      .toList(growable: false);

  static Team? requestedTeam(String text, {required List<Team> teams}) {
    final requested = requestedTeamName(text, teams: teams);
    return requested == null ? null : resolveName(requested, teams: teams);
  }

  static Team? resolveName(String name, {required List<Team> teams}) {
    final requested = name.trim();
    if (requested.isEmpty) return null;
    final exact = teams.where((team) => team.name.trim() == requested).toList();
    if (exact.length == 1) return exact.single;
    if (exact.length > 1) return null;

    final normalized = _normalize(requested);
    if (normalized.isEmpty) return null;
    final matches = teams
        .where((team) => _normalize(team.name) == normalized)
        .toList(growable: false);
    return matches.length == 1 ? matches.single : null;
  }

  static Team? resolveReference({
    String? name,
    String? uuid,
    required List<Team> teams,
  }) {
    final byName = name?.trim().isNotEmpty == true
        ? resolveName(name!.trim(), teams: teams)
        : null;

    final normalizedUuid = uuid?.trim();
    Team? byUuid;
    if (normalizedUuid?.isNotEmpty == true) {
      for (final team in teams) {
        if (team.uuid.trim() == normalizedUuid) {
          byUuid = team;
          break;
        }
      }
    }
    if (byName != null && byUuid != null && byName.uuid != byUuid.uuid) {
      return null;
    }
    return byUuid ?? byName;
  }

  static String _normalize(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(RegExp(r'[‐‑‒–—−－]'), '-')
        .replaceFirst(RegExp(r'(?:班级|班|团队|小组|组)$'), '');
  }
}
