/** 날짜·숫자 표시 (관리자 화면 공통, 한국 시간 기준) */

const KST = 'Asia/Seoul'

export function fmtDateTime(iso?: string | null): string {
  if (!iso) return '-'
  return new Date(iso).toLocaleString('ko-KR', { timeZone: KST, dateStyle: 'short', timeStyle: 'short' })
}

export function fmtDate(iso?: string | null): string {
  if (!iso) return '-'
  return new Date(iso).toLocaleDateString('ko-KR', { timeZone: KST })
}

export function fmtPct(ratio?: number | null, digits = 1): string {
  if (ratio == null || Number.isNaN(ratio)) return '-'
  return `${(ratio * 100).toFixed(digits)}%`
}

export function fmtNum(n?: number | null): string {
  return n == null ? '-' : n.toLocaleString('ko-KR')
}

/** <input type="date">용 YYYY-MM-DD (한국 날짜), days만큼 이전 */
export function kstDateInput(now: Date, daysAgo = 0): string {
  const d = new Date(now.getTime() - daysAgo * 86400000)
  return d.toLocaleDateString('sv-SE', { timeZone: KST })
}
