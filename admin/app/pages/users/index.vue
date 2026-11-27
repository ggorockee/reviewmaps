<script setup lang="ts">
import type { Page, UserRow } from '~/utils/types'

const { api } = useApi()
const page = ref(1)
const q = ref('')
const method = ref<string>('all')
const active = ref<string>('all')

const { data, status, error, refresh } = await useAsyncData('users', () =>
  api<Page<UserRow>>('/admin/v1/users', {
    query: {
      page: page.value,
      q: q.value || undefined,
      login_method: method.value === 'all' ? undefined : method.value,
      is_active: active.value === 'all' ? undefined : active.value
    }
  }), { watch: [page, method, active] })

function search() {
  page.value = 1
  refresh()
}

const methodItems = [{ label: '모든 로그인 방식', value: 'all' }, ...Object.entries(LOGIN_METHOD_LABELS).map(([value, label]) => ({ label, value }))]
const activeItems = [{ label: '전체 상태', value: 'all' }, { label: '활성', value: 'true' }, { label: '비활성', value: 'false' }]
const columns = [
  { accessorKey: 'email', header: '이메일' },
  { accessorKey: 'name', header: '이름' },
  { accessorKey: 'login_method', header: '로그인' },
  { accessorKey: 'is_active', header: '상태' },
  { accessorKey: 'date_joined', header: '가입일' },
  { accessorKey: 'last_login', header: '마지막 로그인' }
]
</script>

<template>
  <UContainer class="py-8">
    <PageHeader
      title="사용자"
      description="앱 회원. 이메일을 누르면 연결된 SNS·키워드·기기를 보고 비활성·삭제할 수 있습니다."
    />
    <form
      class="mb-4 flex flex-wrap gap-2"
      @submit.prevent="search"
    >
      <UInput
        v-model="q"
        icon="i-lucide-search"
        placeholder="이메일 또는 이름"
        class="w-64"
      />
      <USelect
        v-model="method"
        :items="methodItems"
        class="w-40"
      />
      <USelect
        v-model="active"
        :items="activeItems"
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
      empty="조건에 맞는 사용자가 없습니다."
      class="rounded-lg border border-default bg-default"
    >
      <template #email-cell="{ row }">
        <NuxtLink
          :to="`/users/${row.original.id}`"
          class="font-medium text-primary hover:underline"
        >
          {{ row.original.email }}
        </NuxtLink>
        <UBadge
          v-if="row.original.is_staff"
          class="ml-2"
          size="sm"
          color="neutral"
          variant="subtle"
          label="스태프"
        />
      </template>
      <template #login_method-cell="{ row }">
        {{ LOGIN_METHOD_LABELS[row.original.login_method] ?? row.original.login_method }}
      </template>
      <template #is_active-cell="{ row }">
        <UBadge
          :color="row.original.is_active ? 'success' : 'neutral'"
          variant="subtle"
          :label="row.original.is_active ? '활성' : '비활성'"
        />
      </template>
      <template #date_joined-cell="{ row }">
        {{ fmtDateTime(row.original.date_joined) }}
      </template>
      <template #last_login-cell="{ row }">
        {{ fmtDateTime(row.original.last_login) }}
      </template>
    </UTable>
    <AppPager
      v-model:page="page"
      :total="data?.total ?? 0"
      :size="data?.size ?? 50"
    />
  </UContainer>
</template>
