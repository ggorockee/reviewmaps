# 앱 버전 관리 시스템 - 최종 요약

## 🎯 프로젝트 개요

ReviewMaps 앱의 **논리적 버전(Logical Version)** 기반 업데이트 관리 시스템 구축 완료

- **목적**: 네이티브 스토어 버전과 독립적인 플랫폼별 버전 정책 관리
- **핵심 기능**: 강제/권장 업데이트 자동 판단, 네이버 스타일 안내 메시지
- **완료일**: 2025-11-25

## ✅ 구현 완료 항목

### 1. 데이터 모델 ✅

**위치**: `app_config/models.py`

```python
class AppVersion(models.Model):
    platform = CharField  # 'android' | 'ios'
    version = CharField  # 논리적 버전 (예: "1.4.0")
    build_number = IntegerField  # 참고용
    minimum_version = CharField  # 최소 지원 버전
    force_update = BooleanField  # (현재 미사용)
    update_message = TextField  # 커스텀 메시지
    store_url = URLField  # 스토어 링크
    is_active = BooleanField  # 활성화 여부
```

**인덱스**:
- `(platform, is_active)` - 버전 조회 최적화
- `(-created_at)` - 최신 버전 조회

### 2. 버전 비교 유틸리티 ✅

**위치**: `app_config/utils.py`

```python
# Version 클래스 (Semantic Versioning 지원)
v1 = Version("1.3.0")
v2 = Version("1.4.0")
v1 < v2  # True

# 헬퍼 함수
compare_versions("1.3.0", "1.4.0")  # -1 (업데이트 필요)
needs_update("1.3.0", "1.4.0")  # True
is_force_update_required("1.2.0", "1.3.0")  # True
```

**지원 연산**: `==`, `<`, `<=`, `>`, `>=`

### 3. API 엔드포인트 ✅

**위치**: `app_config/api.py`

**Endpoint**: `GET /api/v1/app-config/version`

**파라미터**:
- `platform` (required): "android" | "ios"
- `current_version` (required): "1.3.0" (논리적 버전)

**응답 예시**:
```json
{
  "latest_version": "1.4.0",
  "min_version": "1.3.0",
  "force_update": true,
  "store_url": "https://play.google.com/...",
  "message_title": "필수 업데이트 안내",
  "message_body": "이전 버전은 더 이상 지원되지 않습니다..."
}
```

**로직**:
1. `current < min_version` → 강제 업데이트
2. `min_version ≤ current < latest` → 권장 업데이트
3. `current ≥ latest` → 업데이트 안내 없음

### 4. 스키마 ✅

**위치**: `app_config/schemas.py`

```python
class VersionCheckResponseSchema(Schema):
    latest_version: str
    min_version: str
    force_update: bool
    store_url: str
    message_title: str
    message_body: str
```

### 5. 테스트 코드 ✅

**위치**: `app_config/tests/`

#### 유틸리티 테스트 (`test_utils.py`)
- **24개 테스트 모두 통과** ✅
- Version 클래스 파싱 및 비교
- 엣지 케이스 (음수, 잘못된 형식, 빈 문자열)
- 실제 시나리오 (강제/권장/불필요 업데이트)

```bash
pytest app_config/tests/test_utils.py -v
# 24 passed in 0.19s
```

#### API 테스트 (`test_version_check_api.py`)
- 강제 업데이트 시나리오
- 권장 업데이트 시나리오
- 업데이트 불필요 시나리오
- 플랫폼별 분리 테스트
- 에러 처리 테스트

### 6. 문서화 ✅

#### 명세서 (`docs/specifications/APP_VERSION_MANAGEMENT_SPEC.md`)
- 시스템 개요 및 핵심 원칙
- 데이터 모델 상세 설명
- API 엔드포인트 명세
- 버전 비교 로직 설명
- 클라이언트 구현 예시 (Flutter/Dart)

#### 운영 가이드 (`docs/reports/APP_VERSION_OPERATION_GUIDE.md`)
- 일반적인 배포 시나리오 (정상 업데이트, 긴급 핫픽스, 플랫폼 시간차)
- 운영 베스트 프랙티스
- 심사 속도 차이 대응
- 강제/권장 업데이트 전환 시점
- 트러블슈팅 가이드
- 체크리스트

## 📊 핵심 업데이트 로직

```
앱 시작
  ↓
GET /api/v1/app-config/version
  ↓
┌─────────────────────────────────┐
│ current < min_version?          │
│  YES → force_update: true       │ ← 강제 업데이트
│        스토어로 강제 이동        │
└─────────────────────────────────┘
  ↓ NO
┌─────────────────────────────────┐
│ current < latest_version?       │
│  YES → force_update: false      │ ← 권장 업데이트
│        "나중에" 버튼 제공        │
└─────────────────────────────────┘
  ↓ NO
┌─────────────────────────────────┐
│ current ≥ latest_version        │
│  → 업데이트 안내 없음            │ ← 최신 버전
│     정상 앱 실행                 │
└─────────────────────────────────┘
```

## 🏪 스토어 URL

### Android
```
https://play.google.com/store/apps/details?id=com.reviewmaps.mobile&pli=1
```

### iOS
```
https://apps.apple.com/kr
```

## 🎨 업데이트 메시지 (네이버 스타일)

### 강제 업데이트
```
제목: "필수 업데이트 안내"
내용: "이전 버전은 더 이상 지원되지 않습니다.
      앱을 계속 사용하시려면 최신 버전으로 업데이트해 주세요."
버튼: [업데이트]
```

### 권장 업데이트
```
제목: "업데이트 안내"
내용: "더 안정적이고 편리한 서비스 이용을 위해
      최신 버전으로 업데이트해 주세요."
      (또는 커스텀 메시지)
버튼: [나중에] [업데이트]
```

### 최신 버전
```
업데이트 안내 표시 안함
정상 앱 실행
```

## 📋 운영 베스트 프랙티스 요약

### 1. 버전 번호 관리
- Semantic Versioning 준수 (major.minor.patch)
- major: 호환성 깨지는 변경
- minor: 기능 추가
- patch: 버그 수정

### 2. minimum_version 설정
- **보수적으로 설정**: 새 버전 출시해도 즉시 상향하지 말 것
- **상향 기준**:
  - 신규 버전 업데이트율 > 80%
  - 신규 버전 안정성 확인 (최소 2주)
  - 주요 버그 없음

### 3. 플랫폼별 독립 배포
- Android 먼저 배포 (심사 빠름: 2-3일)
- iOS 나중에 배포 (심사 느림: 1-2주)
- 한쪽 지연이 다른쪽에 영향 없음 ✅

### 4. 긴급 핫픽스
- `minimum_version = latest_version` 설정
- 모든 이전 버전 사용자 강제 업데이트
- ⚠️ 스토어 승인 **후**에만 변경

## 🔧 사용 방법

### 서버 설정 (Django Admin)

1. **Admin 접속**
   ```
   https://api.reviewmaps.com/admin/app_config/appversion/
   ```

2. **새 버전 등록**
   ```
   Platform: android
   Version: 1.4.0
   Build Number: 140
   Minimum Version: 1.3.0
   Store URL: https://play.google.com/...
   Update Message: "새로운 기능이 추가되었습니다!"
   Is Active: ✅
   ```

3. **저장**

### 클라이언트 호출

```dart
// Flutter 예시
final response = await http.get(
  Uri.parse('https://api.reviewmaps.com/api/v1/app-config/version')
    .replace(queryParameters: {
      'platform': 'android',
      'current_version': '1.3.0',
    }),
);

final data = json.decode(response.body);

if (data['force_update']) {
  // 강제 업데이트 모달 (닫기 버튼 없음)
  showForceUpdateDialog(data);
} else if (needsUpdate(currentVersion, data['latest_version'])) {
  // 권장 업데이트 모달 (나중에 버튼 있음)
  showRecommendedUpdateDialog(data);
}
```

## 📝 테스트 실행

```bash
# 유틸리티 테스트
python manage.py test app_config.tests.test_utils -v 2
# ✅ 24 passed

# API 테스트
python manage.py test app_config.tests.test_version_check_api -v 2
```

## 🔄 배포 시나리오 예시

### 시나리오 1: 정상 업데이트 (1.3.0 → 1.4.0)

1. **스토어 제출**
   - Android: Play Console에 1.4.0 제출 (2-3일)
   - iOS: App Store Connect에 1.4.0 제출 (1-2주)

2. **Android 승인 후**
   ```
   Django Admin:
   - Platform: android
   - Version: 1.4.0
   - Minimum Version: 1.3.0 (기존 유지)
   ```

3. **iOS 승인 후**
   ```
   Django Admin:
   - Platform: ios
   - Version: 1.4.0
   - Minimum Version: 1.3.0 (기존 유지)
   ```

4. **2-3주 후 minimum_version 상향**
   ```
   업데이트율 > 80% 확인 후
   Minimum Version: 1.4.0으로 변경
   ```

### 시나리오 2: 긴급 핫픽스 (보안 패치)

1. **긴급 버전 빌드**
   - 버전: 1.3.6
   - 설명: "보안 문제 해결을 위한 긴급 업데이트"

2. **스토어 승인 완료 후**
   ```
   Django Admin:
   - Version: 1.3.6
   - Minimum Version: 1.3.6 ← ⚠️ 최신 버전과 동일
   - Update Message: "보안 문제 해결을 위한 긴급 업데이트입니다."
   ```

3. **효과**
   - 모든 1.3.5 이하 사용자 → 강제 업데이트

## 📂 파일 구조

```
server/
├── app_config/
│   ├── models.py          # AppVersion 모델
│   ├── api.py             # GET /version 엔드포인트
│   ├── schemas.py         # Pydantic 스키마
│   ├── utils.py           # 버전 비교 유틸리티 ✨ NEW
│   ├── admin.py           # Django Admin 설정
│   └── tests/
│       ├── test_utils.py              # 유틸리티 테스트 ✨ NEW
│       └── test_version_check_api.py  # API 테스트 ✨ NEW
└── docs/
    ├── specifications/
    │   └── APP_VERSION_MANAGEMENT_SPEC.md     # 명세서 ✨ NEW
    └── reports/
        ├── APP_VERSION_OPERATION_GUIDE.md     # 운영 가이드 ✨ NEW
        └── APP_VERSION_SYSTEM_SUMMARY.md      # 요약 문서 (현재 파일)
```

## 🎉 성과

### 기술적 성과
- ✅ 논리적 버전 기반 독립 관리 시스템 구축
- ✅ Semantic Versioning 완벽 지원 (Version 클래스)
- ✅ 플랫폼별(iOS/Android) 독립 배포 가능
- ✅ 강제/권장 업데이트 자동 판단
- ✅ 네이버 스타일 사용자 친화적 메시지
- ✅ 24개 유틸리티 테스트 통과
- ✅ 포괄적인 API 테스트 작성

### 운영적 성과
- ✅ 스토어 심사 시간차 대응 가능
- ✅ 긴급 핫픽스 빠른 배포 가능
- ✅ 점진적 업데이트 정책 지원
- ✅ 롤백 전략 수립
- ✅ 운영 가이드 완비

### 문서화 성과
- ✅ 명세서 (기술 사양)
- ✅ 운영 가이드 (실무 지침)
- ✅ 트러블슈팅 가이드
- ✅ 배포 체크리스트
- ✅ 클라이언트 구현 예시

## 🚀 다음 단계

### 즉시 가능
1. Django Admin에서 현재 버전 등록
2. 클라이언트 앱에 버전 체크 로직 통합
3. 첫 배포 시 API 테스트

### 향후 개선
1. **모니터링 대시보드**
   - 버전별 사용자 분포 시각화
   - 업데이트율 실시간 추적

2. **A/B 테스트**
   - 업데이트 메시지 효과 측정
   - 권장 업데이트 전환율 분석

3. **자동화**
   - CI/CD 파이프라인에 버전 자동 등록
   - 스토어 승인 알림 자동화

## 📞 문의

- **기술 문의**: 개발팀
- **운영 문의**: 운영팀
- **긴급 장애**: 24/7 대응팀

---

**작성일**: 2025-11-25
**작성자**: Claude (AI Assistant)
**버전**: 1.0.0
