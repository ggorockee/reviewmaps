// 리뷰맵 관리자 콘솔: 정적 SPA (nuxt generate → nginx), 백엔드는 Go API(/admin/v1)만 사용
export default defineNuxtConfig({
  modules: [
    '@nuxt/eslint',
    '@nuxt/ui'
  ],

  // 관리자 콘솔은 SEO가 필요 없고 Node 서버 없이 정적 배포하므로 SPA
  ssr: false,

  devtools: {
    enabled: false
  },

  app: {
    head: {
      htmlAttrs: { lang: 'ko' },
      title: '리뷰맵 관리자',
      meta: [
        { name: 'viewport', content: 'width=device-width, initial-scale=1' },
        // 검색엔진 노출 방지
        { name: 'robots', content: 'noindex, nofollow' }
      ],
      link: [{ rel: 'icon', type: 'image/png', href: '/favicon.png' }]
    }
  },

  css: ['~/assets/css/main.css'],

  runtimeConfig: {
    public: {
      // 빌드 시 NUXT_PUBLIC_API_BASE로 지정 (운영: https://api.review-maps.com)
      apiBase: 'http://localhost:3000',
      // Grafana 대시보드 바로가기
      grafanaUrl: 'https://monitoring.ggorockee.com/d/reviewmaps-http-metrics'
    }
  },

  compatibilityDate: '2026-06-30',

  eslint: {
    config: {
      stylistic: {
        commaDangle: 'never',
        braceStyle: '1tbs'
      }
    }
  }
})
