<script setup lang="ts">
import type { CategoryRow } from '~/utils/types'

const { api } = useApi()
const toast = useToast()
const { data, status, error, refresh } = await useAsyncData('categories', () => api<CategoryRow[]>('/admin/v1/categories'))
const rows = computed(() => data.value ?? [])

const busy = ref(false)
async function act(fn: () => Promise<unknown>, done: string) {
  busy.value = true
  try {
    await fn()
    toast.add({ title: done, color: 'success' })
    await refresh()
    return true
  } catch (e) {
    toast.add({ title: '처리하지 못했습니다', description: apiErrorMessage(e), color: 'error' })
    return false
  } finally {
    busy.value = false
  }
}

const newName = ref('')
async function create() {
  const name = newName.value.trim()
  if (!name) return
  if (await act(() => api('/admin/v1/categories', { method: 'POST', body: { name } }), `"${name}" 추가`)) newName.value = ''
}

const editing = ref<{ id: number, name: string } | null>(null)
async function saveName() {
  if (!editing.value) return
  const e = editing.value
  if (await act(() => api(`/admin/v1/categories/${e.id}`, { method: 'PATCH', body: { name: e.name.trim() } }), '이름을 바꿨습니다')) editing.value = null
}

// 순서: 위/아래로 옮긴 뒤 전체 순서를 저장
function move(i: number, d: -1 | 1) {
  const ids = rows.value.map(r => r.id)
  const j = i + d
  if (j < 0 || j >= ids.length) return
  ;[ids[i], ids[j]] = [ids[j]!, ids[i]!]
  act(() => api('/admin/v1/categories/order', { method: 'PUT', body: { ids } }), '순서를 바꿨습니다')
}

const remove = (r: CategoryRow) => act(() => api(`/admin/v1/categories/${r.id}`, { method: 'DELETE' }), `"${r.name}" 삭제`)
</script>

<template>
  <UContainer class="py-8">
    <PageHeader
      title="카테고리"
      description="앱의 카테고리 필터에 보이는 표준 카테고리. 순서는 앱 표시 순서입니다. 캠페인이나 매핑에서 쓰는 카테고리는 삭제할 수 없습니다."
    >
      <UButton
        icon="i-lucide-git-merge"
        label="원본 카테고리 매핑"
        to="/categories/mapping"
        variant="outline"
      />
    </PageHeader>
    <form
      class="mb-4 flex gap-2"
      @submit.prevent="create"
    >
      <UInput
        v-model="newName"
        placeholder="새 카테고리 이름"
        class="w-64"
      />
      <UButton
        type="submit"
        icon="i-lucide-plus"
        label="추가"
        :loading="busy"
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
      :data="rows"
      :columns="[
        { accessorKey: 'order', header: '순서' },
        { accessorKey: 'name', header: '이름' },
        { accessorKey: 'campaign_count', header: '캠페인' },
        { accessorKey: 'mapping_count', header: '매핑된 원본' },
        { accessorKey: 'actions', header: '' }
      ]"
      :loading="status === 'pending'"
      class="rounded-lg border border-default bg-default"
    >
      <template #order-cell="{ row }">
        <div class="flex items-center gap-1">
          <UButton
            size="xs"
            color="neutral"
            variant="ghost"
            icon="i-lucide-chevron-up"
            aria-label="위로"
            :disabled="row.index === 0 || busy"
            @click="move(row.index, -1)"
          />
          <UButton
            size="xs"
            color="neutral"
            variant="ghost"
            icon="i-lucide-chevron-down"
            aria-label="아래로"
            :disabled="row.index === rows.length - 1 || busy"
            @click="move(row.index, 1)"
          />
        </div>
      </template>
      <template #name-cell="{ row }">
        <form
          v-if="editing?.id === row.original.id"
          class="flex gap-2"
          @submit.prevent="saveName"
        >
          <UInput
            v-model="editing.name"
            size="sm"
          />
          <UButton
            type="submit"
            size="sm"
            label="저장"
          />
          <UButton
            size="sm"
            color="neutral"
            variant="ghost"
            label="취소"
            @click="editing = null"
          />
        </form>
        <span
          v-else
          class="font-medium"
        >{{ row.original.name }}</span>
      </template>
      <template #campaign_count-cell="{ row }">
        <NuxtLink
          :to="`/campaigns?category=${row.original.id}`"
          class="hover:underline"
        >
          {{ fmtNum(row.original.campaign_count) }}
        </NuxtLink>
      </template>
      <template #mapping_count-cell="{ row }">
        {{ fmtNum(row.original.mapping_count) }}
      </template>
      <template #actions-cell="{ row }">
        <div class="flex justify-end gap-1">
          <UButton
            size="sm"
            color="neutral"
            variant="ghost"
            icon="i-lucide-pencil"
            aria-label="이름 바꾸기"
            @click="editing = { id: row.original.id, name: row.original.name }"
          />
          <UButton
            size="sm"
            color="error"
            variant="ghost"
            icon="i-lucide-trash-2"
            aria-label="삭제"
            :disabled="row.original.campaign_count > 0 || row.original.mapping_count > 0"
            @click="remove(row.original)"
          />
        </div>
      </template>
    </UTable>
  </UContainer>
</template>
