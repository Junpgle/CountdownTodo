import { useState, useEffect } from 'react';
import {
  ArrowLeft, Plus, Trash2, Clock, CheckCircle2, Check, X, RefreshCw, LogOut,
  ChevronDown, ChevronRight, LayoutDashboard, PieChart as PieChartIcon,
  User as UserIcon, Calendar, AlertCircle, Users as UsersIcon, RotateCcw, Bell,
  MessageSquare, Shield, Megaphone
} from 'lucide-react';
import { SyncEngine } from '../services/sync';
import { ApiService } from '../services/api';
import type { TodoItem, CountdownItem, User, TodoGroup, Team, TeamAnnouncement } from '../types';

import {
  CURRENT_WEB_VERSION,
  generateUUID,
  formatDt,
  toDatetimeLocal,
} from './webapp-utils';

import { ScreenTimeView } from './ScreenTimeView';
import { CourseView } from './CourseView';
import { PomodoroStatsView } from './PomodoroStatsView';
import { PomodoroFocusView } from './PomodoroFocusView';
import { TeamManagementView } from './TeamManagementView';

// --------------------------------------------------------
// 主应用组件 (WebApp)
// --------------------------------------------------------
export const WebApp = ({ onBack, user, onLogout }: { onBack: () => void, user: User, onLogout: () => void }) => {
  const [currentTab, setCurrentTab] = useState<'dashboard' | 'screentime' | 'pomodoro' | 'focus' | 'teams'>('dashboard');
  const [todos, setTodos] = useState<TodoItem[]>([]);
  const [todoGroups, setTodoGroups] = useState<TodoGroup[]>([]);
  const [countdowns, setCountdowns] = useState<CountdownItem[]>([]);
  const [showAddModal, setShowAddModal] = useState<'todo' | 'countdown' | 'group' | null>(null);

  // 编辑待办
  const [editingTodo, setEditingTodo] = useState<TodoItem | null>(null);
  const [editTitle, setEditTitle] = useState('');
  const [editRemark, setEditRemark] = useState('');
  const [editStartDate, setEditStartDate] = useState('');
  const [editDueDate, setEditDueDate] = useState('');
  const [editGroupId, setEditGroupId] = useState<string | null>(null);

  const [newItemTitle, setNewItemTitle] = useState('');
  const [newRemark, setNewRemark] = useState('');
  const [newStartDate, setNewStartDate] = useState(toDatetimeLocal(Date.now()));
  const [newDueDate, setNewDueDate] = useState('');
  const [selectedGroupId, setSelectedGroupId] = useState<string | null>(null);
  const [isSyncing, setIsSyncing] = useState(false);
  const [syncCountToday, setSyncCountToday] = useState(0);

  const [nowMs, setNowMs] = useState(Date.now());
  const [mobileTab, setMobileTab] = useState<'home' | 'settings'>('home');

  // --- 详情/高级字段 ---
  const [recurrence, setRecurrence] = useState<number>(0); // 0: None, 1: Daily, 2: Weekly, 3: Monthly, 4: Yearly, 5: Custom
  const [customInterval, setCustomInterval] = useState<string>('');
  const [recurrenceEnd, setRecurrenceEnd] = useState<string>('');
  const [reminderMin, setReminderMin] = useState<string>('');
  const [selectedTeamUuid, setSelectedTeamUuid] = useState<string | null>(null);
  const [collabType, setCollabType] = useState<number>(0); // 0: Shared, 1: Independent
  const [userTeams, setUserTeams] = useState<Team[]>([]);

  // --- 网页版版本更新检查状态 ---
  const [updateInfo, setUpdateInfo] = useState<{ version: string, title: string, desc: string } | null>(null);
  const [priorityAnns, setPriorityAnns] = useState<TeamAnnouncement[]>([]);

  useEffect(() => {
    loadLocalData();
    handleSync();
    fetchUserTeams();
    fetchPriorityAnns();
    
    const timer = setInterval(() => {
      setNowMs(Date.now());
      fetchPriorityAnns(); // Periodically check for important announcements
    }, 60000);

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

    return () => {
      clearInterval(timer);
    };
  }, []);

  const fetchUserTeams = async () => {
    try {
      const res = await ApiService.request('/api/teams');
      if (res.success && Array.isArray(res.teams)) {
        setUserTeams(res.teams as Team[]);
      }
    } catch (e) {}
  };

  const fetchPriorityAnns = async () => {
    try {
      const res = await ApiService.request('/api/teams/announcements/unread_priority');
      if (res.success) {
        setPriorityAnns((res.announcements ?? []) as TeamAnnouncement[]);
      }
    } catch (e) {
      console.error('获取重要公告失败', e);
    }
  };

  const markAnnRead = async (annUuid: string) => {
    try {
      await ApiService.request('/api/teams/announcements/read', {
        method: 'POST',
        body: JSON.stringify({ announcement_uuid: annUuid })
      });
      setPriorityAnns(prev => prev.filter(a => a.uuid !== annUuid));
    } catch (e) {
      console.error('标记已读失败', e);
    }
  };

  const loadLocalData = () => {
    setTodos(SyncEngine.getLocalTodos(user.id).filter(t => !t.is_deleted));
    setTodoGroups(SyncEngine.getLocalTodoGroups(user.id).filter(g => !g.is_deleted));
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
    const today = new Date();
    today.setHours(0,0,0,0);
    const d = t.due_date ? new Date(t.due_date) : new Date(t.created_date || t.created_at);
    d.setHours(0,0,0,0);
    return d.getTime() < today.getTime();
  };

  // 🚀 核心排序逻辑：模拟手机端紧急度计算
  const calculateUrgency = (t: TodoItem) => {
    if (t.is_completed) return -1;
    const now = Date.now();
    const start = t.created_date || t.created_at;
    const end = t.due_date || (start + 86400000); // 默认 24 小时周期 (与手机端对齐)
    const total = end - start;
    if (total <= 0) return 0;
    return Math.min(1, Math.max(0, (now - start) / total));
  };

  const todoSorter = (a: TodoItem, b: TodoItem) => {
    // 1. 状态优先
    if (a.is_completed !== b.is_completed) return a.is_completed ? 1 : -1;
    if (a.is_completed) return (b.due_date || b.created_at) - (a.due_date || a.created_at);
    
    // 2. 紧急度（Progress）优先
    const urgencyA = calculateUrgency(a);
    const urgencyB = calculateUrgency(b);
    if (Math.abs(urgencyA - urgencyB) > 0.001) return urgencyB - urgencyA;

    // 3. 截止日期优先 (处理 NULL 情况)
    if (a.due_date && b.due_date) return a.due_date - b.due_date;
    if (a.due_date) return -1;
    if (b.due_date) return 1;

    // 4. 最后按创建时间
    return (a.created_date || a.created_at) - (b.created_date || b.created_at);
  };

  const todayMs = getTodayStartMs();
  const today = new Date();

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
      group_id: selectedGroupId || null,
      recurrence: recurrence,
      custom_interval_days: recurrence === 5 ? parseInt(customInterval) : null,
      recurrence_end_date: recurrenceEnd ? new Date(recurrenceEnd).getTime() : null,
      team_uuid: selectedTeamUuid,
      collab_type: collabType,
      reminder_minutes: reminderMin ? parseInt(reminderMin) : null
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

  const handleAddGroup = () => {
    if (!newItemTitle.trim()) return;
    const now = Date.now();
    const newG: TodoGroup = {
      id: generateUUID(),
      uuid: generateUUID(),
      name: newItemTitle.trim(),
      is_expanded: true,
      is_deleted: false,
      version: 1,
      updated_at: now,
      created_at: now,
    };
    const all = SyncEngine.getLocalTodoGroups(user.id);
    all.unshift(newG);
    SyncEngine.setLocalTodoGroups(user.id, all);
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
    setSelectedGroupId(null);
    setRecurrence(0);
    setCustomInterval('');
    setRecurrenceEnd('');
    setReminderMin('');
    setSelectedTeamUuid(null);
    setCollabType(0);
  };

  const openEditModal = (todo: TodoItem) => {
    setEditingTodo(todo);
    setEditTitle(todo.content);
    setEditRemark(todo.remark ?? '');
    setEditStartDate(toDatetimeLocal(todo.created_date ?? todo.created_at));
    setEditDueDate(todo.due_date ? toDatetimeLocal(todo.due_date) : '');
    setEditGroupId(todo.group_id ?? null);
    
    // 高级字段
    setRecurrence(todo.recurrence || 0);
    setCustomInterval(todo.custom_interval_days?.toString() || '');
    setRecurrenceEnd(todo.recurrence_end_date ? toDatetimeLocal(todo.recurrence_end_date) : '');
    setReminderMin(todo.reminder_minutes?.toString() || '');
    setSelectedTeamUuid(todo.team_uuid || null);
    setCollabType(todo.collab_type || 0);
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
      target.group_id = editGroupId;
      target.recurrence = recurrence;
      target.custom_interval_days = recurrence === 5 ? parseInt(customInterval) : null;
      target.recurrence_end_date = recurrenceEnd ? new Date(recurrenceEnd).getTime() : null;
      target.team_uuid = selectedTeamUuid;
      target.collab_type = collabType;
      target.reminder_minutes = reminderMin ? parseInt(reminderMin) : null;
      
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

  const deleteGroup = (uuid: string) => {
    if (!window.confirm("确定要删除这个文件夹吗？文件夹内的任务将变为未分类。")) return;
    
    // 1. 删除文件夹
    const groups = SyncEngine.getLocalTodoGroups(user.id);
    const targetG = groups.find(g => g.uuid === uuid);
    if (targetG) {
      targetG.is_deleted = true;
      targetG.version++;
      targetG.updated_at = Date.now();
      SyncEngine.setLocalTodoGroups(user.id, groups);
    }

    // 2. 解散文件夹内的任务
    const allTodos = SyncEngine.getLocalTodos(user.id);
    let changed = false;
    allTodos.forEach(t => {
      if (t.group_id === uuid) {
        t.group_id = null;
        t.version++;
        t.updated_at = Date.now();
        changed = true;
      }
    });
    if (changed) SyncEngine.setLocalTodos(user.id, allTodos);

    loadLocalData();
    handleSync();
  };

  const toggleGroupExpansion = (uuid: string) => {
    const groups = SyncEngine.getLocalTodoGroups(user.id);
    const target = groups.find(g => g.uuid === uuid);
    if (target) {
      target.is_expanded = !target.is_expanded;
      target.version++;
      target.updated_at = Date.now();
      SyncEngine.setLocalTodoGroups(user.id, groups);
      setTodoGroups(groups.filter(g => !g.is_deleted));
      handleSync();
    }
  };

  const getDaysLeft = (targetTime: number) => {
    const d = new Date(targetTime);
    d.setHours(0,0,0,0);
    return Math.floor((d.getTime() - todayMs) / 86400000);
  };

    const TodoCard = ({ todo, isPast, isFuture }: { todo: TodoItem, isPast?: boolean, isFuture?: boolean }) => {
    const progress = calcProgress(todo);
    const cDate = new Date(todo.created_date ?? todo.created_at);

    let dateStr: string;
    if (todo.due_date) {
      const dDate = new Date(todo.due_date);
      const now = new Date();
      now.setHours(0,0,0,0);
      const target = new Date(dDate.getFullYear(), dDate.getMonth(), dDate.getDate());
      const diffDays = Math.floor((target.getTime() - now.getTime()) / 86400000);

      const mainDate = `${formatDt(cDate)} 至 ${formatDt(dDate)}`;
      
      if (todo.is_completed) {
        dateStr = mainDate;
      } else {
        if (diffDays < 0) dateStr = `${mainDate} (已逾期)`;
        else if (diffDays === 0) dateStr = `${mainDate} (今天截止)`;
        else if (diffDays === 1) dateStr = `${mainDate} (明天截止)`;
        else dateStr = `${mainDate} (${diffDays}天后截止)`;
      }
    } else {
      dateStr = `开始于 ${formatDt(cDate)}`;
    }

    const hasTeamInfo = todo.team_name || todo.creator_name;

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
            {hasTeamInfo && (
              <div className="flex flex-wrap gap-1.5 mt-1">
                {todo.team_name && (
                  <span className="px-1.5 py-0.5 bg-indigo-50 text-indigo-500 rounded text-[9px] font-bold uppercase tracking-tight">
                    {todo.team_name}
                  </span>
                )}
                {todo.creator_name && (
                  <span className="px-1.5 py-0.5 bg-slate-100 text-slate-500 rounded text-[9px] font-bold uppercase tracking-tight">
                    By {todo.creator_name}
                  </span>
                )}
              </div>
            )}
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

  const renderTodoFormFields = (isEdit: boolean) => (
    <div className="space-y-5">
      <div>
        <label className="text-[10px] font-black text-slate-400 uppercase tracking-widest ml-1 mb-2 block flex items-center gap-1">
          <Calendar className="w-3 h-3" /> 所属文件夹
        </label>
        <select 
          value={isEdit ? (editGroupId || '') : (selectedGroupId || '')} 
          onChange={e => isEdit ? setEditGroupId(e.target.value || null) : setSelectedGroupId(e.target.value || null)}
          className="w-full bg-slate-50 border border-slate-200 px-4 py-3 rounded-xl text-slate-800 focus:ring-2 focus:ring-indigo-500/20 focus:bg-white outline-none transition font-bold"
        >
          <option value="">未分类</option>
          {todoGroups.map(g => (
            <option key={g.uuid} value={g.uuid}>{g.name}</option>
          ))}
        </select>
      </div>

      <div className="flex flex-col sm:flex-row gap-4">
        <div className="flex-1">
          <label className="text-[10px] font-black text-slate-400 uppercase tracking-widest ml-1 mb-2 block flex items-center gap-1">
            <Clock className="w-3 h-3" /> 开始时间
          </label>
          <input
            type="datetime-local"
            value={isEdit ? editStartDate : newStartDate}
            onChange={e => isEdit ? setEditStartDate(e.target.value) : setNewStartDate(e.target.value)}
            className="w-full bg-slate-50 border border-slate-200 px-4 py-3 rounded-xl text-slate-800 focus:ring-2 focus:ring-indigo-500/20 focus:bg-white outline-none transition font-bold"
          />
        </div>
        <div className="flex-1">
          <label className="text-[10px] font-black text-slate-400 uppercase tracking-widest ml-1 mb-2 block flex items-center gap-1">
            <Clock className="w-3 h-3 text-rose-500" /> 截止时间 (可选)
          </label>
          <input
            type="datetime-local"
            value={isEdit ? editDueDate : newDueDate}
            onChange={e => isEdit ? setEditDueDate(e.target.value) : setNewDueDate(e.target.value)}
            className="w-full bg-slate-50 border border-slate-200 px-4 py-3 rounded-xl text-slate-800 focus:ring-2 focus:ring-rose-500/10 focus:bg-white outline-none transition font-bold"
          />
        </div>
      </div>

      <div className="flex flex-col sm:flex-row gap-4">
        <div className="flex-1">
          <label className="text-[10px] font-black text-slate-400 uppercase tracking-widest ml-1 mb-2 block flex items-center gap-1">
            <RotateCcw className="w-3 h-3 text-indigo-500" /> 重复模式
          </label>
          <select
            value={recurrence}
            onChange={e => setRecurrence(parseInt(e.target.value))}
            className="w-full bg-slate-50 border border-slate-200 px-4 py-3 rounded-xl text-slate-800 focus:ring-2 focus:ring-indigo-500/20 focus:bg-white outline-none transition font-bold"
          >
            <option value={0}>不重复</option>
            <option value={1}>每天</option>
            <option value={2}>每周</option>
            <option value={3}>每月</option>
            <option value={4}>每年</option>
            <option value={5}>自定义天数</option>
          </select>
        </div>
        {recurrence === 5 && (
          <div className="flex-1 animate-in zoom-in-95">
            <label className="text-[10px] font-black text-slate-400 uppercase tracking-widest ml-1 mb-2 block">间隔天数</label>
            <input
              type="number"
              placeholder="天数"
              value={customInterval}
              onChange={e => setCustomInterval(e.target.value)}
              className="w-full bg-slate-50 border border-slate-200 px-4 py-3 rounded-xl text-slate-800 focus:ring-2 focus:ring-indigo-500/20 focus:bg-white outline-none transition font-bold"
            />
          </div>
        )}
      </div>

      {recurrence > 0 && (
        <div className="animate-in slide-in-from-top-2 duration-300">
          <label className="text-[10px] font-black text-slate-400 uppercase tracking-widest ml-1 mb-2 block">重复截止日期 (如有)</label>
          <input
            type="datetime-local"
            value={recurrenceEnd}
            onChange={e => setRecurrenceEnd(e.target.value)}
            className="w-full bg-slate-50 border border-slate-200 px-4 py-3 rounded-xl text-slate-800 focus:ring-2 focus:ring-indigo-500/20 focus:bg-white outline-none transition font-bold"
          />
        </div>
      )}

      <div className="flex flex-col sm:flex-row gap-4">
        <div className="flex-1">
          <label className="text-[10px] font-black text-slate-400 uppercase tracking-widest ml-1 mb-2 block flex items-center gap-1">
            <Bell className="w-3 h-3 text-amber-500" /> 提前提醒 (分钟)
          </label>
          <input
            type="number"
            placeholder="例如: 15"
            value={reminderMin}
            onChange={e => setReminderMin(e.target.value)}
            className="w-full bg-slate-50 border border-slate-200 px-4 py-3 rounded-xl text-slate-800 focus:ring-2 focus:ring-amber-500/10 focus:bg-white outline-none transition font-bold"
          />
        </div>
        <div className="flex-1">
          <label className="text-[10px] font-black text-slate-400 uppercase tracking-widest ml-1 mb-2 block flex items-center gap-1">
            <UsersIcon className="w-3 h-3 text-indigo-500" /> 分配至团队
          </label>
          <select
            value={selectedTeamUuid || ''}
            onChange={e => setSelectedTeamUuid(e.target.value || null)}
            className="w-full bg-slate-50 border border-slate-200 px-4 py-3 rounded-xl text-slate-800 focus:ring-2 focus:ring-indigo-500/20 focus:bg-white outline-none transition font-bold"
          >
            <option value="">个人任务</option>
            {userTeams.map(t => (
              <option key={t.uuid} value={t.uuid}>{t.name}</option>
            ))}
          </select>
        </div>
      </div>

      {selectedTeamUuid && (
        <div className="animate-in slide-in-from-left-2 duration-300">
          <label className="text-[10px] font-black text-slate-400 uppercase tracking-widest ml-1 mb-2 block flex items-center gap-1">
            <Shield className="w-3 h-3 text-emerald-500" /> 协作模式
          </label>
          <select
            value={collabType}
            onChange={e => setCollabType(parseInt(e.target.value))}
            className="w-full bg-emerald-50/30 border border-emerald-100 px-4 py-3 rounded-xl text-slate-800 focus:ring-2 focus:ring-emerald-500/20 focus:bg-white outline-none transition font-bold"
          >
            <option value={0}>全队共享 (一人完成全队通过)</option>
            <option value={1}>独立挑战 (每人需分别完成)</option>
          </select>
        </div>
      )}

      <div>
        <label className="text-[10px] font-black text-slate-400 uppercase tracking-widest ml-1 mb-2 block flex items-center gap-1">
          <MessageSquare className="w-3 h-3" /> 详细备注
        </label>
        <textarea
          rows={3}
          placeholder="添加补充说明..."
          value={isEdit ? editRemark : newRemark}
          onChange={e => isEdit ? setEditRemark(e.target.value) : setNewRemark(e.target.value)}
          className="w-full bg-slate-50 border border-slate-200 px-4 py-3 rounded-xl text-slate-800 focus:ring-2 focus:ring-indigo-500/20 focus:bg-white outline-none transition font-medium resize-none"
        />
      </div>
    </div>
  );

  const renderDashboard = () => (
      <div className="flex flex-col h-full flex-1 min-h-0 animate-in fade-in duration-300">
        {/* Priority Announcements Bar */}
        {priorityAnns.length > 0 && (
          <div className="mb-6 space-y-2">
            {priorityAnns.map(ann => (
              <div 
                key={ann.uuid} 
                className="bg-indigo-600 text-white px-6 py-4 rounded-3xl shadow-xl shadow-indigo-100 flex items-center justify-between group animate-in slide-in-from-top-4"
              >
                <div className="flex items-center gap-4 min-w-0">
                  <div className="w-10 h-10 bg-white/20 rounded-2xl flex items-center justify-center shrink-0">
                    <Megaphone className="w-5 h-5" />
                  </div>
                  <div className="min-w-0">
                    <div className="flex items-center gap-2">
                      <span className="text-[10px] font-black uppercase tracking-widest bg-white/20 px-2 py-0.5 rounded-lg">重要通知</span>
                      <span className="text-[10px] font-bold opacity-60 uppercase">{ann.team_name}</span>
                    </div>
                    <p className="text-sm font-black truncate mt-0.5">{ann.title}</p>
                    <p className="text-xs opacity-80 truncate">{ann.content.substring(0, 100)}...</p>
                  </div>
                </div>
                <div className="flex items-center gap-2 shrink-0">
                  <button 
                    onClick={() => markAnnRead(ann.uuid)}
                    className="px-4 py-2 bg-white text-indigo-600 rounded-xl text-xs font-black hover:bg-indigo-50 transition uppercase tracking-widest"
                  >
                    知晓并忽略
                  </button>
                  <button 
                    onClick={() => setCurrentTab('teams')}
                    className="p-2 bg-white/10 hover:bg-white/20 rounded-xl transition"
                    title="查看详情"
                  >
                    <ChevronRight className="w-5 h-5" />
                  </button>
                </div>
              </div>
            ))}
          </div>
        )}

        <div className="flex flex-col lg:flex-row gap-6 h-full flex-1 min-h-0">
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
              <div className="flex items-center gap-2">
                <button onClick={() => { resetForm(); setShowAddModal('group'); }} className="p-2 text-slate-400 hover:text-indigo-600 transition" title="新建文件夹">
                  <svg xmlns="http://www.w3.org/2000/svg" className="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M4 20h16a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.93a2 2 0 0 1-1.66-.9l-.82-1.2A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13c0 1.1.9 2 2 2Z"/><path d="M12 10v6"/><path d="M9 13h6"/></svg>
                </button>
                <button onClick={() => { resetForm(); setShowAddModal('todo'); }} className="flex items-center gap-1.5 px-4 py-2 bg-slate-900 hover:bg-slate-800 text-white rounded-xl text-sm font-bold transition active:scale-95 shadow-md shadow-slate-900/10">
                  <Plus className="w-4 h-4" /> 新增
                </button>
              </div>
            </div>

            <div className="flex-1 overflow-y-auto p-2 sm:p-4 space-y-4 min-h-0">
              {(() => {
                // 1. 预处理文件夹数据，提取排序元数据
                const processedGroups = todoGroups.map(g => {
                  const gUuid = String(g.uuid || g.id).trim().toLowerCase();
                  const gTodos = todos.filter(t => t.group_id && String(t.group_id).trim().toLowerCase() === gUuid);
                  const isAllDone = gTodos.length > 0 && gTodos.every(t => t.is_completed);
                  
                  let minDate = 0;
                  const undone = gTodos.filter(t => !t.is_completed);
                  if (undone.length > 0) {
                    const dates = undone.map(t => t.due_date || (t.created_date || t.created_at)).filter(d => d);
                    minDate = Math.min(...dates);
                  } else if (gTodos.length > 0) {
                    const dates = gTodos.map(t => t.due_date || (t.created_date || t.created_at)).filter(d => d);
                    minDate = Math.min(...dates);
                  }
                  // 寻找最高紧急度
                  const maxUrgency = gTodos.length > 0 ? Math.max(...gTodos.map(t => calculateUrgency(t))) : -1;
                  return { group: g, todos: gTodos, isAllDone: isAllDone || gTodos.length === 0, minDate, maxUrgency };
                }).filter(g => g.todos.length > 0 || g.group.is_expanded);

                // 2. 获取未分类待办
                const unclassified = todos.filter(t => {
                  if (!t.group_id) return true;
                  const gId = String(t.group_id).trim().toLowerCase();
                  return !todoGroups.find(g => String(g.uuid || g.id).trim().toLowerCase() === gId);
                });

                // 3. 定义项目的归类与混合逻辑
                const getSection = (item: any) => {
                  const date = item.minDate || item.due_date;
                  if (!date) return 'today';
                  const d = new Date(date);
                  d.setHours(0,0,0,0);

                  const isCompleted = item.isAllDone || item.is_completed;
                  const isPast = d.getTime() < todayMs;

                  if (isPast && isCompleted) return 'history';
                  if (isPast && !isCompleted) return 'past';
                  
                  if (d.getFullYear() === today.getFullYear() && 
                      d.getMonth() === today.getMonth() && 
                      d.getDate() === today.getDate()) return 'today';
                  
                  return d.getTime() > todayMs ? 'future' : 'today';
                };

                const mixedItems = [
                  ...unclassified.map(t => ({ type: 'todo', data: t, ...t, minDate: t.due_date || (t.created_date || t.created_at), maxUrgency: calculateUrgency(t), isAllDone: t.is_completed })),
                  ...processedGroups.map(g => ({ type: 'group', data: g.group, ...g }))
                ];

                const pastItems = mixedItems.filter(i => getSection(i) === 'past');
                const todayItems = mixedItems.filter(i => getSection(i) === 'today');
                const futureItems = mixedItems.filter(i => getSection(i) === 'future');

                const mixedSorter = (a: any, b: any) => {
                  if (a.isAllDone !== b.isAllDone) return a.isAllDone ? 1 : -1;
                  // 精确排序：进度高者（紧急度大）排在前面
                  if (a.maxUrgency !== b.maxUrgency) return b.maxUrgency - a.maxUrgency;
                  return (a.minDate || 0) - (b.minDate || 0);
                };
                const renderItem = (item: any) => {
                  if (item.type === 'todo') {
                    return <TodoCard key={item.data.uuid} todo={item.data} isPast={getSection(item) === 'past'} isFuture={getSection(item) === 'future'} />;
                  } else {
                    const group = item.data;
                    const groupTodos = item.todos;
                    const undoneCount = groupTodos.filter((t:any) => !t.is_completed).length;
                    return (
                      <div key={group.uuid || group.id} className="bg-slate-50/50 rounded-2xl border border-slate-100 overflow-hidden transition-all hover:shadow-sm">
                        <div className="flex items-center gap-3 p-3.5 select-none">
                          <div onClick={() => toggleGroupExpansion(group.uuid || group.id)} className={`p-2 rounded-xl cursor-pointer ${item.isAllDone ? 'bg-green-100 text-green-600' : 'bg-indigo-100 text-indigo-600'}`}>
                            {item.isAllDone ? <CheckCircle2 className="w-4 h-4" /> : (group.is_expanded ? <ChevronDown className="w-4 h-4" /> : <ChevronRight className="w-4 h-4" />)}
                          </div>
                          <div onClick={() => toggleGroupExpansion(group.uuid || group.id)} className="flex-1 cursor-pointer">
                            <h4 className={`text-sm font-bold ${item.isAllDone ? 'text-green-700 line-through opacity-60' : 'text-slate-800'}`}>{group.name || '未命名文件夹'}</h4>
                            <p className="text-[10px] text-slate-400 font-bold uppercase tracking-wider">
                              {item.isAllDone ? '全部完成' : `${undoneCount}/${groupTodos.length} 项待处理`}
                            </p>
                          </div>
                          <button onClick={() => deleteGroup(group.uuid || group.id)} className="p-1.5 text-slate-300 hover:text-red-500 transition">
                            <Trash2 className="w-4 h-4" />
                          </button>
                        </div>
                        {group.is_expanded && groupTodos.length > 0 && (
                          <div className="bg-white/50 border-t border-slate-100/80 p-2 space-y-2">
                             {groupTodos.sort(todoSorter).map((t:any) => (
                               <TodoCard key={t.uuid} todo={t} isPast={isHistorical(t)} />
                             ))}
                          </div>
                        )}
                      </div>
                    );
                  }
                };

                return (
                  <div className="space-y-8">
                    {pastItems.length > 0 && (
                      <div className="space-y-3">
                         <div className="flex items-center gap-2 px-1 text-red-500 font-bold text-[10px] uppercase tracking-widest">
                           <AlertCircle className="w-3.5 h-3.5" /> 逾期
                         </div>
                         <div className="space-y-3">{pastItems.sort(mixedSorter).map(renderItem)}</div>
                      </div>
                    )}

                    {todayItems.length > 0 && (
                      <div className="space-y-3">
                         <div className="flex items-center gap-2 px-1 text-blue-500 font-bold text-[10px] uppercase tracking-widest">
                           <Calendar className="w-3.5 h-3.5" /> 今日
                         </div>
                         <div className="space-y-3">{todayItems.sort(mixedSorter).map(renderItem)}</div>
                      </div>
                    )}

                    {futureItems.length > 0 && (
                      <div className="space-y-3">
                         <div className="flex items-center gap-2 px-1 text-slate-400 font-bold text-[10px] uppercase tracking-widest">
                           <Clock className="w-3.5 h-3.5" /> 将来
                         </div>
                         <div className="space-y-3">{futureItems.sort(mixedSorter).map(renderItem)}</div>
                      </div>
                    )}
                  </div>
                );
              })()}

              {todos.length === 0 && countdowns.length === 0 && (
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

            <div className="mt-2 flex items-center gap-2">
              <div className={`px-2 py-1 rounded-lg text-[10px] font-black uppercase tracking-wider ${
                ApiService.getBackendKey() === 'aliyun' ? 'bg-orange-50 text-orange-600 border border-orange-100' : 'bg-blue-50 text-blue-600 border border-blue-100'
              }`}>
                {ApiService.getBackendKey() === 'aliyun' ? 'Aliyun ECS Node' : 'Cloudflare Worker'}
              </div>
              <p className="text-[10px] text-slate-400 font-bold uppercase tracking-widest">
                {ApiService.getBackendUrl()}
              </p>
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
                <button
                    onClick={() => {setCurrentTab('teams'); setMobileTab('home');}}
                    className={`px-4 py-2 rounded-xl text-sm font-bold transition flex items-center gap-2 ${currentTab === 'teams' && mobileTab === 'home' ? 'bg-indigo-50 text-indigo-600' : 'text-slate-500 hover:bg-slate-50'}`}
                >
                  <UsersIcon className="w-4 h-4" /> 团队管理
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
          <button onClick={() => {setCurrentTab('teams'); setMobileTab('home');}} className={`flex flex-col items-center gap-0.5 p-2 ${currentTab === 'teams' && mobileTab === 'home' ? 'text-indigo-500' : 'text-slate-400'}`}>
            <UsersIcon className="w-5 h-5" />
            <span className="text-[9px] font-bold">团队</span>
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
          {currentTab === 'teams' && mobileTab === 'home' && <TeamManagementView user={user} onBack={() => setCurrentTab('dashboard')} />}
        </main>

        {/* 统一添加弹窗 (Todo / Countdown) */}
        {showAddModal && (
            <div className="fixed inset-0 z-[60] bg-slate-900/40 backdrop-blur-sm flex items-center justify-center p-4 animate-in fade-in duration-200">
              <div className="bg-white w-full max-w-lg max-h-[90vh] overflow-y-auto rounded-[2.5rem] p-8 sm:p-10 shadow-2xl animate-in zoom-in-95 duration-200 custom-scrollbar">
                <div className="flex justify-between items-center mb-8 sticky top-0 bg-white z-10 py-2">
                  <h4 className="font-black text-2xl text-slate-800">
                    {showAddModal === 'todo' ? '添加待办事项' : showAddModal === 'countdown' ? '添加重要倒计时' : '创建新文件夹'}
                  </h4>
                  <button onClick={() => setShowAddModal(null)} className="p-2 bg-slate-100 rounded-full text-slate-500 hover:bg-slate-200 transition">
                    <X className="w-5 h-5" />
                  </button>
                </div>

                <div className="space-y-6 mb-8">
                  <div>
                    <label className="text-sm font-bold text-slate-500 ml-1 mb-2 block">{showAddModal === 'group' ? '文件夹名称' : '标题内容'}</label>
                    <input
                        type="text"
                        placeholder={showAddModal === 'group' ? '例如：学习、生活、工作' : '请输入标题'}
                        value={newItemTitle}
                        onChange={e => setNewItemTitle(e.target.value)}
                        className="w-full bg-slate-50 border border-slate-200 px-5 py-4 rounded-2xl text-slate-800 focus:outline-none focus:ring-2 focus:ring-indigo-500/50 focus:bg-white transition text-lg font-medium"
                    />
                  </div>

                  {showAddModal === 'todo' && renderTodoFormFields(false)}

                  {showAddModal === 'countdown' && (
                      <div>
                        <label className="text-sm font-bold text-slate-500 ml-1 mb-2 block">目标日期 (必填)</label>
                        <input
                            type="date"
                            value={newDueDate}
                            onChange={e => setNewDueDate(e.target.value)}
                            className="w-full bg-slate-50 border border-slate-200 px-5 py-4 rounded-2xl text-slate-800 focus:outline-none focus:ring-2 focus:ring-indigo-500/50 focus:bg-white transition font-medium"
                        />
                      </div>
                  )}
                </div>

                <button
                    onClick={() => {
                      if (showAddModal === 'todo') handleAddTodo();
                      else if (showAddModal === 'countdown') handleAddCountdown();
                      else if (showAddModal === 'group') handleAddGroup();
                    }}
                    className="w-full bg-indigo-600 hover:bg-indigo-700 text-white font-black py-5 rounded-[2rem] transition shadow-lg shadow-indigo-200 active:scale-[0.98]"
                >
                  确定添加
                </button>
              </div>
            </div>
        )}

        {/* 编辑待办弹窗 */}
        {editingTodo && (
            <div className="fixed inset-0 z-[60] bg-slate-900/40 backdrop-blur-sm flex items-center justify-center p-4 animate-in fade-in duration-200">
              <div className="bg-white w-full max-w-lg max-h-[90vh] overflow-y-auto rounded-[2.5rem] p-8 sm:p-10 shadow-2xl animate-in zoom-in-95 duration-200 custom-scrollbar">
                <div className="flex justify-between items-center mb-8 sticky top-0 bg-white z-10 py-2">
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

                  {renderTodoFormFields(true)}
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
              <div className="bg-white w-full max-sm rounded-[2.5rem] p-8 shadow-2xl flex flex-col items-center text-center animate-in zoom-in-95 duration-300">
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