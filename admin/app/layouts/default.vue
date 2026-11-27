<script setup lang="ts">
const { user, logout } = useAuth()
const config = useRuntimeConfig()
const route = useRoute()

const is = (p: string) => (p === '/' ? route.path === '/' : route.path.startsWith(p))
const nav = computed(() => [
  { label: '대시보드', icon: 'i-lucide-layout-dashboard', to: '/', active: is('/') },
  { label: '사용자', icon: 'i-lucide-users', to: '/users', active: is('/users') },
  { label: '키워드', icon: 'i-lucide-tag', to: '/keywords', active: is('/keywords') },
  { label: '키워드 알림', icon: 'i-lucide-bell', to: '/alerts', active: is('/alerts') },
  { label: '캠페인', icon: 'i-lucide-map-pin', to: '/campaigns', active: is('/campaigns') },
  { label: '카테고리', icon: 'i-lucide-folder-tree', to: '/categories', active: route.path === '/categories' },
  { label: '카테고리 매핑', icon: 'i-lucide-git-merge', to: '/categories/mapping', active: is('/categories/mapping') },
  { label: '설정·앱 버전', icon: 'i-lucide-settings', to: '/settings', active: is('/settings') },
  { label: '변경 기록', icon: 'i-lucide-history', to: '/audit', active: is('/audit') },
  { label: '모니터링 (Grafana)', icon: 'i-lucide-activity', to: config.public.grafanaUrl as string, target: '_blank' }
])
</script>

<template>
  <div
    v-if="user"
    class="flex min-h-screen"
  >
    <aside class="sticky top-0 flex h-screen w-60 shrink-0 flex-col border-r border-default bg-default">
      <NuxtLink
        to="/"
        class="flex items-center gap-2 px-4 py-4 font-bold"
      >
        <img
          src="/favicon.png"
          alt=""
          class="size-8 rounded-md"
        >
        <span class="text-primary">리뷰맵</span> 관리자
      </NuxtLink>
      <UNavigationMenu
        :items="nav"
        orientation="vertical"
        class="flex-1 overflow-y-auto px-2"
      />
      <div class="border-t border-default p-3">
        <div class="mb-2 truncate text-xs text-muted">
          {{ user.email }}
        </div>
        <UButton
          block
          color="neutral"
          variant="outline"
          icon="i-lucide-log-out"
          label="로그아웃"
          @click="logout"
        />
      </div>
    </aside>
    <main class="min-w-0 flex-1 bg-muted/40">
      <slot />
    </main>
  </div>
  <div v-else>
    <slot />
  </div>
</template>
