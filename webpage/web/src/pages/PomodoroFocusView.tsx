import { useState, useEffect, useMemo } from 'react';
import {
  Plus, Trash2, CheckCircle2, X, ArrowLeft,
  PlayCircle, StopCircle, Hash, RefreshCw, Clock
} from 'lucide-react';
import { ApiService } from '../services/api';
import { SyncEngine } from '../services/sync';
import { CacheService } from '../services/cache';
import { WsService } from '../services/websocket';
import type { TodoItem } from '../types';
import type { PomodoroTag, PomodoroRecord, PomodoroSettings, PomodoroState } from './webapp-utils';
import {
  generateUUID, formatDt, formatHM,
  loadPomodoroSettings, savePomodoroSettings,
  loadPomodoroState, savePomodoroState,
  upsertLocalPomRecord, setPomLastSyncTime,
  getLocalPomRecords,
} from './webapp-utils';

// --------------------------------------------------------
// 番茄钟工作台组件
// --------------------------------------------------------
export const PomodoroFocusView = ({
  userId,
  todos,
  onTodoCompleted,
  remotePomActive,
  remotePomDisplay,
  remotePomData,
}: {
  userId: number;
  todos: TodoItem[];
  onTodoCompleted: (uuid: string) => void;
  remotePomActive: boolean;
  remotePomDisplay: string;
  remotePomData: { tags: string[]; todoTitle: string; note: string; mode: number; timestamp: number; targetEnd: number; duration: number };
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

  // ---- Stats state ----
  const [records, setRecords] = useState<PomodoroRecord[]>([]);
  const [statsLoading, setStatsLoading] = useState(true);
  const [filterYear, setFilterYear] = useState<number | 'all'>(new Date().getFullYear());
  const [filterMonth, setFilterMonth] = useState<number | 'all'>(new Date().getMonth() + 1);
  const [filterDay, setFilterDay] = useState<number | 'all'>('all');
  const [filterTag, setFilterTag] = useState<string | 'all'>('all');

  // Load tags + stats on mount
  useEffect(() => {
    SyncEngine.syncData(userId).catch(console.error);
    fetchTags();
    initStats();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [userId]);

  const initStats = async () => {
    const cachedRecords = await CacheService.getCachedPomRecords(userId);
    const hasCache = cachedRecords && cachedRecords.length > 0;
    if (hasCache) {
      setRecords(cachedRecords.filter(r => !r.is_deleted) as unknown as PomodoroRecord[]);
      setStatsLoading(false);
      // 有缓存时后台静默刷新
      fetchStats(false);
    } else {
      // 无缓存时显示 loading
      fetchStats(true);
    }
  };

  const fetchStats = async (showLoading = true) => {
    if (showLoading) setStatsLoading(true);
    try {
      const localRecords = getLocalPomRecords(userId).filter(r => !r.is_deleted);
      setRecords(localRecords);
      CacheService.setCachedPomRecords(userId, localRecords);
    } catch (e) {
      console.error("获取专注统计失败", e);
    } finally {
      if (showLoading) setStatsLoading(false);
    }
  };

  const filteredRecords = useMemo(() => {
    return records
      .filter(record => {
        const d = new Date(record.start_time);
        const matchYear = filterYear === 'all' || d.getFullYear() === filterYear;
        const matchMonth = filterMonth === 'all' || (d.getMonth() + 1) === filterMonth;
        const matchDay = filterDay === 'all' || d.getDate() === filterDay;
        const matchTag = filterTag === 'all' || (record.tag_uuids && record.tag_uuids.includes(filterTag));
        return matchYear && matchMonth && matchDay && matchTag;
      })
      .sort((a, b) => b.start_time - a.start_time);
  }, [records, filterYear, filterMonth, filterDay, filterTag]);

  const totalFocusSeconds = filteredRecords.reduce((sum, r) => sum + (r.actual_duration || r.planned_duration || 0), 0);
  const completedCount = filteredRecords.filter(r => r.status === 'completed').length;

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
    const teamUuid = todoUuid ? todos.find(t => t.uuid === todoUuid)?.team_uuid : null;
    const state: PomodoroState = {
      phase: 'focus',
      loopIndex,
      endTimeMs: endMs,
      todoUuid,
      tagUuids,
      startTimeMs: nowMs,
      recordUuid,
      teamUuid,
    };
    savePomodoroState(userId, state);
    setPomState(state);
    setIsRunning(true);
    setRemainMs(settings.focusDuration * 1000);

    const todo = todoUuid ? todos.find(t => t.uuid === todoUuid) : null;
    WsService.getInstance().send({
      action: 'START',
      session_uuid: recordUuid,
      todo_uuid: todoUuid,
      todo_title: todo?.content || '',
      duration: settings.focusDuration,
      target_end_ms: endMs,
      mode: 0,
      tags: tagUuids,
      timestamp: nowMs,
    });
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
    WsService.getInstance().send({
      action: 'STOP',
      session_uuid: pomState.recordUuid,
      todo_uuid: pomState.todoUuid,
      timestamp: Date.now(),
    });
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
    WsService.getInstance().send({
      action: 'SWITCH',
      session_uuid: pomState.recordUuid,
      todo_uuid: switchTargetUuid,
      timestamp: Date.now(),
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
    const todo = rec.todo_uuid ? todos.find(t => t.uuid === rec.todo_uuid) : null;
    const fullRec: PomodoroRecord = {
      ...rec,
      status: rec.status as PomodoroRecord['status'],
      end_time: rec.end_time,
      device_id: ApiService.getDeviceId(),
      team_uuid: todo?.team_uuid || null,
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
    const fullTag: PomodoroTag = {
      uuid: generateUUID(),
      name: newTagName.trim(),
      color: newTagColor,
      is_deleted: 0,
      version: 1,
      created_at: Date.now(),
      updated_at: Date.now(),
    };
    try {
      await ApiService.request('/api/pomodoro/tags', {
        method: 'POST',
        body: JSON.stringify({ tags: [fullTag] }),
      });
      setTags(prev => [...prev, fullTag]);
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

  let remoteMins = 0;
  let remoteSecs = 0;
  if (remotePomActive && remotePomDisplay) {
    const parts = remotePomDisplay.split(':').map(Number).filter(n => !isNaN(n));
    if (parts.length === 2) {
      remoteMins = parts[0];
      remoteSecs = parts[1];
    } else if (parts.length === 3) {
      remoteMins = parts[0] * 60 + parts[1];
      remoteSecs = parts[2];
    } else if (parts.length === 1) {
      remoteSecs = parts[0];
    }
  }
  const minProgress = Math.min(1, Math.max(0, (remoteMins % 60) / 60));
  const secProgress = Math.min(1, Math.max(0, remoteSecs / 60));

  return (
    <div className="flex flex-col gap-4 sm:gap-6 animate-in fade-in duration-300 h-full flex-1 min-h-0">
      {/* Header */}
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-3 bg-white p-4 sm:p-6 rounded-3xl shadow-sm border border-slate-100 shrink-0">
        <div>
          <h2 className="text-xl sm:text-2xl font-black text-slate-800 flex items-center gap-2">
            <span className="text-2xl">🍅</span> 番茄专注工作台
          </h2>
          <p className="text-slate-500 text-sm mt-0.5">深度专注，高效完成每一项任务。网页端现已支持与手机/电脑端的实时同步与接管。</p>
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

        {/* Left: Timer */}
        <div className={`${remotePomActive && !pomState ? 'flex-1 max-w-2xl mx-auto' : 'lg:w-[400px] xl:w-[460px] shrink-0'} flex flex-col gap-4 w-full transition-all duration-500 overflow-y-auto min-h-0 pb-4`}>
          {/* Timer Card */}
          <div className={`relative shrink-0 rounded-3xl shadow-sm border flex flex-col items-center justify-center p-8 sm:p-10 gap-6 transition-all ${
            remotePomActive && !pomState
              ? 'bg-gradient-to-br from-purple-50/40 to-indigo-50/40 border-purple-200/60'
              : pomState?.phase === 'rest' ? 'bg-white border-emerald-200' : (isRunning ? 'bg-white border-red-200' : 'bg-white border-slate-100')
          }`}>
            {remotePomActive && !pomState && (
               <div className="absolute inset-0 rounded-3xl bg-gradient-to-tr from-purple-500/5 via-indigo-500/5 to-fuchsia-500/5 pointer-events-none" />
            )}

            {pomState && (
              <div className={`absolute top-4 left-1/2 -translate-x-1/2 px-4 py-1.5 rounded-full text-xs font-black tracking-widest uppercase ${
                pomState.phase === 'rest' ? 'bg-emerald-50 text-emerald-600 border border-emerald-100' : 'bg-red-50 text-red-500 border border-red-100'
              }`}>
                {pomState.phase === 'focus' ? `🍅 第 ${pomState.loopIndex + 1} / ${settings.loopCount} 轮 · 专注中` : '☕ 休息时间'}
              </div>
            )}

            {/* Visual Display */}
            {remotePomActive && !pomState ? (
              <div className="relative w-56 h-56 sm:w-[280px] sm:h-[280px] flex items-center justify-center shrink-0 z-10 my-0 sm:my-4">
                <svg className="absolute inset-0 -rotate-90 w-full h-full overflow-visible" viewBox="0 0 280 280">
                  {/* Outer Ring */}
                  <circle cx="140" cy="140" r="126" fill="none" stroke="#f1f5f9" strokeWidth="16" />
                  <circle cx="140" cy="140" r="126" fill="none" stroke="#8b5cf6" strokeWidth="16" strokeLinecap="round" strokeDasharray={`${2 * Math.PI * 126}`} strokeDashoffset={`${2 * Math.PI * 126 * (1 - minProgress)}`} className="transition-all duration-1000 ease-in-out" />
                  {/* Inner Ring */}
                  <circle cx="140" cy="140" r="98" fill="none" stroke="#f1f5f9" strokeWidth="12" opacity="0.6" />
                  <circle cx="140" cy="140" r="98" fill="none" stroke="#a855f7" strokeWidth="12" strokeLinecap="round" strokeDasharray={`${2 * Math.PI * 98}`} strokeDashoffset={`${2 * Math.PI * 98 * (1 - secProgress)}`} className="transition-all duration-1000 ease-linear" />
                </svg>
                <div className="absolute flex flex-col items-center justify-center text-center">
                  <span className="flex h-3 w-3 relative mb-3">
                    <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-purple-400 opacity-75"></span>
                    <span className="relative inline-flex rounded-full h-3 w-3 bg-purple-500"></span>
                  </span>
                  <span className="text-5xl sm:text-6xl font-black tabular-nums tracking-tight text-slate-800">
                    {remotePomDisplay}
                  </span>
                  <span className="text-sm font-bold text-purple-500 uppercase tracking-widest mt-1">远程专注中</span>
                </div>
              </div>
            ) : (
              <div className="relative w-52 h-52 sm:w-60 sm:h-60 z-10">
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
            )}

            {/* Task Info */}
            {remotePomActive && !pomState ? (
              <div className="flex flex-col items-center w-full relative z-10">
                {remotePomData.todoTitle ? (
                  <div className="w-full bg-white/80 rounded-2xl px-4 py-3 flex items-center justify-center gap-2 border border-purple-100 mb-3 shadow-sm">
                    <CheckCircle2 className="w-4 h-4 text-purple-500 shrink-0" />
                    <p className="font-bold text-purple-800 text-sm truncate">{remotePomData.todoTitle}</p>
                  </div>
                ) : (
                  <div className="w-full bg-white/80 rounded-2xl px-4 py-3 text-sm font-medium text-purple-400 border border-purple-100 text-center mb-3 shadow-sm">自由专注</div>
                )}
                
                {((remotePomData.tags && remotePomData.tags.length > 0) || remotePomData.note) && (
                  <div className="flex flex-col items-center gap-2 w-full">
                    {remotePomData.tags && remotePomData.tags.length > 0 && (
                      <div className="flex flex-wrap justify-center gap-1.5">
                        {remotePomData.tags.map((tag, i) => (
                          <span key={i} className="px-2.5 py-1 rounded-lg text-[11px] font-bold text-purple-600 bg-purple-50 border border-purple-100">
                            {tag}
                          </span>
                        ))}
                      </div>
                    )}
                    {remotePomData.note && (
                      <p className="text-slate-500 text-xs text-center line-clamp-2 max-w-[90%]">📝 {remotePomData.note}</p>
                    )}
                  </div>
                )}
              </div>
            ) : (
              <>
                {/* Current task */}
                {pomState && currentTodo && (
                  <div className="w-full bg-slate-50 rounded-2xl px-5 py-3 flex items-center gap-3 border border-slate-100 relative z-10">
                    <CheckCircle2 className="w-5 h-5 text-indigo-400 shrink-0" />
                    <p className="font-bold text-slate-700 text-sm truncate flex-1">{currentTodo.content}</p>
                    {pomState.phase === 'focus' && (
                      <button onClick={() => setShowSwitchDialog(true)} className="text-xs font-bold text-indigo-500 hover:text-indigo-700 shrink-0">切换</button>
                    )}
                  </div>
                )}
                {pomState && !currentTodo && (
                  <div className="w-full bg-slate-50 rounded-2xl px-5 py-3 text-sm font-medium text-slate-400 border border-slate-100 text-center relative z-10">未绑定任务</div>
                )}

                {/* Tags display */}
                {pomState && pomState.tagUuids.length > 0 && (
                  <div className="flex flex-wrap gap-2 justify-center relative z-10">
                    {pomState.tagUuids.map(uuid => {
                      const tag = tags.find(t => t.uuid === uuid);
                      if (!tag) return null;
                      return <span key={uuid} className="px-3 py-1 rounded-full text-xs font-bold text-white" style={{ backgroundColor: tag.color }}>{tag.name}</span>;
                    })}
                  </div>
                )}
              </>
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

        {/* Right: 专注统计 */}
        <div className="flex-1 flex flex-col gap-4 min-h-0 overflow-hidden">
          {/* 筛选器 */}
          <div className="flex items-center gap-2 bg-white rounded-2xl border border-slate-100 p-3 shrink-0 flex-wrap">
            <select value={filterYear} onChange={e => setFilterYear(e.target.value === 'all' ? 'all' : Number(e.target.value))}
              className="bg-slate-50 border border-slate-200 text-xs font-bold text-slate-600 rounded-xl px-2.5 py-1.5 focus:outline-none">
              <option value="all">全年</option>
              {[...Array(3)].map((_, i) => { const y = new Date().getFullYear() - i; return <option key={y} value={y}>{y}年</option>; })}
            </select>
            <select value={filterMonth} onChange={e => setFilterMonth(e.target.value === 'all' ? 'all' : Number(e.target.value))}
              className="bg-slate-50 border border-slate-200 text-xs font-bold text-slate-600 rounded-xl px-2.5 py-1.5 focus:outline-none">
              <option value="all">全月</option>
              {[...Array(12)].map((_, i) => <option key={i + 1} value={i + 1}>{i + 1}月</option>)}
            </select>
            <select value={filterDay} onChange={e => setFilterDay(e.target.value === 'all' ? 'all' : Number(e.target.value))}
              className="bg-slate-50 border border-slate-200 text-xs font-bold text-slate-600 rounded-xl px-2.5 py-1.5 focus:outline-none">
              <option value="all">全天</option>
              {[...Array(31)].map((_, i) => <option key={i + 1} value={i + 1}>{i + 1}日</option>)}
            </select>
            <select value={filterTag} onChange={e => setFilterTag(e.target.value)}
              className="bg-slate-50 border border-slate-200 text-xs font-bold text-slate-600 rounded-xl px-2.5 py-1.5 focus:outline-none">
              <option value="all">所有标签</option>
              {tags.map(tag => <option key={tag.uuid} value={tag.uuid}>{tag.name}</option>)}
            </select>
            <button onClick={() => fetchStats()} className="ml-auto p-1.5 bg-slate-50 rounded-xl border border-slate-200 text-slate-500 hover:text-indigo-600 transition" title="刷新">
              <RefreshCw className={`w-3.5 h-3.5 ${statsLoading ? 'animate-spin' : ''}`} />
            </button>
          </div>

          {/* 汇总卡片 */}
          <div className="bg-gradient-to-br from-amber-400 to-orange-500 rounded-2xl p-5 text-white shadow-sm relative overflow-hidden shrink-0">
            <div className="relative z-10">
              <p className="text-amber-100 font-bold text-xs mb-1">累计专注时长</p>
              <div className="text-3xl font-black tracking-tight">
                {formatHM(totalFocusSeconds).replace('小时', 'h').replace('分钟', 'm')}
              </div>
              <div className="flex items-center gap-2 mt-2 text-xs font-bold bg-black/10 inline-flex px-3 py-1.5 rounded-xl">
                <CheckCircle2 className="w-3.5 h-3.5" /> 完成 {completedCount} 个
              </div>
            </div>
          </div>

          {/* 专注明细 */}
          <div className="flex-1 bg-white rounded-2xl border border-slate-100 overflow-hidden flex flex-col min-h-0">
            <div className="px-4 py-3 border-b border-slate-100 bg-slate-50/50 shrink-0 flex justify-between items-center">
              <h3 className="font-bold text-sm text-slate-800">记录</h3>
              <span className="text-[11px] font-bold text-slate-400">{filteredRecords.length} 条</span>
            </div>
            <div className="flex-1 overflow-y-auto p-3 space-y-2 min-h-0">
              {filteredRecords.length === 0 ? (
                <div className="h-full flex flex-col items-center justify-center py-12 text-slate-400">
                  <Clock className="w-8 h-8 mb-2 opacity-20" />
                  <p className="text-xs">暂无记录</p>
                </div>
              ) : (
                filteredRecords.map(record => {
                  const todo = todos.find(t => t.uuid === record.todo_uuid);
                  const isCompleted = record.status === 'completed';
                  return (
                    <div key={record.uuid} className="flex items-center justify-between p-3 border border-slate-100 rounded-xl hover:border-amber-200 transition group">
                      <div className="flex items-center gap-3 min-w-0">
                        <div className={`w-9 h-9 rounded-full flex items-center justify-center shrink-0 ${isCompleted ? 'bg-amber-50 text-amber-500' : 'bg-slate-50 text-slate-400'}`}>
                          {isCompleted ? <CheckCircle2 className="w-4 h-4" /> : <Clock className="w-4 h-4" />}
                        </div>
                        <div className="min-w-0">
                          <p className="font-bold text-slate-800 text-xs truncate">{todo ? todo.content : '未关联任务'}</p>
                          <div className="flex items-center gap-1.5 mt-0.5">
                            <span className="text-[10px] text-slate-500">{formatDt(new Date(record.start_time))}</span>
                            <span className={`text-[8px] px-1.5 py-0.5 rounded border ${isCompleted ? 'bg-green-50 text-green-600 border-green-200' : 'bg-slate-50 text-slate-500 border-slate-200'}`}>
                              {record.status === 'completed' ? '完成' : record.status === 'switched' ? '切换' : '中断'}
                            </span>
                          </div>
                        </div>
                      </div>
                      <div className="text-right shrink-0">
                        <p className="font-black text-base text-slate-700">
                          {Math.floor((record.actual_duration || record.planned_duration || 0) / 60)}<span className="text-[10px] font-bold text-slate-400">min</span>
                        </p>
                      </div>
                    </div>
                  );
                })
              )}
            </div>
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
