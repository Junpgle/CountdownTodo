import { useState, useEffect, useMemo } from 'react';
import {
  ArrowLeft, Plus, Trash2, Clock, CheckCircle2, Check, X, RefreshCw, LogOut,
  CalendarDays, ChevronDown, ChevronRight, LayoutDashboard, PieChart as PieChartIcon,
  BookOpen, Monitor, Smartphone, MonitorSmartphone, Calendar, Filter,
  Flag, PlayCircle, StopCircle, User as UserIcon, MapPin, Hash, Sparkles, ArrowLeftCircle
} from 'lucide-react';
import { SyncEngine } from '../services/sync';
import { ApiService } from '../services/api';
import type { TodoItem, CountdownItem, User } from '../types';

// --------------------------------------------------------
// 常量与工具函数
// --------------------------------------------------------
const CURRENT_WEB_VERSION = "1.0.4"; // 当前网页版的硬编码版本号

const generateUUID = () => crypto.randomUUID ? crypto.randomUUID() : Math.random().toString(36).substring(2) + Date.now().toString(36);
const formatDt = (d: Date) => `${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')} ${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
const toDatetimeLocal = (ms: number) => {
  const d = new Date(ms);
  d.setMinutes(d.getMinutes() - d.getTimezoneOffset());
  return d.toISOString().slice(0, 16);
};
const formatHM = (totalSeconds: number) => {
  if (totalSeconds === 0) return "0分钟";
  const h = Math.floor(totalSeconds / 3600);
  const m = Math.floor((totalSeconds % 3600) / 60);
  if (h > 0) return `${h}小时 ${m}分钟`;
  return `${m}分钟`;
};
const simplifyDeviceName = (device: string) => {
  const d = device.toLowerCase();
  if (d.includes("phone")) return "手机";
  if (d.includes("tablet")) return "平板";
  if (d.includes("windows") || d.includes("pc") || d.includes("lapt")) return "电脑";
  return "未知设备";
};
const formatTimeNum = (timeInt: number) => {
  const h = Math.floor(timeInt / 100);
  const m = timeInt % 100;
  return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}`;
};

// --------------------------------------------------------
// 本地缓存工具 (同日有效，避免重复调用 API)
// --------------------------------------------------------
function readDayCache<T>(key: string): T | null {
  try {
    const raw = localStorage.getItem(key);
    if (!raw) return null;
    const { date, data } = JSON.parse(raw) as { date: string; data: T };
    if (date === new Date().toDateString()) return data;
  } catch { /* ignore */ }
  return null;
}

function writeDayCache<T>(key: string, data: T): void {
  try {
    localStorage.setItem(key, JSON.stringify({ date: new Date().toDateString(), data }));
  } catch { /* ignore */ }
}

// --------------------------------------------------------
// 内部类型定义
// --------------------------------------------------------
interface ScreenTimeStat {
  app_name: string;
  category: string;
  device_name: string;
  duration: number;
}

interface AppGroup {
  total: number;
  category: string;
  devices: Record<string, number>;
}

interface CourseItem {
  id: number;
  course_name: string;
  room_name: string;
  teacher_name: string;
  weekday: number;
  start_time: number;
  end_time: number;
  week_index: number;
}

type CalendarItemType = 'course' | 'todo' | 'countdown' | 'multi';

interface CalendarEntry {
  type: 'todo' | 'countdown';
  data: TodoItem | CountdownItem;
}

interface DetailItem {
  type: CalendarItemType;
  data: CourseItem | TodoItem | CountdownItem | CalendarEntry[];
}

// 番茄钟相关类型定义
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
function getLocalPomRecords(userId: number): PomodoroRecord[] {
  try {
    return JSON.parse(localStorage.getItem(`u${userId}_pom_records`) || '[]') as PomodoroRecord[];
  } catch { return []; }
}
function setLocalPomRecords(userId: number, records: PomodoroRecord[]) {
  localStorage.setItem(`u${userId}_pom_records`, JSON.stringify(records));
}
function getPomLastSyncTime(userId: number): number {
  return parseInt(localStorage.getItem(`u${userId}_pom_last_sync`) || '0', 10);
}
function setPomLastSyncTime(userId: number, t: number) {
  localStorage.setItem(`u${userId}_pom_last_sync`, String(t));
}

// 追加 / 更新单条记录到本地，并标记为 dirty（updated_at > lastSync）
function upsertLocalPomRecord(userId: number, rec: PomodoroRecord) {
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
async function syncPomodoroRecords(userId: number): Promise<void> {
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
// 屏幕时间组件
// --------------------------------------------------------
const ScreenTimeView = ({ userId }: { userId: number }) => {
  const cacheKey = `u${userId}_screen_time_${new Date().toDateString()}`;
  const cached = readDayCache<ScreenTimeStat[]>(cacheKey);

  const [stats, setStats] = useState<ScreenTimeStat[]>(cached ?? []);
  const [loading, setLoading] = useState(!cached); // 有缓存则不显示 loading
  const [filter, setFilter] = useState<'all' | 'pc' | 'mobile'>('all');
  const [selectedDate] = useState(new Date());

  useEffect(() => {
    // 有缓存直接用，不再请求 API
    if (cached) return;
    fetchStats();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const fetchStats = async () => {
    setLoading(true);
    try {
      const dateStr = selectedDate.toISOString().split('T')[0];
      const data = await ApiService.request(`/api/screen_time?user_id=${userId}&date=${dateStr}`, { method: 'GET' });
      const result = (Array.isArray(data) ? data : []) as ScreenTimeStat[];
      setStats(result);
      writeDayCache(cacheKey, result);
    } catch (e) {
      console.error("获取屏幕时间失败", e);
    } finally {
      setLoading(false);
    }
  };

  const getFilteredStats = () => {
    return stats.filter(item => {
      const dName = (item.device_name || "").toLowerCase();
      if (filter === 'all') return true;
      if (filter === 'pc') return dName.includes("windows") || dName.includes("pc") || dName.includes("lapt");
      if (filter === 'mobile') return dName.includes("phone") || dName.includes("tablet");
      return true;
    });
  };

  const filteredStats = getFilteredStats();
  const totalDuration = filteredStats.reduce((sum, item) => sum + (item.duration || 0), 0);

  const appGroups = filteredStats.reduce((acc, item) => {
    const appName = item.app_name || '未知应用';
    if (!acc[appName]) acc[appName] = { total: 0, category: item.category || '未分类', devices: {} };
    acc[appName].total += item.duration;
    acc[appName].devices[item.device_name] = (acc[appName].devices[item.device_name] || 0) + item.duration;
    return acc;
  }, {} as Record<string, AppGroup>);

  const topApps = Object.entries(appGroups)
      .map(([name, data]: [string, AppGroup]) => ({
        name,
        total: data.total,
        category: data.category,
        devices: data.devices
      }))
      .sort((a, b) => b.total - a.total);

  return (
      <div className="flex flex-col gap-6 animate-in fade-in duration-300 h-full flex-1 min-h-0">
        <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4 bg-white p-6 rounded-3xl shadow-sm border border-slate-100 shrink-0">
          <div>
            <h2 className="text-2xl font-black text-slate-800 flex items-center gap-2">
              <PieChartIcon className="w-6 h-6 text-indigo-500" />
              屏幕时间看板
            </h2>
            <p className="text-slate-500 text-sm mt-1">跨设备使用时长分析</p>
          </div>
          <div className="flex items-center gap-2 shrink-0">
            <button
                onClick={fetchStats}
                disabled={loading}
                className="p-2 bg-slate-100 hover:bg-slate-200 text-slate-500 rounded-xl transition disabled:opacity-50"
                title="刷新数据"
            >
              <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} />
            </button>
            <div className="flex items-center gap-2 bg-slate-100 p-1.5 rounded-xl">
              <button onClick={() => setFilter('all')} className={`px-4 py-2 rounded-lg text-sm font-bold transition ${filter === 'all' ? 'bg-white shadow-sm text-indigo-600' : 'text-slate-500 hover:text-slate-700'}`}>全部</button>
              <button onClick={() => setFilter('pc')} className={`px-4 py-2 rounded-lg text-sm font-bold transition flex items-center gap-1 ${filter === 'pc' ? 'bg-white shadow-sm text-blue-600' : 'text-slate-500 hover:text-slate-700'}`}><Monitor className="w-4 h-4" /> 电脑</button>
              <button onClick={() => setFilter('mobile')} className={`px-4 py-2 rounded-lg text-sm font-bold transition flex items-center gap-1 ${filter === 'mobile' ? 'bg-white shadow-sm text-purple-600' : 'text-slate-500 hover:text-slate-700'}`}><Smartphone className="w-4 h-4" /> 移动端</button>
            </div>
          </div>
        </div>

        {loading ? (
            <div className="flex-1 flex items-center justify-center min-h-0">
              <RefreshCw className="w-8 h-8 text-indigo-300 animate-spin" />
            </div>
        ) : (
            <div className="grid grid-cols-1 lg:grid-cols-3 gap-6 flex-1 min-h-0">
              <div className="lg:col-span-1 bg-gradient-to-br from-indigo-500 to-purple-600 rounded-3xl p-8 text-white shadow-lg relative overflow-hidden flex flex-col justify-center min-h-[200px] lg:min-h-0 shrink-0">
                <div className="absolute -right-10 -top-10 text-white/10">
                  <MonitorSmartphone className="w-48 h-48" />
                </div>
                <div className="relative z-10">
                  <p className="text-indigo-100 font-bold mb-2 text-lg">今日总计使用</p>
                  <div className="text-5xl font-black mb-4 tracking-tight">
                    {formatHM(totalDuration).replace('小时', 'h').replace('分钟', 'm')}
                  </div>
                  <p className="text-sm text-indigo-100/80 bg-black/20 inline-block px-3 py-1 rounded-full">
                    {selectedDate.toLocaleDateString()} 数据
                  </p>
                </div>
              </div>
              <div className="lg:col-span-2 bg-white rounded-3xl shadow-sm border border-slate-100 overflow-hidden flex flex-col min-h-[400px] lg:min-h-0">
                <div className="p-6 border-b border-slate-100 bg-slate-50/50 flex justify-between items-center shrink-0">
                  <h3 className="font-bold text-lg text-slate-800">最常使用应用</h3>
                  <span className="text-sm font-bold text-slate-400">{topApps.length} 个应用</span>
                </div>
                <div className="p-2 flex-1 overflow-y-auto min-h-0">
                  {topApps.length === 0 ? (
                      <div className="h-full flex flex-col items-center justify-center py-20 text-slate-400">
                        <PieChartIcon className="w-12 h-12 mb-4 opacity-20" />
                        <p>暂无使用数据</p>
                      </div>
                  ) : (
                      <div className="space-y-1">
                        {topApps.map((app, idx) => (
                            <div key={app.name} className="flex items-center gap-4 p-4 hover:bg-slate-50 rounded-2xl transition group">
                              <div className="w-12 h-12 rounded-xl bg-indigo-50 text-indigo-600 flex items-center justify-center font-black text-xl shrink-0">{idx + 1}</div>
                              <div className="flex-1 min-w-0">
                                <p className="font-bold text-slate-800 truncate text-base">{app.name}</p>
                                <div className="flex gap-2 mt-1">
                                  {Object.entries(app.devices).map(([dev]) => (
                                      <span key={dev} className="text-[11px] font-medium bg-slate-100 text-slate-500 px-2 py-0.5 rounded-md flex items-center gap-1">{simplifyDeviceName(dev)}</span>
                                  ))}
                                </div>
                              </div>
                              <div className="text-right shrink-0">
                                <p className="font-black text-lg text-slate-700">{formatHM(app.total).replace('分钟','m').replace('小时','h')}</p>
                                <p className="text-[11px] text-slate-400">{app.category}</p>
                              </div>
                            </div>
                        ))}
                      </div>
                  )}
                </div>
              </div>
            </div>
        )}
      </div>
  );
};

// --------------------------------------------------------
// 课表/周视图组件 (内嵌到首页左侧使用)
// --------------------------------------------------------
const CourseView = ({ userId, todos, countdowns }: { userId: number, todos: TodoItem[], countdowns: CountdownItem[] }) => {
  const courseCacheKey = `u${userId}_courses`;
  const cachedCourses = readDayCache<CourseItem[]>(courseCacheKey);

  const [courses, setCourses] = useState<CourseItem[]>(cachedCourses ?? []);
  const [loading, setLoading] = useState(!cachedCourses);
  const [currentWeek, setCurrentWeek] = useState(1);
  const [semesterMonday, setSemesterMonday] = useState(new Date());

  // 0: 混合查看, 1: 只看课表, 2: 只看待办
  const [viewMode, setViewMode] = useState<0 | 1 | 2>(0);
  const [showViewMenu, setShowViewMenu] = useState(false);

  // 详情弹窗状态
  const [detailItem, setDetailItem] = useState<DetailItem | null>(null);
  const [multiParent, setMultiParent] = useState<DetailItem | null>(null);

  const startHour = 8;
  const endHour = 22;
  const totalMins = (endHour - startHour) * 60;

  // 根据课程列表计算当前周和学期起始周一
  const applyCourseData = (data: CourseItem[]) => {
    let activeWeek = 1;
    if (data.length > 0) {
      const minWeek = Math.min(...data.map((c: CourseItem) => c.week_index));
      activeWeek = minWeek > 0 ? minWeek : 1;
    }
    setCurrentWeek(activeWeek);
    const todayDay = new Date().getDay() || 7;
    const thisMonday = new Date();
    thisMonday.setDate(new Date().getDate() - todayDay + 1);
    thisMonday.setHours(0, 0, 0, 0);
    const semMonday = new Date(thisMonday);
    semMonday.setDate(thisMonday.getDate() - (activeWeek - 1) * 7);
    setSemesterMonday(semMonday);
  };

  useEffect(() => {
    if (cachedCourses) {
      // 缓存命中：直接计算周信息，不请求 API
      applyCourseData(cachedCourses);
      return;
    }
    fetchCourses();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const fetchCourses = async () => {
    setLoading(true);
    try {
      const data = await ApiService.request(`/api/courses?user_id=${userId}`, { method: 'GET' });
      const result = (Array.isArray(data) ? data : []) as CourseItem[];
      setCourses(result);
      writeDayCache(courseCacheKey, result);
      applyCourseData(result);
    } catch (e) {
      console.error("获取课表失败", e);
    } finally {
      setLoading(false);
    }
  };

  const weekDates = useMemo(() => {
    return Array.from({length: 7}).map((_, i) => {
      const d = new Date(semesterMonday);
      d.setDate(semesterMonday.getDate() + (currentWeek - 1) * 7 + i);
      return d;
    });
  }, [semesterMonday, currentWeek]);

  const { allDayItems, intraDayItems } = useMemo(() => {
    const all = { 1:[], 2:[], 3:[], 4:[], 5:[], 6:[], 7:[] } as Record<number, CalendarEntry[]>;
    const intra = { 1:[], 2:[], 3:[], 4:[], 5:[], 6:[], 7:[] } as Record<number, CalendarEntry[]>;

    todos.forEach(t => {
      if (t.is_deleted || t.is_completed) return;
      const start = new Date(t.created_date ?? t.created_at);
      const end = t.due_date ? new Date(t.due_date) : new Date(start.getFullYear(), start.getMonth(), start.getDate(), 23, 59, 59);

      const isAllDay = (t.due_date && start.getHours() === 0 && start.getMinutes() === 0 && end.getHours() === 23 && end.getMinutes() === 59) ||
          (start.toDateString() !== end.toDateString());

      for (let i = 0; i < 7; i++) {
        const dayStart = new Date(weekDates[i]);
        dayStart.setHours(0,0,0,0);
        const dayEnd = new Date(weekDates[i]);
        dayEnd.setHours(23,59,59,999);

        if (start <= dayEnd && end >= dayStart) {
          if (isAllDay) all[i+1].push({ type: 'todo', data: t });
          else intra[i+1].push({ type: 'todo', data: t });
        }
      }
    });

    countdowns.forEach(c => {
      if (c.is_deleted) return;
      const target = new Date(c.target_time);
      for(let i=0; i<7; i++) {
        if (target.getFullYear() === weekDates[i].getFullYear() && target.getMonth() === weekDates[i].getMonth() && target.getDate() === weekDates[i].getDate()) {
          all[i+1].push({ type: 'countdown', data: c });
        }
      }
    });

    return { allDayItems: all, intraDayItems: intra };
  }, [todos, countdowns, weekDates]);

  const weekCourses = courses.filter(c => c.week_index === currentWeek);
  const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  const getTopPercent = (h: number, m: number) => {
    const hm = Math.max(startHour * 60, Math.min(endHour * 60, h * 60 + m));
    return ((hm - startHour * 60) / totalMins) * 100;
  };
  const getHeightPercent = (sh: number, sm: number, eh: number, em: number) => {
    const top = getTopPercent(sh, sm);
    const bottom = getTopPercent(eh, em);
    return Math.max(bottom - top, 2.5);
  };
  const getCourseColor = (name: string) => {
    const colors = ['#60a5fa', '#f472b6', '#34d399', '#fbbf24', '#a78bfa', '#818cf8', '#fb923c'];
    let hash = 0;
    for (let i = 0; i < name.length; i++) hash = name.charCodeAt(i) + ((hash << 5) - hash);
    return colors[Math.abs(hash) % colors.length];
  };

  const getDaysLeftLocal = (targetTime: number) => {
    const d = new Date(targetTime);
    d.setHours(0,0,0,0);
    const today = new Date();
    today.setHours(0,0,0,0);
    return Math.floor((d.getTime() - today.getTime()) / 86400000);
  };

  const hasAnyAllDay = Object.values(allDayItems).some(arr => arr.length > 0);

  // --- 详情弹窗渲染 ---
  const renderDetailModal = () => {
    if (!detailItem) return null;
    const { type, data } = detailItem;

    return (
        <div className="fixed inset-0 z-[60] bg-slate-900/40 backdrop-blur-sm flex items-center justify-center p-4 animate-in fade-in duration-200">
          <div className="bg-white w-full max-w-md rounded-[2.5rem] p-8 shadow-2xl animate-in zoom-in-95 duration-200 flex flex-col max-h-[90dvh]">
            <div className="flex justify-between items-start mb-6 shrink-0">
              <div className="flex items-center gap-3">
                {multiParent && (
                    <button onClick={() => { setDetailItem(multiParent); setMultiParent(null); }} className="p-2 text-slate-400 hover:text-slate-700 bg-slate-100 hover:bg-slate-200 rounded-full transition mr-1">
                      <ArrowLeftCircle className="w-5 h-5" />
                    </button>
                )}
                <div className={`p-2.5 rounded-2xl ${type === 'course' ? 'bg-blue-100 text-blue-600' : type === 'todo' ? 'bg-emerald-100 text-emerald-600' : type === 'multi' ? 'bg-indigo-100 text-indigo-600' : 'bg-amber-100 text-amber-600'}`}>
                  {type === 'course' ? <BookOpen className="w-6 h-6" /> : type === 'todo' ? <CheckCircle2 className="w-6 h-6" /> : type === 'multi' ? <CalendarDays className="w-6 h-6" /> : <Clock className="w-6 h-6" />}
                </div>
                <div>
                  <h4 className="font-black text-xl text-slate-800 tracking-tight">
                    {type === 'course' ? '课程详情' : type === 'todo' ? '待办详情' : type === 'multi' ? '全天事项聚合' : '重要倒计时'}
                  </h4>
                </div>
              </div>
              <button onClick={() => { setDetailItem(null); setMultiParent(null); }} className="p-2 bg-slate-100 rounded-full text-slate-500 hover:bg-slate-200 transition">
                <X className="w-5 h-5" />
              </button>
            </div>

            <div className="space-y-5 overflow-y-auto pr-2 flex-1 min-h-0">
              {type === 'course' && (() => {
                const course = data as CourseItem;
                return (
                    <>
                      <h3 className="text-2xl font-black text-slate-800 leading-tight mb-2">{course.course_name}</h3>
                      <div className="space-y-3 bg-slate-50 p-5 rounded-2xl border border-slate-100">
                        <div className="flex items-center gap-3 text-slate-600">
                          <MapPin className="w-5 h-5 text-blue-400" />
                          <span className="font-bold">{course.room_name || '未安排教室'}</span>
                        </div>
                        <div className="flex items-center gap-3 text-slate-600">
                          <UserIcon className="w-5 h-5 text-blue-400" />
                          <span className="font-bold">{course.teacher_name || '未知讲师'}</span>
                        </div>
                        <div className="flex items-center gap-3 text-slate-600">
                          <Clock className="w-5 h-5 text-blue-400" />
                          <span className="font-bold">
                        周{course.weekday} {formatTimeNum(course.start_time)} - {formatTimeNum(course.end_time)}
                      </span>
                        </div>
                        <div className="flex items-center gap-3 text-slate-600">
                          <Hash className="w-5 h-5 text-blue-400" />
                          <span className="font-bold">第 {course.week_index} 周</span>
                        </div>
                      </div>
                    </>
                );
              })()}

              {type === 'todo' && (() => {
                const todo = data as TodoItem;
                return (
                    <>
                      <h3 className="text-2xl font-black text-slate-800 leading-tight mb-2">{todo.content}</h3>
                      <div className="space-y-3 bg-slate-50 p-5 rounded-2xl border border-slate-100">
                        <div className="flex items-center gap-3 text-slate-600">
                          <Flag className="w-5 h-5 text-emerald-500" />
                          <span className="font-bold">{todo.is_completed ? '已完成' : '进行中'}</span>
                        </div>
                        <div className="flex items-center gap-3 text-slate-600">
                          <PlayCircle className="w-5 h-5 text-emerald-500" />
                          <span className="font-bold text-sm">开始: {formatDt(new Date(todo.created_date ?? todo.created_at))}</span>
                        </div>
                        <div className="flex items-center gap-3 text-slate-600">
                          <StopCircle className="w-5 h-5 text-emerald-500" />
                          <span className="font-bold text-sm">截止: {todo.due_date ? formatDt(new Date(todo.due_date)) : '无限制'}</span>
                        </div>
                        <div className="flex items-center gap-3 text-slate-600">
                          <RefreshCw className="w-5 h-5 text-emerald-500" />
                          <span className="font-bold text-sm">最近同步: {formatDt(new Date(todo.updated_at))}</span>
                        </div>
                        {todo.remark && (
                            <div className="flex items-start gap-3 text-slate-600 pt-1 border-t border-slate-200 mt-1">
                              <BookOpen className="w-5 h-5 text-emerald-500 shrink-0 mt-0.5" />
                              <span className="text-sm font-medium text-slate-500 italic leading-relaxed">{todo.remark}</span>
                            </div>
                        )}
                      </div>
                    </>
                );
              })()}

              {type === 'countdown' && (() => {
                const cd = data as CountdownItem;
                const daysLeft = getDaysLeftLocal(cd.target_time);
                const isPast = daysLeft < 0;
                return (
                    <>
                      <h3 className="text-2xl font-black text-slate-800 leading-tight mb-2">{cd.title}</h3>
                      <div className="space-y-3 bg-slate-50 p-5 rounded-2xl border border-slate-100">
                        <div className="flex items-center justify-between text-slate-600">
                          <div className="flex items-center gap-3">
                            <Clock className="w-5 h-5 text-amber-500" />
                            <span className="font-bold">目标日: {new Date(cd.target_time).toLocaleDateString()}</span>
                          </div>
                        </div>
                        <div className="flex items-center gap-3 text-slate-600 mt-4">
                          <Sparkles className="w-5 h-5 text-amber-500" />
                          <span className="font-bold">状态: </span>
                          <span className={`text-2xl font-black ${isPast ? 'text-slate-400' : 'text-amber-500'}`}>
                        {isPast ? `已过 ${Math.abs(daysLeft)} 天` : `还剩 ${daysLeft} 天`}
                      </span>
                        </div>
                      </div>
                    </>
                );
              })()}

              {type === 'multi' && (
                  <div className="space-y-2">
                    <p className="text-sm font-bold text-slate-500 mb-3">此日包含多项全天任务，请选择查看：</p>
                    {(data as CalendarEntry[]).map((item: CalendarEntry, idx: number) => (
                        <button
                            key={idx}
                            onClick={() => {
                              setMultiParent(detailItem);
                              setDetailItem(item as DetailItem);
                            }}
                            className="w-full text-left bg-slate-50 hover:bg-slate-100 p-4 rounded-2xl border border-slate-200 transition flex items-center gap-3 group"
                        >
                          {item.type === 'todo' ? <CheckCircle2 className="w-5 h-5 text-emerald-500" /> : <Clock className="w-5 h-5 text-amber-500" />}
                          <span className="font-bold text-slate-700 flex-1 truncate group-hover:text-indigo-600 transition">
                      {item.type === 'todo' ? (item.data as TodoItem).content : (item.data as CountdownItem).title}
                    </span>
                          <ChevronRight className="w-4 h-4 text-slate-400 group-hover:text-indigo-500" />
                        </button>
                    ))}
                  </div>
              )}
            </div>

            <button onClick={() => { setDetailItem(null); setMultiParent(null); }} className="mt-6 w-full bg-slate-900 text-white font-bold py-4 rounded-2xl hover:bg-slate-800 transition shadow-lg shadow-slate-900/20 active:scale-[0.98] shrink-0">
              关闭
            </button>
          </div>
        </div>
    );
  };

  return (
      <div className="bg-white rounded-3xl shadow-sm border border-slate-100 overflow-hidden flex flex-col h-full w-full relative">
        {/* 课表控制栏 */}
        <div className="px-4 sm:px-6 py-3 sm:py-4 border-b border-slate-100 flex justify-between items-center bg-slate-50/50 shrink-0">
          <div>
            <h2 className="text-lg sm:text-xl font-black text-slate-800 flex items-center gap-2">
              <Calendar className="w-5 h-5 text-blue-500" />
              周视图
            </h2>
          </div>
          <div className="flex items-center gap-2 sm:gap-3">
            <div className="relative">
              <button onClick={() => setShowViewMenu(!showViewMenu)} className="flex items-center gap-1 text-xs sm:text-sm font-bold text-slate-600 bg-white border border-slate-200 px-2 sm:px-3 py-1.5 sm:py-2 rounded-xl hover:bg-slate-50 transition">
                <Filter className="w-3.5 h-3.5 sm:w-4 sm:h-4 text-slate-400" />
                <span className="hidden sm:inline">{viewMode === 0 ? '混合查看' : (viewMode === 1 ? '只看课表' : '只看待办')}</span>
                <ChevronDown className="w-3.5 h-3.5 sm:w-4 sm:h-4" />
              </button>
              {showViewMenu && (
                  <div className="absolute top-full right-0 mt-2 w-32 bg-white rounded-xl shadow-xl border border-slate-100 py-1 z-50 overflow-hidden">
                    {[0,1,2].map((v) => (
                        <button key={v} onClick={() => { setViewMode(v as 0 | 1 | 2); setShowViewMenu(false); }} className={`w-full text-left px-4 py-2 text-sm font-bold hover:bg-slate-50 transition ${viewMode === v ? 'text-blue-600' : 'text-slate-600'}`}>
                          {v === 0 ? '混合查看' : (v === 1 ? '只看课表' : '只看待办')}
                        </button>
                    ))}
                  </div>
              )}
            </div>
            <div className="flex items-center bg-white p-1 rounded-xl border border-slate-200 shadow-sm shrink-0">
              <button onClick={() => setCurrentWeek(Math.max(1, currentWeek - 1))} className="p-1 sm:p-1.5 hover:bg-slate-100 rounded-lg text-slate-600 transition"><ChevronDown className="w-3.5 h-3.5 sm:w-4 sm:h-4 rotate-90" /></button>
              <span className="font-bold text-slate-700 w-12 sm:w-16 text-center text-xs sm:text-sm">第 {currentWeek} 周</span>
              <button onClick={() => setCurrentWeek(currentWeek + 1)} className="p-1 sm:p-1.5 hover:bg-slate-100 rounded-lg text-slate-600 transition"><ChevronRight className="w-3.5 h-3.5 sm:w-4 sm:h-4" /></button>
            </div>
          </div>
        </div>

        {loading ? (
            <div className="flex-1 flex items-center justify-center min-h-0"><RefreshCw className="w-8 h-8 text-blue-300 animate-spin" /></div>
        ) : (
            <div className="flex-1 flex flex-col min-h-0 relative overflow-hidden">
              {/* 星期与日期头 — 左侧留出与时间轴等宽的空白 */}
              <div className="flex shrink-0 border-b border-slate-50 bg-white z-10">
                {/* 与时间轴等宽的占位 */}
                <div className="w-10 sm:w-12 shrink-0" />
                {/* 7列星期头，flex-1 均分，与下方网格列对齐 */}
                <div className="flex flex-1 min-w-0 py-1.5 sm:py-2 pr-2">
                  {weekdays.map((day, i) => {
                    const d = weekDates[i];
                    const isToday = d.toDateString() === new Date().toDateString();
                    return (
                        <div key={day} className="flex-1 flex flex-col items-center min-w-0">
                          <span className={`text-[9px] sm:text-[11px] font-bold ${isToday ? 'text-blue-600' : 'text-slate-500'}`}>{day}</span>
                          <span className={`text-[8px] sm:text-[10px] font-medium ${isToday ? 'text-blue-500' : 'text-slate-400'}`}>{d.getMonth()+1}/{d.getDate()}</span>
                        </div>
                    );
                  })}
                </div>
              </div>

              {/* 全天事件吸顶区 */}
              {hasAnyAllDay && viewMode !== 1 && (
                  <div className="flex shrink-0 border-b border-slate-50 bg-white z-10">
                    <div className="w-10 sm:w-12 shrink-0" />
                    <div className="flex flex-1 min-w-0 pt-1 pb-1.5 pr-2">
                      {Array.from({length: 7}).map((_, i) => {
                        const items = allDayItems[i+1];
                        if (!items || items.length === 0) return <div key={i} className="flex-1 min-w-0" />;
                        const firstData = items[0].data;
                        const text = items.length === 1
                            ? (items[0].type === 'todo' ? (firstData as TodoItem).content : (firstData as CountdownItem).title)
                            : `${items.length}项全天`;
                        const isAllDone = items.every(x => x.type === 'todo' && (x.data as TodoItem).is_completed);
                        return (
                            <div key={i} className="flex-1 min-w-0 px-px">
                              <button
                                  onClick={() => {
                                    if (items.length === 1) {
                                      setDetailItem(items[0] as DetailItem);
                                    } else {
                                      setDetailItem({ type: 'multi', data: items });
                                    }
                                  }}
                                  className={`w-full h-8 sm:h-9 text-[8px] sm:text-[10px] text-white rounded shadow-sm transition hover:opacity-80 px-0.5 py-0.5 flex items-center justify-center overflow-hidden ${isAllDone ? 'bg-green-500/80 line-through' : 'bg-amber-500/90'}`}
                              >
                                <span className="line-clamp-2 leading-tight break-all text-center">{text}</span>
                              </button>
                            </div>
                        );
                      })}
                    </div>
                  </div>
              )}

              {/* 时间轴 + 网格主体 */}
              <div className="flex flex-1 min-h-0 mt-2 mb-2 pr-2">
                {/* 时间标签列 */}
                <div className="w-10 sm:w-12 shrink-0 relative">
                  {Array.from({ length: endHour - startHour + 1 }).map((_, i) => (
                      <div key={`lbl-${i}`} className="absolute w-full" style={{ top: `${(i * 60 / totalMins) * 100}%` }}>
                  <span className="block text-[9px] sm:text-[10px] font-bold text-slate-400 text-right pr-1.5 -translate-y-1/2">
                    {startHour + i}:00
                  </span>
                      </div>
                  ))}
                </div>

                {/* 网格主体 — 与星期头的 flex-1 区域完全对齐 */}
                <div className="flex-1 relative bg-slate-50/30 border border-slate-100 rounded-xl overflow-hidden shadow-inner min-h-[400px] lg:min-h-0">
                  {/* 横向时间线 */}
                  {Array.from({ length: endHour - startHour + 1 }).map((_, i) => (
                      <div key={`grid-line-${i}`} className="absolute w-full border-t border-slate-200/60" style={{ top: `${(i * 60 / totalMins) * 100}%` }} />
                  ))}

                  {/* 纵向列分割线 */}
                  {Array.from({ length: 8 }).map((_, i) => (
                      <div key={`grid-col-${i}`} className="absolute h-full border-l border-slate-200/60" style={{ left: `${i * (100/7)}%` }} />
                  ))}

                  {/* 渲染课程 */}
                  {viewMode !== 2 && weekCourses.map(course => {
                    const sh = Math.floor(course.start_time / 100);
                    const sm = course.start_time % 100;
                    const eh = Math.floor(course.end_time / 100);
                    const em = course.end_time % 100;
                    const top = getTopPercent(sh, sm);
                    const height = getHeightPercent(sh, sm, eh, em);
                    const left = (course.weekday - 1) * (100 / 7);
                    return (
                        <div key={`c-${course.id}`} className="absolute" style={{ top: `${top}%`, height: `${height}%`, left: `${left}%`, width: `${100/7}%`, padding: '1px' }}>
                          <button
                              onClick={() => setDetailItem({ type: 'course', data: course })}
                              className="w-full h-full text-left rounded shadow-sm border border-white/20 p-0.5 sm:p-1 flex flex-col overflow-hidden text-white transition-transform hover:scale-[1.02] hover:z-20 hover:shadow-md"
                              style={{ backgroundColor: getCourseColor(course.course_name) }}
                          >
                            <span className="font-bold text-[8px] sm:text-[10px] leading-tight line-clamp-3">{course.course_name}</span>
                            {height > 5 && <span className="text-[7px] sm:text-[9px] mt-auto opacity-90 line-clamp-1">{course.room_name}</span>}
                          </button>
                        </div>
                    );
                  })}

                  {/* 渲染日内待办 */}
                  {viewMode !== 1 && Object.entries(intraDayItems).flatMap(([dayStr, items]) => {
                    const weekday = parseInt(dayStr);
                    const collisionMap: Record<number, number> = {};
                    return items.map(item => {
                      const t = item.data as TodoItem;
                      const start = new Date(t.created_date ?? t.created_at);
                      const end = t.due_date ? new Date(t.due_date) : new Date(start.getFullYear(), start.getMonth(), start.getDate(), 23, 59, 59);
                      const top = getTopPercent(start.getHours(), start.getMinutes());
                      const height = getHeightPercent(start.getHours(), start.getMinutes(), end.getHours(), end.getMinutes());
                      const bucket = Math.floor(top / 5);
                      const stackIndex = collisionMap[bucket] || 0;
                      collisionMap[bucket] = stackIndex + 1;
                      const baseLeft = (weekday - 1) * (100 / 7);
                      return (
                          <div key={`t-${t.uuid}`} className="absolute z-10" style={{ top: `${top}%`, height: `${height}%`, left: `calc(${baseLeft}% + ${stackIndex * 3}px)`, width: `calc(${100/7}% - ${stackIndex * 3}px)`, padding: '1px' }}>
                            <button
                                onClick={() => setDetailItem(item as DetailItem)}
                                className={`w-full h-full text-left rounded shadow-sm border border-white p-0.5 sm:p-1 flex flex-col overflow-hidden transition-transform hover:scale-[1.05] hover:z-30 hover:shadow-md ${t.is_completed ? 'bg-green-500/60' : 'bg-amber-500/90'}`}
                            >
                              <div className="flex items-start gap-0.5">
                                <CheckCircle2 className="w-2.5 h-2.5 sm:w-3 sm:h-3 text-white shrink-0 mt-px" />
                                <span className={`text-[7px] sm:text-[9px] font-bold text-white leading-tight break-all ${t.is_completed ? 'line-through opacity-80' : ''}`}>{t.content}</span>
                              </div>
                            </button>
                          </div>
                      );
                    });
                  })}

                  {/* 当前时间红线 */}
                  {(() => {
                    const now = new Date();
                    const h = now.getHours();
                    const m = now.getMinutes();
                    if (h >= startHour && h < endHour) {
                      const currentDay = now.getDay() || 7;
                      const todayIsRendered = weekDates.some(d => d.toDateString() === now.toDateString());
                      if (todayIsRendered) {
                        const top = getTopPercent(h, m);
                        const left = (currentDay - 1) * (100 / 7);
                        return (
                            <>
                              <div className="absolute w-full border-t-[1.5px] border-red-400 z-30 pointer-events-none" style={{ top: `${top}%` }} />
                              <div className="absolute w-2 h-2 bg-red-500 rounded-full z-30 pointer-events-none" style={{ top: `calc(${top}% - 3px)`, left: `calc(${left}% - 2px)` }} />
                            </>
                        );
                      }
                    }
                    return null;
                  })()}
                </div>
              </div>

              {/* 渲染详情弹窗 */}
              {renderDetailModal()}
            </div>
        )}
      </div>
  );
};


// --------------------------------------------------------
// 番茄专注统计组件
// --------------------------------------------------------
const PomodoroStatsView = ({ userId, todos }: { userId: number, todos: TodoItem[] }) => {
  const [records, setRecords] = useState<PomodoroRecord[]>(() =>
    getLocalPomRecords(userId).filter(r => !r.is_deleted)
  );
  const [tags, setTags] = useState<PomodoroTag[]>([]);
  const [loading, setLoading] = useState(false);

  // 筛选状态
  const [filterYear, setFilterYear] = useState<number | 'all'>(new Date().getFullYear());
  const [filterMonth, setFilterMonth] = useState<number | 'all'>(new Date().getMonth() + 1);
  const [filterDay, setFilterDay] = useState<number | 'all'>('all');
  const [filterTag, setFilterTag] = useState<string | 'all'>('all');

  useEffect(() => {
    fetchData();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [userId]);

  const fetchData = async () => {
    setLoading(true);
    try {
      // Delta sync records (uploads dirty + pulls server changes)
      await syncPomodoroRecords(userId);
      setRecords(getLocalPomRecords(userId).filter(r => !r.is_deleted));

      // Tags are small, always pull fresh
      const tagsData = await ApiService.request('/api/pomodoro/tags', { method: 'GET' });
      setTags((Array.isArray(tagsData) ? tagsData : []) as PomodoroTag[]);
    } catch (e) {
      console.error("获取专注数据失败", e);
    } finally {
      setLoading(false);
    }
  };

  // 筛选逻辑 (已接入基于 tag_uuids 的真实筛选)
  const filteredRecords = useMemo(() => {
    return records.filter(record => {
      const d = new Date(record.start_time);
      const matchYear = filterYear === 'all' || d.getFullYear() === filterYear;
      const matchMonth = filterMonth === 'all' || (d.getMonth() + 1) === filterMonth;
      const matchDay = filterDay === 'all' || d.getDate() === filterDay;

      // 检查当前记录的标签数组中是否包含选中的标签
      const matchTag = filterTag === 'all' || (record.tag_uuids && record.tag_uuids.includes(filterTag));

      return matchYear && matchMonth && matchDay && matchTag;
    });
  }, [records, filterYear, filterMonth, filterDay, filterTag]);

  // 统计计算
  const totalFocusSeconds = filteredRecords.reduce((sum, r) => sum + (r.actual_duration || r.planned_duration || 0), 0);
  const completedCount = filteredRecords.filter(r => r.status === 'completed').length;

  return (
      <div className="flex flex-col gap-6 animate-in fade-in duration-300 h-full flex-1 min-h-0">
        {/* 顶部标题与控制器 */}
        <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4 bg-white p-6 rounded-3xl shadow-sm border border-slate-100 shrink-0">
          <div>
            <h2 className="text-2xl font-black text-slate-800 flex items-center gap-2">
              <Clock className="w-6 h-6 text-amber-500" />
              专注统计
            </h2>
            <p className="text-slate-500 text-sm mt-1">回顾你的专注时光</p>
          </div>

          {/* 筛选器组 */}
          <div className="flex flex-wrap items-center gap-2 bg-slate-50 p-2 rounded-2xl border border-slate-100">
            <select
                value={filterYear}
                onChange={e => setFilterYear(e.target.value === 'all' ? 'all' : Number(e.target.value))}
                className="bg-white border border-slate-200 text-sm font-bold text-slate-600 rounded-xl px-3 py-1.5 focus:outline-none"
            >
              <option value="all">全年</option>
              {[...Array(3)].map((_, i) => {
                const y = new Date().getFullYear() - i;
                return <option key={y} value={y}>{y}年</option>;
              })}
            </select>

            <select
                value={filterMonth}
                onChange={e => setFilterMonth(e.target.value === 'all' ? 'all' : Number(e.target.value))}
                className="bg-white border border-slate-200 text-sm font-bold text-slate-600 rounded-xl px-3 py-1.5 focus:outline-none"
            >
              <option value="all">全月</option>
              {[...Array(12)].map((_, i) => <option key={i + 1} value={i + 1}>{i + 1}月</option>)}
            </select>

            <select
                value={filterDay}
                onChange={e => setFilterDay(e.target.value === 'all' ? 'all' : Number(e.target.value))}
                className="bg-white border border-slate-200 text-sm font-bold text-slate-600 rounded-xl px-3 py-1.5 focus:outline-none"
            >
              <option value="all">全天</option>
              {[...Array(31)].map((_, i) => <option key={i + 1} value={i + 1}>{i + 1}日</option>)}
            </select>

            <select
                value={filterTag}
                onChange={e => setFilterTag(e.target.value)}
                className="bg-white border border-slate-200 text-sm font-bold text-slate-600 rounded-xl px-3 py-1.5 focus:outline-none max-w-[120px]"
            >
              <option value="all">所有标签</option>
              {tags.map(tag => <option key={tag.uuid} value={tag.uuid}>{tag.name}</option>)}
            </select>

            <button onClick={fetchData} className="p-2 bg-white rounded-xl border border-slate-200 text-slate-500 hover:text-indigo-600 transition ml-1" title="刷新数据">
              <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} />
            </button>
          </div>
        </div>

        {loading ? (
            <div className="flex-1 flex items-center justify-center min-h-0">
              <RefreshCw className="w-8 h-8 text-amber-300 animate-spin" />
            </div>
        ) : (
            <div className="grid grid-cols-1 lg:grid-cols-3 gap-6 flex-1 min-h-0">
              {/* 左侧：汇总卡片 */}
              <div className="lg:col-span-1 space-y-6 flex flex-col shrink-0 lg:min-h-0">
                <div className="bg-gradient-to-br from-amber-400 to-orange-500 rounded-3xl p-8 text-white shadow-lg relative overflow-hidden">
                  <div className="relative z-10">
                    <p className="text-amber-100 font-bold mb-2 text-lg">累计专注时长</p>
                    <div className="text-5xl font-black mb-4 tracking-tight">
                      {formatHM(totalFocusSeconds).replace('小时', 'h').replace('分钟', 'm')}
                    </div>
                    <div className="flex items-center gap-2 mt-4 text-sm font-bold bg-black/10 inline-flex px-4 py-2 rounded-xl">
                      <CheckCircle2 className="w-4 h-4" /> 完成 {completedCount} 个番茄钟
                    </div>
                  </div>
                </div>
              </div>

              {/* 右侧：专注记录列表 */}
              <div className="lg:col-span-2 bg-white rounded-3xl shadow-sm border border-slate-100 overflow-hidden flex flex-col min-h-[400px] lg:min-h-0">
                <div className="p-6 border-b border-slate-100 bg-slate-50/50 flex justify-between items-center shrink-0">
                  <h3 className="font-bold text-lg text-slate-800">专注明细</h3>
                  <span className="text-sm font-bold text-slate-400">共 {filteredRecords.length} 条记录</span>
                </div>

                <div className="p-4 flex-1 overflow-y-auto space-y-3 min-h-0">
                  {filteredRecords.length === 0 ? (
                      <div className="h-full flex flex-col items-center justify-center py-20 text-slate-400">
                        <Clock className="w-12 h-12 mb-4 opacity-20" />
                        <p>没有找到符合条件的专注记录</p>
                      </div>
                  ) : (
                      filteredRecords.map((record) => {
                        const todo = todos.find(t => t.uuid === record.todo_uuid);
                        const isCompleted = record.status === 'completed';
                        return (
                            <div key={record.uuid} className="flex items-center justify-between p-4 border border-slate-100 rounded-2xl hover:border-amber-200 transition group">
                              <div className="flex items-center gap-4 min-w-0">
                                <div className={`w-12 h-12 rounded-full flex items-center justify-center shrink-0 ${isCompleted ? 'bg-amber-50 text-amber-500' : 'bg-slate-50 text-slate-400'}`}>
                                  {isCompleted ? <CheckCircle2 className="w-6 h-6" /> : <Clock className="w-6 h-6" />}
                                </div>
                                <div className="min-w-0">
                                  <p className="font-bold text-slate-800 text-base truncate">
                                    {todo ? todo.content : '未关联任务'}
                                  </p>
                                  <div className="flex items-center gap-2 mt-1">
                            <span className="text-xs text-slate-500">
                              {formatDt(new Date(record.start_time))}
                            </span>
                                    <span className={`text-[10px] px-2 py-0.5 rounded border ${isCompleted ? 'bg-green-50 text-green-600 border-green-200' : 'bg-slate-50 text-slate-500 border-slate-200'}`}>
                              {record.status === 'completed' ? '已完成' : record.status === 'switched' ? '中途切换' : '被打断'}
                            </span>
                                  </div>
                                </div>
                              </div>
                              <div className="text-right shrink-0">
                                <p className="font-black text-lg text-slate-700">
                                  {Math.floor((record.actual_duration || record.planned_duration || 0) / 60)} <span className="text-xs font-bold text-slate-400">min</span>
                                </p>
                              </div>
                            </div>
                        );
                      })
                  )}
                </div>
              </div>
            </div>
        )}
      </div>
  );
};


// --------------------------------------------------------
// 番茄钟设置类型
// --------------------------------------------------------
interface PomodoroSettings {
  focusDuration: number;   // seconds
  restDuration: number;    // seconds
  loopCount: number;
}

const DEFAULT_POMODORO_SETTINGS: PomodoroSettings = {
  focusDuration: 25 * 60,
  restDuration: 5 * 60,
  loopCount: 4,
};

function loadPomodoroSettings(userId: number): PomodoroSettings {
  try {
    const raw = localStorage.getItem(`u${userId}_pomodoro_settings`);
    if (raw) return { ...DEFAULT_POMODORO_SETTINGS, ...JSON.parse(raw) as Partial<PomodoroSettings> };
  } catch { /* ignore */ }
  return { ...DEFAULT_POMODORO_SETTINGS };
}

function savePomodoroSettings(userId: number, s: PomodoroSettings) {
  localStorage.setItem(`u${userId}_pomodoro_settings`, JSON.stringify(s));
}

interface PomodoroState {
  phase: 'focus' | 'rest';
  loopIndex: number;        // 0-based current loop
  endTimeMs: number;        // absolute timestamp when current phase ends
  todoUuid: string | null;
  tagUuids: string[];
  startTimeMs: number;      // when current focus session began
  recordUuid: string;
}

function loadPomodoroState(userId: number): PomodoroState | null {
  try {
    const raw = localStorage.getItem(`u${userId}_pomodoro_state`);
    if (raw) return JSON.parse(raw) as PomodoroState;
  } catch { /* ignore */ }
  return null;
}

function savePomodoroState(userId: number, state: PomodoroState | null) {
  if (state === null) {
    localStorage.removeItem(`u${userId}_pomodoro_state`);
  } else {
    localStorage.setItem(`u${userId}_pomodoro_state`, JSON.stringify(state));
  }
}

// --------------------------------------------------------
// 番茄钟工作台组件
// --------------------------------------------------------
const PomodoroFocusView = ({
  userId,
  todos,
  onTodoCompleted,
}: {
  userId: number;
  todos: TodoItem[];
  onTodoCompleted: (uuid: string) => void;
}) => {
  const [settings, setSettings] = useState<PomodoroSettings>(() => loadPomodoroSettings(userId));
  const [showSettings, setShowSettings] = useState(false);
  const [settingsDraft, setSettingsDraft] = useState<PomodoroSettings>(settings);

  const [tags, setTags] = useState<PomodoroTag[]>([]);
  const [loadingTags, setLoadingTags] = useState(false);
  const [showTagManager, setShowTagManager] = useState(false);
  const [newTagName, setNewTagName] = useState('');
  const [newTagColor, setNewTagColor] = useState('#6366f1');

  // Timer state
  const [pomState, setPomState] = useState<PomodoroState | null>(() => loadPomodoroState(userId));
  const [remainMs, setRemainMs] = useState(0);
  const [isRunning, setIsRunning] = useState(false);

  // Pre-start config
  const [selectedTodoUuid, setSelectedTodoUuid] = useState<string | null>(null);
  const [selectedTagUuids, setSelectedTagUuids] = useState<string[]>([]);

  // Completion dialog
  const [showCompleteDialog, setShowCompleteDialog] = useState(false);
  const [completedTodoUuid, setCompletedTodoUuid] = useState<string | null>(null);
  const [completedLoopIndex, setCompletedLoopIndex] = useState(0);
  const [completedActualSecs, setCompletedActualSecs] = useState(0);
  const [completedPhase, setCompletedPhase] = useState<'focus' | 'rest'>('focus');

  // Switch task dialog
  const [showSwitchDialog, setShowSwitchDialog] = useState(false);
  const [switchTargetUuid, setSwitchTargetUuid] = useState<string | null>(null);

  // Cross-device active session banner
  const [crossDeviceRecord, setCrossDeviceRecord] = useState<{
    uuid: string; todo_uuid: string | null; start_time: number;
    planned_duration: number; device_id: string | null;
  } | null>(null);

  // Load tags + check cross-device active session on mount
  useEffect(() => {
    fetchTags();
    checkCrossDeviceActive();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [userId]);

  const fetchTags = async () => {
    setLoadingTags(true);
    try {
      const data = await ApiService.request('/api/pomodoro/tags', { method: 'GET' });
      type TagWithDeleted = PomodoroTag & { is_deleted?: number };
      const tagList = (Array.isArray(data) ? data : []) as TagWithDeleted[];
      setTags(tagList.filter(t => !t.is_deleted));
    } catch (e) {
      console.error('获取标签失败', e);
    } finally {
      setLoadingTags(false);
    }
  };

  const checkCrossDeviceActive = async () => {
    // Only check if we don't already have a local session running
    if (loadPomodoroState(userId)) return;
    try {
      const deviceId = ApiService.getDeviceId();
      const res = await ApiService.request(
        `/api/pomodoro/active?device_id=${encodeURIComponent(deviceId)}`,
        { method: 'GET' }
      );
      if (res.active && res.record) {
        type ActiveRecord = { uuid: string; todo_uuid: string | null; start_time: number; planned_duration: number; device_id: string | null };
        setCrossDeviceRecord(res.record as ActiveRecord);
      }
    } catch (e) {
      console.error('检查跨设备番茄钟失败', e);
    }
  };

  // Tick timer
  useEffect(() => {
    if (!pomState) { setIsRunning(false); return; }
    setIsRunning(true);
    const update = () => {
      const now = Date.now();
      const remain = pomState.endTimeMs - now;
      if (remain <= 0) {
        handlePhaseEnd(pomState);
        return;
      }
      setRemainMs(remain);
    };
    update();
    const id = setInterval(update, 500);
    return () => clearInterval(id);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [pomState]);

  const handlePhaseEnd = (state: PomodoroState) => {
    const actualSecs = Math.round((state.endTimeMs - state.startTimeMs) / 1000);
    if (state.phase === 'focus') {
      // Upload record then show completion dialog
      uploadRecord({
        uuid: state.recordUuid,
        todo_uuid: state.todoUuid,
        start_time: state.startTimeMs,
        end_time: state.endTimeMs,
        planned_duration: settings.focusDuration,
        actual_duration: actualSecs,
        status: 'completed',
        tag_uuids: state.tagUuids,
      });
      setCompletedTodoUuid(state.todoUuid);
      setCompletedLoopIndex(state.loopIndex);
      setCompletedActualSecs(actualSecs);
      setCompletedPhase('focus');
      savePomodoroState(userId, null);
      setPomState(null);
      setIsRunning(false);
      setShowCompleteDialog(true);
    } else {
      // Rest ended → start next focus or stop
      const nextLoop = state.loopIndex + 1;
      savePomodoroState(userId, null);
      setPomState(null);
      setIsRunning(false);
      setCompletedPhase('rest');
      if (nextLoop < settings.loopCount) {
        setCompletedTodoUuid(state.todoUuid);
        setCompletedLoopIndex(nextLoop);
        setCompletedActualSecs(0);
        setShowCompleteDialog(true);
      }
    }
  };

  const startFocus = (todoUuid: string | null, tagUuids: string[], loopIndex = 0) => {
    const nowMs = Date.now();
    const endMs = nowMs + settings.focusDuration * 1000;
    const recordUuid = generateUUID();
    const state: PomodoroState = {
      phase: 'focus',
      loopIndex,
      endTimeMs: endMs,
      todoUuid,
      tagUuids,
      startTimeMs: nowMs,
      recordUuid,
    };
    savePomodoroState(userId, state);
    setPomState(state);
    setIsRunning(true);
    setRemainMs(settings.focusDuration * 1000);
  };

  const startRest = (loopIndex: number, todoUuid: string | null, tagUuids: string[]) => {
    const nowMs = Date.now();
    const endMs = nowMs + settings.restDuration * 1000;
    const state: PomodoroState = {
      phase: 'rest',
      loopIndex,
      endTimeMs: endMs,
      todoUuid,
      tagUuids,
      startTimeMs: nowMs,
      recordUuid: generateUUID(),
    };
    savePomodoroState(userId, state);
    setPomState(state);
    setIsRunning(true);
    setRemainMs(settings.restDuration * 1000);
  };

  const stopSession = () => {
    if (!pomState) return;
    if (!window.confirm('确定要放弃当前番茄钟吗？')) return;
    const actualSecs = Math.round((Date.now() - pomState.startTimeMs) / 1000);
    if (pomState.phase === 'focus' && actualSecs > 60) {
      uploadRecord({
        uuid: pomState.recordUuid,
        todo_uuid: pomState.todoUuid,
        start_time: pomState.startTimeMs,
        end_time: Date.now(),
        planned_duration: settings.focusDuration,
        actual_duration: actualSecs,
        status: 'interrupted',
        tag_uuids: pomState.tagUuids,
      });
    }
    savePomodoroState(userId, null);
    setPomState(null);
    setIsRunning(false);
  };

  const handleSwitchTask = () => {
    if (!pomState || !switchTargetUuid) return;
    const actualSecs = Math.round((Date.now() - pomState.startTimeMs) / 1000);
    uploadRecord({
      uuid: pomState.recordUuid,
      todo_uuid: pomState.todoUuid,
      start_time: pomState.startTimeMs,
      end_time: Date.now(),
      planned_duration: settings.focusDuration,
      actual_duration: actualSecs,
      status: 'switched',
      tag_uuids: pomState.tagUuids,
    });
    setShowSwitchDialog(false);
    startFocus(switchTargetUuid, pomState.tagUuids, pomState.loopIndex);
    setSwitchTargetUuid(null);
  };

  const uploadRecord = (rec: {
    uuid: string;
    todo_uuid: string | null;
    start_time: number;
    end_time: number;
    planned_duration: number;
    actual_duration: number;
    status: string;
    tag_uuids: string[];
  }) => {
    const now = Date.now();
    const fullRec: PomodoroRecord = {
      ...rec,
      status: rec.status as PomodoroRecord['status'],
      end_time: rec.end_time,
      device_id: ApiService.getDeviceId(),
      version: 1,
      created_at: rec.start_time,
      updated_at: now,
      is_deleted: 0,
    };
    // 1. Save to local storage immediately (offline-safe)
    upsertLocalPomRecord(userId, fullRec);
    // 2. Best-effort async upload to cloud
    ApiService.request('/api/pomodoro/records', {
      method: 'POST',
      body: JSON.stringify({ record: fullRec }),
    }).then(() => {
      // Mark as synced: update local updated_at to now so it won't be re-uploaded as dirty
      setPomLastSyncTime(userId, now);
    }).catch(e => console.error('上传专注记录失败，已暂存本地', e));
  };

  const handleCompleteDialogAction = (markDone: boolean) => {
    if (markDone && completedTodoUuid) {
      onTodoCompleted(completedTodoUuid);
    }
    setShowCompleteDialog(false);
    if (completedPhase === 'focus') {
      startRest(completedLoopIndex, completedTodoUuid, selectedTagUuids);
    } else {
      setCompletedTodoUuid(null);
    }
  };

  const handleAddTag = async () => {
    if (!newTagName.trim()) return;
    const tag: PomodoroTag = {
      uuid: generateUUID(),
      name: newTagName.trim(),
      color: newTagColor,
    };
    try {
      const fullTag = { ...tag, is_deleted: 0, version: 1, created_at: Date.now(), updated_at: Date.now() };
      await ApiService.request('/api/pomodoro/tags', {
        method: 'POST',
        body: JSON.stringify({ tags: [fullTag] }),
      });
      setTags(prev => [...prev, tag]);
      setNewTagName('');
      setNewTagColor('#6366f1');
    } catch (e) {
      console.error('创建标签失败', e);
    }
  };

  const handleDeleteTag = async (uuid: string) => {
    try {
      const tag = tags.find(t => t.uuid === uuid);
      if (!tag) return;
      const fullTag = { ...tag, is_deleted: 1, version: 2, updated_at: Date.now() };
      await ApiService.request('/api/pomodoro/tags', {
        method: 'POST',
        body: JSON.stringify({ tags: [fullTag] }),
      });
      setTags(prev => prev.filter(t => t.uuid !== uuid));
      setSelectedTagUuids(prev => prev.filter(u => u !== uuid));
    } catch (e) {
      console.error('删除标签失败', e);
    }
  };

  const saveSettings = () => {
    setSettings(settingsDraft);
    savePomodoroSettings(userId, settingsDraft);
    ApiService.request('/api/pomodoro/settings', {
      method: 'POST',
      body: JSON.stringify({
        default_focus_duration: settingsDraft.focusDuration,
        default_rest_duration: settingsDraft.restDuration,
        default_loop_count: settingsDraft.loopCount,
      }),
    }).catch(e => console.error('同步番茄钟设置失败', e));
    setShowSettings(false);
  };

  const formatTimer = (ms: number) => {
    const totalSecs = Math.max(0, Math.ceil(ms / 1000));
    const m = Math.floor(totalSecs / 60);
    const s = totalSecs % 60;
    return `${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
  };

  const activeTodosForPom = todos.filter(t => !t.is_completed && !t.is_deleted);
  const currentTodo = pomState?.todoUuid ? todos.find(t => t.uuid === pomState.todoUuid) : null;

  const totalPhaseSecs = pomState
    ? (pomState.phase === 'focus' ? settings.focusDuration : settings.restDuration)
    : settings.focusDuration;
  const progressPct = pomState
    ? Math.max(0, Math.min(100, (1 - remainMs / (totalPhaseSecs * 1000)) * 100))
    : 0;

  const TAG_COLORS = ['#6366f1', '#f59e0b', '#10b981', '#ef4444', '#8b5cf6', '#06b6d4', '#ec4899', '#84cc16'];

  return (
    <div className="flex flex-col gap-4 sm:gap-6 animate-in fade-in duration-300 h-full flex-1 min-h-0">
      {/* Header */}
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-3 bg-white p-4 sm:p-6 rounded-3xl shadow-sm border border-slate-100 shrink-0">
        <div>
          <h2 className="text-xl sm:text-2xl font-black text-slate-800 flex items-center gap-2">
            <span className="text-2xl">🍅</span> 番茄专注工作台
          </h2>
          <p className="text-slate-500 text-sm mt-0.5">深度专注，高效完成每一项任务。因技术原因，网页端不支持跨端感知。如需使用请下载PC端或者Android端。</p>
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={() => { setSettingsDraft(settings); setShowSettings(true); }}
            className="flex items-center gap-1.5 px-3 py-2 bg-slate-100 hover:bg-slate-200 text-slate-600 rounded-xl text-sm font-bold transition"
          >
            <svg xmlns="http://www.w3.org/2000/svg" className="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.68 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 9 4.68a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 2.83l-.06.06A1.65 1.65 0 0 0 19.4 9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/></svg>
            设置
          </button>
          <button
            onClick={() => { fetchTags(); setShowTagManager(true); }}
            disabled={loadingTags}
            className="flex items-center gap-1.5 px-3 py-2 bg-slate-100 hover:bg-slate-200 text-slate-600 rounded-xl text-sm font-bold transition"
          >
            <Hash className="w-4 h-4" /> 管理标签
          </button>
        </div>
      </div>

      <div className="flex flex-col lg:flex-row gap-4 sm:gap-6 flex-1 min-h-0">
        {/* Cross-device active session banner */}
        {crossDeviceRecord && !pomState && (
          <div className="lg:hidden w-full bg-amber-50 border border-amber-200 rounded-2xl px-5 py-4 flex items-center gap-4">
            <span className="text-2xl shrink-0">📱</span>
            <div className="flex-1 min-w-0">
              <p className="font-bold text-amber-800 text-sm">检测到其他设备正在专注中</p>
              <p className="text-amber-600 text-xs mt-0.5 truncate">
                已专注 {Math.round((Date.now() - crossDeviceRecord.start_time) / 60000)} 分钟 · 剩余 {Math.max(0, Math.round((crossDeviceRecord.planned_duration * 1000 - (Date.now() - crossDeviceRecord.start_time)) / 60000))} 分钟
              </p>
            </div>
            <button
              onClick={() => {
                const endMs = crossDeviceRecord.start_time + crossDeviceRecord.planned_duration * 1000;
                const nowMs = Date.now();
                if (endMs <= nowMs) { setCrossDeviceRecord(null); return; }
                const state: PomodoroState = {
                  phase: 'focus', loopIndex: 0, endTimeMs: endMs,
                  todoUuid: crossDeviceRecord.todo_uuid, tagUuids: [], startTimeMs: crossDeviceRecord.start_time,
                  recordUuid: crossDeviceRecord.uuid,
                };
                savePomodoroState(userId, state);
                setPomState(state);
                setCrossDeviceRecord(null);
              }}
              className="shrink-0 px-4 py-2 bg-amber-500 hover:bg-amber-600 text-white font-bold rounded-xl text-sm transition"
            >
              接管计时
            </button>
            <button onClick={() => setCrossDeviceRecord(null)} className="shrink-0 p-1 text-amber-400 hover:text-amber-600">
              <X className="w-4 h-4" />
            </button>
          </div>
        )}

        {/* Left: Timer */}
        <div className="lg:w-[400px] xl:w-[460px] shrink-0 flex flex-col gap-4">
          {/* Cross-device banner on desktop */}
          {crossDeviceRecord && !pomState && (
            <div className="hidden lg:flex bg-amber-50 border border-amber-200 rounded-2xl px-5 py-4 items-center gap-4">
              <span className="text-2xl shrink-0">📱</span>
              <div className="flex-1 min-w-0">
                <p className="font-bold text-amber-800 text-sm">其他设备专注中</p>
                <p className="text-amber-600 text-xs mt-0.5">
                  已专注 {Math.round((Date.now() - crossDeviceRecord.start_time) / 60000)} 分钟 · 剩余 {Math.max(0, Math.round((crossDeviceRecord.planned_duration * 1000 - (Date.now() - crossDeviceRecord.start_time)) / 60000))} 分钟
                </p>
              </div>
              <button
                onClick={() => {
                  const endMs = crossDeviceRecord.start_time + crossDeviceRecord.planned_duration * 1000;
                  const nowMs = Date.now();
                  if (endMs <= nowMs) { setCrossDeviceRecord(null); return; }
                  const state: PomodoroState = {
                    phase: 'focus', loopIndex: 0, endTimeMs: endMs,
                    todoUuid: crossDeviceRecord.todo_uuid, tagUuids: [], startTimeMs: crossDeviceRecord.start_time,
                    recordUuid: crossDeviceRecord.uuid,
                  };
                  savePomodoroState(userId, state);
                  setPomState(state);
                  setCrossDeviceRecord(null);
                }}
                className="shrink-0 px-3 py-1.5 bg-amber-500 hover:bg-amber-600 text-white font-bold rounded-xl text-xs transition"
              >
                接管
              </button>
              <button onClick={() => setCrossDeviceRecord(null)} className="shrink-0 p-1 text-amber-400 hover:text-amber-600">
                <X className="w-4 h-4" />
              </button>
            </div>
          )}
          {/* Timer Card */}
          <div className={`relative bg-white rounded-3xl shadow-sm border flex flex-col items-center justify-center p-8 sm:p-10 gap-6 ${
            pomState?.phase === 'rest' ? 'border-emerald-200' : (isRunning ? 'border-red-200' : 'border-slate-100')
          }`}>
            {pomState && (
              <div className={`absolute top-4 left-1/2 -translate-x-1/2 px-4 py-1.5 rounded-full text-xs font-black tracking-widest uppercase ${
                pomState.phase === 'rest' ? 'bg-emerald-50 text-emerald-600 border border-emerald-100' : 'bg-red-50 text-red-500 border border-red-100'
              }`}>
                {pomState.phase === 'focus' ? `🍅 第 ${pomState.loopIndex + 1} / ${settings.loopCount} 轮 · 专注中` : '☕ 休息时间'}
              </div>
            )}

            {/* Circular progress */}
            <div className="relative w-52 h-52 sm:w-60 sm:h-60">
              <svg className="absolute inset-0 -rotate-90" viewBox="0 0 200 200">
                <circle cx="100" cy="100" r="88" fill="none" stroke="#f1f5f9" strokeWidth="12" />
                <circle
                  cx="100" cy="100" r="88" fill="none"
                  stroke={pomState?.phase === 'rest' ? '#10b981' : (isRunning ? '#ef4444' : '#6366f1')}
                  strokeWidth="12"
                  strokeLinecap="round"
                  strokeDasharray={`${2 * Math.PI * 88}`}
                  strokeDashoffset={`${2 * Math.PI * 88 * (1 - progressPct / 100)}`}
                  className="transition-all duration-500"
                />
              </svg>
              <div className="absolute inset-0 flex flex-col items-center justify-center">
                <span className="text-5xl sm:text-6xl font-black tabular-nums text-slate-800 tracking-tight">
                  {pomState ? formatTimer(remainMs) : formatTimer(settings.focusDuration * 1000)}
                </span>
                <span className="text-sm font-bold text-slate-400 mt-1">
                  {pomState ? (pomState.phase === 'focus' ? '专注剩余' : '休息剩余') : '准备开始'}
                </span>
              </div>
            </div>

            {/* Current task */}
            {pomState && currentTodo && (
              <div className="w-full bg-slate-50 rounded-2xl px-5 py-3 flex items-center gap-3 border border-slate-100">
                <CheckCircle2 className="w-5 h-5 text-indigo-400 shrink-0" />
                <p className="font-bold text-slate-700 text-sm truncate flex-1">{currentTodo.content}</p>
                {pomState.phase === 'focus' && (
                  <button onClick={() => setShowSwitchDialog(true)} className="text-xs font-bold text-indigo-500 hover:text-indigo-700 shrink-0">切换</button>
                )}
              </div>
            )}
            {pomState && !currentTodo && (
              <div className="w-full bg-slate-50 rounded-2xl px-5 py-3 text-sm font-medium text-slate-400 border border-slate-100 text-center">未绑定任务</div>
            )}

            {/* Tags display */}
            {pomState && pomState.tagUuids.length > 0 && (
              <div className="flex flex-wrap gap-2 justify-center">
                {pomState.tagUuids.map(uuid => {
                  const tag = tags.find(t => t.uuid === uuid);
                  if (!tag) return null;
                  return <span key={uuid} className="px-3 py-1 rounded-full text-xs font-bold text-white" style={{ backgroundColor: tag.color }}>{tag.name}</span>;
                })}
              </div>
            )}

            {/* Controls */}
            {!isRunning ? (
              <div className="flex flex-col gap-3 w-full">
                <div>
                  <label className="text-xs font-bold text-slate-400 mb-1.5 block">选择专注任务（可选）</label>
                  <select
                    value={selectedTodoUuid ?? ''}
                    onChange={e => setSelectedTodoUuid(e.target.value || null)}
                    className="w-full bg-slate-50 border border-slate-200 rounded-2xl px-4 py-3 text-sm font-medium text-slate-700 focus:outline-none focus:ring-2 focus:ring-indigo-400/50"
                  >
                    <option value="">不绑定任务（自由专注）</option>
                    {activeTodosForPom.map(t => (
                      <option key={t.uuid} value={t.uuid}>{t.content}</option>
                    ))}
                  </select>
                </div>
                {tags.length > 0 && (
                  <div>
                    <label className="text-xs font-bold text-slate-400 mb-1.5 block">选择标签（可多选）</label>
                    <div className="flex flex-wrap gap-2">
                      {tags.map(tag => {
                        const isSelected = selectedTagUuids.includes(tag.uuid);
                        return (
                          <button
                            key={tag.uuid}
                            onClick={() => setSelectedTagUuids(prev => isSelected ? prev.filter(u => u !== tag.uuid) : [...prev, tag.uuid])}
                            className={`px-3 py-1.5 rounded-full text-xs font-bold border-2 transition ${isSelected ? 'text-white border-transparent' : 'bg-white text-slate-600 border-slate-200'}`}
                            style={isSelected ? { backgroundColor: tag.color, borderColor: tag.color } : {}}
                          >
                            {tag.name}
                          </button>
                        );
                      })}
                    </div>
                  </div>
                )}
                <button
                  onClick={() => startFocus(selectedTodoUuid, selectedTagUuids)}
                  className="w-full bg-indigo-600 hover:bg-indigo-700 text-white font-black py-4 rounded-2xl text-lg transition shadow-xl shadow-indigo-500/30 active:scale-[0.98] flex items-center justify-center gap-2"
                >
                  <PlayCircle className="w-6 h-6" /> 开始专注
                </button>
              </div>
            ) : (
              <div className="flex gap-3 w-full">
                {pomState?.phase === 'focus' && (
                  <button onClick={() => setShowSwitchDialog(true)} className="flex-1 bg-amber-50 hover:bg-amber-100 text-amber-600 font-bold py-3 rounded-2xl text-sm transition flex items-center justify-center gap-2">
                    <ArrowLeft className="w-4 h-4" /> 切换任务
                  </button>
                )}
                <button onClick={stopSession} className="flex-1 bg-red-50 hover:bg-red-100 text-red-500 font-bold py-3 rounded-2xl text-sm transition flex items-center justify-center gap-2">
                  <StopCircle className="w-4 h-4" /> 放弃
                </button>
              </div>
            )}
          </div>

          {/* Loop progress */}
          <div className="bg-white rounded-2xl border border-slate-100 p-4">
            <p className="text-xs font-bold text-slate-400 mb-3">本组循环进度</p>
            <div className="flex gap-2">
              {Array.from({ length: settings.loopCount }).map((_, i) => {
                const currentLoop = pomState?.loopIndex ?? -1;
                const isDone = i < currentLoop || (i === currentLoop && pomState?.phase === 'rest');
                const isActive = i === currentLoop && pomState?.phase === 'focus';
                return <div key={i} className={`flex-1 h-3 rounded-full transition ${isDone ? 'bg-emerald-400' : (isActive ? 'bg-red-400' : 'bg-slate-100')}`} />;
              })}
            </div>
            <p className="text-xs text-slate-400 mt-2 text-right">
              {pomState ? `${pomState.loopIndex + 1} / ${settings.loopCount}` : `0 / ${settings.loopCount}`}
            </p>
          </div>
        </div>

        {/* Right: Active todos */}
        <div className="flex-1 bg-white rounded-3xl border border-slate-100 shadow-sm flex flex-col overflow-hidden min-h-[300px] lg:min-h-0">
          <div className="px-6 py-4 border-b border-slate-100 bg-slate-50/50 shrink-0">
            <h3 className="font-bold text-slate-800 flex items-center gap-2">
              <CheckCircle2 className="w-5 h-5 text-emerald-500" /> 活跃待办列表
            </h3>
            <p className="text-xs text-slate-400 mt-0.5">点击任务快速绑定为专注目标</p>
          </div>
          <div className="flex-1 overflow-y-auto p-4 space-y-2 min-h-0">
            {activeTodosForPom.length === 0 ? (
              <div className="h-full flex flex-col items-center justify-center text-slate-400 py-16">
                <CheckCircle2 className="w-10 h-10 mb-3 opacity-20" />
                <p className="text-sm">暂无活跃待办</p>
              </div>
            ) : (
              activeTodosForPom.map(todo => {
                const isSelected = selectedTodoUuid === todo.uuid;
                const isCurrent = pomState?.todoUuid === todo.uuid;
                return (
                  <button
                    key={todo.uuid}
                    onClick={() => !isRunning && setSelectedTodoUuid(isSelected ? null : todo.uuid)}
                    disabled={isRunning}
                    className={`w-full text-left p-3 sm:p-4 rounded-2xl border-2 transition flex items-start gap-3 ${
                      isCurrent ? 'bg-red-50 border-red-200' : isSelected ? 'bg-indigo-50 border-indigo-300' : 'bg-white border-slate-100 hover:border-indigo-200 hover:bg-indigo-50/30'
                    } ${isRunning ? 'opacity-60 cursor-default' : 'cursor-pointer'}`}
                  >
                    <div className={`w-5 h-5 rounded-full border-2 flex items-center justify-center mt-0.5 shrink-0 ${isCurrent ? 'border-red-400 bg-red-400' : (isSelected ? 'border-indigo-500 bg-indigo-500' : 'border-slate-200')}`}>
                      {(isSelected || isCurrent) && <Check className="w-3 h-3 text-white" />}
                    </div>
                    <div className="min-w-0 flex-1">
                      <p className="font-semibold text-sm text-slate-800 truncate">{todo.content}</p>
                      {todo.due_date && <p className="text-xs text-slate-400 mt-0.5">截止 {new Date(todo.due_date).toLocaleDateString()}</p>}
                    </div>
                    {isCurrent && <span className="shrink-0 text-[10px] font-black text-red-500 bg-red-50 px-2 py-0.5 rounded-full border border-red-100">专注中</span>}
                  </button>
                );
              })
            )}
          </div>
        </div>
      </div>

      {/* Settings Modal */}
      {showSettings && (
        <div className="fixed inset-0 z-60 bg-slate-900/40 backdrop-blur-sm flex items-center justify-center p-4 animate-in fade-in duration-200">
          <div className="bg-white w-full max-w-md rounded-[2.5rem] p-8 shadow-2xl animate-in zoom-in-95 duration-200">
            <div className="flex justify-between items-center mb-8">
              <h4 className="font-black text-2xl text-slate-800">番茄钟设置</h4>
              <button onClick={() => setShowSettings(false)} className="p-2 bg-slate-100 rounded-full text-slate-500 hover:bg-slate-200 transition"><X className="w-5 h-5" /></button>
            </div>
            <div className="space-y-6 mb-8">
              <div>
                <label className="text-sm font-bold text-slate-500 mb-2 block">专注时长（分钟）</label>
                <input type="number" min="1" max="120" value={Math.round(settingsDraft.focusDuration / 60)}
                  onChange={e => setSettingsDraft(d => ({ ...d, focusDuration: Math.max(1, Number(e.target.value)) * 60 }))}
                  className="w-full bg-slate-50 border border-slate-200 px-5 py-4 rounded-2xl text-slate-800 focus:outline-none focus:ring-2 focus:ring-indigo-500/50 text-lg font-bold" />
              </div>
              <div>
                <label className="text-sm font-bold text-slate-500 mb-2 block">休息时长（分钟）</label>
                <input type="number" min="1" max="60" value={Math.round(settingsDraft.restDuration / 60)}
                  onChange={e => setSettingsDraft(d => ({ ...d, restDuration: Math.max(1, Number(e.target.value)) * 60 }))}
                  className="w-full bg-slate-50 border border-slate-200 px-5 py-4 rounded-2xl text-slate-800 focus:outline-none focus:ring-2 focus:ring-indigo-500/50 text-lg font-bold" />
              </div>
              <div>
                <label className="text-sm font-bold text-slate-500 mb-2 block">每组循环次数</label>
                <input type="number" min="1" max="12" value={settingsDraft.loopCount}
                  onChange={e => setSettingsDraft(d => ({ ...d, loopCount: Math.max(1, Number(e.target.value)) }))}
                  className="w-full bg-slate-50 border border-slate-200 px-5 py-4 rounded-2xl text-slate-800 focus:outline-none focus:ring-2 focus:ring-indigo-500/50 text-lg font-bold" />
              </div>
            </div>
            <button onClick={saveSettings} className="w-full bg-indigo-600 text-white font-black text-lg py-4 rounded-2xl hover:bg-indigo-700 transition shadow-xl shadow-indigo-500/30 active:scale-[0.98]">保存设置</button>
          </div>
        </div>
      )}

      {/* Tag Manager Modal */}
      {showTagManager && (
        <div className="fixed inset-0 z-60 bg-slate-900/40 backdrop-blur-sm flex items-center justify-center p-4 animate-in fade-in duration-200">
          <div className="bg-white w-full max-w-md rounded-[2.5rem] p-8 shadow-2xl animate-in zoom-in-95 duration-200 max-h-[90dvh] flex flex-col">
            <div className="flex justify-between items-center mb-6 shrink-0">
              <h4 className="font-black text-2xl text-slate-800">标签管理</h4>
              <button onClick={() => setShowTagManager(false)} className="p-2 bg-slate-100 rounded-full text-slate-500 hover:bg-slate-200 transition"><X className="w-5 h-5" /></button>
            </div>
            <div className="flex-1 overflow-y-auto space-y-3 min-h-0 mb-6">
              {tags.length === 0 ? (
                <p className="text-center text-slate-400 py-8 text-sm">暂无自定义标签</p>
              ) : (
                tags.map(tag => (
                  <div key={tag.uuid} className="flex items-center gap-3 p-3 bg-slate-50 rounded-2xl border border-slate-100">
                    <div className="w-5 h-5 rounded-full shrink-0" style={{ backgroundColor: tag.color }} />
                    <span className="font-bold text-slate-700 flex-1">{tag.name}</span>
                    <button onClick={() => handleDeleteTag(tag.uuid)} className="p-1.5 text-slate-400 hover:text-red-500 hover:bg-red-50 rounded-xl transition">
                      <Trash2 className="w-4 h-4" />
                    </button>
                  </div>
                ))
              )}
            </div>
            <div className="border-t border-slate-100 pt-5 shrink-0">
              <p className="text-sm font-bold text-slate-500 mb-3">新建标签</p>
              <div className="flex gap-2 mb-3">
                {TAG_COLORS.map(c => (
                  <button key={c} onClick={() => setNewTagColor(c)}
                    className={`w-7 h-7 rounded-full transition border-2 ${newTagColor === c ? 'border-slate-800 scale-110' : 'border-transparent'}`}
                    style={{ backgroundColor: c }} />
                ))}
              </div>
              <div className="flex gap-2">
                <input value={newTagName} onChange={e => setNewTagName(e.target.value)}
                  onKeyDown={e => e.key === 'Enter' && handleAddTag()}
                  placeholder="输入标签名称..."
                  className="flex-1 bg-slate-50 border border-slate-200 px-4 py-3 rounded-2xl text-sm font-medium text-slate-700 focus:outline-none focus:ring-2 focus:ring-indigo-400/50" />
                <button onClick={handleAddTag} disabled={!newTagName.trim()}
                  className="px-5 py-3 bg-indigo-600 hover:bg-indigo-700 text-white font-bold rounded-2xl transition disabled:opacity-40 active:scale-95">
                  <Plus className="w-4 h-4" />
                </button>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Completion Dialog */}
      {showCompleteDialog && (
        <div className="fixed inset-0 z-60 bg-slate-900/50 backdrop-blur-sm flex items-center justify-center p-4 animate-in fade-in duration-200">
          <div className="bg-white w-full max-w-sm rounded-[2.5rem] p-8 shadow-2xl animate-in zoom-in-95 duration-200 text-center">
            <div className="text-5xl mb-4">{completedPhase === 'focus' ? '🎉' : '☕'}</div>
            <h3 className="font-black text-2xl text-slate-800 mb-2">{completedPhase === 'focus' ? '专注时间到！' : '休息结束！'}</h3>
            {completedPhase === 'focus' && completedActualSecs > 0 && (
              <p className="text-slate-500 text-sm mb-4">本轮专注了 <span className="font-black text-indigo-600">{Math.round(completedActualSecs / 60)}</span> 分钟</p>
            )}
            {completedPhase === 'focus' && completedTodoUuid && (
              <div className="bg-slate-50 rounded-2xl p-4 mb-6 border border-slate-100">
                <p className="text-sm text-slate-500 mb-2 truncate">「{todos.find(t => t.uuid === completedTodoUuid)?.content ?? '该任务'}」</p>
                <p className="font-bold text-slate-700">是否已完成这个任务？</p>
              </div>
            )}
            {completedPhase === 'focus' && completedTodoUuid ? (
              <div className="flex gap-3">
                <button onClick={() => handleCompleteDialogAction(false)} className="flex-1 bg-slate-100 hover:bg-slate-200 text-slate-700 font-bold py-4 rounded-2xl transition">还没完成</button>
                <button onClick={() => handleCompleteDialogAction(true)} className="flex-1 bg-emerald-500 hover:bg-emerald-600 text-white font-bold py-4 rounded-2xl transition shadow-lg shadow-emerald-500/30">✅ 已完成！</button>
              </div>
            ) : (
              <button
                onClick={() => { setShowCompleteDialog(false); if (completedPhase === 'rest') startFocus(selectedTodoUuid, selectedTagUuids); }}
                className="w-full bg-indigo-600 hover:bg-indigo-700 text-white font-bold py-4 rounded-2xl transition shadow-lg shadow-indigo-500/30"
              >
                {completedPhase === 'rest' ? '🚀 开始下一轮专注' : '好的，继续'}
              </button>
            )}
          </div>
        </div>
      )}

      {/* Switch Task Dialog */}
      {showSwitchDialog && (
        <div className="fixed inset-0 z-60 bg-slate-900/40 backdrop-blur-sm flex items-center justify-center p-4 animate-in fade-in duration-200">
          <div className="bg-white w-full max-w-md rounded-[2.5rem] p-8 shadow-2xl animate-in zoom-in-95 duration-200 max-h-[80dvh] flex flex-col">
            <div className="flex justify-between items-center mb-6 shrink-0">
              <h4 className="font-black text-xl text-slate-800">切换到另一个任务</h4>
              <button onClick={() => setShowSwitchDialog(false)} className="p-2 bg-slate-100 rounded-full text-slate-500 hover:bg-slate-200 transition"><X className="w-5 h-5" /></button>
            </div>
            <p className="text-sm text-slate-500 mb-4 shrink-0">当前进度将被记录为"中途切换"，并为新任务重新开始计时。</p>
            <div className="flex-1 overflow-y-auto space-y-2 min-h-0 mb-6">
              {activeTodosForPom.filter(t => t.uuid !== pomState?.todoUuid).map(todo => (
                <button key={todo.uuid} onClick={() => setSwitchTargetUuid(todo.uuid)}
                  className={`w-full text-left p-4 rounded-2xl border-2 transition ${switchTargetUuid === todo.uuid ? 'bg-indigo-50 border-indigo-300' : 'bg-slate-50 border-slate-100 hover:border-indigo-200'}`}>
                  <p className="font-semibold text-sm text-slate-800">{todo.content}</p>
                </button>
              ))}
            </div>
            <button onClick={handleSwitchTask} disabled={!switchTargetUuid}
              className="w-full bg-indigo-600 text-white font-black py-4 rounded-2xl transition shadow-xl shadow-indigo-500/30 active:scale-[0.98] disabled:opacity-40">
              确认切换
            </button>
          </div>
        </div>
      )}
    </div>
  );
};

// --------------------------------------------------------
// 主应用组件 (WebApp)
// --------------------------------------------------------
export const WebApp = ({ onBack, user, onLogout }: { onBack: () => void, user: User, onLogout: () => void }) => {
  const [currentTab, setCurrentTab] = useState<'dashboard' | 'screentime' | 'pomodoro' | 'focus'>('dashboard');
  const [todos, setTodos] = useState<TodoItem[]>([]);
  const [countdowns, setCountdowns] = useState<CountdownItem[]>([]);
  const [showAddModal, setShowAddModal] = useState<'todo' | 'countdown' | null>(null);

  // 编辑待办
  const [editingTodo, setEditingTodo] = useState<TodoItem | null>(null);
  const [editTitle, setEditTitle] = useState('');
  const [editRemark, setEditRemark] = useState('');
  const [editStartDate, setEditStartDate] = useState('');
  const [editDueDate, setEditDueDate] = useState('');

  const [newItemTitle, setNewItemTitle] = useState('');
  const [newRemark, setNewRemark] = useState('');
  const [newStartDate, setNewStartDate] = useState(toDatetimeLocal(Date.now()));
  const [newDueDate, setNewDueDate] = useState('');
  const [isSyncing, setIsSyncing] = useState(false);
  const [syncCountToday, setSyncCountToday] = useState(0);

  const [isPastExpanded, setIsPastExpanded] = useState(false);
  const [isTodayExpanded, setIsTodayExpanded] = useState(true);
  const [isFutureExpanded, setIsFutureExpanded] = useState(true);
  const [nowMs, setNowMs] = useState(Date.now());
  const [mobileTab, setMobileTab] = useState<'home' | 'settings'>('home');

  // --- 网页版版本更新检查状态 ---
  const [updateInfo, setUpdateInfo] = useState<{ version: string, title: string, desc: string } | null>(null);

  useEffect(() => {
    loadLocalData();
    handleSync();
    fetchSyncStats();

    const timer = setInterval(() => setNowMs(Date.now()), 60000);

    // 检查网页版更新
    const checkWebUpdate = async () => {
      try {
        const res = await fetch('https://raw.githubusercontent.com/Junpgle/CountdownTodo/refs/heads/master/webpage/web/update_manifest.json');
        const data = await res.json();
        if (data.version_name && data.version_name !== CURRENT_WEB_VERSION) {
          setUpdateInfo({
            version: data.version_name,
            title: data.update_info?.title || '版本更新',
            desc: data.update_info?.description || '发现新版本，请刷新页面。'
          });
        }
      } catch (e) {
        console.error("检查网页版更新失败", e);
      }
    };
    checkWebUpdate();

    return () => clearInterval(timer);
  }, []);

  const loadLocalData = () => {
    setTodos(SyncEngine.getLocalTodos(user.id).filter(t => !t.is_deleted));
    setCountdowns(SyncEngine.getLocalCountdowns(user.id).filter(c => !c.is_deleted));
  };

  const fetchSyncStats = async () => {
    try {
      const res = await ApiService.request(`/api/user/status?user_id=${user.id}`, { method: 'GET' });
      if (res && typeof res.sync_count !== 'undefined') {
        setSyncCountToday(Number(res.sync_count));
      }
    } catch (e) {
      console.warn("拉取同步统计信息失败，采用本地记录兜底", e);
      const savedStats = localStorage.getItem('cdt_sync_stats');
      if (savedStats) {
        const parsed = JSON.parse(savedStats);
        if (parsed.date === new Date().toDateString()) {
          setSyncCountToday(parsed.count);
        } else {
          setSyncCountToday(0);
        }
      }
    }
  };

  const handleSync = async () => {
    if (isSyncing) return;
    setIsSyncing(true);
    try {
      await SyncEngine.syncData(user.id);
      loadLocalData();
      await fetchSyncStats();
    } catch (e) {
      console.error("同步失败", e);
    } finally {
      setIsSyncing(false);
    }
  };

  const handleForceSync = async () => {
    if (isSyncing) return;
    if (!window.confirm("强制全量同步将清除本地同步记录，并从云端重新拉取所有最新数据。\n\n这通常用于解决多设备数据不一致的问题。确定要继续吗？")) return;

    setIsSyncing(true);
    try {
      SyncEngine.resetSync(user.id);
      await SyncEngine.syncData(user.id);
      loadLocalData();
      await fetchSyncStats();
      alert("全量数据拉取成功！");
    } catch (e) {
      console.error("全量同步失败", e);
      alert("拉取失败，请检查网络");
    } finally {
      setIsSyncing(false);
    }
  };

  const getSyncLimit = () => {
    if (user.tier === 'admin') return 99999;
    if (user.tier === 'pro') return 2000;
    return 500;
  };
  const syncLimit = getSyncLimit();

  const calcProgress = (t: TodoItem) => {
    const start = t.created_date ?? t.created_at;
    let endMs;
    if (t.due_date) {
      const d = new Date(t.due_date);
      d.setSeconds(59, 999);
      endMs = d.getTime();
    } else {
      const d = new Date(start);
      d.setHours(23, 59, 59, 999);
      endMs = d.getTime();
    }
    if (nowMs < start) return 0.0;
    const totalMinutes = (endMs - start) / 60000;
    if (totalMinutes <= 0) return 1.0;
    const passedMinutes = (nowMs - start) / 60000;
    return Math.max(0, Math.min(1, passedMinutes / totalMinutes));
  };

  const getTodayStartMs = () => {
    const d = new Date();
    d.setHours(0, 0, 0, 0);
    return d.getTime();
  };

  const isHistorical = (t: TodoItem) => {
    if (!t.is_completed) return false;
    const todayMs = getTodayStartMs();
    const d = new Date(t.due_date ?? (t.created_date ?? t.created_at));
    d.setHours(0, 0, 0, 0);
    return d.getTime() < todayMs;
  };

  const todayMs = getTodayStartMs();
  const activeTodos = todos.filter(t => !isHistorical(t));

  const pastTodos: TodoItem[] = [];
  const todayTodos: TodoItem[] = [];
  const futureTodos: TodoItem[] = [];

  activeTodos.forEach(t => {
    if (t.due_date) {
      const d = new Date(t.due_date);
      d.setHours(0, 0, 0, 0);
      const dMs = d.getTime();
      if (dMs < todayMs) pastTodos.push(t);
      else if (dMs > todayMs) futureTodos.push(t);
      else todayTodos.push(t);
    } else {
      todayTodos.push(t);
    }
  });

  const sortedToday = [
    ...todayTodos.filter(t => !t.is_completed).sort((a, b) => {
      const sa = a.created_date ?? a.created_at;
      const sb = b.created_date ?? b.created_at;
      return sa - sb;
    }),
    ...todayTodos.filter(t => t.is_completed).sort((a, b) => {
      const sa = a.created_date ?? a.created_at;
      const sb = b.created_date ?? b.created_at;
      return sa - sb;
    })
  ];

  const sortedFuture = [
    ...futureTodos.filter(t => !t.is_completed).sort((a, b) => {
      const sa = a.created_date ?? a.created_at;
      const sb = b.created_date ?? b.created_at;
      return sa - sb;
    }),
    ...futureTodos.filter(t => t.is_completed).sort((a, b) => {
      const sa = a.created_date ?? a.created_at;
      const sb = b.created_date ?? b.created_at;
      return sa - sb;
    })
  ];

  const handleTodoCompleted = (uuid: string) => {
    const all = SyncEngine.getLocalTodos(user.id);
    const target = all.find(t => t.uuid === uuid);
    if (target) {
      target.is_completed = true;
      target.version++;
      target.updated_at = Date.now();
      SyncEngine.setLocalTodos(user.id, all);
      loadLocalData();
      handleSync();
    }
  };

  const handleAddTodo = () => {
    const now = Date.now();
    const newTodo: TodoItem = {
      id: generateUUID(),
      uuid: generateUUID(),
      content: newItemTitle,
      is_completed: false,
      is_deleted: false,
      version: 1,
      updated_at: now,
      created_at: now,
      created_date: new Date(newStartDate).getTime(),
      due_date: newDueDate ? new Date(newDueDate).getTime() : null,
      device_id: ApiService.getDeviceId(),
      remark: newRemark.trim() || null,
    };

    const all = SyncEngine.getLocalTodos(user.id);
    all.unshift(newTodo);
    SyncEngine.setLocalTodos(user.id, all);
    loadLocalData();
    setShowAddModal(null);
    resetForm();
    handleSync();
  };

  const handleAddCountdown = () => {
    if (!newItemTitle.trim() || !newDueDate) return;
    const now = Date.now();
    const newC: CountdownItem = {
      id: generateUUID(),
      uuid: generateUUID(),
      title: newItemTitle,
      target_time: new Date(newDueDate).getTime(),
      is_deleted: false,
      version: 1,
      updated_at: now,
      created_at: now,
      device_id: ApiService.getDeviceId()
    };
    const all = SyncEngine.getLocalCountdowns(user.id);
    all.push(newC);
    SyncEngine.setLocalCountdowns(user.id, all);
    loadLocalData();
    setShowAddModal(null);
    resetForm();
    handleSync();
  };

  const resetForm = () => {
    setNewItemTitle('');
    setNewRemark('');
    setNewStartDate(toDatetimeLocal(Date.now()));
    setNewDueDate('');
  };

  const openEditModal = (todo: TodoItem) => {
    setEditingTodo(todo);
    setEditTitle(todo.content);
    setEditRemark(todo.remark ?? '');
    setEditStartDate(toDatetimeLocal(todo.created_date ?? todo.created_at));
    setEditDueDate(todo.due_date ? toDatetimeLocal(todo.due_date) : '');
  };

  const handleSaveTodoEdit = () => {
    if (!editingTodo || !editTitle.trim()) return;
    const all = SyncEngine.getLocalTodos(user.id);
    const target = all.find(t => t.uuid === editingTodo.uuid);
    if (target) {
      target.content = editTitle.trim();
      target.remark = editRemark.trim() || null;
      target.created_date = new Date(editStartDate).getTime();
      target.due_date = editDueDate ? new Date(editDueDate).getTime() : null;
      target.version++;
      target.updated_at = Date.now();
      SyncEngine.setLocalTodos(user.id, all);
      loadLocalData();
      handleSync();
    }
    setEditingTodo(null);
  };

  const toggleTodo = (uuid: string) => {
    const all = SyncEngine.getLocalTodos(user.id);
    const target = all.find(t => t.uuid === uuid);
    if (target) {
      target.is_completed = !target.is_completed;
      target.version++;
      target.updated_at = Date.now();
      SyncEngine.setLocalTodos(user.id, all);
      loadLocalData();
      handleSync();
    }
  };

  const deleteTodo = (uuid: string) => {
    const all = SyncEngine.getLocalTodos(user.id);
    const target = all.find(t => t.uuid === uuid);
    if (target) {
      target.is_deleted = true;
      target.version++;
      target.updated_at = Date.now();
      SyncEngine.setLocalTodos(user.id, all);
      loadLocalData();
      handleSync();
    }
  };

  const deleteCountdown = (uuid: string) => {
    const all = SyncEngine.getLocalCountdowns(user.id);
    const target = all.find(t => t.uuid === uuid);
    if (target) {
      target.is_deleted = true;
      target.version++;
      target.updated_at = Date.now();
      SyncEngine.setLocalCountdowns(user.id, all);
      loadLocalData();
      handleSync();
    }
  };

  const getDaysLeft = (targetTime: number) => {
    const d = new Date(targetTime);
    d.setHours(0,0,0,0);
    return Math.floor((d.getTime() - todayMs) / 86400000);
  };

  const TodoCard = ({ todo, isPast, isFuture }: { todo: TodoItem, isPast: boolean, isFuture: boolean }) => {
    const progress = calcProgress(todo);
    const cDate = new Date(todo.created_date ?? todo.created_at);

    let dateStr: string;
    if (todo.due_date) {
      const dDate = new Date(todo.due_date);
      if (isFuture) {
        const days = Math.floor((new Date(dDate.getFullYear(), dDate.getMonth(), dDate.getDate()).getTime() - todayMs) / 86400000);
        dateStr = `${formatDt(cDate)} 至 ${formatDt(dDate)} (${days}天后截止)`;
      } else if (isPast) {
        dateStr = `${formatDt(cDate)} 至 ${formatDt(dDate)} (已逾期)`;
      } else {
        dateStr = `${formatDt(cDate)} 至 ${formatDt(dDate)} (今天截止)`;
      }
    } else {
      dateStr = `开始于 ${formatDt(cDate)}`;
    }

    return (
        <div className={`relative group flex items-start gap-2 sm:gap-4 p-2.5 sm:p-4 rounded-xl sm:rounded-2xl transition-all duration-300 ${
            todo.is_completed
                ? 'bg-slate-100/50 border border-transparent'
                : `bg-white shadow-sm border border-slate-200 ${isPast ? 'border-red-100' : ''}`
        }`}>
          <button
              onClick={() => toggleTodo(todo.uuid)}
              className={`mt-0.5 shrink-0 w-5 h-5 sm:w-6 sm:h-6 rounded-full border-2 flex items-center justify-center transition-colors ${
                  todo.is_completed ? 'bg-emerald-500 border-emerald-500 text-white' : 'border-slate-300 text-transparent hover:border-emerald-400'
              }`}
          >
            <Check className="w-3 h-3 sm:w-4 sm:h-4" />
          </button>

          <div className="flex-1 min-w-0">
            <p className={`text-sm sm:text-base font-semibold truncate ${
                todo.is_completed ? 'text-slate-400 line-through' : (isPast || isFuture ? 'text-slate-600 font-medium' : 'text-slate-800')
            }`}>
              {todo.content}
            </p>
            <div className="mt-1 sm:mt-2 space-y-1 sm:space-y-2">
              <p className={`text-[10px] sm:text-xs ${todo.is_completed ? 'text-slate-400' : (isPast ? 'text-red-500 font-medium' : 'text-slate-500')}`}>
                {dateStr}
              </p>
              <div className="flex items-center gap-2 sm:gap-3">
                <div className="flex-1 h-1 sm:h-1.5 bg-slate-100 rounded-full overflow-hidden">
                  <div
                      className={`h-full rounded-full transition-all duration-500 ${todo.is_completed ? 'bg-slate-300' : 'bg-indigo-600'}`}
                      style={{ width: `${progress * 100}%` }}
                  />
                </div>
                <span className={`text-[10px] sm:text-[11px] font-bold ${todo.is_completed ? 'text-slate-400' : (isPast ? 'text-red-500' : 'text-slate-500')}`}>
                  {Math.floor(progress * 100)}%
                </span>
              </div>
              {todo.remark && (
                  <div className="flex items-start gap-1.5 mt-1">
                  <span className="text-slate-300 mt-0.5 shrink-0">
                    <svg xmlns="http://www.w3.org/2000/svg" className="w-3 h-3" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><path d="M14 3H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-9"/><path d="M14.5 2.5a2.121 2.121 0 0 1 3 3L12 11l-4 1 1-4 5.5-5.5z"/></svg>
                  </span>
                    <p className={`text-[10px] sm:text-xs italic leading-snug line-clamp-2 ${todo.is_completed ? 'text-slate-300' : 'text-slate-400'}`}>
                      {todo.remark}
                    </p>
                  </div>
              )}
            </div>
          </div>

          <div className="flex flex-col gap-1 opacity-0 group-hover:opacity-100 transition">
            <button
                onClick={() => openEditModal(todo)}
                className="p-1.5 sm:p-2 text-slate-300 hover:text-indigo-500 hover:bg-indigo-50 rounded-lg sm:rounded-xl transition"
                title="编辑"
            >
              <svg xmlns="http://www.w3.org/2000/svg" className="w-4 h-4 sm:w-5 sm:h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/><path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"/></svg>
            </button>
            <button
                onClick={() => deleteTodo(todo.uuid)}
                className="p-1.5 sm:p-2 text-slate-300 hover:text-red-500 hover:bg-red-50 rounded-lg sm:rounded-xl transition"
                title="删除"
            >
              <Trash2 className="w-4 h-4 sm:w-5 sm:h-5" />
            </button>
          </div>
        </div>
    );
  };

  const renderDashboard = () => (
      <div className="flex flex-col lg:flex-row gap-6 h-full flex-1 min-h-0 animate-in fade-in duration-300">
        {/* 左半部分：自适应周视图 */}
        <div className="w-full lg:w-1/2 flex flex-col shrink-0 lg:shrink h-auto lg:h-full min-h-[500px] lg:min-h-0">
          <CourseView userId={user.id} todos={todos} countdowns={countdowns} />
        </div>

        {/* 右半部分：倒计时 (顶部) + 待办清单 (底部) */}
        <div className="w-full lg:w-1/2 flex flex-col gap-6 h-auto lg:h-full min-h-0 shrink-0 lg:shrink">

          {/* 倒计时横滑列表 */}
          <div className="shrink-0 flex flex-col bg-white rounded-3xl shadow-sm border border-slate-100 overflow-hidden">
            <div className="px-6 py-4 flex justify-between items-center border-b border-slate-50 shrink-0">
              <h2 className="text-lg font-black text-slate-800 flex items-center gap-2">
                <Clock className="w-5 h-5 text-indigo-500" /> 重要倒计时
              </h2>
              <button onClick={() => { resetForm(); setShowAddModal('countdown'); }} className="p-1.5 bg-slate-50 hover:bg-slate-100 text-indigo-600 rounded-xl transition">
                <Plus className="w-4 h-4" />
              </button>
            </div>

            <div className="p-4 flex gap-4 overflow-x-auto snap-x hide-scrollbar">
              {countdowns.length === 0 ? (
                  <div className="w-full py-6 text-center text-slate-400 text-sm border-2 border-dashed border-slate-100 rounded-2xl">
                    暂无倒计时，点击右上角添加
                  </div>
              ) : (
                  // 智能过滤排序：未过期的优先展示，过期的沉底
                  countdowns.sort((a, b) => {
                    const daysA = getDaysLeft(a.target_time);
                    const daysB = getDaysLeft(b.target_time);
                    const isPastA = daysA < 0;
                    const isPastB = daysB < 0;
                    if (isPastA && !isPastB) return 1;
                    if (!isPastA && isPastB) return -1;
                    return a.target_time - b.target_time;
                  }).map(c => {
                    const days = getDaysLeft(c.target_time);
                    const isPast = days < 0;
                    return (
                        <div key={c.uuid} className={`shrink-0 w-64 snap-start p-4 rounded-2xl border flex items-center justify-between group relative overflow-hidden ${isPast ? 'bg-slate-50 border-slate-100 opacity-60' : 'bg-white border-slate-200 shadow-sm'}`}>
                          <div className={`absolute top-0 left-0 w-1 h-full rounded-l-full ${isPast ? 'bg-slate-300' : 'bg-indigo-500'}`}></div>
                          <div className="pl-2 min-w-0 pr-2">
                            <p className={`font-bold text-sm truncate ${isPast ? 'text-slate-500 line-through' : 'text-slate-800'}`}>{c.title}</p>
                            <p className="text-xs text-slate-400 mt-1">{new Date(c.target_time).toLocaleDateString()}</p>
                          </div>
                          <div className="text-right shrink-0">
                            <span className={`text-2xl font-black ${isPast ? 'text-slate-400' : 'text-indigo-600'}`}>{Math.abs(days)}</span>
                            <span className="text-[10px] font-bold text-slate-400 ml-0.5">天</span>
                          </div>
                          <button onClick={() => deleteCountdown(c.uuid)} className="absolute top-2 right-2 opacity-0 group-hover:opacity-100 p-1 text-slate-400 hover:text-red-500 bg-white/80 rounded transition">
                            <X className="w-4 h-4" />
                          </button>
                        </div>
                    );
                  })
              )}
            </div>
          </div>

          {/* 待办清单长列表 */}
          <div className="flex-1 flex flex-col bg-white rounded-3xl shadow-sm border border-slate-100 overflow-hidden min-h-[400px] lg:min-h-0">
            <div className="px-4 sm:px-6 py-3 sm:py-4 flex justify-between items-center border-b border-slate-50 shrink-0 bg-white z-10">
              <h2 className="text-lg font-black text-slate-800 flex items-center gap-2">
                <CheckCircle2 className="w-5 h-5 text-emerald-500" />
                待办清单
              </h2>
              <button onClick={() => { resetForm(); setShowAddModal('todo'); }} className="flex items-center gap-1.5 px-4 py-2 bg-slate-900 hover:bg-slate-800 text-white rounded-xl text-sm font-bold transition active:scale-95 shadow-md shadow-slate-900/10">
                <Plus className="w-4 h-4" /> 新增
              </button>
            </div>

            <div className="flex-1 overflow-y-auto p-2 sm:p-4 space-y-2 sm:space-y-4 min-h-0">
              {pastTodos.length > 0 && (
                  <div className="bg-red-50/50 rounded-xl sm:rounded-2xl border border-red-100 p-1.5 sm:p-2">
                    <button onClick={() => setIsPastExpanded(!isPastExpanded)} className="w-full flex items-center gap-2 p-1.5 sm:p-2 text-red-600 hover:bg-red-100/50 rounded-lg sm:rounded-xl transition">
                      {isPastExpanded ? <ChevronDown className="w-4 h-4" /> : <ChevronRight className="w-4 h-4" />}
                      <span className="font-bold text-sm">以往待办 ({pastTodos.length})</span>
                    </button>
                    {isPastExpanded && (
                        <div className="p-1 sm:p-2 space-y-1 sm:space-y-2">
                          {pastTodos.map(t => <TodoCard key={t.uuid} todo={t} isPast={true} isFuture={false} />)}
                        </div>
                    )}
                  </div>
              )}

              <div className="bg-slate-50 rounded-xl sm:rounded-2xl border border-slate-100 p-1.5 sm:p-2">
                <button onClick={() => setIsTodayExpanded(!isTodayExpanded)} className="w-full flex items-center gap-2 p-1.5 sm:p-2 text-slate-600 hover:bg-slate-200/50 rounded-lg sm:rounded-xl transition">
                  {isTodayExpanded ? <ChevronDown className="w-4 h-4" /> : <ChevronRight className="w-4 h-4" />}
                  <span className="font-bold text-sm">
                  今日待办 ({todayTodos.filter(t=>t.is_completed).length}/{todayTodos.length})
                </span>
                </button>
                {isTodayExpanded && (
                    <div className="p-1 sm:p-2 space-y-1 sm:space-y-2">
                      {sortedToday.length === 0 ? (
                          <div className="text-center py-4 sm:py-6 text-sm font-medium text-slate-400">今日暂无待办</div>
                      ) : (
                          sortedToday.map(t => <TodoCard key={t.uuid} todo={t} isPast={false} isFuture={false} />)
                      )}
                    </div>
                )}
              </div>

              {sortedFuture.length > 0 && (
                  <div className="bg-blue-50/50 rounded-xl sm:rounded-2xl border border-blue-100 p-1.5 sm:p-2 flex flex-col min-h-0 shrink-0">
                    <button onClick={() => setIsFutureExpanded(!isFutureExpanded)} className="w-full flex items-center justify-between p-1.5 sm:p-2 text-blue-600 hover:bg-blue-100/50 rounded-lg sm:rounded-xl transition">
                      <div className="flex items-center gap-2">
                        {isFutureExpanded ? <ChevronDown className="w-4 h-4" /> : <ChevronRight className="w-4 h-4" />}
                        <CalendarDays className="w-4 h-4" />
                        <span className="font-bold text-sm">未来待办</span>
                      </div>
                      <span className="text-xs font-bold text-blue-400 mr-2">
                    {sortedFuture.filter(t=>!t.is_completed).length} 未完成
                  </span>
                    </button>
                    {isFutureExpanded && (
                        <div className="p-1 sm:p-2 space-y-1 sm:space-y-2">
                          {sortedFuture.map(t => <TodoCard key={t.uuid} todo={t} isPast={false} isFuture={true} />)}
                        </div>
                    )}
                  </div>
              )}

              {activeTodos.length === 0 && countdowns.length === 0 && (
                  <div className="text-center py-16">
                    <div className="inline-flex items-center justify-center w-16 h-16 bg-slate-100 rounded-full mb-4">
                      <CheckCircle2 className="w-8 h-8 text-slate-300" />
                    </div>
                    <h3 className="text-xl font-black text-slate-800 mb-1">干得漂亮！</h3>
                    <p className="text-slate-500 text-sm">当前没有任何未完成的任务</p>
                  </div>
              )}
            </div>
          </div>
        </div>
      </div>
  );

  const renderSettings = () => {
    const syncProgress = Math.min(100, (syncCountToday / syncLimit) * 100);

    return (
        <div className="max-w-2xl mx-auto space-y-6 animate-in fade-in duration-300 pt-8 px-4 w-full">
          <h2 className="text-3xl font-black text-slate-800 mb-8">账号与设置</h2>

          <div className="bg-white p-8 rounded-3xl shadow-sm border border-slate-100 mb-6">
            <div className="flex justify-between items-start mb-6">
              <div>
                <p className="text-sm font-bold text-slate-400 mb-1 tracking-widest uppercase">当前账号</p>
                <p className="font-black text-3xl text-slate-800">{user.username}</p>
                <p className="text-slate-500 mt-1">{user.email}</p>
              </div>
              <div className={`px-4 py-1.5 rounded-xl text-sm font-bold border ${
                  user.tier === 'pro' ? 'bg-indigo-50 text-indigo-600 border-indigo-100' :
                      user.tier === 'admin' ? 'bg-purple-50 text-purple-600 border-purple-100' :
                          'bg-slate-50 text-slate-600 border-slate-200'
              }`}>
                {user.tier === 'pro' ? 'Pro 专业版' : (user.tier === 'admin' ? 'Admin 管理员' : 'Free 免费版')}
              </div>
            </div>

            <div className="pt-6 border-t border-slate-100">
              <div className="flex justify-between items-end mb-3">
                <div>
                  <p className="text-sm font-bold text-slate-500 mb-1">今日同步次数进度</p>
                  <p className="text-xs text-slate-400">已自动向云端拉取最新统计</p>
                </div>
                <div className="text-right">
                  <span className="text-2xl font-black text-indigo-600">{syncCountToday}</span>
                  <span className="text-sm font-bold text-slate-400 ml-1">/ {syncLimit} 次</span>
                </div>
              </div>
              <div className="w-full h-3 bg-slate-100 rounded-full overflow-hidden">
                <div
                    className={`h-full rounded-full transition-all duration-500 ${syncProgress > 90 ? 'bg-red-500' : 'bg-indigo-500'}`}
                    style={{ width: `${syncProgress}%` }}
                />
              </div>
            </div>
          </div>

          {/* 🚀 新增的：强制全量拉取按钮 */}
          <button
              onClick={handleForceSync}
              disabled={isSyncing}
              className="w-full flex justify-center items-center gap-2 bg-amber-50 text-amber-600 hover:bg-amber-100 font-bold py-5 rounded-2xl transition disabled:opacity-50 active:scale-[0.98]"
          >
            <RefreshCw className={`w-5 h-5 ${isSyncing ? 'animate-spin' : ''}`} />
            {isSyncing ? '正在拉取云端全量数据...' : '强制拉取全量数据 (修复不一致)'}
          </button>

          <button onClick={onLogout} className="w-full flex justify-center items-center gap-2 bg-red-50 text-red-600 hover:bg-red-100 font-bold py-5 rounded-2xl transition active:scale-[0.98]">
            <LogOut className="w-5 h-5" /> 退出当前账号
          </button>
        </div>
    );
  };

  return (
      <div className="min-h-[100dvh] lg:h-[100dvh] bg-slate-50 flex flex-col font-sans selection:bg-indigo-500 selection:text-white lg:overflow-hidden">
        {/* 顶部全屏自适应导航栏 */}
        <header className="bg-white/80 backdrop-blur-xl border-b border-slate-200 z-40 shrink-0">
          <div className="max-w-[1600px] mx-auto px-4 sm:px-6 lg:px-8 h-16 sm:h-20 flex items-center justify-between">
            <div className="flex items-center gap-3 sm:gap-4">
              <button onClick={onBack} className="p-2 hover:bg-slate-100 rounded-full transition text-slate-500" title="返回官网">
                <ArrowLeft className="w-5 h-5 sm:w-6 sm:h-6" />
              </button>
              <div className="flex items-center gap-2 pr-2 sm:pr-4 sm:border-r border-slate-200">
                <div className="bg-indigo-600 p-1.5 rounded-lg">
                  <CheckCircle2 className="text-white w-4 h-4 sm:w-5 sm:h-5" />
                </div>
                <span className="font-black text-lg sm:text-xl text-slate-900">CDT Web</span>
              </div>

              {/* 模块切换导航 (大屏显示) */}
              <div className="hidden sm:flex items-center gap-1">
                <button
                    onClick={() => {setCurrentTab('dashboard'); setMobileTab('home');}}
                    className={`px-4 py-2 rounded-xl text-sm font-bold transition flex items-center gap-2 ${currentTab === 'dashboard' && mobileTab === 'home' ? 'bg-slate-100 text-slate-900' : 'text-slate-500 hover:bg-slate-50'}`}
                >
                  <LayoutDashboard className="w-4 h-4" /> 首页仪表盘
                </button>
                <button
                    onClick={() => {setCurrentTab('screentime'); setMobileTab('home');}}
                    className={`px-4 py-2 rounded-xl text-sm font-bold transition flex items-center gap-2 ${currentTab === 'screentime' && mobileTab === 'home' ? 'bg-indigo-50 text-indigo-700' : 'text-slate-500 hover:bg-slate-50'}`}
                >
                  <PieChartIcon className="w-4 h-4" /> 屏幕时间
                </button>
                <button
                    onClick={() => {setCurrentTab('focus'); setMobileTab('home');}}
                    className={`px-4 py-2 rounded-xl text-sm font-bold transition flex items-center gap-2 ${currentTab === 'focus' && mobileTab === 'home' ? 'bg-red-50 text-red-600' : 'text-slate-500 hover:bg-slate-50'}`}
                >
                  <span>🍅</span> 专注工作台
                </button>
                <button
                    onClick={() => {setCurrentTab('pomodoro'); setMobileTab('home');}}
                    className={`px-4 py-2 rounded-xl text-sm font-bold transition flex items-center gap-2 ${currentTab === 'pomodoro' && mobileTab === 'home' ? 'bg-amber-50 text-amber-700' : 'text-slate-500 hover:bg-slate-50'}`}
                >
                  <Clock className="w-4 h-4" /> 专注统计
                </button>
              </div>
            </div>

            <div className="flex items-center gap-3 sm:gap-6">

              {/* API 限制置顶进度条 */}
              <div className="hidden md:flex flex-col items-end justify-center mr-2 border-r border-slate-200 pr-6">
                <div className="flex items-center gap-2 mb-1.5">
                <span className={`text-[9px] font-black uppercase px-1.5 py-0.5 rounded border ${
                    user.tier === 'pro' ? 'bg-indigo-50 text-indigo-600 border-indigo-100' :
                        user.tier === 'admin' ? 'bg-purple-50 text-purple-600 border-purple-100' :
                            'bg-slate-50 text-slate-500 border-slate-200'
                }`}>
                  {user.tier === 'pro' ? 'PRO' : user.tier === 'admin' ? 'ADMIN' : 'FREE'}
                </span>
                  <span className="text-[11px] font-bold text-slate-500">
                  API 同步: {syncCountToday} / {syncLimit}
                </span>
                </div>
                <div className="w-32 h-1.5 bg-slate-100 rounded-full overflow-hidden flex">
                  <div
                      className={`h-full transition-all duration-500 ${syncCountToday / syncLimit > 0.9 ? 'bg-red-500' : 'bg-indigo-500'}`}
                      style={{ width: `${Math.min(100, (syncCountToday / syncLimit) * 100)}%` }}
                  />
                </div>
              </div>

              <button
                  onClick={handleSync}
                  className={`flex items-center gap-1.5 sm:gap-2 px-3 sm:px-4 py-1.5 sm:py-2 rounded-full text-sm font-bold transition-all ${
                      isSyncing ? 'bg-indigo-50 text-indigo-400 cursor-not-allowed' : 'bg-indigo-50 text-indigo-600 hover:bg-indigo-100 active:scale-95'
                  }`}
              >
                <RefreshCw className={`w-3.5 h-3.5 sm:w-4 sm:h-4 ${isSyncing ? 'animate-spin' : ''}`} />
                <span className="hidden sm:inline">{isSyncing ? '同步中...' : '云端同步'}</span>
                <span className="sm:hidden">{isSyncing ? '同步中' : '同步'}</span>
              </button>

              <div className="h-8 w-px bg-slate-200 hidden sm:block"></div>

              {/* PC端直接点击头像/邮箱进入设置 */}
              <div className="flex items-center gap-3">
                <button onClick={() => setMobileTab('settings')} className="text-right hidden md:block hover:opacity-70 transition cursor-pointer">
                  <p className="text-sm font-bold text-slate-800">{user.username}</p>
                  <p className="text-xs text-slate-500">{user.email}</p>
                </button>
              </div>
            </div>
          </div>
        </header>

        {/* 移动端底部模块切换导航 (包含设置) */}
        <div className="sm:hidden fixed bottom-0 left-0 right-0 bg-white border-t border-slate-200 z-40 px-2 py-2 pb-safe flex justify-around">
          <button onClick={() => {setCurrentTab('dashboard'); setMobileTab('home');}} className={`flex flex-col items-center gap-0.5 p-2 ${currentTab === 'dashboard' && mobileTab === 'home' ? 'text-indigo-600' : 'text-slate-400'}`}>
            <LayoutDashboard className="w-5 h-5" />
            <span className="text-[9px] font-bold">首页</span>
          </button>
          <button onClick={() => {setCurrentTab('screentime'); setMobileTab('home');}} className={`flex flex-col items-center gap-0.5 p-2 ${currentTab === 'screentime' && mobileTab === 'home' ? 'text-indigo-600' : 'text-slate-400'}`}>
            <PieChartIcon className="w-5 h-5" />
            <span className="text-[9px] font-bold">屏幕时间</span>
          </button>
          <button onClick={() => {setCurrentTab('focus'); setMobileTab('home');}} className={`flex flex-col items-center gap-0.5 p-2 ${currentTab === 'focus' && mobileTab === 'home' ? 'text-red-500' : 'text-slate-400'}`}>
            <span className="text-xl leading-none">🍅</span>
            <span className="text-[9px] font-bold">专注</span>
          </button>
          <button onClick={() => {setCurrentTab('pomodoro'); setMobileTab('home');}} className={`flex flex-col items-center gap-0.5 p-2 ${currentTab === 'pomodoro' && mobileTab === 'home' ? 'text-amber-600' : 'text-slate-400'}`}>
            <Clock className="w-5 h-5" />
            <span className="text-[9px] font-bold">统计</span>
          </button>
          <button onClick={() => setMobileTab('settings')} className={`flex flex-col items-center gap-0.5 p-2 ${mobileTab === 'settings' ? 'text-indigo-600' : 'text-slate-400'}`}>
            <UserIcon className="w-5 h-5" />
            <span className="text-[9px] font-bold">设置</span>
          </button>
        </div>

        {/* 主体全屏内容区 */}
        <main className="flex-1 max-w-[1600px] mx-auto w-full p-4 sm:p-6 lg:p-8 pb-24 sm:pb-8 flex flex-col min-h-0 overflow-y-auto lg:overflow-hidden">
          {currentTab === 'dashboard' && mobileTab === 'home' && renderDashboard()}
          {mobileTab === 'settings' && renderSettings()}
          {currentTab === 'screentime' && mobileTab === 'home' && <ScreenTimeView userId={user.id} />}
          {currentTab === 'focus' && mobileTab === 'home' && <PomodoroFocusView userId={user.id} todos={todos} onTodoCompleted={handleTodoCompleted} />}
          {currentTab === 'pomodoro' && mobileTab === 'home' && <PomodoroStatsView userId={user.id} todos={todos} />}
        </main>

        {/* 统一添加弹窗 (Todo / Countdown) */}
        {showAddModal && (
            <div className="fixed inset-0 z-[60] bg-slate-900/40 backdrop-blur-sm flex items-center justify-center p-4 animate-in fade-in duration-200">
              <div className="bg-white w-full max-w-md rounded-[2.5rem] p-8 shadow-2xl animate-in zoom-in-95 duration-200">
                <div className="flex justify-between items-center mb-8">
                  <h4 className="font-black text-2xl text-slate-800">
                    添加{showAddModal === 'todo' ? '待办事项' : '重要倒计时'}
                  </h4>
                  <button onClick={() => setShowAddModal(null)} className="p-2 bg-slate-100 rounded-full text-slate-500 hover:bg-slate-200 transition">
                    <X className="w-5 h-5" />
                  </button>
                </div>

                <div className="space-y-6 mb-8">
                  <div>
                    <label className="text-sm font-bold text-slate-500 ml-1 mb-2 block">标题内容</label>
                    <input
                        type="text"
                        value={newItemTitle}
                        onChange={e => setNewItemTitle(e.target.value)}
                        className="w-full bg-slate-50 border border-slate-200 px-5 py-4 rounded-2xl text-slate-800 focus:outline-none focus:ring-2 focus:ring-indigo-500/50 focus:bg-white transition text-lg font-medium"
                        placeholder="输入内容..."
                        autoFocus
                    />
                  </div>

                  {showAddModal === 'todo' && (
                      <div>
                        <label className="text-sm font-bold text-slate-500 ml-1 mb-2 block">开始时间 (必填)</label>
                        <input
                            type="datetime-local"
                            value={newStartDate}
                            onChange={e => setNewStartDate(e.target.value)}
                            className="w-full bg-slate-50 border border-slate-200 px-5 py-4 rounded-2xl text-slate-800 focus:outline-none focus:ring-2 focus:ring-indigo-500/50 focus:bg-white transition font-medium"
                        />
                      </div>
                  )}

                  {showAddModal === 'todo' && (
                      <div>
                        <label className="text-sm font-bold text-slate-500 ml-1 mb-2 block">备注 (可选)</label>
                        <textarea
                            value={newRemark}
                            onChange={e => setNewRemark(e.target.value)}
                            rows={2}
                            className="w-full bg-slate-50 border border-slate-200 px-5 py-3 rounded-2xl text-slate-800 focus:outline-none focus:ring-2 focus:ring-indigo-500/50 focus:bg-white transition font-medium resize-none text-sm placeholder:text-slate-400"
                            placeholder="添加备注信息..."
                        />
                      </div>
                  )}

                  <div>
                    <label className="text-sm font-bold text-slate-500 ml-1 mb-2 block">
                      {showAddModal === 'todo' ? '截止时间 (可选)' : '目标日期 (必填)'}
                    </label>
                    <input
                        type={showAddModal === 'todo' ? 'datetime-local' : 'date'}
                        value={newDueDate}
                        onChange={e => setNewDueDate(e.target.value)}
                        className="w-full bg-slate-50 border border-slate-200 px-5 py-4 rounded-2xl text-slate-800 focus:outline-none focus:ring-2 focus:ring-indigo-500/50 focus:bg-white transition font-medium"
                    />
                  </div>
                </div>

                <button
                    onClick={showAddModal === 'todo' ? handleAddTodo : handleAddCountdown}
                    className="w-full bg-indigo-600 text-white font-black text-lg py-4 rounded-2xl hover:bg-indigo-700 transition shadow-xl shadow-indigo-500/30 active:scale-[0.98]"
                >
                  保存并同步
                </button>
              </div>
            </div>
        )}

        {/* 编辑待办弹窗 */}
        {editingTodo && (
            <div className="fixed inset-0 z-[60] bg-slate-900/40 backdrop-blur-sm flex items-center justify-center p-4 animate-in fade-in duration-200">
              <div className="bg-white w-full max-w-md rounded-[2.5rem] p-8 shadow-2xl animate-in zoom-in-95 duration-200">
                <div className="flex justify-between items-center mb-8">
                  <h4 className="font-black text-2xl text-slate-800">编辑待办事项</h4>
                  <button onClick={() => setEditingTodo(null)} className="p-2 bg-slate-100 rounded-full text-slate-500 hover:bg-slate-200 transition">
                    <X className="w-5 h-5" />
                  </button>
                </div>

                <div className="space-y-5 mb-8">
                  <div>
                    <label className="text-sm font-bold text-slate-500 ml-1 mb-2 block">待办内容</label>
                    <input
                        type="text"
                        value={editTitle}
                        onChange={e => setEditTitle(e.target.value)}
                        className="w-full bg-slate-50 border border-slate-200 px-5 py-4 rounded-2xl text-slate-800 focus:outline-none focus:ring-2 focus:ring-indigo-500/50 focus:bg-white transition text-lg font-medium"
                        placeholder="输入内容..."
                        autoFocus
                    />
                  </div>

                  <div>
                    <label className="text-sm font-bold text-slate-500 ml-1 mb-2 block">备注 (可选)</label>
                    <textarea
                        value={editRemark}
                        onChange={e => setEditRemark(e.target.value)}
                        rows={2}
                        className="w-full bg-slate-50 border border-slate-200 px-5 py-3 rounded-2xl text-slate-800 focus:outline-none focus:ring-2 focus:ring-indigo-500/50 focus:bg-white transition font-medium resize-none text-sm placeholder:text-slate-400"
                        placeholder="添加备注信息..."
                    />
                  </div>

                  <div>
                    <label className="text-sm font-bold text-slate-500 ml-1 mb-2 block">开始时间</label>
                    <input
                        type="datetime-local"
                        value={editStartDate}
                        onChange={e => setEditStartDate(e.target.value)}
                        className="w-full bg-slate-50 border border-slate-200 px-5 py-4 rounded-2xl text-slate-800 focus:outline-none focus:ring-2 focus:ring-indigo-500/50 focus:bg-white transition font-medium"
                    />
                  </div>

                  <div>
                    <label className="text-sm font-bold text-slate-500 ml-1 mb-2 block">截止时间 (可选)</label>
                    <input
                        type="datetime-local"
                        value={editDueDate}
                        onChange={e => setEditDueDate(e.target.value)}
                        className="w-full bg-slate-50 border border-slate-200 px-5 py-4 rounded-2xl text-slate-800 focus:outline-none focus:ring-2 focus:ring-indigo-500/50 focus:bg-white transition font-medium"
                    />
                    {editDueDate && (
                        <button
                            onClick={() => setEditDueDate('')}
                            className="mt-2 ml-1 text-xs text-slate-400 hover:text-red-400 transition font-medium"
                        >
                          × 清除截止时间
                        </button>
                    )}
                  </div>
                </div>

                <button
                    onClick={handleSaveTodoEdit}
                    disabled={!editTitle.trim()}
                    className="w-full bg-indigo-600 text-white font-black text-lg py-4 rounded-2xl hover:bg-indigo-700 transition shadow-xl shadow-indigo-500/30 active:scale-[0.98] disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  保存修改
                </button>
              </div>
            </div>
        )}

        {/* 版本更新弹窗 (置于最高层级 z-[70]) */}
        {updateInfo && (
            <div className="fixed inset-0 z-[70] bg-slate-900/60 backdrop-blur-sm flex items-center justify-center p-4 animate-in fade-in duration-300">
              <div className="bg-white w-full max-w-sm rounded-[2.5rem] p-8 shadow-2xl flex flex-col items-center text-center animate-in zoom-in-95 duration-300">
                <div className="w-16 h-16 bg-blue-50 text-blue-600 rounded-full flex items-center justify-center mb-6">
                  <RefreshCw className="w-8 h-8" />
                </div>
                <h3 className="text-2xl font-black text-slate-800 mb-2">{updateInfo.title}</h3>
                <p className="text-sm font-bold text-slate-400 mb-6 bg-slate-50 px-4 py-1 rounded-full border border-slate-100">
                  v{CURRENT_WEB_VERSION} ➔ v{updateInfo.version}
                </p>
                <p className="text-slate-600 leading-relaxed mb-8 whitespace-pre-line font-medium">
                  {updateInfo.desc}
                </p>
                <button
                    onClick={() => window.location.reload()}
                    className="w-full bg-blue-600 text-white font-black text-lg py-4 rounded-2xl hover:bg-blue-700 transition shadow-xl shadow-blue-600/30 active:scale-[0.98] flex items-center justify-center gap-2"
                >
                  <RefreshCw className="w-5 h-5" /> 立即刷新更新
                </button>
                <button
                    onClick={() => setUpdateInfo(null)}
                    className="mt-4 text-sm font-bold text-slate-400 hover:text-slate-600 transition"
                >
                  稍后提醒我
                </button>
              </div>
            </div>
        )}
      </div>
  );
};