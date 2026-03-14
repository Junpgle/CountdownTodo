import { useState, useEffect, useMemo } from 'react';
import {
  RefreshCw, Clock, CheckCircle2, X, ChevronDown, ChevronRight,
  Calendar, Filter, BookOpen, Flag, PlayCircle, StopCircle,
  User as UserIcon, MapPin, Hash, Sparkles, CalendarDays, ArrowLeftCircle
} from 'lucide-react';
import { ApiService } from '../services/api';
import type { TodoItem, CountdownItem } from '../types';
import type { CourseItem, CalendarEntry, DetailItem } from './webapp-utils';
import { readDayCache, writeDayCache, formatDt, formatTimeNum } from './webapp-utils';

// --------------------------------------------------------
// 课表/周视图组件 (内嵌到首页左侧使用)
// --------------------------------------------------------
export const CourseView = ({ userId, todos, countdowns }: { userId: number, todos: TodoItem[], countdowns: CountdownItem[] }) => {
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

  /**
   * 根据开学时间（毫秒时间戳）计算学期第一周周一和当前周数。
   * 若 semesterStartMs 无效则回退到用 week_index 反推的旧逻辑。
   */
  const applySemesterStart = (semesterStartMs: number | null, data: CourseItem[]) => {
    if (semesterStartMs && semesterStartMs > 0) {
      // 新逻辑：直接用 semester_start 锚定
      const startDate = new Date(semesterStartMs);
      const startDayOfWeek = startDate.getDay() || 7; // 1=周一 … 7=周日
      const firstMonday = new Date(startDate);
      firstMonday.setDate(startDate.getDate() - startDayOfWeek + 1);
      firstMonday.setHours(0, 0, 0, 0);

      const today = new Date();
      today.setHours(0, 0, 0, 0);
      const diffDays = Math.floor((today.getTime() - firstMonday.getTime()) / 86400000);
      const week = diffDays >= 0 ? Math.floor(diffDays / 7) + 1 : 1;

      setSemesterMonday(firstMonday);
      setCurrentWeek(week);
    } else {
      // 旧逻辑回退：用课程 week_index 反推
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
    }
  };

  useEffect(() => {
    const init = async () => {
      // 1. 课程数据（优先缓存）
      let courseData = cachedCourses;
      if (!courseData) {
        setLoading(true);
        try {
          const data = await ApiService.request(`/api/courses?user_id=${userId}`, { method: 'GET' });
          courseData = (Array.isArray(data) ? data : []) as CourseItem[];
          setCourses(courseData);
          writeDayCache(courseCacheKey, courseData);
        } catch (e) {
          console.error("获取课表失败", e);
          courseData = [];
        }
      }

      // 2. 拉取开学时间（不缓存，保证用最新配置）
      let semesterStartMs: number | null = null;
      try {
        const settings = await ApiService.request('/api/settings', { method: 'GET' });
        if (settings && settings.semester_start) {
          const parsed = Number(settings.semester_start);
          if (!isNaN(parsed) && parsed > 0) semesterStartMs = parsed;
        }
      } catch (e) {
        console.error("获取开学时间失败，使用课表反推", e);
      }

      // 3. 应用开学时间，计算当前周
      applySemesterStart(semesterStartMs, courseData ?? []);
      setLoading(false);
    };

    init();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [userId]);

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
