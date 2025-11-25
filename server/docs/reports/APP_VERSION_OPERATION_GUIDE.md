# 앱 버전 관리 운영 가이드

## 📋 목차

1. [일반적인 배포 시나리오](#일반적인-배포-시나리오)
2. [운영 베스트 프랙티스](#운영-베스트-프랙티스)
3. [심사 속도 차이 대응](#심사-속도-차이-대응)
4. [강제권장-업데이트-전환-시점](#강제권장-업데이트-전환-시점)
5. [트러블슈팅](#트러블슈팅)
6. [체크리스트](#체크리스트)

## 일반적인 배포 시나리오

### 시나리오 1: 정상적인 버전 업데이트

#### 배경
- 현재 운영 버전: 1.3.0
- 새 버전 배포: 1.4.0
- 1.3.0 사용자는 계속 서비스 이용 가능 (호환성 유지)

#### 작업 순서

1. **새 버전 빌드 및 스토어 제출**
   ```
   Android: 1.4.0 (빌드 140) → Play Console 제출
   iOS: 1.4.0 (빌드 140) → App Store Connect 제출
   ```

2. **서버 버전 설정 업데이트 (Django Admin)**
   ```
   Android:
   - version: "1.4.0"
   - minimum_version: "1.3.0"  # 기존 사용자도 계속 사용 가능
   - store_url: "https://play.google.com/store/apps/details?id=com.reviewmaps.mobile&pli=1"
   - is_active: True

   iOS:
   - version: "1.4.0"
   - minimum_version: "1.3.0"
   - store_url: "https://apps.apple.com/kr"
   - is_active: True
   ```

3. **점진적 사용자 업데이트**
   - 1.3.0 사용자: 앱 실행 시 "업데이트 안내" 표시 (권장)
   - 1.4.0 사용자: 업데이트 안내 없음
   - 1.2.x 사용자: "필수 업데이트 안내" 표시 (강제)

#### 예상 결과
- ✅ 기존 사용자 서비스 중단 없음
- ✅ 신규 기능 점진적 배포
- ✅ 1.3.0 사용자는 자발적 업데이트

---

### 시나리오 2: 긴급 핫픽스 (보안 패치)

#### 배경
- 현재 운영 버전: 1.3.5
- 심각한 보안 취약점 발견
- 모든 이전 버전 사용 차단 필요

#### 작업 순서

1. **긴급 버전 빌드 및 스토어 제출**
   ```
   버전: 1.3.6 (보안 패치)
   설명: "보안 문제 해결을 위한 긴급 업데이트"
   ```

2. **서버 설정 즉시 변경**
   ```
   version: "1.3.6"
   minimum_version: "1.3.6"  # ⚠️ 최신 버전과 동일하게 설정
   update_message: "보안 문제 해결을 위한 긴급 업데이트입니다."
   ```

3. **효과**
   - 1.3.5 이하 모든 사용자 → **강제 업데이트**
   - 앱 실행 시 "필수 업데이트 안내" 모달 표시
   - "나중에" 버튼 없음

#### 주의사항
⚠️ 스토어 심사 완료 **전**에는 minimum_version을 변경하지 말 것!
→ 사용자가 업데이트하려 해도 스토어에 앱이 없으면 서비스 중단

---

### 시나리오 3: iOS/Android 배포 시간 차이

#### 배경
- Android: 2-3일 심사 (빠름)
- iOS: 1-2주 심사 (느림)
- 동일한 1.4.0 버전을 양쪽에 배포하려 함

#### 권장 전략

**방법 A: 플랫폼별 독립 배포 (권장)**

1. **Android 먼저 배포**
   ```
   Day 1: Android 1.4.0 Play Store 승인
   Day 1: 서버 Android 버전 업데이트
         - platform: android
         - version: "1.4.0"
         - minimum_version: "1.3.0"
   ```

2. **iOS 나중에 배포**
   ```
   Day 10: iOS 1.4.0 App Store 승인
   Day 10: 서버 iOS 버전 업데이트
          - platform: ios
          - version: "1.4.0"
          - minimum_version: "1.3.0"
   ```

**방법 B: iOS 승인 대기 (비권장)**
```
iOS 심사 완료까지 Android 배포도 보류
→ 불필요하게 Android 사용자 업데이트 지연
```

#### 장점
✅ 플랫폼별 독립 관리로 빠른 업데이트 가능
✅ 한쪽 심사 지연이 다른쪽에 영향 없음

---

## 운영 베스트 프랙티스

### 1. 버전 번호 관리

#### Semantic Versioning 준수
```
major.minor.patch

major: 호환성이 깨지는 대규모 변경
minor: 호환성 유지하며 기능 추가
patch: 버그 수정, 성능 개선
```

**예시**
- 1.3.5 → 1.3.6: 버그 수정 (patch)
- 1.3.6 → 1.4.0: 새 기능 추가 (minor)
- 1.9.9 → 2.0.0: API 변경, UI 대폭 개편 (major)

### 2. minimum_version 설정 원칙

#### 보수적으로 설정하기
```
❌ 나쁜 예:
새 버전 1.5.0 출시 → minimum_version을 1.5.0으로 즉시 변경
→ 모든 사용자 강제 업데이트, 서비스 품질 저하

✅ 좋은 예:
새 버전 1.5.0 출시 → minimum_version은 1.4.0 유지
2-3주 후 사용자 업데이트율 확인 → 1.5.0으로 상향
```

#### minimum_version 상향 기준
- **신규 버전 안정화 확인**: 최소 1주일 이상 크래시율 모니터링
- **업데이트율 확인**: 80% 이상 사용자가 신규 버전 사용 중
- **중요 버그 없음**: 신규 버전에 치명적 버그 없음 확인

### 3. 스토어 심사 타이밍

#### Android (Play Console)
- **심사 시간**: 보통 2-3일
- **긴급 업데이트**: 24시간 이내 가능
- **전략**: 빠른 배포 가능, 즉시 반영 OK

#### iOS (App Store Connect)
- **심사 시간**: 보통 1-2주 (평균 5-7일)
- **긴급 업데이트**: "긴급 릴리스" 요청 시 1-2일
- **전략**:
  - 예정 릴리스 날짜 2주 전 제출
  - 금요일 제출 피하기 (주말 심사 지연)
  - 주요 업데이트는 월/화 제출 권장

### 4. 업데이트 메시지 작성 가이드

#### 강제 업데이트 메시지
```
✅ 좋은 예:
"이전 버전은 더 이상 지원되지 않습니다.
앱을 계속 사용하시려면 최신 버전으로 업데이트해 주세요."

❌ 나쁜 예:
"업데이트 하세요" (이유 없음)
"업데이트 안 하면 앱 안 됨" (부정적)
```

#### 권장 업데이트 메시지
```
✅ 좋은 예:
"더 안정적이고 편리한 서비스 이용을 위해
최신 버전으로 업데이트해 주세요."

"새로운 기능이 추가되었습니다:
• 지도 검색 속도 2배 향상
• 즐겨찾기 기능 추가
• 버그 수정 및 안정성 개선"

❌ 나쁜 예:
"업데이트 해주세요" (구체적 이유 없음)
"버그 수정" (사용자 관점 이점 없음)
```

### 5. 롤백 전략

#### 문제 발생 시 대응

**Case 1: 새 버전에서 심각한 버그 발견**
```
1. 서버 설정만 변경 (스토어는 그대로)
   - minimum_version을 이전 안정 버전으로 하향
   - version은 새 버전 유지 (혼란 방지)

2. 사용자 효과
   - 신규 버전 사용자: 이전 버전으로 재설치 유도 (선택)
   - 기존 버전 사용자: 업데이트 안내 사라짐

3. 버그 수정 후 재배포
```

**Case 2: API 호환성 문제**
```
1. 백엔드 API 롤백 (새 버전 앱 지원 중단)
2. minimum_version 하향 (기존 버전으로 유도)
3. 백엔드 수정 → 새 버전 재배포
```

---

## 강제/권장 업데이트 전환 시점

### 권장 업데이트 기간

#### 목표
사용자가 자발적으로 업데이트하도록 유도, 강제 전환 전 충분한 시간 제공

#### 권장 기간
- **일반 업데이트**: 2-4주
- **주요 기능 추가**: 4-6주
- **UI 대폭 변경**: 6-8주 (사용자 적응 시간)

#### 전환 기준
```
✅ 강제 업데이트로 전환 가능한 시점:
- 신규 버전 업데이트율 > 80%
- 신규 버전 크래시율 < 이전 버전
- 신규 버전 출시 후 최소 2주 경과
- 고객 지원 문의 급증 없음

⚠️ 아직 전환하면 안 되는 시점:
- 신규 버전 업데이트율 < 60%
- 크래시율 상승 중
- 주요 버그 보고 계속 접수 중
- 출시 후 1주일 미만
```

### 전환 프로세스

#### Step 1: 데이터 확인
```sql
-- 버전별 사용자 분포 확인 (예시 쿼리)
SELECT
    app_version,
    COUNT(*) as user_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) as percentage
FROM user_analytics
WHERE last_active_date >= NOW() - INTERVAL '7 days'
GROUP BY app_version
ORDER BY app_version DESC;
```

#### Step 2: Django Admin에서 변경
```
1. Admin → App Config → App Versions
2. 해당 플랫폼 선택
3. minimum_version을 새 버전으로 상향
4. update_message 변경 (선택사항)
5. 저장
```

#### Step 3: 모니터링
```
- 변경 후 1시간: 긴급 이슈 없는지 확인
- 변경 후 24시간: 고객 지원 문의 급증 여부 확인
- 변경 후 1주일: 업데이트율 100% 도달 확인
```

---

## 트러블슈팅

### 문제 1: "활성화된 버전 정보가 없습니다" 오류

#### 원인
- 해당 플랫폼의 `is_active=True` 버전이 없음
- 실수로 모든 버전을 비활성화함

#### 해결
```python
# Django Admin에서
1. App Config → App Versions
2. 해당 플랫폼의 최신 버전 선택
3. is_active 체크박스 활성화
4. 저장
```

### 문제 2: iOS/Android 둘 다 강제 업데이트 표시

#### 원인
- 실수로 양쪽 플랫폼의 minimum_version을 동시에 상향
- 한쪽 플랫폼의 신규 버전이 아직 스토어 승인 안 남

#### 해결
```python
# 승인 안 난 플랫폼만 minimum_version 하향
1. Admin → App Config → App Versions
2. iOS 또는 Android 선택 (승인 안 난 플랫폼)
3. minimum_version을 이전 버전으로 변경
4. 저장
5. 스토어 승인 후 다시 상향
```

### 문제 3: 사용자가 "최신 버전인데 계속 업데이트 요청"

#### 원인
- 클라이언트가 논리적 버전을 잘못 전달
- 서버 버전 설정 오류

#### 진단
```bash
# API 직접 호출 테스트
curl "https://api.reviewmaps.com/api/v1/app-config/version?platform=android&current_version=1.4.0"
```

#### 해결
```python
# 응답 확인
{
  "latest_version": "1.4.0",
  "min_version": "1.3.0",
  "force_update": false,  # false여야 정상
  ...
}

# force_update가 true라면
→ 서버 minimum_version 설정 확인
→ 클라이언트 current_version 파라미터 확인
```

### 문제 4: 버전 형식 오류

#### 에러 메시지
```
"잘못된 버전 형식: 1.3"
```

#### 원인
- 클라이언트가 잘못된 버전 형식 전달
- major.minor.patch 형식 아님

#### 해결
```dart
// 클라이언트 코드 수정 (Flutter 예시)
// ❌ 잘못된 예
String version = "1.3";  // patch 누락

// ✅ 올바른 예
String version = "1.3.0";  // major.minor.patch
```

---

## 체크리스트

### 새 버전 배포 전

- [ ] 빌드 번호 증가 확인
- [ ] 버전 번호 Semantic Versioning 준수
- [ ] 스토어 설명, 스크린샷 업데이트
- [ ] Android: Play Console 제출
- [ ] iOS: App Store Connect 제출
- [ ] 서버 AppVersion 설정 준비 (스토어 승인 전까지 저장 X)

### 스토어 승인 후

- [ ] Django Admin → App Config → App Versions
- [ ] 플랫폼 선택 (android 또는 ios)
- [ ] version: 새 버전 (예: "1.4.0")
- [ ] minimum_version: 최소 지원 버전 (보수적으로)
- [ ] store_url: 정확한 스토어 URL
- [ ] update_message: 사용자 친화적 메시지 (선택)
- [ ] is_active: True
- [ ] 저장
- [ ] API 테스트: `GET /api/v1/app-config/version`

### 모니터링 (배포 후)

- [ ] 1시간 후: 긴급 크래시 없는지 확인
- [ ] 24시간 후: 고객 지원 문의 급증 여부
- [ ] 1주일 후: 업데이트율 확인
- [ ] 2주일 후: minimum_version 상향 검토

### minimum_version 상향 전

- [ ] 신규 버전 업데이트율 > 80%
- [ ] 신규 버전 안정성 확인 (크래시율)
- [ ] 주요 버그 없음
- [ ] 출시 후 최소 2주 경과
- [ ] 고객 지원팀 사전 공지

---

## 빠른 참조

### 주요 명령어

```bash
# API 테스트
curl "https://api.reviewmaps.com/api/v1/app-config/version?platform=android&current_version=1.3.0"

# 테스트 실행
python manage.py test app_config.tests.test_utils -v 2

# Django Admin 접속
https://api.reviewmaps.com/admin/app_config/appversion/
```

### 연락처

- **기술 문의**: [기술팀 이메일]
- **긴급 장애**: [긴급 연락처]
- **고객 지원**: [고객센터 이메일]

---

## 버전 히스토리 예시

| 날짜 | 버전 | min_version | 변경사항 | 비고 |
|------|------|-------------|---------|------|
| 2025-01-15 | 1.4.0 | 1.3.0 | 지도 검색 개선, 즐겨찾기 추가 | 권장 업데이트 |
| 2025-01-30 | 1.4.0 | 1.4.0 | minimum_version 상향 | 강제 업데이트 전환 |
| 2025-02-10 | 1.5.0 | 1.4.0 | 리뷰 작성 기능 추가 | 권장 업데이트 |
| 2025-02-12 | 1.5.1 | 1.5.1 | 보안 취약점 패치 | 긴급 핫픽스 |

---

## 관련 문서

- [앱 버전 관리 명세서](../specifications/APP_VERSION_MANAGEMENT_SPEC.md)
- [API 엔드포인트 레퍼런스](../specifications/API_ENDPOINTS_REFERENCE.md)
- [환경변수 설정](../specifications/ENVIRONMENT_VARIABLES.md)
