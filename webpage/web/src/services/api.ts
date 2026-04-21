const BACKENDS = {
  cloudflare: 'https://mathquiz.junpgle.me',
  aliyun: 'https://api-cdt.junpgle.me'
};

type BackendKey = keyof typeof BACKENDS;

const getInitialBackend = (): BackendKey => {
  const saved = localStorage.getItem('cdt_backend_key') as BackendKey;
  if (saved && BACKENDS[saved]) return saved;
  return 'aliyun';
};

interface RegisterPayload {
  username?: string;
  email: string;
  password?: string;
  code?: string | null;
}

/**
 * ApiService 处理所有与后端的通信
 * 包含 Token 管理、设备 ID 生成以及基于用户 ID 的本地数据隔离逻辑
 */
export const ApiService = {
  getBackendKey: (): BackendKey => getInitialBackend(),
  
  getBackendUrl: (): string => BACKENDS[ApiService.getBackendKey()],

  setBackend: (key: BackendKey): void => {
    localStorage.setItem('cdt_backend_key', key);
    // 切换后端时，建议清除旧的 Token 和用户信息以避免混淆
    ApiService.clearAuthAndData();
  },

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
   * 生成带用户 ID 和服务器标识前缀的存储键名，实现彻底隔离
   */
  getUserKey: (userId: number, key: string) => {
    const backend = ApiService.getBackendKey();
    return `s_${backend}_u${userId}_${key}`;
  },

  getDeviceId: (): string => {
    let did = localStorage.getItem('cdt_device_id');
    if (!did) {
      did = 'web_' + Math.random().toString(36).substring(2, 15);
      localStorage.setItem('cdt_device_id', did);
    }
    return did;
  },

  async request(endpoint: string, options: RequestInit = {}): Promise<Record<string, unknown>> {
    const token = this.getToken();
    const url = this.getBackendUrl();
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      ...(options.headers as Record<string, string> || {}),
    };

    if (token) {
      headers['Authorization'] = `Bearer ${token}`;
    }

    const res = await fetch(`${url}${endpoint}`, {
      ...options,
      headers,
    });

    if (res.status === 401) {
      this.clearAuthAndData();
      // 触发页面重载，并强制留在 App 登录模式
      window.location.hash = 'app'; 
      window.location.search = '';
      window.location.reload(); 
      throw new Error('未授权，请重新登录');
    }

    const data = await res.json() as Record<string, unknown>;
    if (!res.ok) {
      const errMsg = (data.error ?? data.message ?? '请求失败') as string;
      throw new Error(errMsg);
    }
    return data;
  },

  async login(email: string, password: string) {
    return this.request('/api/auth/login', {
      method: 'POST',
      body: JSON.stringify({ email, password })
    });
  },

  async register(payload: RegisterPayload) {
    return this.request('/api/auth/register', {
      method: 'POST',
      body: JSON.stringify(payload)
    });
  },

  async forgotPassword(email: string) {
    return this.request('/api/auth/forgot_password', {
      method: 'POST',
      body: JSON.stringify({ email })
    });
  },

  async resetPassword(email: string, code: string, newPassword: string) {
    return this.request('/api/auth/reset_password', {
      method: 'POST',
      body: JSON.stringify({ email, code, new_password: newPassword })
    });
  }
};