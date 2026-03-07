const BASE_URL = 'https://mathquiz.junpgle.me';

export const ApiService = {
getToken: () => localStorage.getItem('cdt_token'),
  setToken: (token: string) => localStorage.setItem('cdt_token', token),
  clearToken: () => localStorage.removeItem('cdt_token'),

  getDeviceId: () => {
    let did = localStorage.getItem('cdt_device_id');
    if (!did) {
      did = 'web_' + Math.random().toString(36).substring(2, 15);
      localStorage.setItem('cdt_device_id', did);
    }
    return did;
  },

  async request(endpoint: string, options: RequestInit = {}) {
    const token = this.getToken();

    // 修复 TypeScript 字典类型报错
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
      throw new Error(data.error || '请求失败');
    }
    return data;
  },
};