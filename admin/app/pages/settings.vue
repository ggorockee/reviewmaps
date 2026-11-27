<script setup lang="ts">
const { api } = useApi()
const toast = useToast()

interface Setting { key: string, value: unknown, description?: string, editable: boolean, stored: boolean, min?: number, max?: number, default?: number, updated_at?: string }
interface AppVersion { id: number, platform: string, version: string, minimum_version: string, force_update: boolean, is_active: boolean, updated_at: string }
interface AdConfig { id: number, platform: string, ad_network: string, is_enabled: boolean, priority: number }
interface RateLimit { id: number, endpoint: string, max_requests: number, window_seconds: number, is_enabled: boolean }

const { data: settings, refresh } = await useAsyncData('settings', () => api<Setting[]>('/admin/v1/settings'))
const { data: versions } = await useAsyncData('app-versions', () => api<{ items: AppVersion[], note: string }>('/admin/v1/app-versions'))
const { data: ads } = await useAsyncData('ad-configs', () => api<AdConfig[]>('/admin/v1/ad-configs'))
const { data: limits } = await useAsyncData('rate-limits', () => api<RateLimit[]>('/admin/v1/rate-limits'))

const edits = ref<Record<string, number>>({})
watch(settings, (v) => {
  edits.value = Object.fromEntries((v ?? []).filter(s => s.editable).map(s => [s.key, typeof s.value === 'number' ? s.value : (s.default ?? s.min ?? 1)]))
}, { immediate: true })

const busy = ref<string | null>(null)
async function save(s: Setting) {
  busy.value = s.key
  try {
    await api(`/admin/v1/settings/${s.key}`, { method: 'PUT', body: { value: edits.value[s.key] } })
    toast.add({ title: `${s.key} 저장`, description: '앱이 다음에 설정을 불러올 때 반영됩니다.', color: 'success' })
    await refresh()
  } catch (e) {
    toast.add({ title: '저장하지 못했습니다', description: apiErrorMessage(e), color: 'error' })
  } finally {
    busy.value = null
  }
}
</script>

<template>
  <UContainer class="py-8">
    <PageHeader
      title="설정·앱 버전"
      description="서버가 앱에 주는 설정. 앱 버전·광고는 Firebase Remote Config로 옮겨 여기서는 읽기 전용입니다."
    />

    <UCard class="mb-6">
      <template #header>
        <span class="font-semibold">앱 설정</span>
      </template>
      <div class="divide-y divide-default">
        <div
          v-for="s in settings ?? []"
          :key="s.key"
          class="flex flex-wrap items-center justify-between gap-3 py-3"
        >
          <div>
            <div class="font-medium">
              {{ s.description || s.key }}
            </div>
            <div class="text-xs text-muted">
              {{ s.key }}<span v-if="s.editable"> · {{ s.min }}~{{ s.max }}</span><span v-if="s.stored && s.updated_at"> · 수정 {{ fmtDateTime(s.updated_at) }}</span><span v-else-if="!s.stored"> · 저장된 값 없음 (서버 기본값 {{ s.default }} 사용 중)</span>
            </div>
          </div>
          <div
            v-if="s.editable"
            class="flex gap-2"
          >
            <UInputNumber
              v-model="edits[s.key]"
              :min="s.min"
              :max="s.max"
            />
            <UButton
              label="저장"
              :loading="busy === s.key"
              :disabled="edits[s.key] === s.value"
              @click="save(s)"
            />
          </div>
          <code
            v-else
            class="text-sm"
          >{{ JSON.stringify(s.value) }}</code>
        </div>
      </div>
    </UCard>

    <UCard class="mb-6">
      <template #header>
        <span class="font-semibold">앱 버전 (읽기 전용)</span>
      </template>
      <UAlert
        v-if="versions?.note"
        color="info"
        variant="subtle"
        icon="i-lucide-info"
        :title="versions.note"
        class="mb-4"
      />
      <UTable
        :data="versions?.items ?? []"
        :columns="[
          { accessorKey: 'platform', header: '플랫폼' },
          { accessorKey: 'version', header: '최신' },
          { accessorKey: 'minimum_version', header: '최소' },
          { accessorKey: 'force_update', header: '강제' },
          { accessorKey: 'is_active', header: '사용' },
          { accessorKey: 'updated_at', header: '수정' }
        ]"
      >
        <template #force_update-cell="{ row }">
          {{ row.original.force_update ? '예' : '아니오' }}
        </template>
        <template #is_active-cell="{ row }">
          {{ row.original.is_active ? '예' : '아니오' }}
        </template>
        <template #updated_at-cell="{ row }">
          {{ fmtDateTime(row.original.updated_at) }}
        </template>
      </UTable>
    </UCard>

    <div class="grid gap-6 lg:grid-cols-2">
      <UCard>
        <template #header>
          <span class="font-semibold">광고 설정 (읽기 전용, 앱 미사용)</span>
        </template>
        <UTable
          :data="ads ?? []"
          :columns="[
            { accessorKey: 'platform', header: '플랫폼' },
            { accessorKey: 'ad_network', header: '네트워크' },
            { accessorKey: 'is_enabled', header: '사용' },
            { accessorKey: 'priority', header: '우선순위' }
          ]"
          empty="없음"
        >
          <template #is_enabled-cell="{ row }">
            {{ row.original.is_enabled ? '예' : '아니오' }}
          </template>
        </UTable>
      </UCard>
      <UCard>
        <template #header>
          <span class="font-semibold">요청 제한 (읽기 전용)</span>
        </template>
        <UTable
          :data="limits ?? []"
          :columns="[
            { accessorKey: 'endpoint', header: '경로' },
            { accessorKey: 'max_requests', header: '최대 요청' },
            { accessorKey: 'window_seconds', header: '구간(초)' },
            { accessorKey: 'is_enabled', header: '사용' }
          ]"
          empty="없음"
        >
          <template #is_enabled-cell="{ row }">
            {{ row.original.is_enabled ? '예' : '아니오' }}
          </template>
        </UTable>
      </UCard>
    </div>
  </UContainer>
</template>
