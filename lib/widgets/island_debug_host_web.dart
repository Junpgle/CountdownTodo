import 'package:flutter/material.dart';

class IslandDebugHost {
  IslandDebugHost._();

  static bool get shouldShowOverlay => false;

  static Widget route() => const Scaffold(
        body: Center(child: Text('Windows island is not available on Web')),
      );

  static Widget overlay() => const SizedBox.shrink();
}
