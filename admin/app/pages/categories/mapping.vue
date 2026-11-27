<script setup lang="ts">
import type { CategoryRow, CoverageRow, Page } from '~/utils/types'
import { bulkPayload, confidentIds, initialChoices, selectByConfidence, selectionState, toggleAll, CONFIDENCE_DEFAULT, CONFIDENCE_MIN, CONFIDENCE_STEP, type RawCategory } from '~/utils/mapping'

const { api } = useApi()
const toast = useToast()
const page = ref(1)
const size = 100
const q = ref('')
const onlyUnmapped = ref(true)
const sort = ref<'usage' | 'recent'>('usage')

const { data: cats } = await useAsyncData('categories-brief', () => api<CategoryRow[]>('/admin/v1/categories'))
const categoryItems = computed(() => (cats.value ?? []).map(c => ({ label: c.name, value: c.id })))

const { data: cov, refresh: refreshCov } = await useAsyncData('coverage', () =>
  api<{ by_source: CoverageRow[], raw_categories_unmapped: number }>('/admin/v1/categories/coverage'))

const { data, status, error, refresh } = await useAsyncData('raw-categories', () =>
  api<Page<RawCategory>>('/admin/v1/raw-categories', {
    query: { page: page.value, size, q: q.value || undefined, unmapped: onlyUnmapped.value ? '1' : undefined, sort: sort.value === 'recent' ? 'recent' : undefined }
  }), { watch: [page, onlyUnmapped, sort] })
const items = computed(() => data.value?.items ?? [])

// 화면에서 고른 카테고리 (저장 전). 목록이 바뀌면 추천으로 다시 채움
const choices = ref<Record<number, number | undefined>>({})
const selected = ref<number[]>([])
watch(items, (v) => {
  choices.value = initialChoices(v)
  selected.value = []
}, { immediate: true })

const isSelected = (id: number) => selected.value.includes(id)
function toggle(id: number, v: boolean) {
  selected.value = v ? [...selected.value, id] : selected.value.filter(x => x !== id)
}
// 신뢰도 기준 (슬라이더, 백분율). 기준 이상 추천을 한 번에 선택
const threshold = ref(Math.round(CONFIDENCE_DEFAULT * 100))
const confident = computed(() => confidentIds(items.value, threshold.value / 100))
function selectConfident() {
  selected.value = selectByConfidence(selected.value, items.value, threshold.value / 100)
}
// 표 머리 칸: 이 페이지 전체 선택/해제
const allState = computed(() => selectionState(selected.value, items.value))
function onToggleAll(v: boolean | 'indeterminate') {
  selected.value = toggleAll(selected.value, items.value, v === true)
}
function clearSelection() {
  selected.value = []
}
const payload = computed(() => bulkPayload(selected.value, choices.value))

const busy = ref(false)
async function save(body: { items: { raw_category_id: number, category_id: number | null }[] }, msg: string) {
  busy.value = true
  try {
    const r = await api<{ updated: number }>('/admin/v1/raw-categories/bulk-mapping', { method: 'POST', body })
    toast.add({ title: `${msg} ${fmtNum(r.updated)}개`, description: '다음 수집(매일 새벽)부터 캠페인에 반영됩니다.', color: 'success' })
    await Promise.all([refresh(), refreshCov()])
  } catch (e) {
    toast.add({ title: '저장하지 못했습니다', description: apiErrorMessage(e), color: 'error' })
  } finally {
    busy.value = false
  }
}
const saveSelected = () => save(payload.value, '매핑')
function saveOne(r: RawCategory) {
  const c = choices.value[r.id]
  if (c != null) save({ items: [{ raw_category_id: r.id, category_id: c }] }, '매핑')
}
const unmapOne = (r: RawCategory) => save({ items: [{ raw_category_id: r.id, category_id: null }] }, '매핑 해제')

function search() {
  page.value = 1
  refresh()
}

const total = computed(() => cov.value?.by_source.find(s => s.source === '전체'))
// 추천 배지 색: 지금 기준 이상이면 초록 (선택 버튼이 고르는 항목과 같게)
const confColor = (c: number) => (Math.round(c * 100) >= threshold.value ? 'success' : c >= 0.5 ? 'warning' : 'neutral')
</script>

<template>
  <UContainer class="py-8">
    <PageHeader
      title="원본 카테고리 매핑"
      description="수집처(네이버 지역 검색 등)의 원본 카테고리를 리뷰맵 카테고리에 연결합니다. 연결이 없으면 그 캠페인은 카테고리 없이 저장되어 앱 필터에 나오지 않습니다."
    />

    <div class="mb-6 grid gap-4 sm:grid-cols-3">
      <UCard>
        <div class="text-sm text-muted">
          미매핑 원본
        </div>
        <div class="text-3xl font-bold">
          {{ fmtNum(cov?.raw_categories_unmapped) }}
        </div>
      </UCard>
      <UCard>
        <div class="text-sm text-muted">
          카테고리 없는 활성 캠페인
        </div>
        <div class="text-3xl font-bold">
          {{ fmtPct(total?.no_category_ratio) }}
        </div>
        <div class="text-xs text-muted">
          {{ fmtNum(total?.no_category) }} / {{ fmtNum(total?.total) }}건
        </div>
      </UCard>
      <UCard>
        <div class="text-sm text-muted">
          출처별
        </div>
        <div
          v-for="s in cov?.by_source.filter(x => x.source !== '전체') ?? []"
          :key="s.source"
          class="flex justify-between text-sm"
        >
          <span>{{ s.source }}</span><span>{{ fmtPct(s.no_category_ratio) }}</span>
        </div>
      </UCard>
    </div>

    <div class="mb-4 flex flex-wrap items-center gap-2">
      <form
        class="flex gap-2"
        @submit.prevent="search"
      >
        <UInput
          v-model="q"
          icon="i-lucide-search"
          placeholder="원본 카테고리 검색"
          class="w-64"
        />
        <UButton
          type="submit"
          label="검색"
        />
      </form>
      <USwitch
        v-model="onlyUnmapped"
        label="미매핑만"
      />
      <USelect
        v-model="sort"
        :items="[{ label: '많이 쓰인 순', value: 'usage' }, { label: '최근 생긴 순', value: 'recent' }]"
        class="w-36"
      />
      <div class="ml-auto flex flex-wrap items-center gap-2">
        <div class="flex items-center gap-2 rounded-md border border-default px-3 py-1.5">
          <span class="text-sm text-muted whitespace-nowrap">신뢰도</span>
          <USlider
            v-model="threshold"
            :min="Math.round(CONFIDENCE_MIN * 100)"
            :max="100"
            :step="Math.round(CONFIDENCE_STEP * 100)"
            class="w-32"
            aria-label="신뢰도 기준"
          />
          <span class="w-10 text-right text-sm font-semibold tabular-nums">{{ threshold }}%</span>
        </div>
        <UButton
          color="neutral"
          variant="outline"
          icon="i-lucide-sparkles"
          :label="`${threshold}% 이상 선택 (${confident.length})`"
          :disabled="!confident.length"
          @click="selectConfident"
        />
        <UButton
          v-if="selected.length"
          color="neutral"
          variant="ghost"
          icon="i-lucide-x"
          :label="`선택 해제 (${selected.length})`"
          @click="clearSelection"
        />
        <UButton
          icon="i-lucide-check-check"
          :label="`선택한 ${payload.items.length}개 매핑`"
          :disabled="!payload.items.length"
          :loading="busy"
          @click="saveSelected"
        />
      </div>
    </div>

    <UAlert
      v-if="error"
      color="error"
      variant="subtle"
      :title="apiErrorMessage(error)"
      class="mb-4"
    />
    <UTable
      :data="items"
      :columns="[
        { accessorKey: 'select', header: '' },
        { accessorKey: 'raw_text', header: '원본 카테고리' },
        { accessorKey: 'usage', header: '사용' },
        { accessorKey: 'suggestion', header: '추천' },
        { accessorKey: 'choice', header: '리뷰맵 카테고리' },
        { accessorKey: 'actions', header: '' }
      ]"
      :loading="status === 'pending'"
      empty="매핑할 원본 카테고리가 없습니다."
      class="rounded-lg border border-default bg-default"
    >
      <template #select-header>
        <UCheckbox
          :model-value="allState"
          :disabled="!items.length"
          aria-label="이 페이지 전체 선택"
          @update:model-value="onToggleAll"
        />
      </template>
      <template #select-cell="{ row }">
        <UCheckbox
          :model-value="isSelected(row.original.id)"
          :aria-label="`${row.original.raw_text} 선택`"
          @update:model-value="(v) => toggle(row.original.id, v === true)"
        />
      </template>
      <template #raw_text-cell="{ row }">
        <span class="font-medium">{{ row.original.raw_text }}</span>
        <UBadge
          v-if="row.original.category_name"
          class="ml-2"
          size="sm"
          variant="subtle"
          :label="`현재: ${row.original.category_name}`"
        />
      </template>
      <template #usage-cell="{ row }">
        {{ fmtNum(row.original.usage) }}
      </template>
      <template #suggestion-cell="{ row }">
        <UTooltip
          v-if="row.original.suggestion"
          :text="row.original.suggestion.basis"
        >
          <UBadge
            :color="confColor(row.original.suggestion.confidence)"
            variant="subtle"
            :label="`${row.original.suggestion.category_name} ${fmtPct(row.original.suggestion.confidence, 0)}`"
          />
        </UTooltip>
        <span
          v-else
          class="text-xs text-dimmed"
        >추천 없음</span>
      </template>
      <template #choice-cell="{ row }">
        <USelect
          v-model="choices[row.original.id]"
          :items="categoryItems"
          placeholder="선택"
          class="w-36"
        />
      </template>
      <template #actions-cell="{ row }">
        <div class="flex justify-end gap-1">
          <UButton
            size="sm"
            label="저장"
            :disabled="choices[row.original.id] == null || choices[row.original.id] === row.original.category_id || busy"
            @click="saveOne(row.original)"
          />
          <UButton
            v-if="row.original.category_id"
            size="sm"
            color="neutral"
            variant="ghost"
            label="해제"
            :disabled="busy"
            @click="unmapOne(row.original)"
          />
        </div>
      </template>
    </UTable>
    <AppPager
      v-model:page="page"
      :total="data?.total ?? 0"
      :size="size"
    />
  </UContainer>
</template>
