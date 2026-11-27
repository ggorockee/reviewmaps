<script setup lang="ts">
import type { KeywordRow, Page } from '~/utils/types'

const { api } = useApi()
const toast = useToast()
const page = ref(1)
const q = ref('')
const active = ref('all')

const { data, status, error, refresh } = await useAsyncData('keywords', () =>
  api<Page<KeywordRow>>('/admin/v1/keywords', {
    query: { page: page.value, q: q.value || undefined, is_active: active.value === 'all' ? undefined : active.value }
  }), { watch: [page, active] })

function search() {
  page.value = 1
  refresh()
}

const busy = ref<number | null>(null)
async function setActive(row: KeywordRow, v: boolean) {
  busy.value = row.id
  try {
    await api(`/admin/v1/keywords/${row.id}`, { method: 'PATCH', body: { is_active: v } })
    await refresh()
  } catch (e) {
    toast.add({ title: '변경하지 못했습니다', description: apiErrorMessage(e), color: 'error' })
  } finally {
    busy.value = null
  }
}

const target = ref<KeywordRow | null>(null)
async function remove() {
  if (!target.value) return
  try {
    await api(`/admin/v1/keywords/${target.value.id}`, { method: 'DELETE' })
    toast.add({ title: `"${target.value.keyword}" 삭제`, color: 'success' })
    target.value = null
    await refresh()
  } catch (e) {
    toast.add({ title: '삭제하지 못했습니다', description: apiErrorMessage(e), color: 'error' })
  }
}

const columns = [
  { accessorKey: 'keyword', header: '키워드' },
  { accessorKey: 'user_email', header: '사용자' },
  { accessorKey: 'alert_count', header: '알림 수' },
  { accessorKey: 'is_active', header: '알림 받기' },
  { accessorKey: 'created_at', header: '등록' },
  { accessorKey: 'actions', header: '' }
]
</script>

<template>
  <UContainer class="py-8">
    <PageHeader
      title="키워드"
      description="사용자가 등록한 알림 키워드. 끄면 새 캠페인 알림을 보내지 않습니다."
    />
    <form
      class="mb-4 flex flex-wrap gap-2"
      @submit.prevent="search"
    >
      <UInput
        v-model="q"
        icon="i-lucide-search"
        placeholder="키워드"
        class="w-64"
      />
      <USelect
        v-model="active"
        :items="[{ label: '전체', value: 'all' }, { label: '켜짐', value: 'true' }, { label: '꺼짐', value: 'false' }]"
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
      empty="키워드가 없습니다."
      class="rounded-lg border border-default bg-default"
    >
      <template #user_email-cell="{ row }">
        <NuxtLink
          v-if="row.original.user_id"
          :to="`/users/${row.original.user_id}`"
          class="text-primary hover:underline"
        >
          {{ row.original.user_email || `#${row.original.user_id}` }}
        </NuxtLink>
        <span
          v-else
          class="text-muted"
        >비회원</span>
      </template>
      <template #alert_count-cell="{ row }">
        <NuxtLink
          :to="`/alerts?keyword_id=${row.original.id}`"
          class="hover:underline"
        >
          {{ fmtNum(row.original.alert_count) }}
        </NuxtLink>
      </template>
      <template #is_active-cell="{ row }">
        <USwitch
          :model-value="row.original.is_active"
          :loading="busy === row.original.id"
          @update:model-value="(v: boolean) => setActive(row.original, v)"
        />
      </template>
      <template #created_at-cell="{ row }">
        {{ fmtDateTime(row.original.created_at) }}
      </template>
      <template #actions-cell="{ row }">
        <UButton
          color="error"
          variant="ghost"
          icon="i-lucide-trash-2"
          aria-label="삭제"
          @click="target = row.original"
        />
      </template>
    </UTable>
    <AppPager
      v-model:page="page"
      :total="data?.total ?? 0"
      :size="data?.size ?? 50"
    />
    <UModal
      :open="!!target"
      :title="`키워드 &quot;${target?.keyword}&quot;를 삭제할까요?`"
      description="이 키워드의 알림도 함께 삭제됩니다."
      @update:open="(v: boolean) => { if (!v) target = null }"
    >
      <template #footer>
        <div class="flex w-full justify-end gap-2">
          <UButton
            color="neutral"
            variant="outline"
            label="취소"
            @click="target = null"
          />
          <UButton
            color="error"
            label="삭제"
            @click="remove"
          />
        </div>
      </template>
    </UModal>
  </UContainer>
</template>
