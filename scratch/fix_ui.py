
import os

file_path = r'd:\Codes\Android\math_quiz_app\lib\widgets\todo_section_widget.dart'

with open(file_path, 'r', encoding='utf-8') as f:
    lines = f.readlines()

# 目标替换区间：1732 到 1776 (Python 是 0 索引，所以是 1731 到 1776)
start_idx = 1731 
end_idx = 1776

new_block = """                                                    if (recurrenceIcon != null) ...[
                                                      const SizedBox(width: 4),
                                                      recurrenceIcon,
                                                    ],
                                                    const SizedBox(width: 6),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: todo.isDone ? colorScheme.onSurface.withOpacity(0.06) : badgeBg,
                                                        borderRadius: BorderRadius.circular(6),
                                                      ),
                                                      child: Text(
                                                        badge,
                                                        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: todo.isDone ? colorScheme.onSurface.withOpacity(0.3) : badgeColor),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                if (todo.teamUuid != null) ...[
                                                  const SizedBox(height: 5),
                                                  Row(
                                                    children: [
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                        decoration: BoxDecoration(
                                                            color: colorScheme.primary.withOpacity(0.18),
                                                          borderRadius: BorderRadius.circular(4),
                                                            border: Border.all(color: colorScheme.primary.withOpacity(0.4), width: 0.8),
                                                        ),
                                                        child: Row(
                                                          mainAxisSize: MainAxisSize.min,
                                                          children: [
                                                            Icon(_selectedSubTeamUuid == null ? Icons.groups_rounded : Icons.person_outline_rounded, size: 10, color: colorScheme.primary),
                                                            const SizedBox(width: 3),
                                                            Text(
                                                              _selectedSubTeamUuid == null 
                                                                ? "{teamName} · {creatorName}"
                                                                : "创建者：{creatorName}", 
                                                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: colorScheme.primary)
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
"""

# 修复模板变量 (由于刚才的代码块里有 ${}, Python 字符串处理需要小心)
new_block = new_block.replace("{teamName}", "${todo.teamName ?? '团队'}")
new_block = new_block.replace("{creatorName}", "${todo.creatorName ?? '成员'}")

# 执行整体替换
lines[start_idx:end_idx] = [new_block + "\\n"] # 这里加回之前的换行逻辑

with open(file_path, 'w', encoding='utf-8') as f:
    f.writelines(lines)

print("✅ UI Block Repair Completed.")
