<script setup lang="ts">
import type { AlertRow, Page } from '~/utils/types'

const route = useRoute()
const { api } = useApi()
const toast = useToast()
const page = ref(1)
const keywordId = ref<string>((route.query.keyword_id as string) ?? '')
const read = ref('all')

const { data, status, error, refresh } = await useAsyncData('alerts', () =>
  api<Page<AlertRow>>('/admin/v1/alerts', {
    query: { page: page.value, keyword_id: keywordId.value || undefined, is_read: read.value === 'all' ? undefined : read.value }
  }), { watch: [page, read] })

// 일괄 정리: 기준일 이전 알림 soft delete (먼저 건수 확인)
const cleanup = reactive({ before: kstDateInput(new Date(), 30), onlyRead: true })
const preview = ref<number | null>(null)
const busy = ref(false)

function body(dryRun: boolean) {
  return {
    before: cleanup.before,
    is_read: cleanup.onlyRead ? true : undefined,
    keyword_id: keywordId.value ? Number(keywordId.value) : undefined,
    dry_run: dryRun
  }
}

async function check() {
  busy.value = true
  try {
    const r = await api<{ matched: number }>('/admin/v1/alerts/bulk-delete', { method: 'POST', body: body(true) })
    preview.value = r.matched
  } catch (e) {
    toast.add({ title: '확인하지 못했습니다', description: apiErrorMessage(e), color: 'error' })
  } finally {
    busy.value = false
  }
}

async function run() {
  busy.value = true
  try {
    const r = await api<{ deleted: number }>('/admin/v1/alerts/bulk-delete', { method: 'POST', body: body(false) })
    toast.add({ title: `알림 ${fmtNum(r.deleted)}건 정리`, color: 'success' })
    preview.value = null
    await refresh()
  } catch (e) {
    toast.add({ title: '정리하지 못했습니다', description: apiErrorMessage(e), color: 'error' })
  } finally {
    busy.value = false
  }
}
watch(() => [cleanup.before, cleanup.onlyRead, keywordId.value], () => {
  preview.value = null
})

function search() {
  page.value = 1
  refresh()
}

const columns = [
  { accessorKey: 'keyword', header: '키워드' },
  { accessorKey: 'campaign_title', header: '캠페인' },
  { accessorKey: 'matched_field', header: '일치 항목' },
  { accessorKey: 'is_read', header: '읽음' },
  { accessorKey: 'created_at', header: '보낸 시각' }
]
</script>

<template>
  <UContainer class="py-8">
    <PageHeader
      title="키워드 알림"
      description="키워드에 맞는 새 캠페인 알림. 삭제는 soft delete(앱에서만 사라지고 DB에는 남음)입니다."
    />

    <UCard class="mb-6">
      <template #header>
        <span class="font-semibold">오래된 알림 일괄 정리</span>
      </template>
      <div class="flex flex-wrap items-end gap-3">
        <UFormField label="이 날짜 이전 (한국 시간)">
          <UInput
            v-model="cleanup.before"
            type="date"
          />
        </UFormField>
        <UCheckbox
          v-model="cleanup.onlyRead"
          label="읽은 알림만"
        />
        <span
          v-if="keywordId"
          class="text-sm text-muted"
        >키워드 #{{ keywordId }}만</span>
        <UButton
          color="neutral"
          variant="outline"
          label="대상 건수 확인"
          :loading="busy"
          @click="check"
        />
        <UButton
          v-if="preview !== null"
          color="error"
          :label="`${fmtNum(preview)}건 정리`"
          :disabled="preview === 0"
          :loading="busy"
          @click="run"
        />
      </div>
    </UCard>

    <form
      class="mb-4 flex flex-wrap gap-2"
      @submit.prevent="search"
    >
      <UInput
        v-model="keywordId"
        icon="i-lucide-hash"
        placeholder="키워드 ID"
        class="w-40"
      />
      <USelect
        v-model="read"
        :items="[{ label: '전체', value: 'all' }, { label: '읽음', value: 'true' }, { label: '안 읽음', value: 'false' }]"
        class="w-32"
      />
      <UButton
        type="submit"
        label="검색"
      />
    </form>
    <UAlert
      v-if="error"
      color="error"
      variant="subtle"
      :title="apiErrorMessage(error)"
      class="mb-4"
    />
    <UTable
      :data="data?.items ?? []"
      :columns="columns"
      :loading="status === 'pending'"
      empty="알림이 없습니다."
      class="rounded-lg border border-default bg-default"
    >
      <template #campaign_title-cell="{ row }">
        <NuxtLink
          v-if="row.original.campaign_id"
          :to="`/campaigns?id=${row.original.campaign_id}`"
          class="hover:underline"
        >
          {{ row.original.campaign_title || `#${row.original.campaign_id}` }}
        </NuxtLink>
        <span v-else>-</span>
      </template>
      <template #is_read-cell="{ row }">
        <UIcon
          :name="row.original.is_read ? 'i-lucide-check' : 'i-lucide-minus'"
          :class="row.original.is_read ? 'text-primary' : 'text-dimmed'"
        />
      </template>
      <template #created_at-cell="{ row }">
        {{ fmtDateTime(row.original.created_at) }}
      </template>
    </UTable>
    <AppPager
      v-model:page="page"
      :total="data?.total ?? 0"
      :size="data?.size ?? 50"
    />
  </UContainer>
</template>
