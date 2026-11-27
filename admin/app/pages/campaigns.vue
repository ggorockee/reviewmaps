<script setup lang="ts">
import type { CampaignRow, CategoryRow, Page } from '~/utils/types'

const route = useRoute()
const { api } = useApi()
const toast = useToast()
const page = ref(1)
const q = ref('')
const source = ref('all')
const category = ref<string>((route.query.category as string) ?? 'all')
const deleted = ref('active')

const { data: cats } = await useAsyncData('categories-brief', () => api<CategoryRow[]>('/admin/v1/categories'))
const categoryItems = computed(() => [
  { label: '모든 카테고리', value: 'all' },
  { label: '카테고리 없음', value: '0' },
  ...(cats.value ?? []).map(c => ({ label: c.name, value: String(c.id) }))
])

const { data, status, error, refresh } = await useAsyncData('campaigns', () =>
  api<Page<CampaignRow>>('/admin/v1/campaigns', {
    query: {
      page: page.value,
      q: q.value || undefined,
      source: source.value === 'all' ? undefined : source.value,
      category_id: category.value === 'all' ? undefined : category.value,
      deleted: deleted.value === 'active' ? undefined : deleted.value
    }
  }), { watch: [page, source, category, deleted] })

function search() {
  page.value = 1
  refresh()
}

// 상세 (목록 행 클릭 또는 /campaigns?id=)
const selected = ref<CampaignRow | null>(null)
const promotion = ref(0)
async function open(id: number | string) {
  try {
    selected.value = await api<CampaignRow>(`/admin/v1/campaigns/${id}`)
    promotion.value = selected.value.promotion_level
  } catch (e) {
    toast.add({ title: '캠페인을 열지 못했습니다', description: apiErrorMessage(e), color: 'error' })
  }
}
onMounted(() => {
  if (route.query.id) open(route.query.id as string)
})

const busy = ref(false)
async function act(fn: () => Promise<unknown>, done: string) {
  busy.value = true
  try {
    await fn()
    toast.add({ title: done, color: 'success' })
    if (selected.value) await open(selected.value.id)
    await refresh()
  } catch (e) {
    toast.add({ title: '처리하지 못했습니다', description: apiErrorMessage(e), color: 'error' })
  } finally {
    busy.value = false
  }
}
const savePromotion = () => act(() => api(`/admin/v1/campaigns/${selected.value!.id}`, { method: 'PATCH', body: { promotion_level: promotion.value } }), '프로모션 단계를 저장했습니다')
const softDelete = () => act(() => api(`/admin/v1/campaigns/${selected.value!.id}`, { method: 'DELETE' }), '앱에서 숨겼습니다 (soft delete)')
const restore = () => act(() => api(`/admin/v1/campaigns/${selected.value!.id}/restore`, { method: 'POST' }), '복구했습니다')

const columns = [
  { accessorKey: 'company', header: '업체·제목' },
  { accessorKey: 'platform', header: '플랫폼' },
  { accessorKey: 'category_name', header: '카테고리' },
  { accessorKey: 'apply_deadline', header: '마감' },
  { accessorKey: 'promotion_level', header: '프로모션' },
  { accessorKey: 'created_at', header: '수집' }
]
</script>

<template>
  <UContainer class="py-8">
    <PageHeader
      title="캠페인"
      description="수집된 체험단 캠페인. 행을 누르면 상세·프로모션·숨기기를 할 수 있습니다. 내용 수정은 다음 수집 때 덮어쓰여서 제공하지 않습니다."
    />
    <form
      class="mb-4 flex flex-wrap gap-2"
      @submit.prevent="search"
    >
      <UInput
        v-model="q"
        icon="i-lucide-search"
        placeholder="업체·제목·제공 내역"
        class="w-64"
      />
      <USelect
        v-model="source"
        :items="[{ label: '모든 출처', value: 'all' }, { label: 'inflexer', value: 'inflexer' }, { label: '리뷰노트', value: '리뷰노트' }]"
        class="w-36"
      />
      <USelect
        v-model="category"
        :items="categoryItems"
        class="w-40"
      />
      <USelect
        v-model="deleted"
        :items="[{ label: '앱에 보이는 것', value: 'active' }, { label: '숨긴 것만', value: 'only' }, { label: '모두', value: 'include' }]"
        class="w-40"
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
      empty="캠페인이 없습니다."
      class="rounded-lg border border-default bg-default"
      @select="(_e: Event, row: { original: CampaignRow }) => open(row.original.id)"
    >
      <template #company-cell="{ row }">
        <div class="font-medium">
          {{ row.original.company }}
          <UBadge
            v-if="row.original.deleted_at"
            size="sm"
            color="neutral"
            variant="subtle"
            label="숨김"
          />
        </div>
        <div class="max-w-md truncate text-xs text-muted">
          {{ row.original.title || row.original.offer }}
        </div>
      </template>
      <template #platform-cell="{ row }">
        {{ row.original.platform }}
        <div class="text-xs text-muted">
          {{ row.original.source }}
        </div>
      </template>
      <template #category_name-cell="{ row }">
        <span v-if="row.original.category_name">{{ row.original.category_name }}</span>
        <UBadge
          v-else
          color="warning"
          variant="subtle"
          label="없음"
        />
      </template>
      <template #apply_deadline-cell="{ row }">
        {{ fmtDate(row.original.apply_deadline) }}
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

    <USlideover
      :open="!!selected"
      :title="selected?.company"
      :description="selected?.title || selected?.offer"
      @update:open="(v: boolean) => { if (!v) selected = null }"
    >
      <template #body>
        <dl
          v-if="selected"
          class="grid grid-cols-3 gap-y-2 text-sm"
        >
          <dt class="text-muted">
            ID
          </dt><dd class="col-span-2">
            {{ selected.id }}
          </dd>
          <dt class="text-muted">
            플랫폼·출처
          </dt><dd class="col-span-2">
            {{ selected.platform }} · {{ selected.source ?? '-' }}
          </dd>
          <dt class="text-muted">
            제공 내역
          </dt><dd class="col-span-2">
            {{ selected.offer }}
          </dd>
          <dt class="text-muted">
            카테고리
          </dt><dd class="col-span-2">
            {{ selected.category_name ?? '없음' }}
          </dd>
          <dt class="text-muted">
            유형·채널
          </dt><dd class="col-span-2">
            {{ selected.campaign_type ?? '-' }} · {{ selected.campaign_channel ?? '-' }}
          </dd>
          <dt class="text-muted">
            지역·주소
          </dt><dd class="col-span-2">
            {{ selected.region ?? '-' }} · {{ selected.address ?? '-' }}
          </dd>
          <dt class="text-muted">
            마감
          </dt><dd class="col-span-2">
            {{ fmtDate(selected.apply_deadline) }}
          </dd>
          <dt class="text-muted">
            수집
          </dt><dd class="col-span-2">
            {{ fmtDateTime(selected.created_at) }}
          </dd>
          <dt class="text-muted">
            원문
          </dt><dd class="col-span-2 truncate">
            <a
              v-if="selected.content_link"
              :href="selected.content_link"
              target="_blank"
              rel="noopener noreferrer"
              class="text-primary hover:underline"
            >열기</a>
            <span v-else>-</span>
          </dd>
        </dl>
        <USeparator class="my-6" />
        <div
          v-if="selected"
          class="space-y-4"
        >
          <UFormField
            label="프로모션 단계 (0~10)"
            help="높을수록 앱 목록 위쪽에 보입니다. 0은 일반."
          >
            <div class="flex gap-2">
              <UInputNumber
                v-model="promotion"
                :min="0"
                :max="10"
              />
              <UButton
                label="저장"
                :loading="busy"
                :disabled="promotion === selected.promotion_level"
                @click="savePromotion"
              />
            </div>
          </UFormField>
          <UButton
            v-if="!selected.deleted_at"
            color="error"
            variant="outline"
            icon="i-lucide-eye-off"
            label="앱에서 숨기기 (soft delete)"
            :loading="busy"
            @click="softDelete"
          />
          <UButton
            v-else
            icon="i-lucide-undo-2"
            label="복구"
            :loading="busy"
            @click="restore"
          />
        </div>
      </template>
    </USlideover>
  </UContainer>
</template>
