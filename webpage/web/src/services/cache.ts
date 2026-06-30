import type { TodoItem, TodoGroup, CountdownItem, PomodoroRecord, PomodoroTag, Team, TeamAnnouncement, TodoPlanBlock, TimeLogItem } from '../types';
import type { CourseItem, ScreenTimeStat } from '../pages/webapp-utils';

const DB_NAME = 'cdt_cache';
const DB_VERSION = 5;
const STORE_TODOS = 'todos';
const STORE_GROUPS = 'groups';
const STORE_COUNTDOWNS = 'countdowns';
const STORE_PLAN_BLOCKS = 'plan_blocks';
const STORE_TIME_LOGS = 'time_logs';
const STORE_COURSES = 'courses';
const STORE_SETTINGS = 'settings';
const STORE_SCREEN_TIME = 'screen_time';
const STORE_POMODORO_RECORDS = 'pom_records';
const STORE_POMODORO_TAGS = 'pom_tags';
const STORE_TEAMS = 'teams';
const STORE_ANNOUNCEMENTS = 'announcements';

interface CacheItem {
  _key: string;
  [key: string]: unknown;
}

interface SettingsCacheItem {
  _key: string;
  semester_start: number;
  cached_at: number;
}

let dbInstance: IDBDatabase | null = null;

function openDB(): Promise<IDBDatabase> {
  if (dbInstance) return Promise.resolve(dbInstance);

  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, DB_VERSION);

    request.onerror = () => reject(request.error);
    request.onsuccess = () => {
      dbInstance = request.result;
      resolve(dbInstance);
    };

    request.onupgradeneeded = (event) => {
      const db = (event.target as IDBOpenDBRequest).result;
      if (!db.objectStoreNames.contains(STORE_TODOS)) {
        db.createObjectStore(STORE_TODOS, { keyPath: 'uuid' });
      }
      if (!db.objectStoreNames.contains(STORE_GROUPS)) {
        db.createObjectStore(STORE_GROUPS, { keyPath: 'uuid' });
      }
      if (!db.objectStoreNames.contains(STORE_COUNTDOWNS)) {
        db.createObjectStore(STORE_COUNTDOWNS, { keyPath: 'uuid' });
      }
      if (!db.objectStoreNames.contains(STORE_PLAN_BLOCKS)) {
        db.createObjectStore(STORE_PLAN_BLOCKS, { keyPath: 'uuid' });
      }
      if (!db.objectStoreNames.contains(STORE_TIME_LOGS)) {
        db.createObjectStore(STORE_TIME_LOGS, { keyPath: 'uuid' });
      }
      if (!db.objectStoreNames.contains(STORE_COURSES)) {
        db.createObjectStore(STORE_COURSES, { keyPath: 'id' });
      }
      if (!db.objectStoreNames.contains(STORE_SETTINGS)) {
        db.createObjectStore(STORE_SETTINGS, { keyPath: '_key' });
      }
      if (!db.objectStoreNames.contains(STORE_SCREEN_TIME)) {
        db.createObjectStore(STORE_SCREEN_TIME, { keyPath: '_key' });
      }
      if (!db.objectStoreNames.contains(STORE_POMODORO_RECORDS)) {
        db.createObjectStore(STORE_POMODORO_RECORDS, { keyPath: 'uuid' });
      }
      if (!db.objectStoreNames.contains(STORE_POMODORO_TAGS)) {
        db.createObjectStore(STORE_POMODORO_TAGS, { keyPath: 'uuid' });
      }
      if (!db.objectStoreNames.contains(STORE_TEAMS)) {
        db.createObjectStore(STORE_TEAMS, { keyPath: '_key' });
      }
      if (!db.objectStoreNames.contains(STORE_ANNOUNCEMENTS)) {
        db.createObjectStore(STORE_ANNOUNCEMENTS, { keyPath: '_key' });
      }
    };
  });
}

async function getAll<T>(storeName: string): Promise<T[]> {
  const db = await openDB();
  return new Promise((resolve, reject) => {
    const tx = db.transaction(storeName, 'readonly');
    const store = tx.objectStore(storeName);
    const request = store.getAll();
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

async function getOne<T>(storeName: string, key: string): Promise<T | null> {
  const db = await openDB();
  return new Promise((resolve, reject) => {
    const tx = db.transaction(storeName, 'readonly');
    const store = tx.objectStore(storeName);
    const request = store.get(key);
    request.onsuccess = () => resolve(request.result ?? null);
    request.onerror = () => reject(request.error);
  });
}

async function putOne<T>(storeName: string, item: T): Promise<void> {
  const db = await openDB();
  return new Promise((resolve, reject) => {
    const tx = db.transaction(storeName, 'readwrite');
    const store = tx.objectStore(storeName);
    store.put(item);
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
  });
}

async function putAll<T>(storeName: string, items: T[]): Promise<void> {
  const db = await openDB();
  return new Promise((resolve, reject) => {
    const tx = db.transaction(storeName, 'readwrite');
    const store = tx.objectStore(storeName);
    for (const item of items) {
      store.put(item);
    }
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
  });
}

async function clearStoreByPrefix(storeName: string, prefix: string): Promise<void> {
  const db = await openDB();
  return new Promise<void>((resolve, reject) => {
    const tx = db.transaction(storeName, 'readwrite');
    const store = tx.objectStore(storeName);
    const request = store.openCursor();
    request.onsuccess = () => {
      const cursor = request.result;
      if (cursor) {
        if ((cursor.value as CacheItem)._key === prefix) {
          cursor.delete();
        }
        cursor.continue();
      } else {
        resolve();
      }
    };
    request.onerror = () => reject(request.error);
  });
}

async function clearStoreByUser(storeName: string, userId: number): Promise<void> {
  return clearStoreByPrefix(storeName, `u${userId}`);
}

export const CacheService = {
  // Todos
  async getCachedTodos(userId: number): Promise<TodoItem[] | null> {
    try {
      const key = `u${userId}`;
      const all = await getAll<CacheItem>(STORE_TODOS);
      const cached = all.filter(t => t._key === key) as unknown as TodoItem[];
      return cached.length > 0 ? cached : null;
    } catch {
      return null;
    }
  },

  async setCachedTodos(userId: number, todos: TodoItem[]): Promise<void> {
    try {
      const key = `u${userId}`;
      await clearStoreByPrefix(STORE_TODOS, key);
      const itemsWithKey = todos.map(t => ({ ...t, _key: key }));
      await putAll(STORE_TODOS, itemsWithKey);
    } catch (e) {
      console.warn('CacheService: Failed to cache todos', e);
    }
  },

  // Groups
  async getCachedGroups(userId: number): Promise<TodoGroup[] | null> {
    try {
      const key = `u${userId}`;
      const all = await getAll<CacheItem>(STORE_GROUPS);
      const cached = all.filter(g => g._key === key) as unknown as TodoGroup[];
      return cached.length > 0 ? cached : null;
    } catch {
      return null;
    }
  },

  async setCachedGroups(userId: number, groups: TodoGroup[]): Promise<void> {
    try {
      const key = `u${userId}`;
      await clearStoreByPrefix(STORE_GROUPS, key);
      const itemsWithKey = groups.map(g => ({ ...g, _key: key }));
      await putAll(STORE_GROUPS, itemsWithKey);
    } catch (e) {
      console.warn('CacheService: Failed to cache groups', e);
    }
  },

  // Countdowns
  async getCachedCountdowns(userId: number): Promise<CountdownItem[] | null> {
    try {
      const key = `u${userId}`;
      const all = await getAll<CacheItem>(STORE_COUNTDOWNS);
      const cached = all.filter(c => c._key === key) as unknown as CountdownItem[];
      return cached.length > 0 ? cached : null;
    } catch {
      return null;
    }
  },

  async setCachedCountdowns(userId: number, countdowns: CountdownItem[]): Promise<void> {
    try {
      const key = `u${userId}`;
      await clearStoreByPrefix(STORE_COUNTDOWNS, key);
      const itemsWithKey = countdowns.map(c => ({ ...c, _key: key }));
      await putAll(STORE_COUNTDOWNS, itemsWithKey);
    } catch (e) {
      console.warn('CacheService: Failed to cache countdowns', e);
    }
  },

  // Plan Blocks
  async getCachedPlanBlocks(userId: number): Promise<TodoPlanBlock[] | null> {
    try {
      const key = `u${userId}`;
      const all = await getAll<CacheItem>(STORE_PLAN_BLOCKS);
      const cached = all.filter(p => p._key === key) as unknown as TodoPlanBlock[];
      return cached.length > 0 ? cached : null;
    } catch {
      return null;
    }
  },

  async setCachedPlanBlocks(userId: number, blocks: TodoPlanBlock[]): Promise<void> {
    try {
      const key = `u${userId}`;
      await clearStoreByPrefix(STORE_PLAN_BLOCKS, key);
      const itemsWithKey = blocks.map(p => ({ ...p, _key: key }));
      await putAll(STORE_PLAN_BLOCKS, itemsWithKey);
    } catch (e) {
      console.warn('CacheService: Failed to cache plan blocks', e);
    }
  },

  // Time Logs
  async getCachedTimeLogs(userId: number): Promise<TimeLogItem[] | null> {
    try {
      const key = `u${userId}`;
      const all = await getAll<CacheItem>(STORE_TIME_LOGS);
      const cached = all.filter(l => l._key === key) as unknown as TimeLogItem[];
      return cached.length > 0 ? cached : null;
    } catch {
      return null;
    }
  },

  async setCachedTimeLogs(userId: number, logs: TimeLogItem[]): Promise<void> {
    try {
      const key = `u${userId}`;
      await clearStoreByPrefix(STORE_TIME_LOGS, key);
      const itemsWithKey = logs.map(l => ({ ...l, _key: key }));
      await putAll(STORE_TIME_LOGS, itemsWithKey);
    } catch (e) {
      console.warn('CacheService: Failed to cache time logs', e);
    }
  },

  // Courses
  async getCachedCourses(userId: number): Promise<CourseItem[] | null> {
    try {
      const key = `u${userId}`;
      const all = await getAll<CacheItem>(STORE_COURSES);
      const cached = all.filter(c => c._key === key) as unknown as CourseItem[];
      return cached.length > 0 ? cached : null;
    } catch {
      return null;
    }
  },

  async setCachedCourses(userId: number, courses: CourseItem[]): Promise<void> {
    try {
      const key = `u${userId}`;
      await clearStoreByPrefix(STORE_COURSES, key);
      const itemsWithKey = courses.map(c => ({ ...c, _key: key }));
      await putAll(STORE_COURSES, itemsWithKey);
    } catch (e) {
      console.warn('CacheService: Failed to cache courses', e);
    }
  },

  // Semester Start (Settings)
  async getCachedSemesterStart(userId: number): Promise<number | null> {
    try {
      const cacheKey = `u${userId}_semester`;
      const cached = await getOne<SettingsCacheItem>(STORE_SETTINGS, cacheKey);
      if (cached && cached.semester_start > 0) {
        return cached.semester_start;
      }
      return null;
    } catch {
      return null;
    }
  },

  async setCachedSemesterStart(userId: number, semesterStart: number): Promise<void> {
    try {
      const cacheKey = `u${userId}_semester`;
      await putOne(STORE_SETTINGS, {
        _key: cacheKey,
        semester_start: semesterStart,
        cached_at: Date.now(),
      });
    } catch (e) {
      console.warn('CacheService: Failed to cache semester start', e);
    }
  },

  // Screen Time
  async getCachedScreenTime(userId: number): Promise<ScreenTimeStat[] | null> {
    try {
      const key = `u${userId}`;
      const all = await getAll<CacheItem>(STORE_SCREEN_TIME);
      const cached = all.filter(c => c._key === key) as unknown as ScreenTimeStat[];
      return cached.length > 0 ? cached : null;
    } catch {
      return null;
    }
  },

  async setCachedScreenTime(userId: number, stats: ScreenTimeStat[]): Promise<void> {
    try {
      const key = `u${userId}`;
      await clearStoreByPrefix(STORE_SCREEN_TIME, key);
      const itemsWithKey = stats.map(s => ({ ...s, _key: key }));
      await putAll(STORE_SCREEN_TIME, itemsWithKey);
    } catch (e) {
      console.warn('CacheService: Failed to cache screen time', e);
    }
  },

  // Pomodoro Records
  async getCachedPomRecords(userId: number): Promise<PomodoroRecord[] | null> {
    try {
      const key = `u${userId}`;
      const all = await getAll<CacheItem>(STORE_POMODORO_RECORDS);
      const cached = all.filter(r => r._key === key) as unknown as PomodoroRecord[];
      return cached.length > 0 ? cached : null;
    } catch {
      return null;
    }
  },

  async setCachedPomRecords(userId: number, records: PomodoroRecord[]): Promise<void> {
    try {
      const key = `u${userId}`;
      await clearStoreByPrefix(STORE_POMODORO_RECORDS, key);
      const itemsWithKey = records.map(r => ({ ...r, _key: key }));
      await putAll(STORE_POMODORO_RECORDS, itemsWithKey);
    } catch (e) {
      console.warn('CacheService: Failed to cache pom records', e);
    }
  },

  // Pomodoro Tags
  async getCachedPomTags(userId: number): Promise<PomodoroTag[] | null> {
    try {
      const key = `u${userId}`;
      const all = await getAll<CacheItem>(STORE_POMODORO_TAGS);
      const cached = all.filter(t => t._key === key) as unknown as PomodoroTag[];
      return cached.length > 0 ? cached : null;
    } catch {
      return null;
    }
  },

  async setCachedPomTags(userId: number, tags: PomodoroTag[]): Promise<void> {
    try {
      const key = `u${userId}`;
      await clearStoreByPrefix(STORE_POMODORO_TAGS, key);
      const itemsWithKey = tags.map(t => ({ ...t, _key: key }));
      await putAll(STORE_POMODORO_TAGS, itemsWithKey);
    } catch (e) {
      console.warn('CacheService: Failed to cache pom tags', e);
    }
  },

  // Teams
  async getCachedTeams(userId: number): Promise<Team[] | null> {
    try {
      const key = `u${userId}_teams`;
      const cached = await getOne<Team[]>(STORE_TEAMS, key);
      return cached ?? null;
    } catch {
      return null;
    }
  },

  async setCachedTeams(userId: number, teams: Team[]): Promise<void> {
    try {
      const key = `u${userId}_teams`;
      await putOne(STORE_TEAMS, { _key: key, data: teams, cached_at: Date.now() });
    } catch (e) {
      console.warn('CacheService: Failed to cache teams', e);
    }
  },

  // Announcements
  async getCachedAnnouncements(userId: number): Promise<TeamAnnouncement[] | null> {
    try {
      const key = `u${userId}_announcements`;
      const cached = await getOne<{ _key: string; data: TeamAnnouncement[]; cached_at: number }>(STORE_ANNOUNCEMENTS, key);
      if (!cached) return null;
      // TTL: 5 minutes
      if (Date.now() - cached.cached_at > 300000) return null;
      return cached.data;
    } catch {
      return null;
    }
  },

  async setCachedAnnouncements(userId: number, announcements: TeamAnnouncement[]): Promise<void> {
    try {
      const key = `u${userId}_announcements`;
      await putOne(STORE_ANNOUNCEMENTS, { _key: key, data: announcements, cached_at: Date.now() });
    } catch (e) {
      console.warn('CacheService: Failed to cache announcements', e);
    }
  },

  // Sync Stats
  async getCachedSyncStats(userId: number): Promise<{ sync_count: number; tier: string; sync_limit: number } | null> {
    try {
      const key = `u${userId}_sync_stats`;
      const cached = await getOne<{ _key: string; data: { sync_count: number; tier: string; sync_limit: number }; cached_at: number }>(STORE_SETTINGS, key);
      if (!cached) return null;
      return cached.data;
    } catch {
      return null;
    }
  },

  async setCachedSyncStats(userId: number, stats: { sync_count: number; tier: string; sync_limit: number }): Promise<void> {
    try {
      const key = `u${userId}_sync_stats`;
      await putOne(STORE_SETTINGS, { _key: key, data: stats, cached_at: Date.now() });
    } catch (e) {
      console.warn('CacheService: Failed to cache sync stats', e);
    }
  },

  // 清除用户缓存
  async clearUserCache(userId: number): Promise<void> {
    try {
      const stores = [
        STORE_TODOS, STORE_GROUPS, STORE_COUNTDOWNS,
        STORE_PLAN_BLOCKS, STORE_TIME_LOGS,
        STORE_COURSES, STORE_SETTINGS, STORE_SCREEN_TIME,
        STORE_POMODORO_RECORDS, STORE_POMODORO_TAGS,
        STORE_TEAMS, STORE_ANNOUNCEMENTS,
      ];

      for (const storeName of stores) {
        await clearStoreByUser(storeName, userId);
      }
    } catch (e) {
      console.warn('CacheService: Failed to clear cache', e);
    }
  },

  // 比较数据是否有变化
  hasDataChanged<T extends { uuid: string; updated_at?: number; version?: number }>(
    oldData: T[],
    newData: T[]
  ): boolean {
    if (oldData.length !== newData.length) return true;

    const oldMap = new Map(oldData.map(item => [item.uuid, item]));
    for (const newItem of newData) {
      const oldItem = oldMap.get(newItem.uuid);
      if (!oldItem) return true;
      if (oldItem.version !== newItem.version) return true;
      if ((oldItem.updated_at || 0) !== (newItem.updated_at || 0)) return true;
    }

    return false;
  }
};
