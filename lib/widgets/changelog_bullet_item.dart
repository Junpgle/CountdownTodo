import 'package:flutter/material.dart';

/// Parsed category metadata for a changelog item prefix such as `【新增】`.
class ChangelogTagStyle {
  const ChangelogTagStyle({
    required this.prefix,
    required this.label,
    required this.color,
  });

  final String prefix;
  final String label;
  final Color color;
}

/// Resolves a distinct bright accent color for known changelog item prefixes.
ChangelogTagStyle? resolveChangelogTagStyle(
  String item,
  Brightness brightness,
) {
  final isDark = brightness == Brightness.dark;
  if (item.startsWith('【新增】')) {
    return ChangelogTagStyle(
      prefix: '【新增】',
      label: '新增',
      color: isDark ? const Color(0xFF4ADE80) : const Color(0xFF16A34A),
    );
  }
  if (item.startsWith('【优化】')) {
    return ChangelogTagStyle(
      prefix: '【优化】',
      label: '优化',
      color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7),
    );
  }
  if (item.startsWith('【修复】')) {
    return ChangelogTagStyle(
      prefix: '【修复】',
      label: '修复',
      color: isDark ? const Color(0xFFFB923C) : const Color(0xFFEA580C),
    );
  }
  if (item.startsWith('【重构】')) {
    return ChangelogTagStyle(
      prefix: '【重构】',
      label: '重构',
      color: isDark ? const Color(0xFFA78BFA) : const Color(0xFF7C3AED),
    );
  }
  return null;
}

/// Resolves the bullet dot color for a changelog item.
Color resolveChangelogDotColor(String item, ColorScheme scheme) {
  final tagStyle = resolveChangelogTagStyle(item, scheme.brightness);
  if (tagStyle != null) {
    return tagStyle.color;
  }
  if (item.startsWith('⚠️')) {
    return scheme.brightness == Brightness.dark
        ? const Color(0xFFF87171)
        : const Color(0xFFDC2626);
  }
  return scheme.onSurface.withValues(alpha: 0.4);
}

/// Renders a single changelog bullet row with a bright category pill when tagged.
class ChangelogBulletItem extends StatelessWidget {
  const ChangelogBulletItem({
    super.key,
    required this.item,
    this.textAlpha = 0.75,
    this.fontSize = 13.5,
    this.bottomPadding = 7,
    this.trailing,
  });

  final String item;
  final double textAlpha;
  final double fontSize;
  final double bottomPadding;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final tagStyle = resolveChangelogTagStyle(item, scheme.brightness);
    final dotColor = resolveChangelogDotColor(item, scheme);
    final bodyText = tagStyle != null
        ? item.substring(tagStyle.prefix.length).trimLeft()
        : item;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  if (tagStyle != null) ...[
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: tagStyle.color.withValues(
                            alpha: isDark ? 0.22 : 0.14,
                          ),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: tagStyle.color.withValues(
                              alpha: isDark ? 0.5 : 0.38,
                            ),
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          tagStyle.label,
                          style: TextStyle(
                            fontSize: (fontSize - 2).clamp(10.0, 13.0),
                            fontWeight: FontWeight.w700,
                            color: tagStyle.color,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ),
                  ],
                  TextSpan(text: bodyText),
                ],
              ),
              style: TextStyle(
                fontSize: fontSize,
                color: scheme.onSurface.withValues(alpha: textAlpha),
                height: 1.45,
              ),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}
