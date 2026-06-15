import { ApiService } from './api';

type WsEventHandler = (data: Record<string, unknown>) => void;

interface WsMessage {
  action: string;
  [key: string]: unknown;
}

export class WsService {
  private static instance: WsService | null = null;
  private ws: WebSocket | null = null;
  private userId: number | null = null;
  private handlers = new Map<string, Set<WsEventHandler>>();
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null;
  private heartbeatTimer: ReturnType<typeof setInterval> | null = null;
  private lastMessageTime = 0;
  private reconnectAttempt = 0;
  private intendedState: 'connected' | 'disconnected' = 'disconnected';
  private pendingClose = false;

  static getInstance(): WsService {
    if (!WsService.instance) {
      WsService.instance = new WsService();
    }
    return WsService.instance;
  }

  on(action: string, handler: WsEventHandler): () => void {
    if (!this.handlers.has(action)) {
      this.handlers.set(action, new Set());
    }
    this.handlers.get(action)!.add(handler);
    return () => { this.handlers.get(action)?.delete(handler); };
  }

  send(data: Record<string, unknown>) {
    if (this.ws?.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(data));
    }
  }

  connect(userId: number) {
    this.intendedState = 'connected';
    this.pendingClose = false;
    if (this.ws) {
      const state = this.ws.readyState;
      if (state === WebSocket.OPEN || state === WebSocket.CONNECTING) {
        this.userId = userId;
        return;
      }
    }
    this.userId = userId;
    this.reconnectAttempt = 0;
    this.doConnect();
  }

  disconnect() {
    this.intendedState = 'disconnected';
    this.stopHeartbeat();
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
    if (!this.ws) return;
    const state = this.ws.readyState;
    if (state === WebSocket.CONNECTING) {
      this.pendingClose = true;
      this.ws.onopen = null;
      this.ws.onclose = null;
      this.ws.onerror = null;
      this.ws.onmessage = null;
      try { this.ws.close(); } catch { /* ignore */ }
      this.ws = null;
      return;
    }
    if (state === WebSocket.OPEN || state === WebSocket.CLOSING) {
      this.ws.onclose = null;
      this.ws.onerror = null;
      try { this.ws.close(); } catch { /* ignore */ }
      this.ws = null;
    }
  }

  private doConnect() {
    if (!this.userId) return;
    const token = ApiService.getToken();

    const baseUrl = ApiService.getBackendUrl();
    const wsBase = baseUrl.replace('https://', 'wss://').replace('http://', 'ws://');
    const deviceId = ApiService.getDeviceId();
    const version = '4.1.6';
    const params = new URLSearchParams({
      userId: String(this.userId),
      deviceId,
      platform: 'web',
      version,
    });
    if (token) params.set('token', token);
    const url = `${wsBase}/ws?${params.toString()}`;
    console.log(`[WS] connecting to ${url}`);

    let ws: WebSocket;
    try {
      ws = new WebSocket(url);
    } catch {
      this.scheduleReconnect();
      return;
    }
    this.ws = ws;

    const onopen = () => {
      if (this.ws !== ws) {
        try { ws.close(); } catch { /* ignore */ }
        return;
      }
      if (this.pendingClose || this.intendedState === 'disconnected') {
        this.pendingClose = false;
        try { ws.close(); } catch { /* ignore */ }
        return;
      }
      this.reconnectAttempt = 0;
      this.lastMessageTime = Date.now();
      this.startHeartbeat();
      console.log(`[WS] connected userId=${this.userId}`);
    };

    const onmessage = (e: MessageEvent) => {
      if (this.ws !== ws) return;
      this.lastMessageTime = Date.now();
      try {
        const data = JSON.parse(e.data) as WsMessage;
        const action = data.action;

        // 静默跳过内部信令，不触发任何 handler
        if (!action || ['PONG', 'HEARTBEAT', 'CONNECTED', 'SUBSCRIBED'].includes(action)) {
          if (action === 'PONG' || action === 'HEARTBEAT') return;
          return;
        }

        console.log(`[WS] received action=${action} exact=${this.handlers.get(action)?.size ?? 0} wildcard=${this.handlers.get('*')?.size ?? 0}`);

        const hs = this.handlers.get(action);
        if (hs) hs.forEach(h => h(data));
        const wildcard = this.handlers.get('*');
        if (wildcard) wildcard.forEach(h => h(data));
      } catch { /* ignore malformed messages */ }
    };

    const onclose = () => {
      if (this.ws !== ws) return;
      this.ws = null;
      this.stopHeartbeat();
      if (this.intendedState === 'connected') {
        this.scheduleReconnect();
      }
    };

    const onerror = () => { /* onclose will fire next */ };

    ws.onopen = onopen;
    ws.onmessage = onmessage;
    ws.onclose = onclose;
    ws.onerror = onerror;
  }

  private startHeartbeat() {
    this.stopHeartbeat();
    this.heartbeatTimer = setInterval(() => {
      if (this.ws?.readyState === WebSocket.OPEN) {
        this.ws.send(JSON.stringify({ action: 'HEARTBEAT' }));
      }
      if (Date.now() - this.lastMessageTime > 75000) {
        const ws = this.ws;
        if (ws) {
          ws.onclose = null;
          try { ws.close(); } catch { /* ignore */ }
        }
        this.ws = null;
        this.stopHeartbeat();
        if (this.intendedState === 'connected') {
          this.scheduleReconnect();
        }
      }
    }, 30000);
  }

  private stopHeartbeat() {
    if (this.heartbeatTimer) {
      clearInterval(this.heartbeatTimer);
      this.heartbeatTimer = null;
    }
  }

  private scheduleReconnect() {
    if (this.reconnectTimer) clearTimeout(this.reconnectTimer);
    const delays = [3000, 5000, 10000, 30000, 60000];
    const delay = delays[Math.min(this.reconnectAttempt, delays.length - 1)];
    this.reconnectAttempt++;
    this.reconnectTimer = setTimeout(() => {
      if (this.intendedState === 'connected') {
        this.doConnect();
      }
    }, delay);
  }
}
