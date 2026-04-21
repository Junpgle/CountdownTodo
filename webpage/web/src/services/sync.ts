import { ApiService } from './api';
import type { TodoItem, CountdownItem, TodoGroup, PomodoroRecord, PomodoroTag } from '../types';

export const SyncEngine = {
  // --- 带用户 ID 隔离的存储键 ---

  getLocalTodos: (userId: number): TodoItem[] => JSON.parse(localStorage.getItem(ApiService.getUserKey(userId, 'web_todos')) || '[]'),
  getLocalCountdowns: (userId: number): CountdownItem[] => JSON.parse(localStorage.getItem(ApiService.getUserKey(userId, 'web_countdowns')) || '[]'),
  getLocalTodoGroups: (userId: number): TodoGroup[] => JSON.parse(localStorage.getItem(ApiService.getUserKey(userId, 'web_todo_groups')) || '[]'),
  getLocalTimeLogs: (userId: number): PomodoroRecord[] => JSON.parse(localStorage.getItem(ApiService.getUserKey(userId, 'pom_records')) || '[]'),
  getLocalPomodoroTags: (userId: number): PomodoroTag[] => JSON.parse(localStorage.getItem(ApiService.getUserKey(userId, 'pom_tags')) || '[]'),
  getLastSyncTime: (userId: number) => parseInt(localStorage.getItem(ApiService.getUserKey(userId, 'last_sync_time')) || '0', 10),

  setLocalTodos: (userId: number, todos: TodoItem[]) => localStorage.setItem(ApiService.getUserKey(userId, 'web_todos'), JSON.stringify(todos)),
  setLocalCountdowns: (userId: number, cds: CountdownItem[]) => localStorage.setItem(ApiService.getUserKey(userId, 'web_countdowns'), JSON.stringify(cds)),
  setLocalTodoGroups: (userId: number, groups: TodoGroup[]) => localStorage.setItem(ApiService.getUserKey(userId, 'web_todo_groups'), JSON.stringify(groups)),
  setLocalTimeLogs: (userId: number, logs: PomodoroRecord[]) => localStorage.setItem(ApiService.getUserKey(userId, 'pom_records'), JSON.stringify(logs)),
  setLocalPomodoroTags: (userId: number, tags: PomodoroTag[]) => localStorage.setItem(ApiService.getUserKey(userId, 'pom_tags'), JSON.stringify(tags)),
  setLastSyncTime: (userId: number, time: number) => localStorage.setItem(ApiService.getUserKey(userId, 'last_sync_time'), time.toString()),
  resetSync: (userId: number) => localStorage.setItem(ApiService.getUserKey(userId, 'last_sync_time'), '0'),

  async syncData(userId: number) {
    const lastSyncTime = this.getLastSyncTime(userId);
    const deviceId = ApiService.getDeviceId();
    const allLocalTodos = this.getLocalTodos(userId);
    const allLocalCds = this.getLocalCountdowns(userId);
    const allLocalGroups = this.getLocalTodoGroups(userId);
    const allLocalLogs = this.getLocalTimeLogs(userId);
    const allLocalTags = this.getLocalPomodoroTags(userId);

    // 筛选脏数据 (待上传)
    const dirtyTodos = allLocalTodos.filter(t => t.updated_at > lastSyncTime || t.is_deleted);
    const dirtyCds = allLocalCds.filter(c => c.updated_at > lastSyncTime || c.is_deleted);
    const dirtyGroups = allLocalGroups.filter(g => g.updated_at > lastSyncTime || g.is_deleted);
    const dirtyLogs = allLocalLogs.filter(r => r.updated_at > lastSyncTime || r.is_deleted);
    const dirtyTags = allLocalTags.filter(t => t.updated_at > lastSyncTime || t.is_deleted);

    try {
      console.log(`[Sync] Starting sync. LastSyncTime: ${lastSyncTime}, Backend: ${ApiService.getBackendKey()}`);
      const payload = {
        user_id: userId,
        last_sync_time: lastSyncTime,
        device_id: deviceId,
        todos: dirtyTodos,
        countdowns: dirtyCds,
        todo_groups: dirtyGroups,
        pomodoro_records_changes: dirtyLogs, // 兼容 Aliyun
        pomodoro_tags_changes: dirtyTags,    // 兼容 Aliyun
        screen_time: null
      };

      const response = await ApiService.request('/api/sync', {
        method: 'POST',
        body: JSON.stringify(payload)
      });

      if (response.success) {
        // --- 合并 Todos ---
        const serverTodos = (Array.isArray(response.server_todos) ? response.server_todos : []) as TodoItem[];
        const todoMap = new Map(allLocalTodos.map(t => [t.uuid, t]));
        for (const sTodo of serverTodos) {
          const lTodo = todoMap.get(sTodo.uuid);
          if (!lTodo || sTodo.version > lTodo.version || (sTodo.version === lTodo.version && (sTodo.updated_at || 0) >= (lTodo.updated_at || 0))) {
            todoMap.set(sTodo.uuid, sTodo);
          }
        }
        this.setLocalTodos(userId, Array.from(todoMap.values()));

        // --- 合并 Todo Groups ---
        const serverGroups = (Array.isArray(response.server_todo_groups) ? response.server_todo_groups : []) as TodoGroup[];
        const groupMap = new Map(allLocalGroups.map(g => [String(g.uuid || (g as any).id), g]));
        for (const sGroup of serverGroups) {
          const sUuid = String(sGroup.uuid || sGroup.id);
          const lGroup = groupMap.get(sUuid);
          if (!lGroup || sGroup.version > lGroup.version || ((sGroup.updated_at || 0) >= (lGroup.updated_at || 0))) {
            groupMap.set(sUuid, sGroup);
          }
        }
        this.setLocalTodoGroups(userId, Array.from(groupMap.values()));

        // --- 合并 Countdowns ---
        const serverCds = (Array.isArray(response.server_countdowns) ? response.server_countdowns : []) as CountdownItem[];
        const cdMap = new Map(allLocalCds.map(c => [c.uuid, c]));
        for (const sCd of serverCds) {
          const lCd = cdMap.get(sCd.uuid);
          if (!lCd || sCd.version > lCd.version || ((sCd.updated_at || 0) >= (lCd.updated_at || 0))) {
            cdMap.set(sCd.uuid, sCd);
          }
        }
        this.setLocalCountdowns(userId, Array.from(cdMap.values()));

        // --- 合并 Pomodoro Records ---
        const serverLogs = (Array.isArray(response.server_pomodoro_records) ? response.server_pomodoro_records : []) as PomodoroRecord[];
        const logMap = new Map(allLocalLogs.map(l => [l.uuid, l]));
        for (const sLog of serverLogs) {
          const lLog = logMap.get(sLog.uuid);
          if (!lLog || sLog.version > lLog.version || ((sLog.updated_at || 0) >= (lLog.updated_at || 0))) {
            logMap.set(sLog.uuid, sLog);
          }
        }
        this.setLocalTimeLogs(userId, Array.from(logMap.values()));

        // --- 合并 Pomodoro Tags ---
        const serverTags = (Array.isArray(response.server_pomodoro_tags) ? response.server_pomodoro_tags : []) as PomodoroTag[];
        const tagMap = new Map(allLocalTags.map(t => [t.uuid, t]));
        for (const sTag of serverTags) {
          const lTag = tagMap.get(sTag.uuid);
          if (!lTag || sTag.version > lTag.version || ((sTag.updated_at || 0) >= (lTag.updated_at || 0))) {
            tagMap.set(sTag.uuid, sTag);
          }
        }
        this.setLocalPomodoroTags(userId, Array.from(tagMap.values()));

        this.setLastSyncTime(userId, Number(response.new_sync_time));
        return true;
      }
      return false;
    } catch (e) {
      console.error('Sync failed:', e);
      throw e;
    }
  }
};

