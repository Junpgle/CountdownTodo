export interface AppInfo {
  version: string;
  url: string;
  desc: string;
}

export interface User {
  id: number;
  username: string;
  email: string;
  tier?: string;
}

export interface TodoItem {
  id: string;
  uuid: string;
  content: string;
  is_completed: boolean;
  is_deleted: boolean;
  version: number;
  updated_at: number;
  created_at: number;
  created_date: number | null;
  due_date: number | null;
  device_id: string;
  recurrence?: number;
  custom_interval_days?: number | null;
  recurrence_end_date?: number | null;
  remark?: string | null;
  group_id?: string | null;
  // --- Team Fields ---
  team_uuid?: string | null;
  team_name?: string | null;
  creator_name?: string | null;
  collab_type?: number; // 0: Shared, 1: Independent
  reminder_minutes?: number | null;
}

export interface TodoGroup {
  id: string;
  uuid: string;
  name: string;
  is_expanded: boolean;
  is_deleted: boolean;
  version: number;
  updated_at: number;
  created_at: number;
  // --- Team Fields ---
  team_uuid?: string | null;
  team_name?: string | null;
}

export interface CountdownItem {
  id: string;
  uuid: string;
  title: string;
  target_time: number;
  is_deleted: boolean;
  version: number;
  updated_at: number;
  created_at: number;
  device_id: string;
  // --- Team Fields ---
  team_uuid?: string | null;
  team_name?: string | null;
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
  device_id?: string | null;
  version: number;
  created_at: number;
  updated_at: number;
  is_deleted: boolean | number;
}
export interface PomodoroTag {
  uuid: string;
  name: string;
  color: string;
  is_deleted: boolean;
  version: number;
  created_at: number;
  updated_at: number;
}
export interface Team {
  uuid: string;
  name: string;
  creator_id: number;
  created_at: number;
  role?: number; // 0: Admin, 1: Member
  member_count?: number;
  invite_code?: string | null;
}

export interface TeamMember {
  user_id: number;
  username: string;
  email: string;
  avatar_url?: string;
  role: number;
  joined_at: number;
}

export interface JoinRequest {
  id: number;
  team_uuid: string;
  user_id: number;
  username?: string;
  avatar_url?: string;
  status: number; // 0: Pending, 1: Approved, 2: Rejected, 3: Invitation
  message?: string;
  requested_at: number;
  team_name?: string; // For invitations
}

export interface TeamAnnouncement {
  uuid: string;
  team_uuid: string;
  creator_id: number;
  creator_name?: string;
  title: string;
  content: string;
  is_priority: boolean | number;
  expires_at: number | null;
  created_at: number;
  updated_at: number;
  is_read?: boolean | number;
}

export interface AnnouncementStats {
  total_members: number;
  read_count: number;
  read_rate: number;
  read_members: Array<{
    username: string;
    read_at: number;
  }>;
}
