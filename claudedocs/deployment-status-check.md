# 서버 배포 상태 확인 가이드

## 현재 상황
- **커밋**: 1ba506e (키워드 알림 API 거리 계산 기능)
- **Docker 이미지**: ggorockee/reviewmaps-server:20251222-1ba506e
- **Infra PR**: #835 (MERGED at 13:48)
- **배포 대기 중**: ArgoCD가 Kubernetes에 배포 중

## 배포 완료 확인 방법

### 1. ArgoCD UI 확인
```
https://argocd.your-domain.com
→ reviewmaps 앱 선택
→ Deployment 상태 확인
→ Image: ggorockee/reviewmaps-server:20251222-1ba506e 확인
```

### 2. kubectl로 확인 (직접 접근 가능한 경우)
```bash
# Pod 이미지 확인
kubectl get pods -n production -o jsonpath='{.items[*].spec.containers[*].image}' | grep reviewmaps-server

# 최근 배포 상태
kubectl rollout status deployment/reviewmaps-server -n production
```

### 3. API 헬스체크
```bash
# 서버 버전 확인 (배포 완료 후 테스트)
curl https://api.review-maps.com/v1/healthz

# 키워드 알림 API 테스트
curl -H "Authorization: Bearer <token>" \
  "https://api.review-maps.com/v1/keyword-alerts/alerts?lat=37.621668&lng=126.748298&sort=distance"
```

## 예상 배포 시간
- **일반적인 경우**: 1-3분
- **첫 배포**: 5분 내외
- **이미지 Pull 지연**: 최대 10분

## 배포 완료 후 테스트

### Flutter 앱에서 확인
1. 앱 재시작 불필요 (API 변경만 있음)
2. 키워드 알림 화면으로 이동
3. 새로고침 (Pull to refresh)
4. 에러 없이 알림 목록 표시 확인

### 예상 응답
```json
{
  "items": [
    {
      "id": 123,
      "keyword": {...},
      "campaign": {...},
      "distance": 1.23,
      "is_read": false,
      ...
    }
  ],
  "total": 10,
  "unread_count": 5,
  "page": 1,
  "limit": 1000,
  "total_pages": 1
}
```

## 문제 해결

### 여전히 500 에러가 발생하는 경우
1. **배포 확인**: ArgoCD에서 Deployment가 Healthy 상태인지 확인
2. **Pod 로그 확인**:
   ```bash
   kubectl logs -f deployment/reviewmaps-server -n production
   ```
3. **이미지 태그 확인**:
   ```bash
   kubectl describe deployment reviewmaps-server -n production | grep Image
   ```
4. **DB 마이그레이션**: GORM AutoMigrate가 실행되었는지 확인

### Auto-merge가 실패하는 경우
Infra PR #835는 이미 성공적으로 머지되었으므로 문제 없습니다.
향후 배포에서도 동일한 워크플로우가 작동합니다:
1. Main 브랜치에 push
2. CI/CD가 Docker 이미지 빌드
3. Infra repo에 PR 자동 생성
4. Auto-merge로 자동 머지
5. ArgoCD가 변경 감지 후 배포

## 다음 배포부터
현재 워크플로우는 정상 작동 중이므로 별도 수정 불필요합니다.
