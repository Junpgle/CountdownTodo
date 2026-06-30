import { ApiService } from './api';
import type { TodoItem, CountdownItem, TodoGroup, PomodoroRecord, PomodoroTag, TodoPlanBlock, TimeLogItem } from '../types';

interface IndependentCompletion {
  is_completed: boolean;
  updated_at: number;
}

export const SyncEngine = {
  // --- 带用户 ID 隔离的存储键 ---

  getLocalTodos: (userId: number): TodoItem[] => JSON.parse(localStorage.getItem(ApiService.getUserKey(userId, 'web_todos')) || '[]'),
  getLocalCountdowns: (userId: number): CountdownItem[] => JSON.parse(localStorage.getItem(ApiService.getUserKey(userId, 'web_countdowns')) || '[]'),
  getLocalTodoGroups: (userId: number): TodoGroup[] => JSON.parse(localStorage.getItem(ApiService.getUserKey(userId, 'web_todo_groups')) || '[]'),
  getLocalPlanBlocks: (userId: number): TodoPlanBlock[] => JSON.parse(localStorage.getItem(ApiService.getUserKey(userId, 'web_plan_blocks')) || '[]'),
  getLocalTimeLogs: (userId: number): TimeLogItem[] => JSON.parse(localStorage.getItem(ApiService.getUserKey(userId, 'web_time_logs')) || '[]'),
  getLocalPomodoroRecords: (userId: number): PomodoroRecord[] => JSON.parse(localStorage.getItem(ApiService.getUserKey(userId, 'pom_records')) || '[]'),
  getLocalPomodoroTags: (userId: number): PomodoroTag[] => JSON.parse(localStorage.getItem(ApiService.getUserKey(userId, 'pom_tags')) || '[]'),
  getLastSyncTime: (userId: number) => parseInt(localStorage.getItem(ApiService.getUserKey(userId, 'last_sync_time')) || '0', 10),

  // 🚀 独立完成状态存储 (collabType=1)
  getLocalIndependentCompletions: (userId: number): Record<string, IndependentCompletion> =>
    JSON.parse(localStorage.getItem(ApiService.getUserKey(userId, 'independent_completions')) || '{}'),
  setLocalIndependentCompletions: (userId: number, completions: Record<string, IndependentCompletion>) =>
    localStorage.setItem(ApiService.getUserKey(userId, 'independent_completions'), JSON.stringify(completions)),

  setLocalTodos: (userId: number, todos: TodoItem[]) => localStorage.setItem(ApiService.getUserKey(userId, 'web_todos'), JSON.stringify(todos)),
  setLocalCountdowns: (userId: number, cds: CountdownItem[]) => localStorage.setItem(ApiService.getUserKey(userId, 'web_countdowns'), JSON.stringify(cds)),
  setLocalTodoGroups: (userId: number, groups: TodoGroup[]) => localStorage.setItem(ApiService.getUserKey(userId, 'web_todo_groups'), JSON.stringify(groups)),
  setLocalPlanBlocks: (userId: number, blocks: TodoPlanBlock[]) => localStorage.setItem(ApiService.getUserKey(userId, 'web_plan_blocks'), JSON.stringify(blocks)),
  setLocalTimeLogs: (userId: number, logs: TimeLogItem[]) => localStorage.setItem(ApiService.getUserKey(userId, 'web_time_logs'), JSON.stringify(logs)),
  setLocalPomodoroRecords: (userId: number, logs: PomodoroRecord[]) => localStorage.setItem(ApiService.getUserKey(userId, 'pom_records'), JSON.stringify(logs)),
  setLocalPomodoroTags: (userId: number, tags: PomodoroTag[]) => localStorage.setItem(ApiService.getUserKey(userId, 'pom_tags'), JSON.stringify(tags)),
  setLastSyncTime: (userId: number, time: number) => localStorage.setItem(ApiService.getUserKey(userId, 'last_sync_time'), time.toString()),
  resetSync: (userId: number) => localStorage.setItem(ApiService.getUserKey(userId, 'last_sync_time'), '0'),

  // 🚀 更新独立完成状态 (用户勾选/取消勾选时调用)
  updateIndependentCompletion: (userId: number, todoUuid: string, isCompleted: boolean) => {
    const completions = SyncEngine.getLocalIndependentCompletions(userId);
    completions[todoUuid] = {
      is_completed: isCompleted,
      updated_at: Date.now()
    };
    SyncEngine.setLocalIndependentCompletions(userId, completions);
  },

  // 🚀 应用独立完成状态到待办列表 (加载数据时调用，模拟 Flutter 端的 SQL JOIN 逻辑)
  applyIndependentCompletions: (userId: number, todos: TodoItem[]): TodoItem[] => {
    const completions = SyncEngine.getLocalIndependentCompletions(userId);
    if (Object.keys(completions).length === 0) return todos;

    return todos.map(todo => {
      if (todo.collab_type === 1 && completions[todo.uuid]) {
        return {
          ...todo,
          is_completed: completions[todo.uuid].is_completed
        };
      }
      return todo;
    });
  },

  async syncData(userId: number) {
    const lastSyncTime = this.getLastSyncTime(userId);
    const planBlocksSyncInitKey = ApiService.getUserKey(userId, 'web_plan_blocks_sync_initialized');
    const timeLogsSyncInitKey = ApiService.getUserKey(userId, 'web_time_logs_sync_initialized');
    const shouldBackfillPlanBlocks = localStorage.getItem(planBlocksSyncInitKey) !== 'true';
    const shouldBackfillTimeLogs = localStorage.getItem(timeLogsSyncInitKey) !== 'true';
    const syncSince = shouldBackfillPlanBlocks || shouldBackfillTimeLogs ? 0 : lastSyncTime;
    const deviceId = ApiService.getDeviceId();
    const allLocalTodos = this.getLocalTodos(userId);
    const allLocalCds = this.getLocalCountdowns(userId);
    const allLocalGroups = this.getLocalTodoGroups(userId);
    const allLocalPlanBlocks = this.getLocalPlanBlocks(userId);
    const allLocalTimeLogs = this.getLocalTimeLogs(userId);
    const allLocalLogs = this.getLocalPomodoroRecords(userId);
    const allLocalTags = this.getLocalPomodoroTags(userId);

    // 筛选脏数据 (待上传)
    const dirtyTodos = allLocalTodos.filter(t => t.updated_at > lastSyncTime || t.is_deleted);
    const dirtyCds = allLocalCds.filter(c => c.updated_at > lastSyncTime || c.is_deleted);
    const dirtyGroups = allLocalGroups.filter(g => g.updated_at > lastSyncTime || g.is_deleted);
    const dirtyPlanBlocks = allLocalPlanBlocks.filter(p => p.updated_at > lastSyncTime || p.is_deleted);
    const dirtyTimeLogs = allLocalTimeLogs.filter(l => l.updated_at > lastSyncTime || l.is_deleted);
    const dirtyLogs = allLocalLogs.filter(r => r.updated_at > lastSyncTime || r.is_deleted);
    const dirtyTags = allLocalTags.filter(t => t.updated_at > lastSyncTime || t.is_deleted);

    try {
      console.log(`[Sync] Starting sync. LastSyncTime: ${syncSince}, Backend: ${ApiService.getBackendKey()}`);
      const payload = {
        user_id: userId,
        last_sync_time: syncSince,
        device_id: deviceId,
        todos: dirtyTodos,
        countdowns: dirtyCds,
        todo_groups: dirtyGroups,
        todo_plan_blocks_changes: dirtyPlanBlocks,
        time_logs_changes: dirtyTimeLogs,
        pomodoro_records_changes: dirtyLogs, // 兼容 Aliyun
        pomodoro_tags_changes: dirtyTags,    // 兼容 Aliyun
        screen_time: null
      };

      const response = await ApiService.request('/api/sync', {
        method: 'POST',
        body: JSON.stringify(payload)
      });

      if (response.success) {
        // --- 处理独立完成状态 (independent_completions) ---
        const independentCompletions = response.independent_completions as Array<{
          todo_uuid: string;
          is_completed: boolean | number;
          updated_at: number;
        }> | undefined;
        const localCompletions = this.getLocalIndependentCompletions(userId);

        if (Array.isArray(independentCompletions)) {
          for (const ic of independentCompletions) {
            if (!ic.todo_uuid) continue;
            const serverCompleted = ic.is_completed === true || ic.is_completed === 1;
            const serverUpdatedAt = ic.updated_at || 0;
            const local = localCompletions[ic.todo_uuid];

            // 仅当服务端更新时间大于本地更新时间时才覆盖
            if (!local || serverUpdatedAt > local.updated_at) {
              localCompletions[ic.todo_uuid] = {
                is_completed: serverCompleted,
                updated_at: serverUpdatedAt
              };
            }
          }
          this.setLocalIndependentCompletions(userId, localCompletions);
        }

        // --- 合并 Todos ---
        // 🚀 服务端返回的 server_todos 中 is_completed 已经从 todo_completions 获取了正确值
        //    所以对于 collabType=1 的待办，直接使用服务端返回的值即可
        const serverTodos = (Array.isArray(response.server_todos) ? response.server_todos : []) as TodoItem[];
        const todoMap = new Map(allLocalTodos.map(t => [t.uuid, t]));

        for (const sTodo of serverTodos) {
          const lTodo = todoMap.get(sTodo.uuid);
          if (!lTodo || sTodo.version > lTodo.version || (sTodo.version === lTodo.version && (sTodo.updated_at || 0) >= (lTodo.updated_at || 0))) {
            // 服务端数据更新，直接使用（is_completed 已经是正确值）
            todoMap.set(sTodo.uuid, sTodo);
          }
          // 本地版本更新时保留本地数据
        }
        this.setLocalTodos(userId, Array.from(todoMap.values()));

        // --- 合并 Todo Groups ---
        const serverGroups = (Array.isArray(response.server_todo_groups) ? response.server_todo_groups : []) as TodoGroup[];
        const groupMap = new Map(allLocalGroups.map(g => [String(g.uuid || g.id), g]));
        for (const sGroup of serverGroups) {
          const sUuid = String(sGroup.uuid || sGroup.id);
          const lGroup = groupMap.get(sUuid);
          if (!lGroup || sGroup.version > lGroup.version || ((sGroup.updated_at || 0) >= (lGroup.updated_at || 0))) {
            groupMap.set(sUuid, sGroup);
          }
        }
        this.setLocalTodoGroups(userId, Array.from(groupMap.values()));

        // --- 合并 Todo Plan Blocks ---
        const serverPlanBlocks = (Array.isArray(response.server_plan_blocks) ? response.server_plan_blocks : []) as TodoPlanBlock[];
        const planBlockMap = new Map(allLocalPlanBlocks.map(p => [p.uuid, p]));
        for (const sPlan of serverPlanBlocks) {
          const lPlan = planBlockMap.get(sPlan.uuid);
          if (!lPlan || sPlan.version > lPlan.version || ((sPlan.updated_at || 0) >= (lPlan.updated_at || 0))) {
            planBlockMap.set(sPlan.uuid, sPlan);
          }
        }
        this.setLocalPlanBlocks(userId, Array.from(planBlockMap.values()));

        // --- 合并 Time Logs ---
        const serverTimeLogs = (Array.isArray(response.server_time_logs) ? response.server_time_logs : []) as TimeLogItem[];
        const timeLogMap = new Map(allLocalTimeLogs.map(l => [l.uuid || l.id, l]));
        for (const sLog of serverTimeLogs) {
          const sUuid = sLog.uuid || sLog.id;
          const lLog = timeLogMap.get(sUuid);
          if (!lLog || sLog.version > lLog.version || ((sLog.updated_at || 0) >= (lLog.updated_at || 0))) {
            timeLogMap.set(sUuid, { ...sLog, uuid: sUuid, id: sUuid });
          }
        }
        this.setLocalTimeLogs(userId, Array.from(timeLogMap.values()));

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
        this.setLocalPomodoroRecords(userId, Array.from(logMap.values()));

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

        if (Array.isArray(response.joined_team_uuids)) {
          this.cleanupOrphanedTeamItems(userId, response.joined_team_uuids);
        }
        localStorage.setItem(planBlocksSyncInitKey, 'true');
        localStorage.setItem(timeLogsSyncInitKey, 'true');
        this.setLastSyncTime(userId, Number(response.new_sync_time));
        return true;
      }
      return false;
    } catch (e) {
      console.error('Sync failed:', e);
      throw e;
    }
  },

  cleanupOrphanedTeamItems(userId: number, currentTeamUuids: string[]) {
    const teamSet = new Set(currentTeamUuids);

    // 清理 Todos
    const todos = this.getLocalTodos(userId);
    const filteredTodos = todos.filter(t => !t.team_uuid || teamSet.has(t.team_uuid));
    if (filteredTodos.length !== todos.length) {
      console.log(`[Sync] Purged ${todos.length - filteredTodos.length} orphaned team todos.`);
      this.setLocalTodos(userId, filteredTodos);
    }

    // 清理 Countdowns
    const cds = this.getLocalCountdowns(userId);
    const filteredCds = cds.filter(c => !c.team_uuid || teamSet.has(c.team_uuid));
    if (filteredCds.length !== cds.length) {
      this.setLocalCountdowns(userId, filteredCds);
    }

    // 清理 Time Logs
    const timeLogs = this.getLocalTimeLogs(userId);
    const filteredTimeLogs = timeLogs.filter(l => !l.team_uuid || teamSet.has(l.team_uuid));
    if (filteredTimeLogs.length !== timeLogs.length) {
      this.setLocalTimeLogs(userId, filteredTimeLogs);
    }

    // 清理 Groups
    const groups = this.getLocalTodoGroups(userId);
    const filteredGroups = groups.filter(g => !g.team_uuid || teamSet.has(g.team_uuid));
    if (filteredGroups.length !== groups.length) {
      this.setLocalTodoGroups(userId, filteredGroups);
    }
  }
};
