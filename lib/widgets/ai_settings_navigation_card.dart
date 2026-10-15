import 'package:flutter/material.dart';

import '../services/ai_settings_navigation_service.dart';
import '../utils/ai_settings_navigation.dart';

class AiSettingsNavigationCard extends StatefulWidget {
  const AiSettingsNavigationCard({
    super.key,
    required this.target,
    required this.username,
    this.onReturned,
  });

  final String target;
  final String username;
  final Future<void> Function()? onReturned;

  @override
  State<AiSettingsNavigationCard> createState() =>
      _AiSettingsNavigationCardState();
}

class _AiSettingsNavigationCardState extends State<AiSettingsNavigationCard> {
  final _sourceKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final destination = AiSettingsNavigationService.destination(widget.target);
    if (destination == null) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    return Card(
      key: _sourceKey,
      margin: const EdgeInsets.only(top: 8),
      color: colors.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.settings_rounded,
                  color: colors.onSecondaryContainer,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    destination.title,
                    style: TextStyle(
                      color: colors.onSecondaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              destination.path,
              style: TextStyle(
                color: colors.onSecondaryContainer,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: () async {
                await AiSettingsNavigation.open(
                  context: context,
                  target: widget.target,
                  username: widget.username,
                  sourceKey: _sourceKey,
                );
                if (mounted) await widget.onReturned?.call();
              },
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: const Text('一键直达'),
            ),
          ],
        ),
      ),
    );
  }
}
