import { describe, expect, it } from 'vitest'
import { bulkPayload, confidentIds, initialChoices, selectByConfidence, selectionState, toggleAll, type RawCategory } from '../app/utils/mapping'
import { fmtPct, kstDateInput } from '../app/utils/format'

const items: RawCategory[] = [
  { id: 1, raw_text: '1', usage: 3381, suggestion: { category_id: 1, category_name: '맛집', confidence: 1, basis: '' }, created_at: '' },
  { id: 2, raw_text: '스포츠시설>파크골프장', usage: 2, suggestion: { category_id: 5, category_name: '액티비티', confidence: 0.57, basis: '' }, created_at: '' },
  { id: 3, raw_text: '농업>곡물재배', usage: 0, created_at: '' },
  { id: 4, raw_text: '음식점>한식', usage: 9, category_id: 1, category_name: '맛집', created_at: '' }
]

describe('매핑 선택 규칙', () => {
  it('추천이 있으면 미리 선택, 이미 매핑된 것은 현재 값', () => {
    expect(initialChoices(items)).toEqual({ 1: 1, 2: 5, 3: undefined, 4: 1 })
  })

  it('신뢰도 80% 이상이고 아직 매핑 안 된 것만', () => {
    expect(confidentIds(items)).toEqual([1])
    expect(confidentIds(items, 0.5)).toEqual([1, 2])
  })

  it('신뢰도 경계값은 백분율로 비교 (슬라이더 소수 오차)', () => {
    const edge: RawCategory[] = [{ id: 9, raw_text: 'x', usage: 1, suggestion: { category_id: 1, category_name: '맛집', confidence: 0.8, basis: '' }, created_at: '' }]
    expect(confidentIds(edge, 0.7999999999999999)).toEqual([9])
    expect(confidentIds(edge, 0.85)).toEqual([])
  })

  it('머리 칸 전체 선택 상태', () => {
    expect(selectionState([], items)).toBe(false)
    expect(selectionState([1], items)).toBe('indeterminate')
    expect(selectionState([1, 2, 3, 4], items)).toBe(true)
    expect(selectionState([1], [])).toBe(false)
  })

  it('전체 선택·해제는 이 페이지만, 다른 페이지 선택은 유지', () => {
    expect(toggleAll([99], items, true)).toEqual([99, 1, 2, 3, 4])
    expect(toggleAll([99, 1, 2], items, false)).toEqual([99])
  })

  it('신뢰도 기준으로 선택을 바꾼다 (기준을 내리면 더 많이, 올리면 줄어듦)', () => {
    expect(selectByConfidence([3, 99], items, 0.5)).toEqual([99, 1, 2])
    expect(selectByConfidence([1, 2], items, 0.9)).toEqual([1])
  })

  it('카테고리를 고르지 않은 행은 요청에서 뺀다', () => {
    expect(bulkPayload([1, 3], initialChoices(items))).toEqual({ items: [{ raw_category_id: 1, category_id: 1 }] })
  })
})

describe('표시 형식', () => {
  it('비율', () => {
    expect(fmtPct(0.496)).toBe('49.6%')
    expect(fmtPct(undefined)).toBe('-')
  })

  it('한국 날짜 (UTC 15시 = 다음 날 0시)', () => {
    expect(kstDateInput(new Date('2026-11-26T15:30:00Z'))).toBe('2026-11-27')
    expect(kstDateInput(new Date('2026-11-26T15:30:00Z'), 7)).toBe('2026-11-20')
  })
})
