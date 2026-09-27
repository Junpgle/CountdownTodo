import 'package:flutter/material.dart';

import '../models.dart';
import '../widgets/app_detail_widgets.dart';

/// A readable destination for searchable records that do not have their own
/// detail screen. The fields are captured with the search result so a result
/// remains openable even when its list screen has no deep-link API.
class SearchRecordDetailScreen extends StatelessWidget {
  const SearchRecordDetailScreen({super.key, required this.result});

  final SearchResult result;

  @override
  Widget build(BuildContext context) {
    final fields = (result.extraData?['fields'] as Map?)?.map(
          (key, value) => MapEntry(key.toString(), value.toString()),
        ) ??
        const <String, String>{};
    return AppDetailScreen(
      appBarTitle: result.extraData?['detail_label']?.toString() ?? '搜索结果',
      icon: result.icon,
      title: result.title,
      headerSubtitle: result.subtitle,
      sections: [
        AppDetailSection(
          title: '记录详情',
          children: [
            for (final entry in fields.entries)
              if (entry.value.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(entry.key,
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          )),
                      const SizedBox(height: 4),
                      SelectableText(entry.value),
                    ],
                  ),
                ),
          ],
        ),
      ],
    );
  }
}
