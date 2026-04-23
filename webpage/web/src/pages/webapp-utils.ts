import { ApiService } from '../services/api';

// --------------------------------------------------------
// 常量与工具函数
// --------------------------------------------------------
export const CURRENT_WEB_VERSION = "4.1.6"; // 当前网页版的硬编码版本号

export const generateUUID = () => crypto.randomUUID ? crypto.randomUUID() : Math.random().toString(36).substring(2) + Date.now().toString(36);
export const formatDt = (d: Date) => `${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')} ${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
export const toDatetimeLocal = (ms: number) => {
  const d = new Date(ms);
  d.setMinutes(d.getMinutes() - d.getTimezoneOffset());
  return d.toISOString().slice(0, 16);
};
export const formatHM = (totalSeconds: number) => {
  if (totalSeconds === 0) return "0分钟";
  const h = Math.floor(totalSeconds / 3600);
  const m = Math.floor((totalSeconds % 3600) / 60);
  if (h > 0) return `${h}小时 ${m}分钟`;
  return `${m}分钟`;
};
export const simplifyDeviceName = (device: string) => {
  const d = device.toLowerCase();
  if (d.includes("phone")) return "手机";
  if (d.includes("tablet")) return "平板";
  if (d.includes("windows") || d.includes("pc") || d.includes("lapt")) return "电脑";
  return "未知设备";
};
export const formatTimeNum = (timeInt: number) => {
  const h = Math.floor(timeInt / 100);
  const m = timeInt % 100;
  return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}`;
};

// --------------------------------------------------------
// 本地缓存工具 (同日有效，避免重复调用 API)
// --------------------------------------------------------
export function readDayCache<T>(key: string): T | null {
  try {
    const raw = localStorage.getItem(key);
    if (!raw) return null;
    const { date, data } = JSON.parse(raw) as { date: string; data: T };
    if (date === new Date().toDateString()) return data;
  } catch { /* ignore */ }
  return null;
}

export function writeDayCache<T>(key: string, data: T): void {
  try {
    localStorage.setItem(key, JSON.stringify({ date: new Date().toDateString(), data }));
  } catch { /* ignore */ }
}

// --------------------------------------------------------
// 内部类型定义
// --------------------------------------------------------
export interface ScreenTimeStat {
  app_name: string;
  category: string;
  device_name: string;
  duration: number;
}

export interface AppGroup {
  total: number;
  category: string;
  devices: Record<string, number>;
}

export interface CourseItem {
  id: number;
  course_name: string;
  room_name: string;
  teacher_name: string;
  weekday: number;
  start_time: number;
  end_time: number;
  week_index: number;
}

export type CalendarItemType = 'course' | 'todo' | 'countdown' | 'multi';

export interface CalendarEntry {
  type: 'todo' | 'countdown';
  data: import('../types').TodoItem | import('../types').CountdownItem;
}

export interface DetailItem {
  type: CalendarItemType;
  data: CourseItem | import('../types').TodoItem | import('../types').CountdownItem | CalendarEntry[];
}

// --------------------------------------------------------
// 番茄钟相关类型定义
// --------------------------------------------------------
export interface PomodoroTag {
  uuid: string;
  name: string;
  color: string;
}

export interface PomodoroRecord {
  uuid: string;
  todo_uuid: string | null;
  start_time: number;
  end_time: number | null;
  planned_duration: number;
  actual_duration: number | null;
  status: 'completed' | 'interrupted' | 'switched';
  tag_uuids: string[];
  // sync fields
  device_id?: string | null;
  team_uuid?: string | null;
  version: number;
  created_at: number;
  updated_at: number;
  is_deleted: number;
}

// ── 番茄钟记录本地存储 ──
export function getLocalPomRecords(userId: number): PomodoroRecord[] {
  try {
    return JSON.parse(localStorage.getItem(ApiService.getUserKey(userId, 'pom_records')) || '[]') as PomodoroRecord[];
  } catch { return []; }
}
export function setLocalPomRecords(userId: number, records: PomodoroRecord[]) {
  localStorage.setItem(ApiService.getUserKey(userId, 'pom_records'), JSON.stringify(records));
}
export function getPomLastSyncTime(userId: number): number {
  return parseInt(localStorage.getItem(ApiService.getUserKey(userId, 'pom_last_sync')) || '0', 10);
}
export function setPomLastSyncTime(userId: number, t: number) {
  localStorage.setItem(ApiService.getUserKey(userId, 'pom_last_sync'), String(t));
}

// 追加 / 更新单条记录到本地，并标记为 dirty（updated_at > lastSync）
export function upsertLocalPomRecord(userId: number, rec: PomodoroRecord) {
  const all = getLocalPomRecords(userId);
  const idx = all.findIndex(r => r.uuid === rec.uuid);
  if (idx >= 0) {
    all[idx] = rec;
  } else {
    all.unshift(rec);
  }
  setLocalPomRecords(userId, all);
}

// Delta sync: upload dirty records → merge server records
export async function syncPomodoroRecords(userId: number): Promise<void> {
  const lastSync = getPomLastSyncTime(userId);
  const all = getLocalPomRecords(userId);

  // 找出本地尚未同步到云端的记录（dirty）
  const dirty = all.filter(r => r.updated_at > lastSync);

  const now = Date.now();

  // 1. 上传本地变动
  if (dirty.length > 0) {
    try {
      await ApiService.request('/api/pomodoro/records', {
        method: 'POST',
        body: JSON.stringify({ records: dirty }),
      });
    } catch (e) {
      console.error('上传失败', e);
    }
  }

  // 2. 拉取云端变动
  try {
    // 🚀 核心优化：
    // 如果没有 sync 过，拉取 30 天内的数据。
    // 如果 sync 过，拉取从 (lastSync - 2天) 开始的数据，确保由于 start_time 过滤导致的历史遗留记录能被补齐。
    const safeFromMs = lastSync > 0
        ? Math.max(0, lastSync - 2 * 24 * 3600 * 1000)
        : (now - 30 * 24 * 3600 * 1000);

    const serverData = await ApiService.request(
      `/api/pomodoro/records?user_id=${userId}&from=${safeFromMs}`,
      { method: 'GET' }
    );

    const serverRecords = (Array.isArray(serverData) ? serverData : []) as PomodoroRecord[];

    // 使用 Map 进行去重合并（UUID 为准）
    const map = new Map(all.map(r => [r.uuid, r]));

    for (const sr of serverRecords) {
      const local = map.get(sr.uuid);
      // LWW 策略：如果本地没有，或者云端版本/更新时间更晚，则覆盖本地
      if (!local || sr.version > local.version || sr.updated_at > local.updated_at) {
        map.set(sr.uuid, {
            ...sr,
            // 兜底处理：确保 tag_uuids 始终是数组
            tag_uuids: Array.isArray(sr.tag_uuids) ? sr.tag_uuids : []
        });
      }
    }

    setLocalPomRecords(userId, Array.from(map.values()));

    // 只有成功拉取后才更新同步标记
    setPomLastSyncTime(userId, now);
  } catch (e) {
    console.error('拉取失败', e);
  }
}

// --------------------------------------------------------
// 番茄钟设置类型
// --------------------------------------------------------
export interface PomodoroSettings {
  focusDuration: number;   // seconds
  restDuration: number;    // seconds
  loopCount: number;
}

export const DEFAULT_POMODORO_SETTINGS: PomodoroSettings = {
  focusDuration: 25 * 60,
  restDuration: 5 * 60,
  loopCount: 4,
};

export function loadPomodoroSettings(userId: number): PomodoroSettings {
  try {
    const raw = localStorage.getItem(ApiService.getUserKey(userId, 'pomodoro_settings'));
    if (raw) return { ...DEFAULT_POMODORO_SETTINGS, ...JSON.parse(raw) as Partial<PomodoroSettings> };
  } catch { /* ignore */ }
  return { ...DEFAULT_POMODORO_SETTINGS };
}

export function savePomodoroSettings(userId: number, s: PomodoroSettings) {
  localStorage.setItem(ApiService.getUserKey(userId, 'pomodoro_settings'), JSON.stringify(s));
}

export interface PomodoroState {
  phase: 'focus' | 'rest';
  loopIndex: number;        // 0-based current loop
  endTimeMs: number;        // absolute timestamp when current phase ends
  todoUuid: string | null;
  tagUuids: string[];
  startTimeMs: number;      // when current focus session began
  recordUuid: string;
  teamUuid?: string | null;
}

export function loadPomodoroState(userId: number): PomodoroState | null {
  try {
    const raw = localStorage.getItem(ApiService.getUserKey(userId, 'pomodoro_state'));
    if (raw) return JSON.parse(raw) as PomodoroState;
  } catch { /* ignore */ }
  return null;
}

export function savePomodoroState(userId: number, state: PomodoroState | null) {
  const key = ApiService.getUserKey(userId, 'pomodoro_state');
  if (state === null) {
    localStorage.removeItem(key);
  } else {
    localStorage.setItem(key, JSON.stringify(state));
  }
}
