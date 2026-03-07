const BASE_URL = 'https://mathquiz.junpgle.me';

/**
* ApiService 处理所有与后端的通信
* 包含 Token 管理、设备 ID 生成以及基于用户 ID 的本地数据隔离逻辑
*/
export const ApiService = {
getToken: (): string | null => localStorage.getItem('cdt_token'),
  setToken: (token: string): void => localStorage.setItem('cdt_token', token),

  /**
   * 清除登录状态及关联的标记
   */
  clearAuthAndData: (): void => {
    localStorage.removeItem('cdt_token');
    localStorage.removeItem('cdt_user');
    localStorage.removeItem('cdt_sync_stats');
  },

  /**
   * 生成带用户 ID 前缀的存储键名，实现物理隔离
   */
  getUserKey: (userId: number, key: string) => `u${userId}_${key}`,

  getDeviceId: (): string => {
    let did = localStorage.getItem('cdt_device_id');
    if (!did) {
      did = 'web_' + Math.random().toString(36).substring(2, 15);
      localStorage.setItem('cdt_device_id', did);
    }
    return did;
  },

  async request(endpoint: string, options: RequestInit = {}) {
    const token = this.getToken();
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      ...(options.headers as Record<string, string> || {}),
    };

    if (token) {
      headers['Authorization'] = `Bearer ${token}`;
    }

    const res = await fetch(`${BASE_URL}${endpoint}`, {
      ...options,
      headers,
    });

    const data = await res.json();
    if (!res.ok) {
      throw new Error(data.error || data.message || '请求失败');
    }
    return data;
  },

  async login(email: string, password: string) {
    return this.request('/api/auth/login', {
      method: 'POST',
      body: JSON.stringify({ email, password })
    });
  },

  async register(payload: any) {
    return this.request('/api/auth/register', {
      method: 'POST',
      body: JSON.stringify(payload)
    });
  }
};