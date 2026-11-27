// 로그인하지 않았으면 /login으로
export default defineNuxtRouteMiddleware(async (to) => {
  const { user, checked, refresh } = useAuth()
  if (!checked.value) await refresh()
  if (to.path === '/login') {
    if (user.value) return navigateTo('/')
    return
  }
  if (!user.value) return navigateTo('/login')
})
