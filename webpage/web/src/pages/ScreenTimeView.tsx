import { useState, useEffect } from 'react';
import {
  RefreshCw, Monitor, Smartphone, MonitorSmartphone,
  PieChart as PieChartIcon
} from 'lucide-react';
import { ApiService } from '../services/api';
import { CacheService } from '../services/cache';
import type { ScreenTimeStat, AppGroup } from './webapp-utils';
import { formatHM, simplifyDeviceName } from './webapp-utils';

// --------------------------------------------------------
// 屏幕时间组件
// --------------------------------------------------------
export const ScreenTimeView = ({ userId }: { userId: number }) => {
  const [stats, setStats] = useState<ScreenTimeStat[]>([]);
  const [loading, setLoading] = useState(true);
  const [filter, setFilter] = useState<'all' | 'pc' | 'mobile'>('all');
  const [selectedDate] = useState(new Date());

  useEffect(() => {
    const init = async () => {
      // 1. 先从 IndexedDB 缓存加载
      const cached = await CacheService.getCachedScreenTime(userId);
      if (cached && cached.length > 0) {
        setStats(cached);
        setLoading(false);
        // 有缓存时后台静默刷新
        fetchStats(false);
      } else {
        // 无缓存时显示 loading
        fetchStats(true);
      }
    };
    init();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const fetchStats = async (showLoading = true) => {
    if (showLoading) setLoading(true);
    try {
      const dateStr = selectedDate.toISOString().split('T')[0];
      const data = await ApiService.request(`/api/screen_time?user_id=${userId}&date=${dateStr}`, { method: 'GET' });
      const result = (Array.isArray(data) ? data : []) as ScreenTimeStat[];
      setStats(result);
      CacheService.setCachedScreenTime(userId, result);
    } catch (e) {
      console.error("获取屏幕时间失败", e);
    } finally {
      if (showLoading) setLoading(false);
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

  const categories = Object.entries(appGroups).reduce((acc, [appName, data]) => {
    const cat = data.category || '未分类';
    if (!acc[cat]) acc[cat] = { total: 0, items: [] };
    acc[cat].total += data.total;
    acc[cat].items.push({ name: appName, total: data.total, devices: data.devices });
    return acc;
  }, {} as Record<string, { total: number; items: { name: string; total: number; devices: Record<string, number> }[] }>);

  const sortedCategories = Object.entries(categories)
    .map(([name, data]) => ({
      name,
      total: data.total,
      items: data.items.sort((a, b) => b.total - a.total)
    }))
    .sort((a, b) => b.total - a.total);

  const CAT_COLORS = ['bg-emerald-400', 'bg-blue-400', 'bg-amber-400', 'bg-rose-400', 'bg-fuchsia-400', 'bg-cyan-400', 'bg-indigo-400'];
  const compactHM = (ms: number) => formatHM(ms).replace('小时', 'h ').replace('分钟', 'm');

  return (
      <div className="flex flex-col gap-6 animate-in fade-in duration-300 h-full flex-1 min-h-0">
        <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-3 sm:gap-4 bg-white p-4 sm:p-6 rounded-3xl shadow-sm border border-slate-100 shrink-0">
          <div className="flex justify-between items-center w-full sm:w-auto">
            <div>
              <h2 className="text-xl sm:text-2xl font-black text-slate-800 flex items-center gap-2">
                <PieChartIcon className="w-5 h-5 sm:w-6 sm:h-6 text-indigo-500" />
                屏幕时间看板
              </h2>
              <p className="text-slate-500 text-sm mt-1 hidden sm:block">跨设备使用时长分析</p>
            </div>
            <button
                onClick={() => fetchStats()}
                disabled={loading}
                className="p-2 bg-slate-100 hover:bg-slate-200 text-slate-500 rounded-xl transition disabled:opacity-50 sm:hidden"
                title="刷新数据"
            >
              <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} />
            </button>
          </div>
          <div className="flex items-center gap-2 shrink-0 w-full sm:w-auto">
            <button
                onClick={() => fetchStats()}
                disabled={loading}
                className="hidden sm:block p-2 bg-slate-100 hover:bg-slate-200 text-slate-500 rounded-xl transition disabled:opacity-50"
                title="刷新数据"
            >
              <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} />
            </button>
            <div className="flex items-center gap-1 sm:gap-2 bg-slate-100 p-1 sm:p-1.5 rounded-xl w-full sm:w-auto">
              <button onClick={() => setFilter('all')} className={`flex-1 sm:flex-none justify-center px-3 py-1.5 sm:px-4 sm:py-2 rounded-lg text-xs sm:text-sm font-bold transition ${filter === 'all' ? 'bg-white shadow-sm text-indigo-600' : 'text-slate-500 hover:text-slate-700'}`}>全部</button>
              <button onClick={() => setFilter('pc')} className={`flex-1 sm:flex-none justify-center px-3 py-1.5 sm:px-4 sm:py-2 rounded-lg text-xs sm:text-sm font-bold transition flex items-center gap-1 ${filter === 'pc' ? 'bg-white shadow-sm text-blue-600' : 'text-slate-500 hover:text-slate-700'}`}><Monitor className="w-3.5 h-3.5 sm:w-4 sm:h-4" /> 电脑</button>
              <button onClick={() => setFilter('mobile')} className={`flex-1 sm:flex-none justify-center px-3 py-1.5 sm:px-4 sm:py-2 rounded-lg text-xs sm:text-sm font-bold transition flex items-center gap-1 ${filter === 'mobile' ? 'bg-white shadow-sm text-purple-600' : 'text-slate-500 hover:text-slate-700'}`}><Smartphone className="w-3.5 h-3.5 sm:w-4 sm:h-4" /> 移动端</button>
            </div>
          </div>
        </div>

        {loading ? (
            <div className="flex-1 flex items-center justify-center min-h-0">
              <RefreshCw className="w-8 h-8 text-indigo-300 animate-spin" />
            </div>
        ) : (
            <div className="flex flex-col lg:flex-row gap-4 sm:gap-6 flex-1 min-h-0">
              {/* Left: Summary Card */}
              <div className="lg:w-[320px] xl:w-[380px] bg-gradient-to-br from-indigo-600 to-purple-700 rounded-3xl p-6 sm:p-8 text-white shadow-xl relative overflow-hidden flex flex-col shrink-0">
                <div className="absolute -right-12 -top-12 text-white/10 pointer-events-none">
                  <MonitorSmartphone className="w-56 h-56" />
                </div>
                <div className="relative z-10 flex-1 flex flex-col">
                  <div>
                    <p className="text-indigo-100/90 font-bold mb-1 sm:mb-2 text-sm sm:text-base">今日总计使用</p>
                    <div className="text-4xl sm:text-5xl font-black mb-3 tracking-tight">
                      {compactHM(totalDuration)}
                    </div>
                    <p className="text-xs font-bold text-indigo-100 bg-black/20 inline-flex px-3 py-1.5 rounded-full backdrop-blur-sm">
                      {selectedDate.toLocaleDateString()} 数据
                    </p>
                  </div>
                  
                  {/* Category Progress Bar */}
                  {totalDuration > 0 && (
                    <div className="mt-8 sm:mt-auto pt-6 border-t border-white/10">
                      <p className="text-xs font-bold text-indigo-100/70 mb-3">使用分类占比</p>
                      <div className="flex w-full h-2.5 sm:h-3 rounded-full overflow-hidden gap-0.5 bg-black/20">
                        {sortedCategories.map((cat, i) => (
                          <div 
                            key={cat.name} 
                            style={{ width: `${(cat.total / totalDuration) * 100}%` }}
                            className={`${CAT_COLORS[i % CAT_COLORS.length]} transition-all duration-500`}
                          />
                        ))}
                      </div>
                      <div className="flex flex-wrap gap-x-3 gap-y-2 mt-4 text-[11px] sm:text-xs font-medium text-white/90">
                        {sortedCategories.map((cat, i) => (
                          <div key={cat.name} className="flex items-center gap-1.5">
                            <span className={`w-2.5 h-2.5 rounded-[3px] ${CAT_COLORS[i % CAT_COLORS.length]} shadow-sm`} />
                            <span>{cat.name}</span>
                            <span className="text-white/60 ml-0.5">{Math.round((cat.total / totalDuration) * 100)}%</span>
                          </div>
                        ))}
                      </div>
                    </div>
                  )}
                </div>
              </div>

              {/* Right: Category App List */}
              <div className="flex-1 bg-white rounded-3xl shadow-sm border border-slate-100 overflow-hidden flex flex-col min-h-[400px] lg:min-h-0">
                <div className="px-5 py-4 sm:px-6 sm:py-5 border-b border-slate-100 bg-slate-50/50 flex justify-between items-center shrink-0">
                  <h3 className="font-bold text-base sm:text-lg text-slate-800">应用使用详情</h3>
                  <span className="text-xs sm:text-sm font-bold text-slate-400 bg-white px-3 py-1.5 rounded-full border border-slate-100 shadow-sm">
                    {sortedCategories.reduce((sum, c) => sum + c.items.length, 0)} 个应用
                  </span>
                </div>
                
                <div className="flex-1 overflow-y-auto p-4 sm:p-6 min-h-0">
                  {sortedCategories.length === 0 ? (
                      <div className="h-full flex flex-col items-center justify-center py-10 text-slate-400">
                        <PieChartIcon className="w-12 h-12 mb-4 opacity-20" />
                        <p className="text-sm font-medium">暂无使用数据</p>
                      </div>
                  ) : (
                      <div className="space-y-6 sm:space-y-8">
                        {sortedCategories.map((cat, catIdx) => (
                          <div key={cat.name} className="animate-in fade-in slide-in-from-bottom-2 duration-500" style={{ animationDelay: `${catIdx * 100}ms` }}>
                            {/* Category Header */}
                            <div className="flex justify-between items-end mb-3 border-b border-slate-100 pb-2">
                               <h4 className="font-black text-slate-700 flex items-center gap-2 text-sm sm:text-base">
                                 <span className={`w-3.5 h-3.5 rounded-md ${CAT_COLORS[catIdx % CAT_COLORS.length]} shadow-sm`} />
                                 {cat.name}
                               </h4>
                               <span className="text-sm font-black text-slate-400 tabular-nums">{compactHM(cat.total)}</span>
                            </div>
                            
                            {/* App Grid - Highly dense on mobile and desktop */}
                            <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-3 gap-2 sm:gap-3">
                               {cat.items.map(app => (
                                  <div key={app.name} className="flex justify-between items-center bg-slate-50/80 hover:bg-indigo-50/80 p-2.5 sm:p-3 rounded-2xl border border-transparent hover:border-indigo-100 transition group">
                                     <div className="flex flex-col min-w-0 pr-3 flex-1">
                                        <span className="text-sm font-bold text-slate-700 truncate group-hover:text-indigo-700 transition-colors">{app.name}</span>
                                        <div className="flex flex-wrap gap-1 mt-1.5">
                                          {Object.keys(app.devices).map(dev => (
                                             <span key={dev} className="text-[9px] sm:text-[10px] font-bold text-slate-400 bg-white border border-slate-200/60 px-1.5 py-0.5 rounded-md leading-none">{simplifyDeviceName(dev)}</span>
                                          ))}
                                        </div>
                                     </div>
                                     <span className="text-sm sm:text-base font-black text-slate-600 group-hover:text-indigo-600 transition-colors shrink-0 tabular-nums">
                                       {compactHM(app.total)}
                                     </span>
                                  </div>
                               ))}
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
