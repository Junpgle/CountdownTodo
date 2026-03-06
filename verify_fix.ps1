# 🔍 修复验证脚本：检查 created_date 修复是否完整
# PowerShell 版本

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "🔍 验证 created_date 修复完整性" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

$PASS = 0
$FAIL = 0

function Check-File {
    param(
        [string]$FilePath,
        [string]$Pattern,
        [string]$Description
    )

    if (-not (Test-Path $FilePath)) {
        Write-Host "✗ 文件不存在: $FilePath" -ForegroundColor Red
        $script:FAIL++
        return $false
    }

    $content = Get-Content $FilePath -Raw -ErrorAction SilentlyContinue
    if ($content -match $Pattern) {
        Write-Host "✓ $Description" -ForegroundColor Green
        $script:PASS++
        return $true
    } else {
        Write-Host "✗ $Description (未找到)" -ForegroundColor Red
        $script:FAIL++
        return $false
    }
}

Write-Host "📋 检查 1：后端数据库表结构" -ForegroundColor Yellow
Check-File "math-quiz-backend\schema.sql" "created_date TIMESTAMP" "数据库包含 created_date 字段"
Write-Host ""

Write-Host "📋 检查 2：后端同步 API" -ForegroundColor Yellow
Check-File "math-quiz-backend\src\index.js" "tCreatedDate" "API 接收 created_date 参数"
Check-File "math-quiz-backend\src\index.js" "created_date" "INSERT 语句包含 created_date"
Check-File "math-quiz-backend\src\index.js" "finalCreatedDate" "UPDATE 语句保留 created_date"
Write-Host ""

Write-Host "📋 检查 3：Flutter 数据模型" -ForegroundColor Yellow
Check-File "lib\models.dart" "int\? createdDate;" "TodoItem 包含 createdDate 字段"
Check-File "lib\models.dart" "'created_date': createdDate" "toJson 正确序列化 createdDate"
Write-Host ""

Write-Host "📋 检查 4：UI 层修复（关键文件）" -ForegroundColor Yellow
Check-File "lib\widgets\todo_section_widget.dart" "createdDate: createdAt\.millisecondsSinceEpoch" "添加待办时保存 createdDate"
Check-File "lib\widgets\todo_section_widget.dart" "todo\.createdDate \?\? todo\.createdAt" "显示待办时兼容旧数据"
Check-File "lib\screens\course_screens.dart" "todo\.createdDate \?\? todo\.createdAt" "课程表使用 createdDate"
Check-File "lib\services\notification_service.dart" "t\.createdDate \?\? t\.createdAt" "通知服务使用 createdDate"
Write-Host ""

Write-Host "📋 检查 5：文档完整性" -ForegroundColor Yellow
Check-File "BUGFIX_CREATED_DATE.md" "修复报告" "存在完整修复报告"
Check-File "DEPLOYMENT_GUIDE.md" "部署指南" "存在部署指南"
Check-File "CHANGELOG_v1.7.2.md" "版本更新日志" "存在版本更新日志"
Check-File "math-quiz-backend\migrations\add_created_date_column.sql" "ALTER TABLE todos ADD COLUMN created_date" "存在数据库迁移脚本"
Write-Host ""

Write-Host "📋 检查 6：版本号更新" -ForegroundColor Yellow
Check-File "pubspec.yaml" "version: 1\.7\.2" "版本号已更新为 1.7.2"
Write-Host ""

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "📊 验证结果统计" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "通过: $PASS 项" -ForegroundColor Green
Write-Host "失败: $FAIL 项" -ForegroundColor Red
Write-Host ""

if ($FAIL -eq 0) {
    Write-Host "🎉 所有检查通过！修复完整。" -ForegroundColor Green
    Write-Host ""
    Write-Host "📝 下一步：" -ForegroundColor Cyan
    Write-Host "1. 提交代码到 Git"
    Write-Host "2. 按照 DEPLOYMENT_GUIDE.md 部署到生产环境"
    Write-Host "3. 通知用户更新应用"
    exit 0
} else {
    Write-Host "⚠️  存在 $FAIL 项未通过检查，请修复后再部署！" -ForegroundColor Red
    exit 1
}

