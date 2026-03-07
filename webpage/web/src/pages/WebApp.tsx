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
const CURRENT_WEB_VERSION = "1.0.0"; // 当前网页版的硬编码版本号

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
// 屏幕时间组件
// --------------------------------------------------------
const ScreenTimeView = ({ userId }: { userId: number }) => {
  const [stats, setStats] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [filter, setFilter] = useState<'all' | 'pc' | 'mobile'>('all');
  const [selectedDate] = useState(new Date());

  useEffect(() => {
    fetchStats();
  }, [selectedDate]);

  const fetchStats = async () => {
    setLoading(true);
    try {
      const dateStr = selectedDate.toISOString().split('T')[0];
      const data = await ApiService.request(`/api/screen_time?user_id=${userId}&date=${dateStr}`, { method: 'GET' });
      setStats(data || []);
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
  }, {} as Record<string, any>);

  const topApps = Object.entries(appGroups)
    .map(([name, data]: [string, any]) => ({
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
        <div className="flex items-center gap-2 bg-slate-100 p-1.5 rounded-xl shrink-0">
          <button onClick={() => setFilter('all')} className={`px-4 py-2 rounded-lg text-sm font-bold transition ${filter === 'all' ? 'bg-white shadow-sm text-indigo-600' : 'text-slate-500 hover:text-slate-700'}`}>全部</button>
          <button onClick={() => setFilter('pc')} className={`px-4 py-2 rounded-lg text-sm font-bold transition flex items-center gap-1 ${filter === 'pc' ? 'bg-white shadow-sm text-blue-600' : 'text-slate-500 hover:text-slate-700'}`}><Monitor className="w-4 h-4" /> 电脑</button>
          <button onClick={() => setFilter('mobile')} className={`px-4 py-2 rounded-lg text-sm font-bold transition flex items-center gap-1 ${filter === 'mobile' ? 'bg-white shadow-sm text-purple-600' : 'text-slate-500 hover:text-slate-700'}`}><Smartphone className="w-4 h-4" /> 移动端</button>
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
  const [courses, setCourses] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [currentWeek, setCurrentWeek] = useState(1);
  const [semesterMonday, setSemesterMonday] = useState(new Date());

  // 0: 混合查看, 1: 只看课表, 2: 只看待办
  const [viewMode, setViewMode] = useState<0 | 1 | 2>(0);
  const [showViewMenu, setShowViewMenu] = useState(false);

  // 详情弹窗状态
  const [detailItem, setDetailItem] = useState<{type: 'course'|'todo'|'countdown'|'multi', data: any} | null>(null);
  const [multiParent, setMultiParent] = useState<{type: 'course'|'todo'|'countdown'|'multi', data: any} | null>(null);

  const startHour = 8;
  const endHour = 22;
  const totalMins = (endHour - startHour) * 60;

  useEffect(() => {
    fetchCourses();
  }, []);

  const fetchCourses = async () => {
    setLoading(true);
    try {
      const data = await ApiService.request(`/api/courses?user_id=${userId}`, { method: 'GET' });
      setCourses(data || []);

      let activeWeek = 1;
      if (data && data.length > 0) {
         const minWeek = Math.min(...data.map((c:any) => c.week_index));
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
    const all = { 1:[], 2:[], 3:[], 4:[], 5:[], 6:[], 7:[] } as Record<number, any[]>;
    const intra = { 1:[], 2:[], 3:[], 4:[], 5:[], 6:[], 7:[] } as Record<number, any[]>;

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
            {type === 'course' && (
              <>
                <h3 className="text-2xl font-black text-slate-800 leading-tight mb-2">{data.course_name}</h3>
                <div className="space-y-3 bg-slate-50 p-5 rounded-2xl border border-slate-100">
                  <div className="flex items-center gap-3 text-slate-600">
                    <MapPin className="w-5 h-5 text-blue-400" />
                    <span className="font-bold">{data.room_name || '未安排教室'}</span>
                  </div>
                  <div className="flex items-center gap-3 text-slate-600">
                    <UserIcon className="w-5 h-5 text-blue-400" />
                    <span className="font-bold">{data.teacher_name || '未知讲师'}</span>
                  </div>
                  <div className="flex items-center gap-3 text-slate-600">
                    <Clock className="w-5 h-5 text-blue-400" />
                    <span className="font-bold">
                      周{data.weekday} {formatTimeNum(data.start_time)} - {formatTimeNum(data.end_time)}
                    </span>
                  </div>
                  <div className="flex items-center gap-3 text-slate-600">
                    <Hash className="w-5 h-5 text-blue-400" />
                    <span className="font-bold">第 {data.week_index} 周</span>
                  </div>
                </div>
              </>
            )}

            {type === 'todo' && (
              <>
                <h3 className="text-2xl font-black text-slate-800 leading-tight mb-2">{data.content}</h3>
                <div className="space-y-3 bg-slate-50 p-5 rounded-2xl border border-slate-100">
                  <div className="flex items-center gap-3 text-slate-600">
                    <Flag className="w-5 h-5 text-emerald-500" />
                    <span className="font-bold">{data.is_completed ? '已完成' : '进行中'}</span>
                  </div>
                  <div className="flex items-center gap-3 text-slate-600">
                    <PlayCircle className="w-5 h-5 text-emerald-500" />
                    <span className="font-bold text-sm">开始: {formatDt(new Date(data.created_date ?? data.created_at))}</span>
                  </div>
                  <div className="flex items-center gap-3 text-slate-600">
                    <StopCircle className="w-5 h-5 text-emerald-500" />
                    <span className="font-bold text-sm">截止: {data.due_date ? formatDt(new Date(data.due_date)) : '无限制'}</span>
                  </div>
                  <div className="flex items-center gap-3 text-slate-600">
                    <RefreshCw className="w-5 h-5 text-emerald-500" />
                    <span className="font-bold text-sm">最近同步: {formatDt(new Date(data.updated_at))}</span>
                  </div>
                </div>
              </>
            )}

            {type === 'countdown' && (() => {
               const daysLeft = getDaysLeftLocal(data.target_time);
               const isPast = daysLeft < 0;
               return (
                 <>
                  <h3 className="text-2xl font-black text-slate-800 leading-tight mb-2">{data.title}</h3>
                  <div className="space-y-3 bg-slate-50 p-5 rounded-2xl border border-slate-100">
                    <div className="flex items-center justify-between text-slate-600">
                      <div className="flex items-center gap-3">
                        <Clock className="w-5 h-5 text-amber-500" />
                        <span className="font-bold">目标日: {new Date(data.target_time).toLocaleDateString()}</span>
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
               )
            })()}

            {type === 'multi' && (
              <div className="space-y-2">
                <p className="text-sm font-bold text-slate-500 mb-3">此日包含多项全天任务，请选择查看：</p>
                {data.map((item: any, idx: number) => (
                  <button
                    key={idx}
                    onClick={() => {
                       setMultiParent(detailItem); // 记住父级状态
                       setDetailItem(item); // 钻入子级
                    }}
                    className="w-full text-left bg-slate-50 hover:bg-slate-100 p-4 rounded-2xl border border-slate-200 transition flex items-center gap-3 group"
                  >
                    {item.type === 'todo' ? <CheckCircle2 className="w-5 h-5 text-emerald-500" /> : <Clock className="w-5 h-5 text-amber-500" />}
                    <span className="font-bold text-slate-700 flex-1 truncate group-hover:text-indigo-600 transition">
                      {item.type === 'todo' ? item.data.content : item.data.title}
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
                  <button key={v} onClick={() => { setViewMode(v as any); setShowViewMenu(false); }} className={`w-full text-left px-4 py-2 text-sm font-bold hover:bg-slate-50 transition ${viewMode === v ? 'text-blue-600' : 'text-slate-600'}`}>
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
        <div className="flex-1 flex flex-col min-h-0 relative">
          {/* 星期与日期头 */}
          <div className="flex ml-10 sm:ml-12 pr-2 py-1.5 sm:py-2 bg-white z-10 relative border-b border-slate-50 shrink-0">
            {weekdays.map((day, i) => {
              const d = weekDates[i];
              const isToday = d.toDateString() === new Date().toDateString();
              return (
                <div key={day} className="flex-1 flex flex-col items-center">
                  <span className={`text-[9px] sm:text-[11px] font-bold ${isToday ? 'text-blue-600' : 'text-slate-500'}`}>{day}</span>
                  <span className={`text-[8px] sm:text-[10px] font-medium ${isToday ? 'text-blue-500' : 'text-slate-400'}`}>{d.getMonth()+1}/{d.getDate()}</span>
                </div>
              );
            })}
          </div>

          {/* 全天事件吸顶区 */}
          {hasAnyAllDay && viewMode !== 1 && (
            <div className="flex ml-10 sm:ml-12 pr-2 pb-1.5 bg-white z-10 relative shrink-0 border-b border-slate-50">
              {Array.from({length: 7}).map((_, i) => {
                const items = allDayItems[i+1];
                if (!items || items.length === 0) return <div key={i} className="flex-1 px-0.5"></div>;
                const text = items.length === 1 ? (items[0].data.title || items[0].data.content) : `${items.length}项全天`;
                const isAllDone = items.every(x => x.type === 'todo' && x.data.is_completed);
                return (
                  <div key={i} className="flex-1 px-0.5 flex flex-col justify-end">
                     <button
                        onClick={() => {
                           if (items.length === 1) {
                             setDetailItem(items[0]);
                           } else {
                             setDetailItem({ type: 'multi', data: items });
                           }
                        }}
                        className={`w-full text-[8px] sm:text-[10px] text-white text-center rounded py-0.5 px-0.5 sm:px-1 shadow-sm transition hover:scale-[1.02] ${isAllDone ? 'bg-green-500/80 line-through' : 'bg-amber-500/90'}`}
                     >
                       <span className="block truncate w-full">{text}</span>
                     </button>
                  </div>
                );
              })}
            </div>
          )}

          {/* 绝对自适应时间轴网格 */}
          <div className="flex-1 relative ml-10 sm:ml-12 mr-2 mb-2 mt-2 bg-slate-50/30 border border-slate-100 rounded-xl overflow-hidden shadow-inner min-h-[400px] lg:min-h-0">
            {/* 横向时间线 */}
            {Array.from({ length: endHour - startHour + 1 }).map((_, i) => (
              <div key={`grid-line-${i}`} className="absolute w-full border-t border-slate-200/60" style={{ top: `${(i * 60 / totalMins) * 100}%` }}>
                <span className="absolute -top-2 -left-8 sm:-left-10 text-[9px] sm:text-[10px] font-bold text-slate-400 w-6 sm:w-8 text-right">{startHour + i}:00</span>
              </div>
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
                 <div key={`c-${course.id}`} className="absolute p-[1px] sm:p-0.5" style={{ top: `${top}%`, height: `${height}%`, left: `${left}%`, width: `${100/7}%` }}>
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
                     <div key={`t-${t.uuid}`} className="absolute p-[1px] sm:p-0.5 z-10" style={{ top: `${top}%`, height: `${height}%`, left: `calc(${baseLeft}% + ${stackIndex * 3}px)`, width: `calc(${100/7}% - ${stackIndex * 3}px)` }}>
                       <button
                         onClick={() => setDetailItem(item)}
                         className={`w-full h-full text-left rounded shadow-sm border border-white p-0.5 sm:p-1 flex flex-col overflow-hidden transition-transform hover:scale-[1.05] hover:z-30 hover:shadow-md ${t.is_completed ? 'bg-green-500/60' : 'bg-amber-500/90'}`}
                       >
                         <div className="flex items-start gap-0.5">
                            <CheckCircle2 className="w-2.5 h-2.5 sm:w-3 sm:h-3 text-white shrink-0 mt-[1px]" />
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
                         <div className="absolute w-full border-t-[1.5px] border-red-400 z-30 pointer-events-none shadow-sm" style={{ top: `${top}%` }} />
                         <div className="absolute w-2 h-2 bg-red-500 rounded-full z-30 pointer-events-none" style={{ top: `calc(${top}% - 3px)`, left: `calc(${left}% - 2px)` }} />
                       </>
                     );
                 }
               }
               return null;
            })()}
          </div>

          {/* 渲染详情弹窗 */}
          {renderDetailModal()}
        </div>
      )}
    </div>
  );
};


// --------------------------------------------------------
// 主应用组件 (WebApp)
// --------------------------------------------------------
export const WebApp = ({ onBack, user, onLogout }: { onBack: () => void, user: User, onLogout: () => void }) => {
  const [currentTab, setCurrentTab] = useState<'dashboard' | 'screentime'>('dashboard');
  const [todos, setTodos] = useState<TodoItem[]>([]);
  const [countdowns, setCountdowns] = useState<CountdownItem[]>([]);
  const [showAddModal, setShowAddModal] = useState<'todo' | 'countdown' | null>(null);

  const [newItemTitle, setNewItemTitle] = useState('');
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
    setTodos(SyncEngine.getLocalTodos().filter(t => !t.is_deleted));
    setCountdowns(SyncEngine.getLocalCountdowns().filter(c => !c.is_deleted));
  };

  // 🚀 核心修复：请求正确的后端 API 路径 /api/user/status
  const fetchSyncStats = async () => {
    try {
       const res = await ApiService.request(`/api/user/status?user_id=${user.id}`, { method: 'GET' });
       if (res && typeof res.sync_count !== 'undefined') {
           setSyncCountToday(res.sync_count);
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

  // --- 新增：强制拉取全量数据 ---
  const handleForceSync = async () => {
    if (isSyncing) return;
    if (!window.confirm("强制全量同步将清除本地同步记录，并从云端重新拉取所有最新数据。\n\n这通常用于解决多设备数据不一致的问题。确定要继续吗？")) return;

    setIsSyncing(true);
    try {
      SyncEngine.resetSync(); // 关键：重置水位线，强迫后端下发全量
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

  const durationMinutes = (t: TodoItem) => {
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
    const mins = (endMs - start) / 60000;
    return mins <= 0 ? 1 : mins;
  };

  const getTodayStartMs = () => {
    const d = new Date();
    d.setHours(0, 0, 0, 0);
    return d.getTime();
  };

  const isHistorical = (t: TodoItem) => {
    if (!t.is_completed) return false;
    const todayMs = getTodayStartMs();
    let d = new Date(t.due_date ?? (t.created_date ?? t.created_at));
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
      const pa = calcProgress(a);
      const pb = calcProgress(b);
      if (pb !== pa) return pb - pa;
      return durationMinutes(a) - durationMinutes(b);
    }),
    ...todayTodos.filter(t => t.is_completed)
  ];

  const sortedFuture = [
    ...futureTodos.filter(t => !t.is_completed).sort((a, b) => {
      const pa = calcProgress(a);
      const pb = calcProgress(b);
      if (pb !== pa) return pb - pa;
      const da = a.due_date || 9999999999999;
      const db = b.due_date || 9999999999999;
      return da - db;
    }),
    ...futureTodos.filter(t => t.is_completed)
  ];

  const handleAddTodo = () => {
    if (!newItemTitle.trim()) return;
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
      device_id: ApiService.getDeviceId()
    };

    const all = SyncEngine.getLocalTodos();
    all.unshift(newTodo);
    SyncEngine.setLocalTodos(all);
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
    const all = SyncEngine.getLocalCountdowns();
    all.push(newC);
    SyncEngine.setLocalCountdowns(all);
    loadLocalData();
    setShowAddModal(null);
    resetForm();
    handleSync();
  };

  const resetForm = () => {
    setNewItemTitle('');
    setNewStartDate(toDatetimeLocal(Date.now()));
    setNewDueDate('');
  };

  const toggleTodo = (uuid: string) => {
    const all = SyncEngine.getLocalTodos();
    const target = all.find(t => t.uuid === uuid);
    if (target) {
      target.is_completed = !target.is_completed;
      target.version++;
      target.updated_at = Date.now();
      SyncEngine.setLocalTodos(all);
      loadLocalData();
      handleSync();
    }
  };

  const deleteTodo = (uuid: string) => {
    const all = SyncEngine.getLocalTodos();
    const target = all.find(t => t.uuid === uuid);
    if (target) {
      target.is_deleted = true;
      target.version++;
      target.updated_at = Date.now();
      SyncEngine.setLocalTodos(all);
      loadLocalData();
      handleSync();
    }
  };

  const deleteCountdown = (uuid: string) => {
    const all = SyncEngine.getLocalCountdowns();
    const target = all.find(t => t.uuid === uuid);
    if (target) {
      target.is_deleted = true;
      target.version++;
      target.updated_at = Date.now();
      SyncEngine.setLocalCountdowns(all);
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

    let dateStr = "";
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
      <div className={`relative group flex items-start gap-4 p-4 rounded-2xl transition-all duration-300 ${
        todo.is_completed
          ? 'bg-slate-100/50 border border-transparent'
          : `bg-white shadow-sm border border-slate-200 ${isPast ? 'border-red-100' : ''}`
      }`}>
        <button
          onClick={() => toggleTodo(todo.uuid)}
          className={`mt-1 flex-shrink-0 w-6 h-6 rounded-full border-2 flex items-center justify-center transition-colors ${
            todo.is_completed ? 'bg-emerald-500 border-emerald-500 text-white' : 'border-slate-300 text-transparent hover:border-emerald-400'
          }`}
        >
          <Check className="w-4 h-4" />
        </button>

        <div className="flex-1 min-w-0">
          <p className={`text-base font-semibold truncate ${
            todo.is_completed ? 'text-slate-400 line-through' : (isPast || isFuture ? 'text-slate-600 font-medium' : 'text-slate-800')
          }`}>
            {todo.content}
          </p>
          <div className="mt-2 space-y-2">
            <p className={`text-xs ${todo.is_completed ? 'text-slate-400' : (isPast ? 'text-red-500 font-medium' : 'text-slate-500')}`}>
              {dateStr}
            </p>
            <div className="flex items-center gap-3">
              <div className="flex-1 h-1.5 bg-slate-100 rounded-full overflow-hidden">
                <div
                  className={`h-full rounded-full transition-all duration-500 ${todo.is_completed ? 'bg-slate-300' : 'bg-indigo-600'}`}
                  style={{ width: `${progress * 100}%` }}
                />
              </div>
              <span className={`text-[11px] font-bold ${todo.is_completed ? 'text-slate-400' : (isPast ? 'text-red-500' : 'text-slate-500')}`}>
                {Math.floor(progress * 100)}%
              </span>
            </div>
          </div>
        </div>

        <button
          onClick={() => deleteTodo(todo.uuid)}
          className="opacity-0 group-hover:opacity-100 p-2 text-slate-300 hover:text-red-500 hover:bg-red-50 rounded-xl transition"
        >
          <Trash2 className="w-5 h-5" />
        </button>
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
          <div className="px-6 py-4 flex justify-between items-center border-b border-slate-50 shrink-0 bg-white z-10">
            <h2 className="text-lg font-black text-slate-800 flex items-center gap-2">
              <CheckCircle2 className="w-5 h-5 text-emerald-500" />
              待办清单
            </h2>
            <button onClick={() => { resetForm(); setShowAddModal('todo'); }} className="flex items-center gap-1.5 px-4 py-2 bg-slate-900 hover:bg-slate-800 text-white rounded-xl text-sm font-bold transition active:scale-95 shadow-md shadow-slate-900/10">
              <Plus className="w-4 h-4" /> 新增
            </button>
          </div>

          <div className="flex-1 overflow-y-auto p-4 space-y-4 min-h-0">
            {pastTodos.length > 0 && (
              <div className="bg-red-50/50 rounded-2xl border border-red-100 p-2">
                <button onClick={() => setIsPastExpanded(!isPastExpanded)} className="w-full flex items-center gap-2 p-2 text-red-600 hover:bg-red-100/50 rounded-xl transition">
                  {isPastExpanded ? <ChevronDown className="w-4 h-4" /> : <ChevronRight className="w-4 h-4" />}
                  <span className="font-bold text-sm">以往待办 ({pastTodos.length})</span>
                </button>
                {isPastExpanded && (
                  <div className="p-2 space-y-2">
                    {pastTodos.map(t => <TodoCard key={t.uuid} todo={t} isPast={true} isFuture={false} />)}
                  </div>
                )}
              </div>
            )}

            <div className="bg-slate-50 rounded-2xl border border-slate-100 p-2">
              <button onClick={() => setIsTodayExpanded(!isTodayExpanded)} className="w-full flex items-center gap-2 p-2 text-slate-600 hover:bg-slate-200/50 rounded-xl transition">
                {isTodayExpanded ? <ChevronDown className="w-4 h-4" /> : <ChevronRight className="w-4 h-4" />}
                <span className="font-bold text-sm">
                  今日待办 ({todayTodos.filter(t=>t.is_completed).length}/{todayTodos.length})
                </span>
              </button>
              {isTodayExpanded && (
                <div className="p-2 space-y-2">
                  {sortedToday.length === 0 ? (
                    <div className="text-center py-6 text-sm font-medium text-slate-400">今日暂无待办</div>
                  ) : (
                    sortedToday.map(t => <TodoCard key={t.uuid} todo={t} isPast={false} isFuture={false} />)
                  )}
                </div>
              )}
            </div>

            {sortedFuture.length > 0 && (
              <div className="bg-blue-50/50 rounded-2xl border border-blue-100 p-2 flex flex-col min-h-0 shrink-0">
                <button onClick={() => setIsFutureExpanded(!isFutureExpanded)} className="w-full flex items-center justify-between p-2 text-blue-600 hover:bg-blue-100/50 rounded-xl transition">
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
                  <div className="p-2 space-y-2">
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
                onClick={() => setCurrentTab('screentime')}
                className={`px-4 py-2 rounded-xl text-sm font-bold transition flex items-center gap-2 ${currentTab === 'screentime' ? 'bg-indigo-50 text-indigo-700' : 'text-slate-500 hover:bg-slate-50'}`}
              >
                <PieChartIcon className="w-4 h-4" /> 屏幕时间
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
              <button onClick={() => {setMobileTab('settings'); setCurrentTab('dashboard');}} className="text-right hidden md:block hover:opacity-70 transition cursor-pointer">
                <p className="text-sm font-bold text-slate-800">{user.username}</p>
                <p className="text-xs text-slate-500">{user.email}</p>
              </button>
            </div>
          </div>
        </div>
      </header>

      {/* 移动端底部模块切换导航 (包含设置) */}
      <div className="sm:hidden fixed bottom-0 left-0 right-0 bg-white border-t border-slate-200 z-40 px-4 py-2 pb-safe flex justify-around">
        <button onClick={() => {setCurrentTab('dashboard'); setMobileTab('home');}} className={`flex flex-col items-center gap-1 p-2 ${currentTab === 'dashboard' && mobileTab === 'home' ? 'text-indigo-600' : 'text-slate-400'}`}>
          <LayoutDashboard className="w-5 h-5" />
          <span className="text-[10px] font-bold">首页</span>
        </button>
        <button onClick={() => setCurrentTab('screentime')} className={`flex flex-col items-center gap-1 p-2 ${currentTab === 'screentime' ? 'text-indigo-600' : 'text-slate-400'}`}>
          <PieChartIcon className="w-5 h-5" />
          <span className="text-[10px] font-bold">屏幕时间</span>
        </button>
        <button onClick={() => {setCurrentTab('dashboard'); setMobileTab('settings');}} className={`flex flex-col items-center gap-1 p-2 ${mobileTab === 'settings' ? 'text-indigo-600' : 'text-slate-400'}`}>
          <UserIcon className="w-5 h-5" />
          <span className="text-[10px] font-bold">设置</span>
        </button>
      </div>

      {/* 主体全屏内容区 */}
      <main className="flex-1 max-w-[1600px] mx-auto w-full p-4 sm:p-6 lg:p-8 pb-24 sm:pb-8 flex flex-col min-h-0 overflow-y-auto lg:overflow-hidden">
        {currentTab === 'dashboard' && mobileTab === 'home' && renderDashboard()}
        {mobileTab === 'settings' && renderSettings()}
        {currentTab === 'screentime' && mobileTab !== 'settings' && <ScreenTimeView userId={user.id} />}
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