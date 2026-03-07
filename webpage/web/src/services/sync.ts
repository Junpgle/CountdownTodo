import { ApiService } from './api';
import type { TodoItem, CountdownItem } from '../types';

export const SyncEngine = {
  getLocalTodos: (): TodoItem[] => JSON.parse(localStorage.getItem('cdt_web_todos') || '[]'),
  getLocalCountdowns: (): CountdownItem[] => JSON.parse(localStorage.getItem('cdt_web_countdowns') || '[]'),
  getLastSyncTime: () => parseInt(localStorage.getItem('cdt_last_sync_time') || '0', 10),

  setLocalTodos: (todos: TodoItem[]) => localStorage.setItem('cdt_web_todos', JSON.stringify(todos)),
  setLocalCountdowns: (cds: CountdownItem[]) => localStorage.setItem('cdt_web_countdowns', JSON.stringify(cds)),
  setLastSyncTime: (time: number) => localStorage.setItem('cdt_last_sync_time', time.toString()),
  resetSync: () => localStorage.setItem('cdt_last_sync_time', '0'),

  async syncData(userId: number) {
    const lastSyncTime = this.getLastSyncTime();
    const deviceId = ApiService.getDeviceId();
    const allLocalTodos = this.getLocalTodos();
    const allLocalCds = this.getLocalCountdowns();

    // 筛选脏数据 (待上传)
    const dirtyTodos = allLocalTodos.filter(t => t.updated_at > lastSyncTime || t.is_deleted);
    const dirtyCds = allLocalCds.filter(c => c.updated_at > lastSyncTime || c.is_deleted);

    try {
      const payload = {
        user_id: userId,
        last_sync_time: lastSyncTime,
        device_id: deviceId,
        todos: dirtyTodos,
        countdowns: dirtyCds
      };

      const response = await ApiService.request('/api/sync', {
        method: 'POST',
        body: JSON.stringify(payload)
      });

      if (response.success) {
        // --- 合并 Todos ---
        const serverTodos: TodoItem[] = response.server_todos || [];
        const todoMap = new Map(allLocalTodos.map(t => [t.uuid, t]));

        for (const sTodo of serverTodos) {
          const lTodo = todoMap.get(sTodo.uuid);
          if (!lTodo) {
             todoMap.set(sTodo.uuid, sTodo);
          } else {
             // LWW 策略
             if (sTodo.version > lTodo.version || (sTodo.version === lTodo.version && sTodo.updated_at > lTodo.updated_at)) {
                todoMap.set(sTodo.uuid, sTodo);
             }
          }
        }
        this.setLocalTodos(Array.from(todoMap.values()));

        // --- 合并 Countdowns ---
        const serverCds: CountdownItem[] = response.server_countdowns || [];
        const cdMap = new Map(allLocalCds.map(c => [c.uuid, c]));

        for (const sCd of serverCds) {
          const lCd = cdMap.get(sCd.uuid);
          if (!lCd) {
             cdMap.set(sCd.uuid, sCd);
          } else {
             if (sCd.version > lCd.version || (sCd.version === lCd.version && sCd.updated_at > lCd.updated_at)) {
                cdMap.set(sCd.uuid, sCd);
             }
          }
        }
        this.setLocalCountdowns(Array.from(cdMap.values()));

        this.setLastSyncTime(response.new_sync_time);
        return true;
      }
      return false;
    } catch (e) {
      console.error('Sync failed:', e);
      throw e;
    }
  }
};
