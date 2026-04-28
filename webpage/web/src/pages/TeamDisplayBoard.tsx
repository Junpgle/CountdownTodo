import React, { useState, useEffect, useCallback, useRef, useMemo } from 'react';
import { ApiService } from '../services/api';
import { SyncEngine } from '../services/sync';
import { readDayCache, writeDayCache } from './webapp-utils';
import { Search, ZoomIn, ZoomOut, Minus, Plus, X, Clock, Calendar, User as UserIcon, CheckCircle2, BookOpen, AlertCircle, RefreshCcw, Tag, Layers, ArrowRight, ArrowLeft } from 'lucide-react';

interface User {
  id: number;
  username: string;
  email: string;
  avatar_url?: string;
}

interface Team {
  uuid: string;
  name: string;
  role: number;
  member_count: number;
}

interface TeamMember {
  user_id: number;
  username: string;
  email: string;
  role: number;
  avatar_url?: string;
  joined_at?: number;
}

interface Todo {
  uuid: string;
  content: string;
  due_date: number | null;
  created_date: number | null;
  created_at: number;
  is_completed: number | boolean;
  collab_type: number;
  creator_name?: string;
  team_uuid?: string | null;
  team_name?: string | null;
  user_id?: number;
  description?: string;
  remark?: string;
  recurrence?: number;
  reminder_minutes?: number;
  is_all_day?: boolean | number;
  category_id?: string | null;
  is_deleted?: boolean | number;
}

interface Course {
  id: number;
  course_name: string;
  room_name: string;
  teacher_name: string;
  start_time: number;
  end_time: number;
  weekday: number;
  week_index: number;
  lesson_type: string;
}

interface Countdown {
  uuid: string;
  title: string;
  target_time: number;
  team_uuid?: string | null;
  user_id?: number;
}

interface TeamAnnouncement {
  uuid: string;
  title: string;
  content: string;
  is_priority: boolean | number;
  created_at: number;
  creator_name?: string;
}

const GlassCard: React.FC<{ children: React.ReactNode; className?: string; title?: string; headerExtra?: React.ReactNode }> = ({ children, className, title, headerExtra }) => (
  <div className={`backdrop-blur-xl bg-white/5 border border-white/10 rounded-[2.5rem] p-6 shadow-2xl overflow-hidden relative group transition-all duration-500 hover:bg-white/10 flex flex-col ${className}`}>
    <div className="absolute top-0 left-0 w-full h-1 bg-gradient-to-r from-transparent via-blue-500/20 to-transparent opacity-0 group-hover:opacity-100 transition-opacity" />
    {title && (
      <div className="flex items-center justify-between mb-4 shrink-0 px-1">
        <h3 className="text-xl font-black bg-clip-text text-transparent bg-gradient-to-r from-white to-white/40 tracking-tight flex items-center gap-2">
          {title}
        </h3>
        {headerExtra}
      </div>
    )}
    <div className="flex-1 min-h-0">
      {children}
    </div>
  </div>
);

const AnimatedBackground = () => (
  <div className="fixed inset-0 -z-10 bg-[#020617] overflow-hidden">
    <div className="absolute top-[-5%] left-[-5%] w-[40%] h-[40%] rounded-full bg-blue-600/10 blur-[120px] animate-pulse" />
    <div className="absolute bottom-[-5%] right-[-5%] w-[40%] h-[40%] rounded-full bg-indigo-600/10 blur-[120px] animate-pulse" style={{ animationDelay: '2s' }} />
    <svg className="absolute inset-0 w-full h-full opacity-[0.02]" xmlns="http://www.w3.org/2000/svg">
      <filter id="noise"><feTurbulence type="fractalNoise" baseFrequency="0.6" numOctaves="3" /></filter>
      <rect width="100%" height="100%" filter="url(#noise)" />
    </svg>
  </div>
);

const TodayHourlyTimeline: React.FC<{ todos: Todo[], courses: Course[], semesterStart?: number, onTaskClick: (task: Todo) => void }> = ({ todos, courses, semesterStart, onTaskClick }) => {
  const hours = Array.from({ length: 24 }, (_, i) => i);
  const now = new Date();
  const todayStart = new Date().setHours(0,0,0,0);
  const todayEnd = new Date().setHours(23,59,59,999);
  const currentWeekday = now.getDay();

  const currentWeek = useMemo(() => {
    if (!semesterStart || isNaN(Number(semesterStart)) || Number(semesterStart) <= 0) return 1; // 默认第一周
    const startDate = new Date(Number(semesterStart));
    const startDayOfWeek = startDate.getDay() || 7; 
    const firstMonday = new Date(startDate);
    firstMonday.setDate(startDate.getDate() - startDayOfWeek + 1);
    firstMonday.setHours(0, 0, 0, 0);

    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const diffDays = Math.floor((today.getTime() - firstMonday.getTime()) / 86400000);
    const week = diffDays >= 0 ? Math.floor(diffDays / 7) + 1 : 1;
    return week;
  }, [semesterStart]);

  const todayCourses = useMemo(() => {
    const jsDay = currentWeekday === 0 ? 7 : currentWeekday;
    // 只有在明确周数或者课程是全周(0)时才显示
    return courses.filter(c => c.weekday === jsDay && (c.week_index === 0 || c.week_index === currentWeek));
  }, [courses, currentWeekday, currentWeek]);

  const { floatingTasks, hourlyTasks } = useMemo(() => {
    const floating: Todo[] = [];
    const hourly: Todo[] = [];

    todos.forEach(t => {
      if (t.is_deleted) return;
      
      const startMs = t.created_date || t.created_at;
      const endMs = t.due_date || 0;
      
      const isActiveToday = (endMs === 0) || 
                            (endMs < todayStart && !t.is_completed) || 
                            (startMs <= todayEnd && endMs >= todayStart);

      if (!isActiveToday) return;

      const isAllDay = t.is_all_day || endMs === 0 || (endMs < todayStart);
      const isCrossDay = (endMs > 0 && startMs > 0 && new Date(startMs).toDateString() !== new Date(endMs).toDateString());

      if (isAllDay || isCrossDay) {
        floating.push(t);
      } else if (endMs >= todayStart && endMs <= todayEnd) {
        hourly.push(t);
      } else {
        floating.push(t);
      }
    });
    return { floatingTasks: floating, hourlyTasks: hourly };
  }, [todos, todayStart, todayEnd]);

  const [isFloatingExpanded, setIsFloatingExpanded] = useState(false);

  return (
    <div className="h-full flex flex-col gap-1 overflow-hidden">
      {floatingTasks.length > 0 && (
        <div className="shrink-0 mb-1 space-y-1">
          <div className="text-[7px] font-black text-blue-400/40 uppercase tracking-widest px-1">
             <span>全天事项 ({floatingTasks.length})</span>
          </div>
          <div className="flex flex-col gap-0.5">
            {(isFloatingExpanded ? floatingTasks : floatingTasks.slice(0, 3)).map(t => (
              <div key={t.uuid} onClick={() => onTaskClick(t)} className={`px-2 py-0.5 rounded-lg border cursor-pointer transition-all truncate text-[8px] font-bold ${t.is_completed ? 'bg-emerald-500/5 border-emerald-500/10 text-white/30 line-through' : 'bg-blue-500/5 border-blue-500/10 text-white/70'}`}>
                {t.content}
              </div>
            ))}
            {floatingTasks.length > 3 && (
              <button onClick={() => setIsFloatingExpanded(!isFloatingExpanded)} className="text-[7px] font-black text-white/20 hover:text-blue-400 text-center py-0.5">
                {isFloatingExpanded ? '收起' : `+${floatingTasks.length - 3} 项`}
              </button>
            )}
          </div>
          <div className="h-px w-full bg-white/5 mt-0.5" />
        </div>
      )}

      <div className="flex-1 flex flex-col min-h-0 relative overflow-hidden">
        <div className="absolute left-[2rem] top-0 bottom-0 w-px bg-white/5" />
        {hours.map(hour => {
          const hTasks = hourlyTasks.filter(t => {
            if (!t.due_date) return false;
            const d = new Date(Number(t.due_date));
            return d.getHours() === hour;
          });
          const hCourses = todayCourses.filter(c => Math.floor(c.start_time / 100) === hour);
          const isCurrent = now.getHours() === hour;
          
          return (
            <div key={hour} className={`flex-1 flex gap-2 min-h-0 border-b border-white/[0.02] relative group ${isCurrent ? 'bg-blue-500/[0.05]' : ''}`}>
              <div className={`w-7 text-right text-[8px] font-black tabular-nums transition-colors shrink-0 flex items-center justify-end ${isCurrent ? 'text-blue-400' : 'text-white/10'}`}>
                {hour.toString().padStart(2, '0')}
              </div>
              <div className="flex-1 flex flex-wrap items-center gap-1 min-w-0 pr-1">
                {hCourses.map(c => (
                  <div key={`c-${c.id}`} className="px-1 py-0 rounded bg-indigo-500/20 border border-indigo-500/10 shrink-0">
                    <span className="text-[9px] font-bold text-white/80 leading-none">{c.course_name}</span>
                  </div>
                ))}
                {hTasks.map(t => (
                  <div key={t.uuid} onClick={() => onTaskClick(t)} className={`px-1 py-0 rounded border cursor-pointer transition-all flex items-center gap-1 shrink-0 ${t.is_completed ? 'bg-emerald-500/10 border-emerald-500/10 opacity-40' : 'bg-blue-600/20 border-blue-500/20'}`}>
                    <div className={`w-1 h-1 rounded-full ${t.is_completed ? 'bg-emerald-400' : 'bg-blue-400'}`} />
                    <span className={`text-[9px] font-bold leading-none ${t.is_completed ? 'text-white/50 line-through' : 'text-white/90'}`}>{t.content}</span>
                  </div>
                ))}
              </div>
              {isCurrent && <div className="absolute left-7 right-0 h-px bg-blue-500/30 z-10" style={{ top: `${(now.getMinutes()/60)*100}%` }} />}
            </div>
          );
        })}
      </div>
    </div>
  );
};

const TaskDetailModal: React.FC<{ task: Todo; todoGroups: any[]; onClose: () => void }> = ({ task, todoGroups, onClose }) => {
  const rMap: Record<number, string> = { 0: '无', 1: '每天', 2: '每周', 3: '每月', 4: '每年', 5: '工作日' };
  const groupName = useMemo(() => {
    if (!task.category_id) return '默认分组';
    const group = todoGroups.find(g => g.uuid === task.category_id || g.id === task.category_id);
    return group ? group.name : '未知文件夹';
  }, [task.category_id, todoGroups]);

  return (
    <div className="fixed inset-0 z-[100] flex items-center justify-center p-4 lg:p-6 backdrop-blur-3xl bg-black/80 animate-in fade-in zoom-in duration-300">
      <div className="relative w-full max-w-3xl bg-[#0f172a] border border-white/10 rounded-3xl lg:rounded-[3rem] shadow-[0_0_100px_rgba(0,0,0,0.8)] overflow-hidden flex flex-col max-h-[90vh]">
        <div className="absolute top-0 left-0 w-full h-1.5 bg-gradient-to-r from-blue-600 to-indigo-600" />
        <button onClick={onClose} className="absolute top-4 right-4 lg:top-10 lg:right-10 p-2 lg:p-3 text-white/30 hover:text-white transition-colors z-10">
          <X className="w-6 h-6 lg:w-8 lg:h-8" />
        </button>
        <div className="p-6 lg:p-16 space-y-8 lg:space-y-12 overflow-y-auto custom-scrollbar">
          <div className="space-y-4 lg:space-y-6">
            <div className="flex flex-wrap items-center gap-2 lg:gap-3">
              <span className={`px-3 py-1 lg:px-4 lg:py-1.5 rounded-full text-[8px] lg:text-[10px] font-black uppercase tracking-widest ${task.team_uuid ? 'bg-blue-500/20 text-blue-400 border border-blue-500/30' : 'bg-emerald-500/20 text-emerald-400 border border-emerald-500/30'}`}>
                {task.team_uuid ? (task.team_name || '团队任务') : '个人空间'}
              </span>
              {task.is_completed && (
                <span className="flex items-center gap-2 text-emerald-400 text-[8px] lg:text-[10px] font-black uppercase tracking-widest bg-emerald-400/10 px-3 py-1 lg:px-4 lg:py-1.5 rounded-full border border-emerald-400/20">
                  <CheckCircle2 className="w-3 h-3 lg:w-4 lg:h-4" /> 已归档
                </span>
              )}
            </div>
            <h2 className="text-2xl lg:text-5xl font-black text-white leading-tight tracking-tighter">{task.content}</h2>
          </div>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-x-12 gap-y-6 lg:gap-y-10">
            {[
              { icon: Clock, label: '开始时间', value: task.created_date ? new Date(task.created_date).toLocaleString() : new Date(task.created_at).toLocaleString(), color: 'text-white/90' },
              { icon: Calendar, label: '截止时间', value: task.due_date ? new Date(task.due_date).toLocaleString() : '无截止日期', color: 'text-red-400' },
              { icon: Layers, label: '归属文件夹', value: groupName, color: 'text-blue-400' },
              { icon: UserIcon, label: '归属关系', value: task.team_name ? `团队: ${task.team_name}` : '个人', color: 'text-white/90' },
              { icon: RefreshCcw, label: '重复周期', value: rMap[task.recurrence || 0], color: 'text-indigo-400' }
            ].map((item, idx) => (
              <div key={idx} className="space-y-1 lg:space-y-2">
                <div className="text-[8px] lg:text-[10px] font-black text-white/20 uppercase tracking-[0.2em] flex items-center gap-2">
                  <item.icon className="w-3 h-3 lg:w-3.5 lg:h-3.5" /> {item.label}
                </div>
                <div className={`text-sm lg:text-xl font-bold ${item.color}`}>{item.value}</div>
              </div>
            ))}
          </div>
          <div className="space-y-3 lg:space-y-4">
            <div className="text-[8px] lg:text-[10px] font-black text-white/20 uppercase tracking-widest flex items-center gap-2">
              <Tag className="w-3 h-3 lg:w-3.5 lg:h-3.5" /> 备注与详情
            </div>
            <div className="p-4 lg:p-10 rounded-2xl lg:rounded-[2.5rem] bg-white/[0.03] border border-white/5 text-sm lg:text-lg text-white/70 italic leading-relaxed min-h-[100px] lg:min-h-[160px] whitespace-pre-wrap">
              {task.remark || task.description || '暂无详细备注说明。'}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

const GanttChart: React.FC<{ todos: Todo[], dayWidth: number, onTaskClick: (task: Todo) => void }> = ({ todos, dayWidth, onTaskClick }) => {
  const scrollRef = useRef<HTMLDivElement>(null);
  const [currentScrollX, setCurrentScrollX] = useState(0);
  const tasks = useMemo(() => todos.filter(t => t.due_date), [todos]);
  const dayMs = 86400000;
  const todayMs = new Date().setHours(0,0,0,0);

  const packedRows = useMemo(() => {
    if (tasks.length === 0) return [];
    const pack = (items: Todo[]) => {
      const enriched = items.map(t => ({
        ...t,
        start: t.created_date || t.created_at || (t.due_date! - dayMs * 3),
        end: t.due_date!
      }));
      enriched.sort((a, b) => a.start - b.start);
      const rows: (typeof enriched)[] = [];
      enriched.forEach(item => {
        let placed = false;
        for (let row of rows) {
          if (item.start >= row[row.length - 1].end + dayMs * 0.5) {
            row.push(item);
            placed = true;
            break;
          }
        }
        if (!placed) rows.push([item]);
      });
      return rows;
    };
    const activeTasks = tasks.filter(t => !t.is_completed);
    const completedTasks = tasks.filter(t => t.is_completed);
    return [...pack(activeTasks), ...pack(completedTasks)];
  }, [tasks, dayMs]);

  const { minDate, totalWidth, totalDays, totalRange } = useMemo(() => {
    const min = todayMs - dayMs * 7;
    const max = todayMs + dayMs * 30;
    const tMin = tasks.length > 0 ? Math.min(...tasks.map(t => t.created_date || t.created_at || (t.due_date! - dayMs * 3))) : min;
    const tMax = tasks.length > 0 ? Math.max(...tasks.map(t => t.due_date!)) : max;
    const fMin = Math.min(tMin, min);
    const fMax = Math.max(tMax, max);
    const range = Math.max(dayMs, fMax - fMin);
    const days = Math.ceil(range / dayMs);
    return { minDate: fMin, totalWidth: days * dayWidth, totalDays: days, totalRange: range };
  }, [tasks, todayMs, dayWidth]);

  const isDragging = useRef(false);
  const startX = useRef(0);
  const scrollLeft = useRef(0);

  const handleMouseDown = (e: React.MouseEvent) => {
    isDragging.current = true;
    startX.current = e.pageX - (scrollRef.current?.offsetLeft || 0);
    scrollLeft.current = scrollRef.current?.scrollLeft || 0;
    if (scrollRef.current) scrollRef.current.style.cursor = 'grabbing';
  };

  const handleMouseLeave = () => {
    isDragging.current = false;
    if (scrollRef.current) scrollRef.current.style.cursor = 'default';
  };

  const handleMouseUp = () => {
    isDragging.current = false;
    if (scrollRef.current) scrollRef.current.style.cursor = 'default';
  };

  const handleMouseMove = (e: React.MouseEvent) => {
    if (!isDragging.current) return;
    e.preventDefault();
    const x = e.pageX - (scrollRef.current?.offsetLeft || 0);
    const walk = (x - startX.current) * 1.5;
    if (scrollRef.current) scrollRef.current.scrollLeft = scrollLeft.current - walk;
  };

  useEffect(() => {
    if (scrollRef.current && !isDragging.current) {
      const offset = ((todayMs - minDate) / totalRange) * totalWidth;
      scrollRef.current.scrollLeft = offset - scrollRef.current.offsetWidth / 2;
    }
  }, [minDate, todayMs, totalRange, totalWidth]);

  return (
    <div className="h-full flex flex-col relative overflow-hidden">
      <div ref={scrollRef} className="flex-1 overflow-x-auto custom-scrollbar overflow-y-hidden cursor-grab active:cursor-grabbing select-none" onScroll={() => setCurrentScrollX(scrollRef.current?.scrollLeft || 0)} onMouseDown={handleMouseDown} onMouseLeave={handleMouseLeave} onMouseUp={handleMouseUp} onMouseMove={handleMouseMove}>
        <div style={{ width: totalWidth }} className="relative h-full flex flex-col">
          <div className="absolute top-0 bottom-0 w-px bg-blue-500/50 z-10 pointer-events-none" style={{ left: ((todayMs - minDate) / totalRange) * totalWidth }} />
          <div className="flex border-b border-white/5 sticky top-0 bg-[#020617]/90 backdrop-blur-xl z-20 shrink-0">
            {Array.from({ length: totalDays }).map((_, i) => {
              const d = new Date(minDate + i * dayMs);
              return (
                <div key={i} className="flex-shrink-0 text-center py-2 text-white/20" style={{ width: dayWidth }}>
                  <div className="text-[8px] font-black uppercase">{d.toLocaleDateString('zh-CN', { weekday: 'short' })}</div>
                  <div className="text-[10px] font-bold">{d.getDate()}</div>
                </div>
              );
            })}
          </div>
          <div className="flex-1 min-h-0 flex flex-col px-4 pb-4 gap-1.5 h-full mt-2">
            {packedRows.map((row, i) => (
              <div key={i} className="relative flex-1 min-h-[16px] max-h-[60px] group/row transition-all duration-300">
                {row.map(task => {
                  const left = ((task.start - minDate) / totalRange) * totalWidth;
                  const width = Math.max(dayWidth * 0.5, ((task.end - task.start) / totalRange) * totalWidth);
                  const labelOffset = Math.max(12, Math.min(width - 40, currentScrollX - left + 12));
                  return (
                    <div key={task.uuid} className="absolute h-full cursor-pointer group/item py-0.5" style={{ left, width }} onClick={() => onTaskClick(task)}>
                      <div className={`h-full rounded-lg border border-white/10 transition-all duration-300 shadow-md flex items-center relative overflow-hidden pointer-events-auto ${task.team_uuid ? 'bg-blue-500/10 border-blue-500/30 hover:bg-blue-500/20' : 'bg-emerald-500/10 border-emerald-500/30 hover:bg-emerald-500/20'}`}>
                        <div className="absolute inset-y-0 flex items-center z-10" style={{ transform: `translateX(${labelOffset}px)` }}>
                          <span className={`text-[9px] font-black truncate drop-shadow-md ${task.is_completed ? 'line-through opacity-30' : 'text-white'}`}>{task.content}</span>
                        </div>
                        {task.is_completed && <div className="absolute inset-0 bg-white/5" />}
                      </div>
                    </div>
                  );
                })}
              </div>
            ))}
            {packedRows.length < 5 && <div className="flex-[4] pointer-events-none" />}
          </div>
        </div>
      </div>
    </div>
  );
};

const TeamDisplayBoard: React.FC<{ user: User; onBack?: () => void }> = ({ user, onBack }) => {
  const [time, setTime] = useState(new Date());
  const [selectedTeam, setSelectedTeam] = useState<Team | null>(null);
  const [teamTodos, setTeamTodos] = useState<Todo[]>([]);
  const [personalTodos, setPersonalTodos] = useState<Todo[]>([]);
  const [courses, setCourses] = useState<Course[]>([]);
  const [semesterStart, setSemesterStart] = useState<number | undefined>();
  const [teamCountdowns, setTeamCountdowns] = useState<Countdown[]>([]);
  const [todoGroups, setTodoGroups] = useState<any[]>([]);
  const [announcements, setAnnouncements] = useState<TeamAnnouncement[]>([]);
  const [dayWidth, setDayWidth] = useState(100);
  const [detailTask, setDetailTask] = useState<Todo | null>(null);
  const [mobileTab, setMobileTab] = useState<'stream' | 'roadmap' | 'mission'>('stream');
  const [missionControlTab, setMissionControlTab] = useState<'active' | 'completed'>('active');
  const [allUniqueTodos, setAllUniqueTodos] = useState<Todo[]>([]);

  const loadLocalData = useCallback(() => {
    if (!user) return;
    try {
      // 1. 加载并去重 Todos
      const rawTodos = SyncEngine.getLocalTodos(user.id);
      const all = (Array.isArray(rawTodos) ? rawTodos : []).filter(t => t && !t.is_deleted);
      const uniqueTodos = Array.from(new Map(all.map(t => [t.uuid, t])).values());
      setAllUniqueTodos(uniqueTodos);
      
      setTeamTodos(uniqueTodos.filter(t => t.team_uuid === selectedTeam?.uuid));
      setPersonalTodos(uniqueTodos.filter(t => !t.team_uuid || t.team_uuid === ''));

      // 2. 加载并去重 Countdowns (过滤已过期)
      const now = Date.now();
      const rawCds = SyncEngine.getLocalCountdowns(user.id);
      const allCds = (Array.isArray(rawCds) ? rawCds : []).filter(c => c && !c.is_deleted && c.target_time > now);
      const uniqueCds = Array.from(new Map(allCds.map(c => [c.uuid, c])).values())
        .sort((a,b) => (a.target_time || 0) - (b.target_time || 0));
      setTeamCountdowns(uniqueCds);

      // 3. 文件夹
      const rawGroups = SyncEngine.getLocalTodoGroups(user.id);
      const allGroups = (Array.isArray(rawGroups) ? rawGroups : []).filter(g => g && !g.is_deleted);
      setTodoGroups(Array.from(new Map(allGroups.map(g => [g.uuid || (g as any).id, g])).values()));

      // 4. 加载课程与设置缓存
      const cachedCourses = readDayCache<Course[]>(`u${user.id}_courses`);
      if (cachedCourses) setCourses(cachedCourses);
      
      const cachedSemester = readDayCache<number>(`u${user.id}_semester_start`);
      if (cachedSemester) setSemesterStart(cachedSemester);
    } catch (err) {
      console.error("Local data load error:", err);
    }
  }, [user, selectedTeam]);

  const fetchTeamData = useCallback(async (teamUuid: string) => {
    if (!user) return;
    
    // 0. 先同步加载本地旧数据，保证“秒开”
    loadLocalData();

    try {
      // 1. 并行获取非同步核心数据
      const requests: Promise<any>[] = [
        ApiService.request(`/api/courses?user_id=${user.id}`),
        ApiService.request('/api/settings')
      ];
      
      // 只有在有团队 UUID 时才获取公告
      if (teamUuid) {
        requests.push(ApiService.request(`/api/teams/announcements?team_uuid=${teamUuid}`));
      }

      const [coursesData, settingsData, announcementsData] = await Promise.all(requests);

      // 2. 触发后台同步
      await SyncEngine.syncData(user.id);

      if (announcementsData && announcementsData.success) setAnnouncements(announcementsData.announcements);
      if (Array.isArray(coursesData)) {
        setCourses(coursesData);
        writeDayCache(`u${user.id}_courses`, coursesData);
      }
      if (settingsData && settingsData.success) {
        const start = Number(settingsData.semester_start);
        setSemesterStart(start);
        writeDayCache(`u${user.id}_semester_start`, start);
      }

      // 3. 同步完成后再次刷新本地展示
      loadLocalData();
    } catch (e) { 
        console.error(e); 
        loadLocalData(); 
    }
  }, [user, loadLocalData]);

  // 1. 初始化加载：进入即读取缓存
  useEffect(() => {
    const t = setInterval(() => setTime(new Date()), 1000);
    if (user) loadLocalData();
    
    const initLoad = async () => {
      if (!user) return;
      loadLocalData();
      try {
        const data = await ApiService.request('/api/teams');
        if (data.success && Array.isArray(data.teams)) {
          // ...
        }
      } catch (e) { console.error(e); }
    };
    
    initLoad();
    return () => clearInterval(t);
  }, [user, loadLocalData]);

  // 2. 详细数据与同步逻辑
  useEffect(() => { 
    if (user) fetchTeamData(selectedTeam?.uuid || ''); 
  }, [selectedTeam, user, fetchTeamData]);

  useEffect(() => {
    if (!user || !selectedTeam) return;
    const ws = new WebSocket(`${ApiService.getBackendUrl().replace('http', 'ws')}/ws?token=${ApiService.getToken()}&deviceId=display_board&platform=web&version=4.0.0`);
    ws.onmessage = (e) => {
      const data = JSON.parse(e.data);
      if (['SYNC_DATA', 'NEW_ANNOUNCEMENT'].includes(data.action)) fetchTeamData(selectedTeam.uuid);
    };
    return () => ws.close();
  }, [user, selectedTeam, fetchTeamData]);

  if (!user) return null;
  const allTodos = [...teamTodos, ...personalTodos];
  
  // 汇总展示：如果选了团队则展示团队的，否则展示全量（包含所有团队）
  const displayTodos = selectedTeam ? teamTodos : allUniqueTodos;
  
  const incompleteDisplayTodos = displayTodos.filter(t => !t.is_completed && t.due_date).sort((a,b) => (a.due_date || 0) - (b.due_date || 0));
  const completedDisplayTodos = displayTodos.filter(t => t.is_completed).slice(0, 20);
  const completionRate = displayTodos.length > 0 ? Math.round((displayTodos.filter(t => t.is_completed).length / displayTodos.length) * 100) : 0;

  return (
    <div className="h-screen w-screen text-white font-sans flex flex-col bg-[#020617] overflow-hidden">
      <AnimatedBackground />
      {detailTask && <TaskDetailModal task={detailTask} todoGroups={todoGroups} onClose={() => setDetailTask(null)} />}
      <header className="px-6 py-3 lg:px-10 lg:py-5 flex flex-col sm:flex-row justify-between items-center border-b border-white/5 backdrop-blur-md shrink-0 z-50 gap-2 lg:gap-4">
        <div className="flex items-center gap-4 text-center sm:text-left">
          <button 
            onClick={() => { 
                if (onBack) onBack();
                else window.location.hash = '#app'; 
            }}
            className="p-2 lg:p-3 rounded-2xl bg-white/5 border border-white/10 hover:bg-white/10 text-white/40 hover:text-white transition-all group"
            title="返回工作区"
          >
            <ArrowLeft className="w-5 h-5 lg:w-6 lg:h-6 group-hover:-translate-x-1 transition-transform" />
          </button>
          <h1 className="text-xl lg:text-4xl font-black tracking-tighter bg-clip-text text-transparent bg-gradient-to-r from-white to-white/30">{selectedTeam?.name || '看板'}</h1>
        </div>
        <div className="hidden sm:flex flex-wrap justify-center gap-2 lg:gap-4">
          {teamCountdowns.slice(0, 4).map(cd => {
            const diff = cd.target_time - Date.now();
            const days = Math.floor(diff / 86400000);
            const isUrgent = days < 3;
            return (
              <div key={cd.uuid} className={`px-3 py-1 lg:px-6 lg:py-2.5 rounded-xl border flex flex-col items-center min-w-[80px] lg:min-w-[150px] ${isUrgent ? 'bg-red-500/10 border-red-500/30' : 'bg-blue-500/10 border-blue-500/20'}`}>
                <span className={`text-[7px] lg:text-[9px] font-black uppercase tracking-widest ${isUrgent ? 'text-red-400' : 'text-blue-400'}`}>{cd.title}</span>
                <span className={`text-sm lg:text-2xl font-black tabular-nums ${isUrgent ? 'text-red-400' : 'text-white'}`}>{Math.max(0, days)} 天</span>
              </div>
            );
          })}
        </div>
        <div className="text-2xl lg:text-5xl font-black tabular-nums tracking-tighter opacity-80">{time.toLocaleTimeString([], { hour12: false, hour: '2-digit', minute: '2-digit' })}</div>
      </header>
      <main className="flex-1 min-h-0 p-4 lg:p-6 w-full max-w-[2560px] mx-auto overflow-hidden relative">
        <div className="h-full grid grid-cols-1 lg:grid-cols-12 gap-6">
          <div className={`${mobileTab === 'stream' ? 'flex' : 'hidden'} lg:flex col-span-1 lg:col-span-3 flex-col gap-6 h-full min-h-0`}>
            <GlassCard title="今日执行流" className="flex-1"><TodayHourlyTimeline todos={displayTodos} courses={courses} semesterStart={semesterStart} onTaskClick={setDetailTask} /></GlassCard>
          </div>
          <div className={`${mobileTab === 'roadmap' ? 'flex' : 'hidden'} lg:flex col-span-1 lg:col-span-6 flex-col gap-6 h-full min-h-0`}>
            <GlassCard title="战略路线图" className="flex-1 overflow-hidden" headerExtra={<div className="flex items-center gap-3 bg-white/5 px-2 py-1 rounded-lg border border-white/5 scale-75 lg:scale-100 origin-right"><button onClick={() => setDayWidth(prev => Math.max(40, prev - 20))}><ZoomOut className="w-4 h-4 opacity-40" /></button><button onClick={() => setDayWidth(prev => Math.min(300, prev + 20))}><ZoomIn className="w-4 h-4 opacity-40" /></button></div>}>
              <GanttChart todos={displayTodos} dayWidth={dayWidth} onTaskClick={setDetailTask} />
            </GlassCard>
          </div>
          <div className={`${mobileTab === 'mission' ? 'flex' : 'hidden'} lg:flex col-span-1 lg:col-span-3 flex-col gap-6 h-full min-h-0`}>
            <GlassCard title="作战指挥中心" className="flex-1 overflow-hidden" headerExtra={<div className="flex flex-col items-end gap-1 scale-75 lg:scale-100 origin-right"><div className="text-[8px] font-black uppercase text-white/30 tracking-widest">完成率</div><div className="text-xs font-black text-emerald-400">{completionRate}%</div></div>}>
              <div className="flex flex-col h-full overflow-hidden gap-4">
                <div className="flex p-1 bg-white/5 rounded-xl border border-white/5 shrink-0">
                  <button onClick={() => setMissionControlTab('active')} className={`flex-1 py-1.5 lg:py-2 rounded-lg text-[9px] lg:text-[10px] font-black uppercase tracking-widest transition-all ${missionControlTab === 'active' ? 'bg-blue-500 text-white shadow-lg' : 'text-white/30 hover:text-white/60'}`}>活跃任务</button>
                  <button onClick={() => setMissionControlTab('completed')} className={`flex-1 py-1.5 lg:py-2 rounded-lg text-[9px] lg:text-[10px] font-black uppercase tracking-widest transition-all ${missionControlTab === 'completed' ? 'bg-emerald-500 text-white shadow-lg' : 'text-white/30 hover:text-white/60'}`}>历史记录</button>
                </div>
                <div className="flex-1 overflow-hidden flex flex-col gap-4">
                  {missionControlTab === 'active' ? (
                    <div className="flex-1 flex flex-col gap-2 min-h-0 overflow-hidden">
                      <div className="text-[9px] font-black text-blue-400/50 uppercase tracking-widest px-1">优先待办事项</div>
                      <div className="flex-1 overflow-y-auto custom-scrollbar pr-1 space-y-2">
                        {incompleteDisplayTodos.map(t => {
                          const isOverdue = t.due_date && t.due_date < Date.now();
                          return (
                            <div key={t.uuid} className={`group p-2.5 rounded-xl border transition-all flex items-center gap-3 ${isOverdue ? 'bg-red-500/5 border-red-500/20' : 'bg-white/[0.02] border-white/5'}`}>
                              <div className="shrink-0 w-1.5 h-1.5 rounded-full bg-blue-500/40" />
                              <div className="flex-1 min-w-0 cursor-pointer" onClick={() => setDetailTask(t)}>
                                <div className="text-[11px] font-bold text-white/90 truncate">{t.content}</div>
                                <div className="text-[8px] font-black text-white/20 uppercase tracking-tighter truncate">{t.creator_name || '用户'} · {t.due_date ? new Date(t.due_date).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }) : ''}</div>
                              </div>
                            </div>
                          );
                        })}
                      </div>
                    </div>
                  ) : (
                    <div className="flex-1 flex flex-col gap-3 min-h-0 overflow-hidden">
                      <div className="text-[9px] font-black text-emerald-400/50 uppercase tracking-widest px-1">运营成就存档</div>
                      <div className="flex-1 overflow-y-auto custom-scrollbar pr-1 space-y-2 opacity-50">
                        {completedDisplayTodos.map(t => (
                          <div key={t.uuid} onClick={() => setDetailTask(t)} className="p-2 rounded-xl bg-emerald-500/5 border border-emerald-500/10 cursor-pointer flex items-center gap-3"><CheckCircle2 className="w-3 h-3 text-emerald-400 shrink-0" /><div className="text-[10px] font-medium text-white/60 truncate line-through">{t.content}</div></div>
                        ))}
                      </div>
                    </div>
                  )}
                </div>
              </div>
            </GlassCard>
          </div>
        </div>
      </main>
      <nav className="lg:hidden shrink-0 h-16 bg-[#0f172a] border-t border-white/10 flex items-center px-6 z-50">
        <button onClick={() => setMobileTab('stream')} className={`flex-1 flex flex-col items-center gap-1 transition-all ${mobileTab === 'stream' ? 'text-blue-500' : 'text-white/20'}`}><Clock className="w-5 h-5" /><span className="text-[8px] font-black uppercase tracking-widest">今日</span></button>
        <button onClick={() => setMobileTab('roadmap')} className={`flex-1 flex flex-col items-center gap-1 transition-all ${mobileTab === 'roadmap' ? 'text-indigo-500' : 'text-white/20'}`}><Layers className="w-5 h-5" /><span className="text-[8px] font-black uppercase tracking-widest">路线图</span></button>
        <button onClick={() => setMobileTab('mission')} className={`flex-1 flex flex-col items-center gap-1 transition-all ${mobileTab === 'mission' ? 'text-emerald-500' : 'text-white/20'}`}><CheckCircle2 className="w-5 h-5" /><span className="text-[8px] font-black uppercase tracking-widest">任务</span></button>
      </nav>
      <footer className="hidden lg:flex shrink-0 bg-blue-600/10 border-t border-white/5 py-3 px-10 z-50 overflow-hidden">
        <div className="animate-marquee whitespace-nowrap text-sm font-bold opacity-60">{announcements[0] ? `【${announcements[0].title}】 ${announcements[0].content}` : "实时执行流同步中..."}</div>
      </footer>
      <style>{`
        @keyframes marquee { 0% { transform: translateX(100%); } 100% { transform: translateX(-100%); } }
        .animate-marquee { animation: marquee 35s linear infinite; }
        .custom-scrollbar::-webkit-scrollbar { height: 4px; width: 4px; }
        .custom-scrollbar::-webkit-scrollbar-track { background: rgba(255, 255, 255, 0.01); }
        .custom-scrollbar::-webkit-scrollbar-thumb { background: rgba(255, 255, 255, 0.08); border-radius: 20px; }
      `}</style>
    </div>
  );
};

export default TeamDisplayBoard;
