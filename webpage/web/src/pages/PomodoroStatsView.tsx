import { useState, useEffect, useMemo } from 'react';
import {
  RefreshCw, Clock, CheckCircle2
} from 'lucide-react';
import { ApiService } from '../services/api';
import type { TodoItem } from '../types';
import type { PomodoroTag, PomodoroRecord } from './webapp-utils';
import {
  formatDt, formatHM,
  getLocalPomRecords, syncPomodoroRecords
} from './webapp-utils';

// --------------------------------------------------------
// 番茄专注统计组件
// --------------------------------------------------------
export const PomodoroStatsView = ({ userId, todos }: { userId: number, todos: TodoItem[] }) => {
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
