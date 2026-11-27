import { describe, expect, it } from 'vitest'
import { bulkPayload, confidentIds, initialChoices, type RawCategory } from '../app/utils/mapping'
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
