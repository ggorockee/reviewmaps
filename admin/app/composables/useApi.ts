import type { FetchError } from 'ofetch'

/** Go API(/admin/v1) 호출. 세션 쿠키(rm_admin)를 함께 보낸다. */
export function useApi() {
  const config = useRuntimeConfig()
  const base = config.public.apiBase as string

  const api = $fetch.create({
    baseURL: base,
    credentials: 'include',
    async onResponseError({ request, response }) {
      // 세션 확인(/me)은 미들웨어가 직접 처리하므로 여기서 이동하지 않는다
      if (response.status !== 401 || String(request).endsWith('/admin/v1/me')) return
      useAuth().user.value = null
      if (useRouter().currentRoute.value.path !== '/login') await navigateTo('/login')
    }
  })

  return { api, base }
}

/** 서버 오류를 사람이 읽을 문장으로 */
export function apiErrorMessage(e: unknown): string {
  const err = e as FetchError<{ message?: string, error?: string }>
  const status = err?.response?.status
  const msg = err?.data?.message ?? err?.data?.error ?? (typeof err?.data === 'string' ? err.data : undefined)
  switch (status) {
    case 400: return `입력값을 확인해 주세요${msg ? `: ${msg}` : '.'}`
    case 401: return '로그인이 필요합니다.'
    case 403: return msg === 'origin not allowed' ? '허용되지 않은 주소에서 보낸 요청입니다.' : '관리자 권한이 없는 계정입니다.'
    case 404: return '대상을 찾을 수 없습니다. 이미 삭제됐을 수 있습니다.'
    case 409: return msg === 'category is used by campaigns or mappings'
      ? '캠페인이나 매핑에서 쓰는 카테고리라 삭제할 수 없습니다.'
      : '이미 같은 이름이 있습니다.'
    case 429: return '로그인 시도가 너무 많습니다. 1분 뒤 다시 시도해 주세요.'
    case 503: return '서버 또는 데이터베이스에 연결할 수 없습니다.'
  }
  return msg ?? '요청을 처리하지 못했습니다.'
}
