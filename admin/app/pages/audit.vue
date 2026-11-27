<script setup lang="ts">
import type { AuditLog, Page } from '~/utils/types'

const { api } = useApi()
const page = ref(1)
const entity = ref('all')

const { data, status, error } = await useAsyncData('audit', () =>
  api<Page<AuditLog>>('/admin/v1/audit-logs', { query: { page: page.value, entity: entity.value === 'all' ? undefined : entity.value } }),
{ watch: [page, entity] })

const entityItems = [{ label: '모든 대상', value: 'all' }, ...Object.entries(ENTITY_LABELS).map(([value, label]) => ({ label, value }))]
const pretty = (s?: string) => (s ? JSON.stringify(JSON.parse(s), null, 2) : '-')
const expanded = ref<number | null>(null)
</script>

<template>
  <UContainer class="py-8">
    <PageHeader
      title="변경 기록"
      description="관리자 화면에서 바꾼 모든 내용 (누가, 언제, 바꾸기 전·후). 기록은 삭제할 수 없습니다."
    >
      <USelect
        v-model="entity"
        :items="entityItems"
        class="w-44"
        @update:model-value="page = 1"
      />
    </PageHeader>
    <UAlert
      v-if="error"
      color="error"
      variant="subtle"
      :title="apiErrorMessage(error)"
      class="mb-4"
    />
    <UTable
      :data="data?.items ?? []"
      :columns="[
        { accessorKey: 'created_at', header: '시각' },
        { accessorKey: 'admin_email', header: '관리자' },
        { accessorKey: 'what', header: '내용' },
        { accessorKey: 'detail', header: '' }
      ]"
      :loading="status === 'pending'"
      empty="기록이 없습니다."
      class="rounded-lg border border-default bg-default"
    >
      <template #created_at-cell="{ row }">
        {{ fmtDateTime(row.original.created_at) }}
      </template>
      <template #what-cell="{ row }">
        {{ ENTITY_LABELS[row.original.entity] ?? row.original.entity }}
        {{ ACTION_LABELS[row.original.action] ?? row.original.action }}
        <span
          v-if="row.original.entity_id"
          class="text-muted"
        >#{{ row.original.entity_id }}</span>
        <div
          v-if="expanded === row.original.id"
          class="mt-2 grid gap-2 md:grid-cols-2"
        >
          <pre class="overflow-x-auto rounded bg-muted p-2 text-xs">전: {{ pretty(row.original.before) }}</pre>
          <pre class="overflow-x-auto rounded bg-muted p-2 text-xs">후: {{ pretty(row.original.after) }}</pre>
        </div>
      </template>
      <template #detail-cell="{ row }">
        <UButton
          size="xs"
          color="neutral"
          variant="ghost"
          :label="expanded === row.original.id ? '접기' : '전·후 보기'"
          @click="expanded = expanded === row.original.id ? null : row.original.id"
        />
      </template>
    </UTable>
    <AppPager
      v-model:page="page"
      :total="data?.total ?? 0"
      :size="data?.size ?? 50"
    />
  </UContainer>
</template>
