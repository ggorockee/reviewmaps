<script setup lang="ts">
// 서버 페이지 나눔 (page는 1부터)
const page = defineModel<number>('page', { required: true })
defineProps<{ total: number, size: number }>()
</script>

<template>
  <div class="mt-4 flex flex-wrap items-center justify-between gap-2 text-sm text-muted">
    <span>전체 {{ total.toLocaleString('ko-KR') }}건</span>
    <UPagination
      v-if="total > size"
      v-model:page="page"
      :total="total"
      :items-per-page="size"
    />
  </div>
</template>
