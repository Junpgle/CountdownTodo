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
}
