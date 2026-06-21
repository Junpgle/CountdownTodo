import 'package:flutter/material.dart';
import '../../models/help_article.dart';

class HelpArticleScreen extends StatelessWidget {
  final HelpArticle article;
  final bool isEmbedded;

  const HelpArticleScreen(
      {super.key, required this.article, this.isEmbedded = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: isEmbedded
          ? null
          : AppBar(
              title: Text(article.title),
            ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: article.iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(article.icon, size: 36, color: article.iconColor),
          ),
          const SizedBox(height: 20),
          Text(
            article.title,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            article.summary,
            style: TextStyle(
              fontSize: 15,
              color: scheme.onSurface.withValues(alpha: 0.6),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 28),
          for (int i = 0; i < article.steps.length; i++) ...[
            _buildStep(i + 1, article.steps[i], scheme, article.iconColor),
            if (i < article.steps.length - 1) const SizedBox(height: 16),
          ],
          if (article.onAction != null) ...[
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  article.onAction!();
                },
                icon: const Icon(Icons.arrow_forward_rounded),
                label: Text(article.actionLabel),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: article.iconColor,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStep(int number, String text, ColorScheme scheme, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            '$number',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              text,
              style: TextStyle(
                fontSize: 15,
                color: scheme.onSurface.withValues(alpha: 0.8),
                height: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
