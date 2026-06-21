import 'package:flutter/material.dart';

class HelpArticle {
  final String id;
  final String title;
  final String summary;
  final IconData icon;
  final Color iconColor;
  final List<String> steps;
  final String actionLabel;
  final VoidCallback? onAction;

  const HelpArticle({
    required this.id,
    required this.title,
    required this.summary,
    required this.icon,
    required this.iconColor,
    required this.steps,
    required this.actionLabel,
    this.onAction,
  });
}
