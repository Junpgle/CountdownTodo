#!/bin/bash

# 1. 进入项目目录（确保环境变量 .env 能被正确加载）
cd /root/CountDownTodo/math_quiz_backend/

echo "--------------------------------------------------"
echo "[$(date)] 🚀 开始执行全量双向同步任务..."

# 2. 第一步：从 Cloudflare 拉取最新数据到阿里云 (Pull)
echo "[$(date)] 📥 步骤 1/2: 正在从 Cloudflare 拉取数据..."
/usr/bin/node cron_sync_from_cf.js

# 检查上一步是否成功
if [ $? -eq 0 ]; then
    echo "[$(date)] ✅ 步骤 1 完成。"
else
    # 如果第一步失败，我们通常不希望继续执行第二步，以免数据状态混乱
    echo "[$(date)] ❌ 步骤 1 失败，跳过步骤 2。"
    echo "--------------------------------------------------"
    exit 1
fi

# 3. 第二步：将阿里云合并后的最新数据推送到 Cloudflare (Push)
echo "[$(date)] 📤 步骤 2/2: 正在将本地数据推送到 Cloudflare..."
/usr/bin/node full_sync_to_cf.js

if [ $? -eq 0 ]; then
    echo "[$(date)] ✅ 步骤 2 完成。"
else
    echo "[$(date)] ❌ 步骤 2 推送失败，请检查网络或数据量。"
    echo "--------------------------------------------------"
    exit 1
fi

echo "[$(date)] ✨ 双向同步任务结束。"
echo "--------------------------------------------------"