<script setup lang="ts">
import type { CoverageRow, Summary } from '~/utils/types'

const { api } = useApi()
const { data, error } = await useAsyncData('summary', () => api<Summary>('/admin/v1/summary'))
const { data: cov } = await useAsyncData('coverage', () =>
  api<{ by_source: CoverageRow[], raw_categories_unmapped: number }>('/admin/v1/categories/coverage'))

const cards = computed(() => {
  const s = data.value
  if (!s) return []
  return [
    { label: '전체 사용자', value: fmtNum(s.users_total), sub: `오늘 가입 ${fmtNum(s.users_today)}명`, icon: 'i-lucide-users', to: '/users' },
    { label: '활성 키워드', value: fmtNum(s.keywords_active), sub: `최근 7일 알림 ${fmtNum(s.alerts_last_7_days)}건`, icon: 'i-lucide-tag', to: '/keywords' },
    { label: '활성 캠페인', value: fmtNum(s.campaigns_active), sub: `삭제됨 ${fmtNum(s.campaigns_deleted)}건`, icon: 'i-lucide-map-pin', to: '/campaigns' },
    {
      label: '카테고리 없는 캠페인',
      value: fmtNum(s.campaigns_no_category),
      sub: `미매핑 원본 ${fmtNum(s.raw_categories_unmapped)}개`,
      icon: 'i-lucide-folder-x',
      to: '/categories/mapping',
      warn: s.raw_categories_unmapped > 50
    }
  ]
})
</script>

<template>
  <UContainer class="py-8">
    <PageHeader
      title="대시보드"
      description="리뷰맵 데이터 요약. 숫자를 누르면 해당 화면으로 이동합니다."
    />
    <UAlert
      v-if="error"
      color="error"
      variant="subtle"
      :title="apiErrorMessage(error)"
      class="mb-4"
    />

    <div class="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
      <NuxtLink
        v-for="c in cards"
        :key="c.label"
        :to="c.to"
      >
        <UCard :class="c.warn ? 'ring-2 ring-warning' : ''">
          <div class="flex items-start justify-between">
            <div>
              <div class="text-sm text-muted">
                {{ c.label }}
              </div>
              <div class="mt-1 text-3xl font-bold">
                {{ c.value }}
              </div>
              <div class="mt-1 text-xs text-muted">
                {{ c.sub }}
              </div>
            </div>
            <UIcon
              :name="c.icon"
              class="size-6 text-primary"
            />
          </div>
        </UCard>
      </NuxtLink>
    </div>

    <div class="mt-8 grid gap-6 lg:grid-cols-2">
      <UCard>
        <template #header>
          <div class="font-semibold">
            출처별 카테고리 없는 캠페인
          </div>
          <div class="text-xs text-muted">
            카테고리가 없으면 앱의 카테고리 필터에 나오지 않습니다. 매핑하면 다음 수집(매일 새벽)부터 반영됩니다.
          </div>
        </template>
        <UTable
          :data="cov?.by_source ?? []"
          :columns="[
            { accessorKey: 'source', header: '출처' },
            { accessorKey: 'total', header: '활성 캠페인' },
            { accessorKey: 'no_category', header: '카테고리 없음' },
            { accessorKey: 'no_category_ratio', header: '비율' }
          ]"
        >
          <template #total-cell="{ row }">
            {{ fmtNum(row.original.total) }}
          </template>
          <template #no_category-cell="{ row }">
            {{ fmtNum(row.original.no_category) }}
          </template>
          <template #no_category_ratio-cell="{ row }">
            <UBadge
              :color="row.original.no_category_ratio > 0.3 ? 'error' : row.original.no_category_ratio > 0.1 ? 'warning' : 'success'"
              variant="subtle"
              :label="fmtPct(row.original.no_category_ratio)"
            />
          </template>
        </UTable>
      </UCard>

      <UCard>
        <template #header>
          <div class="flex items-center justify-between">
            <span class="font-semibold">최근 변경</span>
            <UButton
              size="xs"
              variant="link"
              label="전체 보기"
              to="/audit"
            />
          </div>
        </template>
        <ul class="divide-y divide-default text-sm">
          <li
            v-for="l in data?.recent_changes ?? []"
            :key="l.id"
            class="flex justify-between gap-2 py-2"
          >
            <span>
              {{ ENTITY_LABELS[l.entity] ?? l.entity }} {{ ACTION_LABELS[l.action] ?? l.action }}
              <span
                v-if="l.entity_id"
                class="text-muted"
              >#{{ l.entity_id }}</span>
            </span>
            <span class="shrink-0 text-xs text-muted">{{ l.admin_email }} · {{ fmtDateTime(l.created_at) }}</span>
          </li>
          <li
            v-if="!data?.recent_changes?.length"
            class="py-2 text-muted"
          >
            아직 변경 기록이 없습니다.
          </li>
        </ul>
      </UCard>
    </div>
  </UContainer>
</template>
