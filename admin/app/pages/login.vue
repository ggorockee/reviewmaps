<script setup lang="ts">
import type { FetchError } from 'ofetch'
import type { AdminConfig } from '~/composables/useAuth'

definePageMeta({ layout: false })

const { api } = useApi()
const { loginWithGoogle, loginWithPassword, devLogin } = useAuth()
const toast = useToast()
const config = ref<AdminConfig>()
const loading = ref(false)
const error = ref('')
const form = reactive({ id: '', password: '' })

// Google 버튼은 직접 그린다 (Google 제공 버튼은 브라우저에 로그인된 계정 이름을 표시함).
// 로그인은 OpenID Connect 리디렉션: Google → /login#id_token=...&state=... 로 돌아온다. (라익찍스와 같은 방식)
const OAUTH_STATE_KEY = 'rm-oauth-state'

function randomString(): string {
  const b = new Uint8Array(16)
  crypto.getRandomValues(b)
  return Array.from(b, x => x.toString(16).padStart(2, '0')).join('')
}

function startGoogleLogin() {
  if (!config.value?.google_client_id) return
  const state = randomString()
  const nonce = randomString()
  sessionStorage.setItem(OAUTH_STATE_KEY, JSON.stringify({ state, nonce }))
  const params = new URLSearchParams({
    client_id: config.value.google_client_id,
    redirect_uri: `${location.origin}/login`,
    response_type: 'id_token',
    scope: 'openid email',
    prompt: 'select_account',
    state,
    nonce
  })
  location.assign(`https://accounts.google.com/o/oauth2/v2/auth?${params}`)
}

/** Google에서 돌아온 경우 주소의 id_token으로 로그인 */
async function finishGoogleLogin() {
  const hash = new URLSearchParams(location.hash.slice(1))
  if (!hash.has('id_token') && !hash.has('error')) return
  history.replaceState(null, '', location.pathname)

  const saved = sessionStorage.getItem(OAUTH_STATE_KEY)
  sessionStorage.removeItem(OAUTH_STATE_KEY)
  if (hash.has('error')) {
    if (hash.get('error') !== 'access_denied') error.value = `Google 로그인에 실패했습니다 (${hash.get('error')}).`
    return
  }
  const token = hash.get('id_token')!
  const expected = saved ? JSON.parse(saved) as { state: string, nonce: string } : null
  if (!expected || hash.get('state') !== expected.state || tokenNonce(token) !== expected.nonce) {
    error.value = 'Google 로그인 응답을 확인할 수 없습니다. 다시 시도해 주세요.'
    return
  }
  await run(() => loginWithGoogle(token))
}

function tokenNonce(token: string): string | undefined {
  try {
    const payload = token.split('.')[1]!.replace(/-/g, '+').replace(/_/g, '/')
    return (JSON.parse(atob(payload)) as { nonce?: string }).nonce
  } catch {
    return undefined
  }
}

async function onPasswordLogin() {
  if (!form.id || !form.password) {
    error.value = '아이디와 비밀번호를 입력해 주세요.'
    return
  }
  await run(() => loginWithPassword(form.id, form.password))
  form.password = ''
}

async function run(login: () => Promise<void>) {
  loading.value = true
  error.value = ''
  try {
    await login()
    toast.add({ title: '로그인했습니다', color: 'success' })
    await navigateTo('/')
  } catch (e) {
    const status = (e as FetchError).response?.status
    error.value = status === 401 ? '아이디 또는 비밀번호가 올바르지 않습니다.' : apiErrorMessage(e)
  } finally {
    loading.value = false
  }
}

onMounted(async () => {
  try {
    config.value = await api<AdminConfig>('/admin/v1/config')
  } catch (e) {
    error.value = apiErrorMessage(e)
    return
  }
  await finishGoogleLogin()
})
</script>

<template>
  <div class="flex min-h-screen items-center justify-center bg-brand-50 p-6">
    <UCard class="w-full max-w-sm">
      <div class="flex flex-col items-center gap-4 text-center">
        <img
          src="/favicon.png"
          alt=""
          class="size-20 rounded-2xl"
        >
        <h1 class="text-xl font-bold">
          <span class="text-primary">리뷰맵</span> 관리자
        </h1>

        <UButton
          v-if="config?.google_client_id"
          block
          size="lg"
          color="neutral"
          variant="outline"
          icon="i-simple-icons-google"
          label="Google로 로그인"
          :disabled="loading"
          @click="startGoogleLogin"
        />

        <template v-if="config?.password_login">
          <USeparator
            v-if="config?.google_client_id"
            label="또는"
          />
          <form
            class="flex w-full flex-col gap-3"
            @submit.prevent="onPasswordLogin"
          >
            <UInput
              v-model="form.id"
              placeholder="아이디"
              autocomplete="username"
              size="lg"
              class="w-full"
            />
            <UInput
              v-model="form.password"
              type="password"
              placeholder="비밀번호"
              autocomplete="current-password"
              size="lg"
              class="w-full"
            />
            <UButton
              type="submit"
              block
              size="lg"
              label="로그인"
              :loading="loading"
            />
          </form>
        </template>

        <UButton
          v-if="config?.dev_login"
          color="neutral"
          variant="ghost"
          icon="i-lucide-wrench"
          label="개발용 로그인 (로컬 전용)"
          @click="run(devLogin)"
        />
        <UAlert
          v-if="error"
          color="error"
          variant="subtle"
          :title="error"
          class="text-left"
        />
      </div>
    </UCard>
  </div>
</template>
