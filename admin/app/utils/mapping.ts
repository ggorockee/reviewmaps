/** 원본 카테고리 매핑 화면의 선택 규칙 (계획 C-3) */

export interface Suggestion { category_id: number, category_name: string, confidence: number, basis: string }
export interface RawCategory {
  id: number
  raw_text: string
  usage: number
  category_id?: number
  category_name?: string
  suggestion?: Suggestion
  created_at: string
}

/** 화면 첫 상태: 추천이 있으면 추천 카테고리를 미리 골라 둔다 (아직 저장 안 함) */
export function initialChoices(items: RawCategory[]): Record<number, number | undefined> {
  const out: Record<number, number | undefined> = {}
  for (const it of items) out[it.id] = it.category_id ?? it.suggestion?.category_id
  return out
}

/** 신뢰도가 threshold 이상인 추천 항목 id */
export function confidentIds(items: RawCategory[], threshold = CONFIDENCE_DEFAULT): number[] {
  // 슬라이더 소수 오차(0.8 → 0.7999...) 때문에 백분율 정수로 비교
  const t = Math.round(threshold * 100)
  return items.filter(it => !it.category_id && it.suggestion && Math.round(it.suggestion.confidence * 100) >= t).map(it => it.id)
}

/** 신뢰도 기준 슬라이더 (화면에서 조절, 2026-11-27) */
export const CONFIDENCE_DEFAULT = 0.8
export const CONFIDENCE_MIN = 0.3
export const CONFIDENCE_STEP = 0.05

/** 현재 페이지 기준 전체 선택 상태: 체크박스 머리 칸 표시용 */
export function selectionState(selected: number[], items: RawCategory[]): boolean | 'indeterminate' {
  if (!items.length) return false
  const picked = items.filter(it => selected.includes(it.id)).length
  if (picked === 0) return false
  return picked === items.length ? true : 'indeterminate'
}

/** 머리 칸 체크: 이 페이지 전부 선택하거나 전부 해제 (다른 페이지 선택은 유지) */
export function toggleAll(selected: number[], items: RawCategory[], on: boolean): number[] {
  const ids = items.map(it => it.id)
  return on ? [...new Set([...selected, ...ids])] : selected.filter(id => !ids.includes(id))
}

/** 신뢰도 기준 이상 추천만 골라 선택을 바꾼다 (이 페이지의 나머지 선택은 해제) */
export function selectByConfidence(selected: number[], items: RawCategory[], threshold: number): number[] {
  const ids = items.map(it => it.id)
  const keepOtherPages = selected.filter(id => !ids.includes(id))
  return [...keepOtherPages, ...confidentIds(items, threshold)]
}

/** 선택한 행 중 카테고리를 고른 것만 일괄 매핑 요청으로 */
export function bulkPayload(selected: number[], choices: Record<number, number | undefined>) {
  return {
    items: selected
      .filter(id => choices[id] != null)
      .map(id => ({ raw_category_id: id, category_id: choices[id]! }))
  }
}
