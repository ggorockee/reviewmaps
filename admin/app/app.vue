<script setup lang="ts">
import { ko } from '@nuxt/ui/locale'
</script>

<template>
  <UApp :locale="ko">
    <NuxtLayout>
      <NuxtPage />
    </NuxtLayout>
  </UApp>
</template>
