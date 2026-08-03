import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/thirty_day_challenge.dart';
import 'challenge_share_codec.dart';

enum ClipboardShareKind { challenge, teamInvite }

class ClipboardSharePayload {
  static const String locallyGeneratedSignatureKey =
      'clipboard_share_locally_generated_signature_v1';

  final ClipboardShareKind kind;
  final ChallengeDraft? challenge;
  final String? inviteCode;
  final String? teamName;

  const ClipboardSharePayload.challenge(this.challenge)
      : kind = ClipboardShareKind.challenge,
        inviteCode = null,
        teamName = null;

  const ClipboardSharePayload.teamInvite({
    required this.inviteCode,
    this.teamName,
  })  : kind = ClipboardShareKind.teamInvite,
        challenge = null;

  static String signature(String text) {
    return sha256.convert(utf8.encode(text.trim())).toString();
  }

  static Future<void> markLocallyGenerated(String text) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(locallyGeneratedSignatureKey, signature(text));
  }

  static ClipboardSharePayload? tryDecode(String text) {
    final challenge = ChallengeShareCodec.tryDecode(text);
    if (challenge != null) {
      return ClipboardSharePayload.challenge(challenge);
    }

    final inviteMatch = RegExp(
      r'邀请码\s*[:：]\s*\[([a-zA-Z0-9]+)\]',
    ).firstMatch(text);
    if (inviteMatch == null) return null;

    final teamName =
        RegExp(r'邀请您加入「([^」]+)」团队').firstMatch(text)?.group(1)?.trim();
    return ClipboardSharePayload.teamInvite(
      inviteCode: inviteMatch.group(1)!,
      teamName: teamName == null || teamName.isEmpty ? null : teamName,
    );
  }
}
