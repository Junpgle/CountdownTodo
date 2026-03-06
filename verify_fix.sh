#!/bin/bash
# 🔍 修复验证脚本：检查 created_date 修复是否完整

echo "========================================="
echo "🔍 验证 created_date 修复完整性"
echo "========================================="
echo ""

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 计数器
PASS=0
FAIL=0

# 检查函数
check_file() {
    local file=$1
    local pattern=$2
    local description=$3

    if [ ! -f "$file" ]; then
        echo -e "${RED}✗${NC} 文件不存在: $file"
        FAIL=$((FAIL+1))
        return 1
    fi

    if grep -q "$pattern" "$file"; then
        echo -e "${GREEN}✓${NC} $description"
        PASS=$((PASS+1))
        return 0
    else
        echo -e "${RED}✗${NC} $description (未找到)"
        FAIL=$((FAIL+1))
        return 1
    fi
}

echo "📋 检查 1：后端数据库表结构"
check_file "math-quiz-backend/schema.sql" "created_date TIMESTAMP" "数据库包含 created_date 字段"
echo ""

echo "📋 检查 2：后端同步 API"
check_file "math-quiz-backend/src/index.js" "tCreatedDate" "API 接收 created_date 参数"
check_file "math-quiz-backend/src/index.js" "created_date" "INSERT 语句包含 created_date"
check_file "math-quiz-backend/src/index.js" "finalCreatedDate" "UPDATE 语句保留 created_date"
echo ""

echo "📋 检查 3：Flutter 数据模型"
check_file "lib/models.dart" "int? createdDate;" "TodoItem 包含 createdDate 字段"
check_file "lib/models.dart" "'created_date': createdDate" "toJson 正确序列化 createdDate"
echo ""

echo "📋 检查 4：UI 层修复（关键文件）"
check_file "lib/widgets/todo_section_widget.dart" "createdDate: createdAt.millisecondsSinceEpoch" "添加待办时保存 createdDate"
check_file "lib/widgets/todo_section_widget.dart" "todo.createdDate ?? todo.createdAt" "显示待办时兼容旧数据"
check_file "lib/screens/course_screens.dart" "todo.createdDate ?? todo.createdAt" "课程表使用 createdDate"
check_file "lib/services/notification_service.dart" "t.createdDate ?? t.createdAt" "通知服务使用 createdDate"
echo ""

echo "📋 检查 5：文档完整性"
check_file "BUGFIX_CREATED_DATE.md" "修复报告" "存在完整修复报告"
check_file "DEPLOYMENT_GUIDE.md" "部署指南" "存在部署指南"
check_file "CHANGELOG_v1.7.2.md" "版本更新日志" "存在版本更新日志"
check_file "math-quiz-backend/migrations/add_created_date_column.sql" "ALTER TABLE todos ADD COLUMN created_date" "存在数据库迁移脚本"
echo ""

echo "📋 检查 6：版本号更新"
check_file "pubspec.yaml" "version: 1.7.2" "版本号已更新为 1.7.2"
echo ""

echo "========================================="
echo "📊 验证结果统计"
echo "========================================="
echo -e "通过: ${GREEN}$PASS${NC} 项"
echo -e "失败: ${RED}$FAIL${NC} 项"
echo ""

if [ $FAIL -eq 0 ]; then
    echo -e "${GREEN}🎉 所有检查通过！修复完整。${NC}"
    echo ""
    echo "📝 下一步："
    echo "1. 提交代码到 Git"
    echo "2. 按照 DEPLOYMENT_GUIDE.md 部署到生产环境"
    echo "3. 通知用户更新应用"
    exit 0
else
    echo -e "${RED}⚠️  存在 $FAIL 项未通过检查，请修复后再部署！${NC}"
    exit 1
fi

