# 앱 버전 관리 시스템 명세서

## 📋 개요

ReviewMaps 앱의 논리적 버전(Logical Version) 기반 업데이트 관리 시스템입니다.
네이티브 스토어 버전(CFBundleShortVersionString, versionName)과 독립적으로 동작하며, 플랫폼별(iOS/Android) 최소 지원 버전 및 강제/권장 업데이트 정책을 제공합니다.

## 🎯 핵심 원칙

1. **논리적 버전(Logical Version) 기준**: 실제 스토어/네이티브 버전은 신경 쓰지 않음
2. **플랫폼별 독립 관리**: iOS와 Android의 min_version을 따로 관리
3. **명확한 업데이트 정책**:
   - `current < min_version` → **강제 업데이트**
   - `min_version ≤ current < latest_version` → **권장 업데이트**
   - `current ≥ latest_version` → **업데이트 안내 없음**

## 📊 데이터 모델

### AppVersion 모델

```python
class AppVersion(models.Model):
    """앱 버전 관리 모델"""
    platform = models.CharField(max_length=20, choices=[('android', 'Android'), ('ios', 'iOS')])
    version = models.CharField(max_length=20)  # 논리적 버전 (예: "1.4.0")
    build_number = models.IntegerField()  # 참고용 빌드 번호
    minimum_version = models.CharField(max_length=20)  # 최소 지원 버전
    force_update = models.BooleanField(default=False)  # 강제 업데이트 플래그 (현재 미사용)
    update_message = models.TextField(null=True, blank=True)  # 커스텀 업데이트 메시지
    store_url = models.URLField(max_length=500)  # 플레이스토어/앱스토어 URL
    is_active = models.BooleanField(default=True)  # 활성화 여부
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
```

### 인덱스

- `idx_appver_platform_active`: `(platform, is_active)` - 버전 조회 최적화
- `idx_appver_created`: `(-created_at)` - 최신 버전 조회 최적화

## 🔌 API 엔드포인트

### GET /api/v1/app-config/version

앱 버전 설정 조회 (클라이언트가 자체 비교)

#### 요청 파라미터

| 파라미터 | 타입 | 필수 | 설명 |
|---------|------|------|------|
| platform | string | ✅ | `android` 또는 `ios` |
| current_version | string | ⚪ | (선택) 현재 버전 - 제공 시 서버가 force_update, 메시지 자동 계산 |

> **권장**: `current_version` 없이 호출하고 클라이언트가 직접 버전 비교
> - 불필요한 네트워크 전송 감소
> - 오프라인 캐싱 가능
> - 클라이언트 로직 유연성

#### 응답 예시

**기본 응답 (current_version 없이 호출)**
```json
{
  "latest_version": "1.4.0",
  "min_version": "1.3.0",
  "force_update": false,
  "store_url": "https://play.google.com/store/apps/details?id=com.reviewmaps.mobile&pli=1",
  "message_title": "업데이트 안내",
  "message_body": "더 안정적이고 편리한 서비스 이용을 위해\n최신 버전으로 업데이트해 주세요."
}
```

> **클라이언트 로직**:
> ```
> if (currentVersion < minVersion) → 강제 업데이트
> else if (currentVersion < latestVersion) → 권장 업데이트
> else → 업데이트 안내 없음
> ```

**서버 판단 응답 (current_version 제공 시)**

강제 업데이트 (current=1.2.0 < min_version=1.3.0):
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

#### 에러 응답

**404 - 활성화된 버전 정보 없음**
```json
{
  "detail": "android 플랫폼의 활성화된 버전 정보가 없습니다."
}
```

**404 - 잘못된 버전 형식**
```json
{
  "detail": "잘못된 버전 형식: 1.3"
}
```

**422 - 필수 파라미터 누락**
```json
{
  "detail": [
    {
      "type": "missing",
      "loc": ["query", "platform"],
      "msg": "Field required"
    }
  ]
}
```

## 🧮 버전 비교 로직

### Version 클래스

Semantic Versioning (major.minor.patch) 형식을 지원하는 버전 비교 클래스

```python
from app_config.utils import Version

v1 = Version("1.3.0")
v2 = Version("1.4.0")

v1 < v2  # True
v1 == Version("1.3.0")  # True
```

#### 지원 연산

- `==`: 동일 버전 비교
- `<`: 버전이 낮은지 비교
- `<=`: 버전이 같거나 낮은지 비교
- `>`: 버전이 높은지 비교
- `>=`: 버전이 같거나 높은지 비교

### 헬퍼 함수

```python
from app_config.utils import compare_versions, needs_update, is_force_update_required

# 두 버전 비교
compare_versions("1.3.0", "1.4.0")  # -1 (업데이트 필요)
compare_versions("1.4.0", "1.4.0")  # 0 (동일)
compare_versions("1.5.0", "1.4.0")  # 1 (최신)

# 업데이트 필요 여부
needs_update("1.3.0", "1.4.0")  # True

# 강제 업데이트 필요 여부
is_force_update_required("1.2.0", "1.3.0")  # True
```

### 버전 형식 요구사항

- 형식: `major.minor.patch` (예: "1.3.5")
- 각 파트는 0 이상의 정수
- 정확히 3개 파트 필요 (2개 또는 4개 불가)
- 선행 0 없이 (예: "1.03.0" 불가)

**유효한 버전**
- ✅ "1.0.0"
- ✅ "1.3.5"
- ✅ "2.10.15"
- ✅ "0.9.0"

**유효하지 않은 버전**
- ❌ "1.3" (파트 부족)
- ❌ "1.3.5.6" (파트 과다)
- ❌ "1.3.a" (숫자 아님)
- ❌ "1.-3.5" (음수)

## 🏪 스토어 URL

### Android
```
https://play.google.com/store/apps/details?id=com.reviewmaps.mobile&pli=1
```

### iOS
```
https://apps.apple.com/kr
```

## 🔄 업데이트 판단 플로우

```
앱 시작
  ↓
GET /api/v1/app-config/version?platform={platform}&current_version={version}
  ↓
서버: 버전 비교
  ↓
┌─────────────────────────────────────┐
│ current < min_version?              │
│  YES → force_update: true           │
│        "필수 업데이트 안내" 표시     │
│        스토어로 강제 이동            │
└─────────────────────────────────────┘
  ↓ NO
┌─────────────────────────────────────┐
│ current < latest_version?           │
│  YES → force_update: false          │
│        "업데이트 안내" 표시          │
│        "나중에" 버튼 제공            │
└─────────────────────────────────────┘
  ↓ NO
┌─────────────────────────────────────┐
│ current ≥ latest_version            │
│  → force_update: false              │
│     업데이트 안내 표시 안함          │
│     정상 앱 실행                     │
└─────────────────────────────────────┘
```

## 📱 클라이언트 구현

> **📖 상세 가이드**: [클라이언트 구현 가이드](CLIENT_IMPLEMENTATION_GUIDE.md)
> - Flutter/Dart 완전한 예시
> - React Native (TypeScript) 예시
> - 버전 비교 로직 상세
> - UI/UX 권장사항
> - 캐싱 전략

### 빠른 예시 (Flutter/Dart)

```dart
// 1. 서버에서 버전 설정 조회 (current_version 없이!)
final config = await fetchVersionConfig(platform);

// 2. 클라이언트에서 버전 비교
final currentVersion = packageInfo.version;
final needsUpdate = compareVersions(currentVersion, config.latestVersion) < 0;
final forceUpdate = compareVersions(currentVersion, config.minVersion) < 0;

// 3. UI 표시
if (forceUpdate) {
  showForceUpdateDialog(config);  // 닫기 버튼 없음
} else if (needsUpdate) {
  showRecommendedUpdateDialog(config);  // "나중에" 버튼 있음
}

// 버전 비교 함수
int compareVersions(String v1, String v2) {
  final parts1 = v1.split('.').map(int.parse).toList();
  final parts2 = v2.split('.').map(int.parse).toList();
  for (int i = 0; i < 3; i++) {
    if (parts1[i] < parts2[i]) return -1;
    if (parts1[i] > parts2[i]) return 1;
  }
  return 0;
}
```

**장점**:
- ✅ 불필요한 네트워크 전송 없음 (currentVersion을 서버로 보내지 않음)
- ✅ 오프라인 캐싱 가능
- ✅ 클라이언트 로직 유연성

## 🛠️ Django Admin 설정

### 설정 위치
`app_config/admin.py`

### 사용 가능한 기능
- 플랫폼별 버전 필터링
- 활성/비활성 필터
- 버전, 최소 버전, 스토어 URL 수정
- 커스텀 업데이트 메시지 작성
- 여러 버전 동시 활성화/비활성화

### Admin 사용 팁
1. 새 버전 배포 시 **기존 버전은 비활성화하지 말 것** (히스토리 보존)
2. `is_active=True`인 최신 항목이 실제 사용됨
3. 플랫폼별로 항상 활성 버전이 1개 이상 있어야 함

## 🧪 테스트

### 유틸리티 테스트
```bash
python manage.py test app_config.tests.test_utils -v 2
```

**테스트 커버리지**
- Version 클래스 파싱 및 비교 (24개 테스트)
- 엣지 케이스 (음수, 잘못된 형식, 빈 문자열)
- 실제 시나리오 (강제/권장/불필요 업데이트)

### API 테스트
```bash
python manage.py test app_config.tests.test_version_check_api -v 2
```

**테스트 시나리오**
- 강제 업데이트 (current < min_version)
- 권장 업데이트 (min_version ≤ current < latest)
- 업데이트 불필요 (current ≥ latest)
- 플랫폼별 분리
- 에러 처리 (잘못된 버전, 활성 설정 없음)

## 📚 참고 자료

### 관련 파일
- 모델: `app_config/models.py`
- API: `app_config/api.py`
- 스키마: `app_config/schemas.py`
- 유틸리티: `app_config/utils.py`
- 테스트: `app_config/tests/test_utils.py`, `app_config/tests/test_version_check_api.py`

### 관련 문서
- [클라이언트 구현 가이드](CLIENT_IMPLEMENTATION_GUIDE.md) ⭐ **필수**
- [운영 가이드](../reports/APP_VERSION_OPERATION_GUIDE.md)
- [시스템 요약](../reports/APP_VERSION_SYSTEM_SUMMARY.md)
- [환경변수 명세](ENVIRONMENT_VARIABLES.md)
