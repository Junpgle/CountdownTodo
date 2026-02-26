# **CountDownTodo 生态系统**

这是一个跨平台的生产力与时间管理套件，包含 **Flutter 移动端**、**C++ 桌面悬浮组件** 以及基于 **Cloudflare Workers** 的云端后端。它旨在通过跨设备同步，帮助用户在手机和电脑端统一管理待办事项、倒计时，并深度统计多端的屏幕使用时长。
其中移动端和后端代码在这个文件库中，桌面端代码在 [CountDownTodoLite](https://github.com/Junpgle/CountDownTodoLite)
## **🌟 核心特性**

### **1\. 跨平台数据同步**

* **待办事项 (Todo)**：支持每日/自定义周期重复，采用 LWW (Last Write Wins) 策略实现手机与电脑端双向同步。  
* **重要日倒计时**：集中管理重要纪念日，实时计算剩余天数，并支持云端备份与删除同步。

### **2\. 统一屏幕时间统计 (特色功能)**

* **多端聚合**：采集 Android 原生使用统计与 Windows 进程活跃时间。  
* **云端归类字典**：后端 D1 数据库存储应用包名映射表，自动将 com.tencent.mm 等包名转换为“微信”，并划分为“社交通讯”、“学习办公”等类别。  
* **深度分析界面**：  
  * **二级详情页**：展示今日总时长、较昨日增减趋势。  
  * **趋势图表**：纯手工绘制的近七日条形图，标注最高值与平均线。  
  * **三级分类页**：按类别（3x2 宫格）展示，点击可查看该分类下各 App 的多端详细用时。

### **3\. 桌面效率组件 (Windows)**

* **轻量悬浮窗**：基于 Win32 API 与 GDI+ 开发，支持半透明背景、DPI 自适应缩放。  
* **实时监控**：后台线程静默监测 Windows 活动窗口。  
* **自动更新**：支持通过 GitHub Manifest 实现静默或手动版本检查，引导下载最新安装包。

### **4\. 趣味数学练习**

* **每日挑战**：自定义运算符与难度，通过排行榜与全球用户竞技。

## **🛠 技术架构**

### **后端 (Serverless)**

* **Runtime**: Cloudflare Workers (Node.js)  
* **Database**: Cloudflare D1 (SQLite)  
* **Auth**: 基于邮箱验证码的注册流，配合 SHA-256 加密存储。  
* **Mail**: 集成 Resend API 发送系统邮件。

### **移动端 (Mobile)**

* **Framework**: Flutter (Dart)  
* **Storage**: SharedPreferences (本地缓存) \+ 7天周期的云端分类字典同步。  
* **UI**: 现代圆角卡片设计，适配深色模式，使用 CustomPainter 绘制高性能图表。

### **桌面端 (PC)**

* **Language**: C++ 17  
* **Graphics**: GDI+ (Vector Drawing)  
* **Networking**: WinHTTP (支持 TLS 1.2/1.3)  
* **JSON**: nlohmann/json

## **📂 项目结构**

├── math-quiz-backend/          \# Cloudflare Worker 后端代码  
│   ├── src/index.js            \# API 路由逻辑 (Auth, Todo, ScreenTime, Mappings)  
│   ├── schema.sql              \# D1 数据库表结构  
│   └── init\_mappings.sql       \# 应用名称映射初始化脚本  
├── lib/                        \# Flutter 移动端代码  
│   ├── screens/                \# 详情页、统计页、登录页  
│   ├── services/               \# API 服务、屏幕时间原生插件封装  
│   └── widgets/                \# 首页卡片组件库  
└── MathQuizLite/               \# C++ 桌面端代码  
    ├── main.cpp                \# 程序入口与更新逻辑  
    ├── ui.cpp                  \# 窗口绘制与右键菜单  
    └── api.cpp                 \# WinHTTP 封装

## **🚀 快速开始**

### **后端部署**

1. 进入 math-quiz-backend 文件夹。  
2. 执行 npx wrangler d1 execute math\_quiz\_db \--remote \--file=./schema.sql 初始化数据库。  
3. 执行 npx wrangler deploy 部署至 Cloudflare。

### **移动端运行**

1. 确保安装了 Flutter SDK。  
2. 运行 flutter pub get。  
3. 连接安卓设备执行 flutter run。

### **桌面端编译**

1. 使用 Visual Studio 2022 打开项目。  
2. 确保包含 json.hpp 头文件。  
3. 链接 winhttp.lib, gdiplus.lib, crypt32.lib 等库。  
4. 编译为 Release x64 版本。

## **📄 开源协议**

本项目遵循 MIT 协议。