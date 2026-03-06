# 🚀 快速部署指南：修复 created_date 问题

## ⚡ 一键部署脚本

### 步骤 1：备份数据库（生产环境必做）
```bash
cd math-quiz-backend
npx wrangler d1 execute math_quiz_db --remote --command "SELECT * FROM todos" > backup_$(date +%Y%m%d).sql
```

### 步骤 2：执行数据库迁移
```bash
npx wrangler d1 execute math_quiz_db --remote --file=./migrations/add_created_date_column.sql
```

### 步骤 3：验证迁移结果
```bash
npx wrangler d1 execute math_quiz_db --remote --command "PRAGMA table_info(todos);"
```
期望输出中应包含 `created_date | TIMESTAMP` 列。

### 步骤 4：部署新版本后端
```bash
npx wrangler deploy
```

### 步骤 5：构建并发布 Flutter 应用
```bash
cd ..
flutter clean
flutter pub get
flutter build apk --release
```

---

## 📋 部署检查清单

### 部署前
- [ ] 已备份生产数据库
- [ ] 已在测试环境验证迁移脚本
- [ ] 已更新 `pubspec.yaml` 版本号（建议 1.7.2）
- [ ] 已提交所有代码到 Git

### 部署中
- [ ] 数据库迁移成功（无错误日志）
- [ ] 后端 API 部署成功（访问 `/api/sync` 正常）
- [ ] Flutter 应用构建成功（无编译错误）

### 部署后
- [ ] 测试添加新待办（指定开始时间）
- [ ] 验证课程表显示位置正确
- [ ] 检查云端同步正常（`created_date` 字段保留）
- [ ] 旧数据兼容性正常（显示无异常）

---

## 🐛 故障排查

### 问题 1：迁移失败 "duplicate column name"
**原因**：`created_date` 列已存在  
**解决**：跳过此步骤，直接部署后端

### 问题 2：旧待办显示异常时间
**原因**：`createdDate` 为 `null`，但 fallback 逻辑未生效  
**解决**：检查代码中是否有遗漏的 `?? todo.createdAt`

### 问题 3：云端同步后 `created_date` 丢失
**原因**：后端未正确处理字段  
**解决**：检查 `index.js` 是否包含 `created_date` 的 INSERT/UPDATE 逻辑

---

## 📞 技术支持

如遇到问题，请参考：
- [完整修复报告](./BUGFIX_CREATED_DATE.md)
- [项目架构文档](./PROJECT_ARCHITECTURE.md)
- [GitHub Issues](https://github.com/Junpgle/CountdownTodo/issues)

