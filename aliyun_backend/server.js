// server.js
const WebSocket = require('ws');

// 在 8080 端口启动 WebSocket 服务 (避开未备案拦截的 80/443)
const wss = new WebSocket.Server({ port: 8081 });

// 核心状态机：存储所有在线用户及其连接的设备
// 结构: Map<userId, Set<WebSocket>>
const activeClients = new Map();

wss.on('connection', (ws, req) => {
  // 1. 客户端连接时，从 URL 提取 user_id 和 device_id
  const url = new URL(req.url, `http://${req.headers.host}`);
  const userId = url.searchParams.get('userId');
  const deviceId = url.searchParams.get('deviceId');

  // 如果没有身份信息，直接拒绝连接
  if (!userId || !deviceId) {
    ws.close(1008, 'Missing userId or deviceId');
    return;
  }

  // 2. 将设备加入该用户的专属“房间”
  if (!activeClients.has(userId)) {
    activeClients.set(userId, new Set());
  }
  const userRoom = activeClients.get(userId);
  userRoom.add(ws);
  ws.deviceId = deviceId; // 给这个连接打上设备标签

  console.log(`[上线] 用户 ${userId} 的设备 ${deviceId} 已连接。当前在线设备数: ${userRoom.size}`);

  // 3. 监听当前设备发来的消息
  ws.on('message', (messageAsString) => {
    try {
      const data = JSON.parse(messageAsString);

      // 组装要广播的消息，带上发送源的 deviceId
      const broadcastMsg = JSON.stringify({
        sourceDevice: deviceId,
        timestamp: Date.now(),
        ...data
      });

      // 4. 广播给该用户房间内的【其他】设备
      userRoom.forEach(client => {
        if (client !== ws && client.readyState === WebSocket.OPEN) {
          client.send(broadcastMsg);
        }
      });

    } catch (e) {
      console.error('解析消息失败:', e);
    }
  });

  // 5. 监听断开连接，清理内存
  ws.on('close', () => {
    userRoom.delete(ws);
    console.log(`[下线] 用户 ${userId} 的设备 ${deviceId} 已断开。`);
    // 如果这个用户没有任何设备在线了，销毁房间释放内存
    if (userRoom.size === 0) {
      activeClients.delete(userId);
    }
  });
});

console.log('🚀 跨端状态同步 WebSocket 服务已启动: ws://0.0.0.0:8080');