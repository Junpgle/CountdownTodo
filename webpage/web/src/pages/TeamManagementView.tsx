import React, { useState, useEffect } from 'react';
import { 
  Users, Plus, LogOut, Trash2, X, User,
  Link as LinkIcon, ChevronRight, Loader2, AlertCircle,
  MessageSquare, UserPlus, ShieldCheck, Search
} from 'lucide-react';
import { ApiService } from '../services/api';
import type { Team, TeamMember, JoinRequest, User as UserType } from '../types';

interface TeamManagementViewProps {
  user: UserType;
  onBack: () => void;
}

export const TeamManagementView = ({ user, onBack }: TeamManagementViewProps) => {
  const [teams, setTeams] = useState<Team[]>([]);
  const [invitations, setInvitations] = useState<JoinRequest[]>([]);
  const [loading, setLoading] = useState(true);
  const [activeTeamId, setActiveTeamId] = useState<string | null>(null);
  const [teamMembers, setTeamMembers] = useState<TeamMember[]>([]);
  const [joinRequests, setJoinRequests] = useState<JoinRequest[]>([]);
  
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [showJoinModal, setShowJoinModal] = useState(false);
  const [newTeamName, setNewTeamName] = useState('');
  const [inviteCode, setInviteCode] = useState('');
  
  const [actionLoading, setActionLoading] = useState(false);
  const [, setError] = useState('');

  useEffect(() => {
    fetchInitialData();
  }, []);

  useEffect(() => {
    if (activeTeamId) {
      fetchTeamDetails(activeTeamId);
    }
  }, [activeTeamId]);

  const fetchInitialData = async () => {
    setLoading(true);
    try {
      const teamsRes = await ApiService.request('/api/teams');
      const invRes = await ApiService.request('/api/teams/invitations');
      if (teamsRes.success) setTeams(teamsRes.teams as Team[]);
      if (invRes.success) setInvitations(invRes.invitations as JoinRequest[]);
    } catch (e: any) {
      setError(e.message || '获取数据失败');
    } finally {
      setLoading(false);
    }
  };

  const fetchTeamDetails = async (teamUuid: string) => {
    try {
      const membersRes = await ApiService.request(`/api/teams/members?team_uuid=${teamUuid}`);
      if (membersRes.success) setTeamMembers(membersRes.members as TeamMember[]);
      
      const team = teams.find(t => t.uuid === teamUuid);
      if (team && team.role === 0) {
        const reqRes = await ApiService.request(`/api/teams/pending_requests?team_uuid=${teamUuid}`);
        if (reqRes.success) setJoinRequests(reqRes.requests as JoinRequest[]);
      }
    } catch (e: any) {
      console.error('获取团队详情失败', e);
    }
  };

  const handleCreateTeam = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!newTeamName.trim()) return;
    setActionLoading(true);
    try {
      const res = await ApiService.request('/api/teams/create', {
        method: 'POST',
        body: JSON.stringify({ name: newTeamName })
      });
      if (res.success) {
        setNewTeamName('');
        setShowCreateModal(false);
        fetchInitialData();
      }
    } catch (e: any) {
      setError(e.message);
    } finally {
      setActionLoading(false);
    }
  };

  const handleJoinTeam = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!inviteCode.trim()) return;
    setActionLoading(true);
    try {
      const res = await ApiService.request('/api/teams/join', {
        method: 'POST',
        body: JSON.stringify({ code: inviteCode.trim() })
      });
      if (res.success) {
        setInviteCode('');
        setShowJoinModal(false);
        alert(res.message || '申请已提交');
      }
    } catch (e: any) {
      setError(e.message);
    } finally {
      setActionLoading(false);
    }
  };

  const handleRespondInvitation = async (teamUuid: string, action: 'accept' | 'decline') => {
    try {
      const res = await ApiService.request('/api/teams/respond_invitation', {
        method: 'POST',
        body: JSON.stringify({ team_uuid: teamUuid, action })
      });
      if (res.success) {
        fetchInitialData();
      }
    } catch (e: any) {
      alert(e.message);
    }
  };

  const handleProcessRequest = async (targetUserId: number, action: 'approve' | 'reject') => {
    if (!activeTeamId) return;
    try {
      const res = await ApiService.request('/api/teams/process_request', {
        method: 'POST',
        body: JSON.stringify({ team_uuid: activeTeamId, target_user_id: targetUserId, action })
      });
      if (res.success) {
        fetchTeamDetails(activeTeamId);
      }
    } catch (e: any) {
      alert(e.message);
    }
  };

  const handleLeaveTeam = async (teamUuid: string) => {
    if (!window.confirm('确定要退出该团队吗？')) return;
    try {
      const res = await ApiService.request('/api/teams/leave', {
        method: 'POST',
        body: JSON.stringify({ team_uuid: teamUuid })
      });
      if (res.success) {
        if (activeTeamId === teamUuid) setActiveTeamId(null);
        fetchInitialData();
      }
    } catch (e: any) {
      alert(e.message);
    }
  };

  const handleDeleteTeam = async (teamUuid: string) => {
    if (!window.confirm('确定要解散该团队吗？此操作无法撤销！')) return;
    try {
      const res = await ApiService.request('/api/teams/delete', {
        method: 'POST',
        body: JSON.stringify({ team_uuid: teamUuid })
      });
      if (res.success) {
        if (activeTeamId === teamUuid) setActiveTeamId(null);
        fetchInitialData();
      }
    } catch (e: any) {
      alert(e.message);
    }
  };

  const handleRemoveMember = async (targetUserId: number, targetUsername: string) => {
    if (!activeTeamId) return;
    if (!window.confirm(`确定要将成员 "${targetUsername}" 移出团队吗？`)) return;
    try {
      const res = await ApiService.request('/api/teams/members/remove', {
        method: 'POST',
        body: JSON.stringify({ team_uuid: activeTeamId, target_user_id: targetUserId })
      });
      if (res.success) {
        fetchTeamDetails(activeTeamId);
      }
    } catch (e: any) {
      alert(e.message);
    }
  };

  const activeTeam = teams.find(t => t.uuid === activeTeamId);

  return (
    <div className="flex flex-col h-full bg-slate-50 animate-in fade-in duration-300">
      {/* Header */}
      <div className="bg-white border-b border-slate-100 px-6 py-4 flex items-center justify-between sticky top-0 z-20">
        <div className="flex items-center gap-4">
          <button onClick={onBack} className="p-2 hover:bg-slate-50 rounded-xl transition">
            <X className="w-5 h-5 text-slate-500" />
          </button>
          <div>
            <h1 className="text-xl font-black text-slate-800">团队协作</h1>
            <p className="text-xs text-slate-400 font-bold uppercase tracking-widest mt-0.5">跨端同步与多人管理</p>
          </div>
        </div>
        <div className="flex gap-2">
          <button 
            onClick={() => setShowJoinModal(true)}
            className="flex items-center gap-2 px-4 py-2 bg-white border border-slate-200 text-slate-600 rounded-xl text-sm font-bold hover:bg-slate-50 transition"
          >
            <Search className="w-4 h-4" /> 加入团队
          </button>
          <button 
            onClick={() => setShowCreateModal(true)}
            className="flex items-center gap-2 px-4 py-2 bg-indigo-600 text-white rounded-xl text-sm font-bold hover:bg-indigo-700 transition shadow-lg shadow-indigo-100"
          >
            <Plus className="w-4 h-4" /> 创建团队
          </button>
        </div>
      </div>

      <div className="flex-1 overflow-hidden flex flex-col lg:flex-row p-4 lg:p-6 gap-6">
        {/* Left Sidebar: Team List & Invitations */}
        <div className="w-full lg:w-80 flex flex-col gap-6 shrink-0">
          {/* Invitations Section */}
          {invitations.length > 0 && (
            <div className="bg-amber-50 border border-amber-100 rounded-3xl p-4">
              <div className="flex items-center gap-2 mb-4">
                <ShieldCheck className="w-4 h-4 text-amber-600" />
                <span className="text-sm font-black text-amber-800 uppercase tracking-wider">收到邀请 ({invitations.length})</span>
              </div>
              <div className="space-y-3">
                {invitations.map(inv => (
                  <div key={inv.team_uuid} className="bg-white/80 backdrop-blur rounded-2xl p-3 border border-amber-200 shadow-sm">
                    <p className="text-sm font-bold text-slate-800">{inv.team_name}</p>
                    <p className="text-[10px] text-slate-400 mt-1">创建者: {inv.username || '匿名'}</p>
                    <div className="flex gap-2 mt-3">
                      <button 
                        onClick={() => handleRespondInvitation(inv.team_uuid, 'accept')}
                        className="flex-1 bg-green-500 text-white text-[10px] font-black py-1.5 rounded-lg hover:bg-green-600 transition uppercase"
                      >
                        接 受
                      </button>
                      <button 
                        onClick={() => handleRespondInvitation(inv.team_uuid, 'decline')}
                        className="flex-1 bg-slate-200 text-slate-600 text-[10px] font-black py-1.5 rounded-lg hover:bg-slate-300 transition uppercase"
                      >
                        拒 绝
                      </button>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* Teams List */}
          <div className="bg-white rounded-3xl shadow-sm border border-slate-100 flex-1 overflow-hidden flex flex-col">
            <div className="px-5 py-4 border-b border-slate-50">
              <h2 className="text-sm font-black text-slate-400 uppercase tracking-widest flex items-center gap-2">
                <Users className="w-4 h-4" /> 我的团队
              </h2>
            </div>
            <div className="flex-1 overflow-y-auto p-2 space-y-1">
              {loading ? (
                <div className="flex flex-col items-center justify-center py-12 gap-3 opacity-40">
                  <Loader2 className="w-6 h-6 animate-spin text-indigo-500" />
                  <span className="text-[10px] font-bold uppercase tracking-widest">正在加载团队列表...</span>
                </div>
              ) : teams.length === 0 ? (
                <div className="text-center py-12 px-6">
                  <div className="w-12 h-12 bg-slate-50 rounded-2xl flex items-center justify-center mx-auto mb-3">
                    <AlertCircle className="w-6 h-6 text-slate-300" />
                  </div>
                  <p className="text-xs font-bold text-slate-400 leading-relaxed uppercase tracking-wider">暂未加入任何团队</p>
                </div>
              ) : (
                teams.map(team => (
                  <button
                    key={team.uuid}
                    onClick={() => setActiveTeamId(team.uuid)}
                    className={`w-full flex items-center gap-3 p-3 rounded-2xl transition-all ${
                      activeTeamId === team.uuid 
                        ? 'bg-indigo-50 text-indigo-600' 
                        : 'text-slate-600 hover:bg-slate-50'
                    }`}
                  >
                    <div className={`w-10 h-10 rounded-xl flex items-center justify-center shrink-0 ${
                      activeTeamId === team.uuid ? 'bg-indigo-600 text-white shadow-lg shadow-indigo-100' : 'bg-slate-100 text-slate-400'
                    }`}>
                      <Users className="w-5 h-5" />
                    </div>
                    <div className="text-left min-w-0">
                      <p className="text-sm font-bold truncate">{team.name}</p>
                      <p className={`text-[10px] font-bold uppercase tracking-tighter ${activeTeamId === team.uuid ? 'text-indigo-400' : 'text-slate-400'}`}>
                        {team.role === 0 ? '管理员' : '普通成员'} · {team.member_count || 0} 人
                      </p>
                    </div>
                    {activeTeamId === team.uuid && <ChevronRight className="w-4 h-4 ml-auto" />}
                  </button>
                ))
              )}
            </div>
          </div>
        </div>

        {/* Right Content: Team Details & Management */}
        <div className="flex-1 flex flex-col gap-6 min-w-0 h-full">
          {!activeTeamId ? (
            <div className="flex-1 bg-white rounded-[2.5rem] border-2 border-dashed border-slate-100 flex flex-col items-center justify-center p-12 text-center">
              <div className="w-24 h-24 bg-indigo-50 text-indigo-200 rounded-[2rem] flex items-center justify-center mb-6">
                <Users className="w-12 h-12" />
              </div>
              <h2 className="text-2xl font-black text-slate-800 mb-2">选择一个团队以管理</h2>
              <p className="text-slate-400 max-w-sm font-medium leading-relaxed">
                在这里你可以管理团队成员、审核加入申请以及查看团队专属数据同步。（仅支持阿里云服务器，可在账号设置界面退出登录并切换服务器）
              </p>
            </div>
          ) : (
            <div className="flex-1 flex flex-col min-h-0 bg-white rounded-[2.5rem] shadow-sm border border-slate-100 overflow-hidden">
              {/* Team Header */}
              <div className="px-8 py-6 border-b border-slate-50 flex items-center justify-between shrink-0">
                <div className="flex items-center gap-4">
                  <div className="w-14 h-14 bg-indigo-600 text-white rounded-2xl flex items-center justify-center shadow-xl shadow-indigo-100">
                    <Users className="w-7 h-7" />
                  </div>
                  <div>
                    <h2 className="text-2xl font-black text-slate-900">{activeTeam?.name}</h2>
                    <div className="flex items-center gap-2 mt-1">
                      <span className="px-2 py-0.5 bg-indigo-50 text-indigo-600 rounded-lg text-[10px] font-black uppercase tracking-wider">
                        {activeTeam?.role === 0 ? '团队主理人' : '已加入'}
                      </span>
                      <span className="text-slate-300">·</span>
                      <span className="text-[10px] font-bold text-slate-400 uppercase tracking-widest">UID: {activeTeam?.uuid.substring(0, 8)}...</span>
                    </div>
                  </div>
                </div>
                <div className="flex gap-2">
                  {activeTeam?.role === 0 ? (
                    <>
                      <button onClick={() => handleDeleteTeam(activeTeam.uuid)} className="p-3 text-slate-300 hover:text-red-500 hover:bg-red-50 rounded-2xl transition" title="解散团队">
                        <Trash2 className="w-5 h-5" />
                      </button>
                    </>
                  ) : (
                    <button onClick={() => handleLeaveTeam(activeTeam!.uuid)} className="flex items-center gap-2 px-5 py-2.5 bg-rose-50 text-rose-600 rounded-2xl text-sm font-bold hover:bg-rose-100 transition">
                      <LogOut className="w-4 h-4" /> 退出
                    </button>
                  )}
                </div>
              </div>

              {/* Scrollable Content */}
              <div className="flex-1 overflow-y-auto p-8 flex flex-col lg:flex-row gap-8">
                {/* Members List */}
                <div className="flex-1">
                  <div className="flex items-center justify-between mb-6">
                    <h3 className="text-base font-black text-slate-800 flex items-center gap-2">
                      <ShieldCheck className="w-5 h-5 text-indigo-500" /> 团队成员
                    </h3>
                  </div>
                  <div className="space-y-3">
                    {teamMembers.map(member => (
                      <div key={member.user_id} className="flex items-center justify-between p-4 bg-slate-50/50 hover:bg-slate-50 border border-slate-100 rounded-2xl transition">
                        <div className="flex items-center gap-3">
                          <div className="w-10 h-10 rounded-xl bg-white border border-slate-200 flex items-center justify-center text-slate-400">
                            <User className="w-5 h-5" />
                          </div>
                          <div>
                            <p className="text-sm font-bold text-slate-800 flex items-center gap-2">
                              {member.username} 
                              {member.user_id === user.id && <span className="text-[10px] bg-slate-200 text-slate-500 px-1.5 py-0.5 rounded italic">你</span>}
                            </p>
                            <p className="text-[10px] text-slate-400 font-medium">{member.email}</p>
                          </div>
                        </div>
                        <div className="flex items-center gap-4">
                           <span className={`px-2 py-0.5 rounded-lg text-[9px] font-black uppercase tracking-widest ${
                             member.role === 0 ? 'bg-amber-100 text-amber-700' : 'bg-slate-200 text-slate-600'
                           }`}>
                             {member.role === 0 ? '管理员' : '成员'}
                           </span>
                           {activeTeam?.role === 0 && member.user_id !== user.id && (
                             <button 
                               onClick={() => handleRemoveMember(member.user_id, member.username)}
                               className="p-2 text-slate-300 hover:text-red-500 transition"
                               title="移除成员"
                             >
                               <LogOut className="w-4 h-4" />
                             </button>
                           )}
                        </div>
                      </div>
                    ))}
                  </div>
                </div>

                {/* Vertical Divider (Desktop) */}
                <div className="hidden lg:block w-px bg-slate-100" />

                {/* Management Section (Admin Only) */}
                <div className="w-full lg:w-96 space-y-8">
                  {/* Join Requests */}
                  {activeTeam?.role === 0 && (
                    <div>
                      <div className="flex items-center justify-between mb-6">
                        <h3 className="text-base font-black text-slate-800 flex items-center gap-2">
                          <MessageSquare className="w-5 h-5 text-emerald-500" /> 待处理审批
                        </h3>
                        {joinRequests.length > 0 && <span className="bg-rose-500 text-white text-[10px] px-1.5 py-0.5 rounded-full font-black">{joinRequests.length}</span>}
                      </div>

                      {joinRequests.length === 0 ? (
                        <div className="bg-slate-50 border border-dashed border-slate-200 rounded-2xl p-8 text-center">
                          <p className="text-xs font-bold text-slate-400 uppercase tracking-widest">当前无待处理申请</p>
                        </div>
                      ) : (
                        <div className="space-y-3">
                          {joinRequests.map(req => (
                            <div key={req.user_id} className="bg-white p-4 rounded-2xl border border-slate-200 shadow-sm animate-in zoom-in-95">
                              <div className="flex items-center gap-3 mb-3">
                                <div className="w-10 h-10 rounded-xl bg-slate-50 flex items-center justify-center">
                                  <User className="w-5 h-5 text-slate-400" />
                                </div>
                                <div>
                                  <p className="text-sm font-bold text-slate-800">{req.username}</p>
                                  <p className="text-[10px] text-slate-400">申请时间: {new Date(req.requested_at).toLocaleDateString()}</p>
                                </div>
                              </div>
                              <div className="flex gap-2">
                                <button 
                                  onClick={() => handleProcessRequest(req.user_id, 'approve')}
                                  className="flex-1 bg-indigo-600 text-white text-[10px] font-black py-2 rounded-xl hover:bg-indigo-700 transition uppercase tracking-widest"
                                >
                                  批 准
                                </button>
                                <button 
                                  onClick={() => handleProcessRequest(req.user_id, 'reject')}
                                  className="flex-1 bg-slate-100 text-slate-600 text-[10px] font-black py-2 rounded-xl hover:bg-slate-200 transition uppercase tracking-widest"
                                >
                                  拒 绝
                                </button>
                              </div>
                            </div>
                          ))}
                        </div>
                      )}
                    </div>
                  )}

                  {/* Share/Invite Section */}
                  <div>
                    <h3 className="text-base font-black text-slate-800 flex items-center gap-2 mb-6">
                      <UserPlus className="w-5 h-5 text-blue-500" /> 邀请新成员
                    </h3>
                    <div className="bg-slate-50 rounded-3xl p-6 space-y-4 border border-slate-100">
                      <div className="bg-white p-4 rounded-2xl border border-slate-100 shadow-sm">
                        <p className="text-[10px] font-black text-slate-400 uppercase tracking-widest mb-2">邀请码</p>
                        <div className="flex items-center justify-between">
                          <code className="text-xl font-black text-indigo-600 tracking-tighter">
                            {activeTeam?.invite_code || '------'}
                          </code>
                          <button 
                            className="p-2 text-slate-400 hover:text-indigo-600 transition"
                            onClick={() => {
                                if (activeTeam?.invite_code) {
                                    navigator.clipboard.writeText(activeTeam.invite_code);
                                    alert('邀请码已复制到剪贴板');
                                }
                            }}
                          >
                            <LinkIcon className="w-4 h-4" />
                          </button>
                        </div>
                      </div>
                      <p className="text-[11px] text-slate-400 font-medium leading-relaxed">
                        管理员生成邀请码后，其他用户可以通过输入该代码来申请加入团队。
                      </p>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          )}
        </div>
      </div>

      {/* Modals */}
      {showCreateModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
          <div className="absolute inset-0 bg-slate-900/60 backdrop-blur-sm animate-in fade-in" onClick={() => setShowCreateModal(false)} />
          <form 
            onSubmit={handleCreateTeam}
            className="w-full max-w-md bg-white rounded-[2.5rem] p-10 shadow-2xl relative animate-in zoom-in-95 duration-200"
          >
            <h3 className="text-2xl font-black text-slate-800 mb-6">创建新团队</h3>
            <div className="space-y-4">
              <div className="relative group">
                <Users className="absolute left-4 top-4 w-5 h-5 text-slate-400" />
                <input
                  type="text"
                  required
                  placeholder="团队名称"
                  value={newTeamName}
                  onChange={e => setNewTeamName(e.target.value)}
                  className="w-full bg-slate-50 border-2 border-slate-100 pl-12 pr-4 py-4 rounded-2xl focus:border-indigo-500 focus:bg-white outline-none transition-all text-slate-900 font-bold"
                  autoFocus
                />
              </div>
              <button
                disabled={actionLoading}
                type="submit"
                className="w-full bg-indigo-600 text-white font-black py-4 rounded-2xl mt-4 hover:bg-indigo-700 active:scale-[0.98] transition-all shadow-xl shadow-indigo-100 disabled:opacity-50 flex items-center justify-center gap-3 text-lg"
              >
                {actionLoading ? <Loader2 className="w-6 h-6 animate-spin" /> : '立即创建'}
              </button>
              <button
                type="button"
                onClick={() => setShowCreateModal(false)}
                className="w-full py-4 text-slate-400 font-bold hover:text-slate-600"
              >
                取 消
              </button>
            </div>
          </form>
        </div>
      )}

      {showJoinModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
          <div className="absolute inset-0 bg-slate-900/60 backdrop-blur-sm animate-in fade-in" onClick={() => setShowJoinModal(false)} />
          <form 
            onSubmit={handleJoinTeam}
            className="w-full max-w-md bg-white rounded-[2.5rem] p-10 shadow-2xl relative animate-in zoom-in-95 duration-200"
          >
            <h3 className="text-2xl font-black text-slate-800 mb-6">加入他人的团队</h3>
            <div className="space-y-4">
              <div className="relative group">
                <Search className="absolute left-4 top-4 w-5 h-5 text-slate-400" />
                <input
                  type="text"
                  required
                  maxLength={6}
                  placeholder="输入6位邀请码"
                  value={inviteCode}
                  onChange={e => setInviteCode(e.target.value.toUpperCase())}
                  className="w-full bg-slate-50 border-2 border-slate-100 pl-12 pr-4 py-4 rounded-2xl focus:border-indigo-500 focus:bg-white outline-none transition-all text-center text-2xl font-black tracking-[0.2em] uppercase"
                  autoFocus
                />
              </div>
              <button
                disabled={actionLoading}
                type="submit"
                className="w-full bg-indigo-600 text-white font-black py-4 rounded-2xl mt-4 hover:bg-indigo-700 active:scale-[0.98] transition-all shadow-xl shadow-indigo-100 disabled:opacity-50 flex items-center justify-center gap-3 text-lg"
              >
                {actionLoading ? <Loader2 className="w-6 h-6 animate-spin" /> : '发送加入申请'}
              </button>
              <div className="bg-amber-50 rounded-2xl p-4 flex gap-3">
                <AlertCircle className="w-5 h-5 text-amber-500 shrink-0 mt-0.5" />
                <p className="text-[11px] leading-relaxed text-amber-700 font-medium">
                  加入团队后，你的同步内容（待办、番茄钟）可能会被团队其他成员查看或协作。请确认邀请人的身份。
                </p>
              </div>
              <button
                type="button"
                onClick={() => setShowJoinModal(false)}
                className="w-full py-4 text-slate-400 font-bold hover:text-slate-600"
              >
                取 消
              </button>
            </div>
          </form>
        </div>
      )}
    </div>
  );
};
