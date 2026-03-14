import { ApiService } from '../services/api';

// --------------------------------------------------------
// 常量与工具函数
// --------------------------------------------------------
export const CURRENT_WEB_VERSION = "2.0.9"; // 当前网页版的硬编码版本号

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
  version: number;
  created_at: number;
  updated_at: number;
  is_deleted: number;
}

// ── 番茄钟记录本地存储 ──
export function getLocalPomRecords(userId: number): PomodoroRecord[] {
  try {
    return JSON.parse(localStorage.getItem(`u${userId}_pom_records`) || '[]') as PomodoroRecord[];
  } catch { return []; }
}
export function setLocalPomRecords(userId: number, records: PomodoroRecord[]) {
  localStorage.setItem(`u${userId}_pom_records`, JSON.stringify(records));
}
export function getPomLastSyncTime(userId: number): number {
  return parseInt(localStorage.getItem(`u${userId}_pom_last_sync`) || '0', 10);
}
export function setPomLastSyncTime(userId: number, t: number) {
  localStorage.setItem(`u${userId}_pom_last_sync`, String(t));
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
  const dirty = all.filter(r => r.updated_at > lastSync || r.is_deleted);

  const now = Date.now();

  // Upload dirty records
  if (dirty.length > 0) {
    try {
      await ApiService.request('/api/pomodoro/records', {
        method: 'POST',
        body: JSON.stringify({ records: dirty }),
      });
    } catch (e) {
      console.error('上传番茄钟记录失败', e);
    }
  }

  // Pull server records since lastSync
  try {
    const fromMs = lastSync > 0 ? lastSync : (now - 365 * 24 * 3600 * 1000);
    const serverData = await ApiService.request(
      `/api/pomodoro/records?user_id=${userId}&from=${fromMs}`,
      { method: 'GET' }
    );
    const serverRecords = (Array.isArray(serverData) ? serverData : []) as PomodoroRecord[];
    const map = new Map(all.map(r => [r.uuid, r]));
    for (const sr of serverRecords) {
      const local = map.get(sr.uuid);
      if (!local || sr.version > local.version || sr.updated_at > local.updated_at) {
        // Preserve tag_uuids from local if server doesn't have them
        map.set(sr.uuid, { ...sr, tag_uuids: sr.tag_uuids ?? local?.tag_uuids ?? [] });
      }
    }
    setLocalPomRecords(userId, Array.from(map.values()));
    setPomLastSyncTime(userId, now);
  } catch (e) {
    console.error('拉取番茄钟记录失败', e);
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
    const raw = localStorage.getItem(`u${userId}_pomodoro_settings`);
    if (raw) return { ...DEFAULT_POMODORO_SETTINGS, ...JSON.parse(raw) as Partial<PomodoroSettings> };
  } catch { /* ignore */ }
  return { ...DEFAULT_POMODORO_SETTINGS };
}

export function savePomodoroSettings(userId: number, s: PomodoroSettings) {
  localStorage.setItem(`u${userId}_pomodoro_settings`, JSON.stringify(s));
}

export interface PomodoroState {
  phase: 'focus' | 'rest';
  loopIndex: number;        // 0-based current loop
  endTimeMs: number;        // absolute timestamp when current phase ends
  todoUuid: string | null;
  tagUuids: string[];
  startTimeMs: number;      // when current focus session began
  recordUuid: string;
}

export function loadPomodoroState(userId: number): PomodoroState | null {
  try {
    const raw = localStorage.getItem(`u${userId}_pomodoro_state`);
    if (raw) return JSON.parse(raw) as PomodoroState;
  } catch { /* ignore */ }
  return null;
}

export function savePomodoroState(userId: number, state: PomodoroState | null) {
  if (state === null) {
    localStorage.removeItem(`u${userId}_pomodoro_state`);
  } else {
    localStorage.setItem(`u${userId}_pomodoro_state`, JSON.stringify(state));
  }
}
