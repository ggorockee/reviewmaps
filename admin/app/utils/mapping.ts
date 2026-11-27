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
export function confidentIds(items: RawCategory[], threshold = 0.8): number[] {
  return items.filter(it => !it.category_id && it.suggestion && it.suggestion.confidence >= threshold).map(it => it.id)
}

/** 선택한 행 중 카테고리를 고른 것만 일괄 매핑 요청으로 */
export function bulkPayload(selected: number[], choices: Record<number, number | undefined>) {
  return {
    items: selected
      .filter(id => choices[id] != null)
      .map(id => ({ raw_category_id: id, category_id: choices[id]! }))
  }
}
