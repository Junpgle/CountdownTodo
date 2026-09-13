/// Extracts the version marker used to decide whether privacy consent is
/// still valid.
class PrivacyPolicyVersion {
  const PrivacyPolicyVersion._();

  /// Returns a normalized `yyyy-MM-dd` marker, or `null` when the document
  /// does not contain a supported version marker.
  static String? extract(String content) {
    // Keep the explicit version marker ahead of the implementation-review
    // date. The current policy uses the latter, while older policies used the
    // former. The effective date is only a final compatibility fallback.
    const labels = ['版本日期', '最近按实现核对', '生效日期'];
    for (final label in labels) {
      final escapedLabel = RegExp.escape(label);
      final localizedMatch = RegExp(
        '$escapedLabel\\s*[：:]?\\s*'
        r'(\d{4})年\s*(\d{1,2})月\s*(\d{1,2})日',
      ).firstMatch(content);
      if (localizedMatch != null) {
        return _formatDate(
          localizedMatch.group(1)!,
          localizedMatch.group(2)!,
          localizedMatch.group(3)!,
        );
      }

      final isoMatch = RegExp(
        '$escapedLabel\\s*[：:]?\\s*'
        r'(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})',
      ).firstMatch(content);
      if (isoMatch != null) {
        return _formatDate(
          isoMatch.group(1)!,
          isoMatch.group(2)!,
          isoMatch.group(3)!,
        );
      }
    }
    return null;
  }

  static String _formatDate(String year, String month, String day) {
    return '$year-${month.padLeft(2, '0')}-${day.padLeft(2, '0')}';
  }
}
