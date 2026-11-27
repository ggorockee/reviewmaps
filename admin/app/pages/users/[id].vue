<script setup lang="ts">
import type { UserDetail } from '~/utils/types'

const route = useRoute()
const { api } = useApi()
const toast = useToast()
const id = route.params.id as string

const { data, error, refresh } = await useAsyncData(`user-${id}`, () => api<UserDetail>(`/admin/v1/users/${id}`))

const busy = ref(false)
async function setActive(v: boolean) {
  busy.value = true
  try {
    await api(`/admin/v1/users/${id}`, { method: 'PATCH', body: { is_active: v } })
    toast.add({ title: v ? '활성으로 바꿨습니다' : '비활성으로 바꿨습니다', description: v ? '' : '이 사용자는 앱에 로그인할 수 없습니다.', color: 'success' })
    await refresh()
  } catch (e) {
    toast.add({ title: '변경하지 못했습니다', description: apiErrorMessage(e), color: 'error' })
  } finally {
    busy.value = false
  }
}

const confirmOpen = ref(false)
const confirmEmail = ref('')
async function remove() {
  busy.value = true
  try {
    await api(`/admin/v1/users/${id}`, { method: 'DELETE', body: { confirm_email: confirmEmail.value } })
    toast.add({ title: '사용자를 삭제했습니다', color: 'success' })
    await navigateTo('/users')
  } catch (e) {
    toast.add({ title: '삭제하지 못했습니다', description: apiErrorMessage(e), color: 'error' })
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <UContainer class="py-8">
    <UButton
      variant="link"
      color="neutral"
      icon="i-lucide-arrow-left"
      label="사용자 목록"
      to="/users"
      class="mb-2 px-0"
    />
    <UAlert
      v-if="error"
      color="error"
      variant="subtle"
      :title="apiErrorMessage(error)"
    />
    <template v-if="data">
      <PageHeader
        :title="data.email"
        :description="`${data.name || '이름 없음'} · ${LOGIN_METHOD_LABELS[data.login_method] ?? data.login_method} · 가입 ${fmtDateTime(data.date_joined)} · 마지막 로그인 ${fmtDateTime(data.last_login)}`"
      >
        <USwitch
          :model-value="data.is_active"
          :loading="busy"
          :label="data.is_active ? '활성' : '비활성'"
          @update:model-value="setActive"
        />
        <UButton
          color="error"
          variant="outline"
          icon="i-lucide-trash-2"
          label="사용자 삭제"
          @click="confirmOpen = true"
        />
      </PageHeader>

      <div class="grid gap-6 lg:grid-cols-3">
        <UCard>
          <template #header>
            <span class="font-semibold">SNS 계정 ({{ data.social_accounts.length }})</span>
          </template>
          <ul class="space-y-2 text-sm">
            <li
              v-for="s in data.social_accounts"
              :key="s.provider + s.created_at"
            >
              <UBadge
                color="neutral"
                variant="subtle"
                :label="LOGIN_METHOD_LABELS[s.provider] ?? s.provider"
              />
              <span class="ml-2">{{ s.email ?? '-' }}</span>
              <div class="text-xs text-muted">
                연결 {{ fmtDateTime(s.created_at) }}
              </div>
            </li>
            <li
              v-if="!data.social_accounts.length"
              class="text-muted"
            >
              없음
            </li>
          </ul>
        </UCard>
        <UCard>
          <template #header>
            <span class="font-semibold">키워드 ({{ data.keywords.length }})</span>
          </template>
          <div class="flex flex-wrap gap-2">
            <UBadge
              v-for="k in data.keywords"
              :key="k.id"
              :color="k.is_active ? 'primary' : 'neutral'"
              variant="subtle"
              :label="k.keyword"
            />
            <span
              v-if="!data.keywords.length"
              class="text-sm text-muted"
            >없음</span>
          </div>
        </UCard>
        <UCard>
          <template #header>
            <span class="font-semibold">푸시 기기 ({{ data.devices.length }})</span>
          </template>
          <ul class="space-y-2 text-sm">
            <li
              v-for="d in data.devices"
              :key="d.id"
            >
              {{ d.device_type }} · <code class="text-xs">{{ d.token_hint }}</code>
              <UBadge
                v-if="!d.is_active"
                size="sm"
                color="neutral"
                variant="subtle"
                label="비활성"
                class="ml-1"
              />
              <div class="text-xs text-muted">
                갱신 {{ fmtDateTime(d.updated_at) }}
              </div>
            </li>
            <li
              v-if="!data.devices.length"
              class="text-muted"
            >
              없음
            </li>
          </ul>
        </UCard>
      </div>

      <UModal
        v-model:open="confirmOpen"
        title="사용자를 삭제할까요?"
        description="SNS 연결, 키워드, 키워드 알림, 푸시 기기가 함께 삭제되며 되돌릴 수 없습니다 (앱 회원 탈퇴와 같음)."
      >
        <template #body>
          <UFormField :label="`확인을 위해 이메일 ${data.email} 을 입력하세요`">
            <UInput
              v-model="confirmEmail"
              class="w-full"
              :placeholder="data.email"
            />
          </UFormField>
        </template>
        <template #footer>
          <div class="flex w-full justify-end gap-2">
            <UButton
              color="neutral"
              variant="outline"
              label="취소"
              @click="confirmOpen = false"
            />
            <UButton
              color="error"
              label="삭제"
              :loading="busy"
              :disabled="confirmEmail.trim().toLowerCase() !== data.email.toLowerCase()"
              @click="remove"
            />
          </div>
        </template>
      </UModal>
    </template>
  </UContainer>
</template>
