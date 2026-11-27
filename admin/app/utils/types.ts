/** /admin/v1 응답 타입 (server/internal/adminapi) */

export interface Page<T> { items: T[], total: number, page: number, size: number }

export interface AuditLog {
  id: number
  admin_email: string
  action: string
  entity: string
  entity_id: string
  before?: string
  after?: string
  created_at: string
}

export interface Summary {
  users_total: number
  users_today: number
  keywords_active: number
  alerts_last_7_days: number
  campaigns_active: number
  campaigns_deleted: number
  campaigns_no_category: number
  raw_categories_unmapped: number
  recent_changes: AuditLog[]
}

export interface CoverageRow { source: string, total: number, no_category: number, no_category_ratio: number }

export interface UserRow {
  id: number
  email: string
  name: string
  login_method: string
  is_active: boolean
  is_staff: boolean
  date_joined: string
  last_login?: string
}

export interface UserDetail extends UserRow {
  social_accounts: { provider: string, email?: string, created_at: string }[]
  keywords: { id: number, keyword: string, is_active: boolean, created_at: string }[]
  devices: { id: number, device_type: string, token_hint: string, is_active: boolean, updated_at: string }[]
}

export interface KeywordRow {
  id: number
  keyword: string
  user_id?: number
  user_email?: string
  anonymous: boolean
  is_active: boolean
  alert_count: number
  created_at: string
}

export interface AlertRow {
  id: number
  keyword_id: number
  keyword: string
  campaign_id?: number
  campaign_title?: string
  matched_field: string
  is_read: boolean
  created_at: string
}

export interface CampaignRow {
  id: number
  platform: string
  source?: string
  company: string
  title?: string
  offer: string
  category_id?: number
  category_name?: string
  campaign_type?: string
  campaign_channel?: string
  region?: string
  address?: string
  apply_deadline?: string
  content_link?: string
  status?: string
  promotion_level: number
  created_at: string
  deleted_at?: string
}

export interface CategoryRow {
  id: number
  name: string
  display_order: number
  mapping_count: number
  campaign_count: number
  created_at: string
}

export const ACTION_LABELS: Record<string, string> = {
  create: '추가', update: '수정', delete: '삭제', restore: '복구', reorder: '순서 변경',
  map: '매핑', unmap: '매핑 해제', bulk_delete: '일괄 삭제'
}

export const ENTITY_LABELS: Record<string, string> = {
  user: '사용자', keyword: '키워드', keyword_alert: '키워드 알림', campaign: '캠페인', category: '카테고리',
  category_mapping: '카테고리 매핑', app_setting: '앱 설정'
}

export const LOGIN_METHOD_LABELS: Record<string, string> = {
  email: '이메일', google: 'Google', kakao: '카카오', apple: 'Apple'
}
