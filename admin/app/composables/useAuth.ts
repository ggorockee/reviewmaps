export interface AdminUser { email: string }
export interface AdminConfig { google_client_id: string, dev_login: boolean, password_login: boolean }

export function useAuth() {
  const user = useState<AdminUser | null>('admin-user', () => null)
  const checked = useState('admin-user-checked', () => false)
  const { api } = useApi()

  /** 세션 확인 (앱 시작 시 1회) */
  async function refresh() {
    try {
      user.value = await api<AdminUser>('/admin/v1/me')
    } catch {
      user.value = null
    } finally {
      checked.value = true
    }
  }

  async function loginWithGoogle(credential: string) {
    user.value = await api<AdminUser>('/admin/v1/auth/google', { method: 'POST', body: { credential } })
  }

  /** Google을 쓸 수 없을 때를 위한 예비 아이디/비밀번호 로그인 (서버에 설정된 경우만) */
  async function loginWithPassword(id: string, password: string) {
    user.value = await api<AdminUser>('/admin/v1/auth/password', { method: 'POST', body: { id, password } })
  }

  /** 로컬 개발 전용 (서버가 SERVER_ENV=local이고 ADMIN_DEV_EMAIL이 있을 때만) */
  async function devLogin() {
    user.value = await api<AdminUser>('/admin/v1/auth/dev', { method: 'POST' })
  }

  async function logout() {
    try {
      await api('/admin/v1/auth/logout', { method: 'POST' })
    } finally {
      user.value = null
      await navigateTo('/login')
    }
  }

  return { user, checked, refresh, loginWithGoogle, loginWithPassword, devLogin, logout }
}
