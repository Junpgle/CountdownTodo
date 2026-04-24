import 'package:flutter/material.dart';
import 'island_ui.dart';

class IslandDebugPage extends StatefulWidget {
  const IslandDebugPage({super.key});

  @override
  State<IslandDebugPage> createState() => _IslandDebugPageState();
}

class _IslandDebugPageState extends State<IslandDebugPage> {
  bool _shown = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Island Debug')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton(
              onPressed: () => setState(() => _shown = !_shown),
              child: Text(_shown ? 'Hide island (in-layout)' : 'Show island (in-layout)'),
            ),
            const SizedBox(height: 12),
            if (_shown) SizedBox(width: 360, height: 120, child: IslandUI(initialPayload: {'endMs': DateTime.now().millisecondsSinceEpoch + 60000, 'title': 'Debug Focus'})),
          ],
        ),
      ),
    );
  }
}

