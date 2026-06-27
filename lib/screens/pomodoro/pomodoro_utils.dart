import 'package:flutter/material.dart';

import '../../utils/app_color_utils.dart';
export '../../utils/time_utils.dart';

Color hexToColor(String hex) {
  return AppColorUtils.hexToColor(
    hex,
    fallback: const Color(0xFF607D8B),
  );
}
