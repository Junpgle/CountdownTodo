/// Shared text normalization and truncation helpers.
abstract final class AppTextUtils {
  /// Returns the trimmed text, or `null` when [value] is null or blank.
  static String? trimToNull(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  /// Truncates [value] to at most [maxLength] UTF-16 code units, appending
  /// [ellipsis] when shortened.
  static String truncate(String value, int maxLength, {String ellipsis = '…'}) {
    if (maxLength <= 0) return '';
    if (value.length <= maxLength) return value;
    return '${value.substring(0, maxLength)}$ellipsis';
  }
}
