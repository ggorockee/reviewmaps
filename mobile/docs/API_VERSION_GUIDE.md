# 앱 버전 체크 시스템 가이드

## 개요

플랫폼별(iOS, Android) 앱 버전 관리 및 업데이트 체크 시스템이 이미 구현되어 있습니다.

### 주요 기능
- 플랫폼별 최신 버전 정보 관리
- 버전 비교 및 업데이트 필요 여부 판단
- 강제 업데이트 정책 관리
- Semantic Versioning(1.4.0) 기반 비교

---

## 1. 데이터베이스 모델

### AppVersion 모델
| 필드 | 타입 | 설명 |
|------|------|------|
| platform | CharField | ios 또는 android |
| version | CharField | 최신 버전 (예: 1.4.1) |
| build_number | IntegerField | 빌드 번호 (예: 50) |
| minimum_version | CharField | 최소 지원 버전 (이 버전 미만은 강제 업데이트) |
| force_update | BooleanField | 강제 업데이트 여부 |
| update_message | TextField | 업데이트 안내 메시지 |
| store_url | URLField | Play Store 또는 App Store URL |
| is_active | BooleanField | 활성화 여부 (최신 활성 버전 사용) |

### Django Admin 설정
Django Admin에서 버전 정보를 쉽게 관리할 수 있습니다:
```
http://your-domain/admin/app_config/appversion/
```

---

## 2. API 엔드포인트

### 버전 체크 API
**Endpoint**: `GET /v1/app-config/version`

**Query Parameters**:
| Parameter | Required | Type | Description |
|-----------|----------|------|-------------|
| platform | ✅ | string | ios 또는 android |
| current_version | ✅ | string | 현재 앱 버전 (예: 1.4.0) |

### 요청 예시
```
GET /v1/app-config/version?platform=ios&current_version=1.4.0
```

### 응답 스키마
```json
{
  "needs_update": false,
  "force_update": false,
  "latest_version": "1.4.1",
  "message": "새로운 기능이 추가되었습니다.",
  "store_url": "https://apps.apple.com/app/id123456789"
}
```

| 필드 | 타입 | 설명 |
|------|------|------|
| needs_update | boolean | 업데이트 필요 여부 (false=최신, true=업데이트 필요) |
| force_update | boolean | 강제 업데이트 여부 |
| latest_version | string | 서버의 최신 버전 |
| message | string | 업데이트 안내 메시지 (선택) |
| store_url | string | 스토어 다운로드 URL |

---

## 3. 버전 비교 로직

### Semantic Versioning 비교
버전은 `major.minor.patch` 형식으로 비교됩니다:

**예시 1: 업데이트 불필요**
- 현재 버전: 1.4.1
- 최신 버전: 1.4.1
- 결과: `needs_update: false`, `force_update: false`

**예시 2: 업데이트 권장**
- 현재 버전: 1.4.0
- 최신 버전: 1.4.1
- 최소 버전: 1.0.0
- 결과: `needs_update: true`, `force_update: false`

**예시 3: 강제 업데이트**
- 현재 버전: 1.1.0
- 최신 버전: 1.4.1
- 최소 버전: 1.2.0
- 결과: `needs_update: true`, `force_update: true`

### 강제 업데이트 조건
다음 중 하나라도 해당되면 강제 업데이트:
1. 현재 버전 < minimum_version
2. AppVersion.force_update = True

---

## 4. 클라이언트 통합 가이드

### Flutter/React Native 예시
```dart
Future<void> checkAppVersion() async {
  // 1. 현재 앱 버전 가져오기
  PackageInfo packageInfo = await PackageInfo.fromPlatform();
  String currentVersion = packageInfo.version; // 예: "1.4.0"

  // 2. 플랫폼 확인
  String platform = Platform.isIOS ? 'ios' : 'android';

  // 3. 서버에 버전 체크 요청
  final response = await http.get(
    Uri.parse('https://api.example.com/v1/app-config/version')
        .replace(queryParameters: {
      'platform': platform,
      'current_version': currentVersion,
    }),
  );

  final data = jsonDecode(response.body);

  // 4. 업데이트 필요 여부 확인
  if (data['needs_update']) {
    if (data['force_update']) {
      // 강제 업데이트 다이얼로그 표시 (닫기 버튼 없음)
      showForceUpdateDialog(
        message: data['message'],
        storeUrl: data['store_url'],
      );
    } else {
      // 선택적 업데이트 다이얼로그 표시 (나중에 하기 버튼 있음)
      showOptionalUpdateDialog(
        message: data['message'],
        storeUrl: data['store_url'],
      );
    }
  }
}
```

### iOS (Swift) 예시
```swift
func checkAppVersion() {
    guard let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
        return
    }

    let url = URL(string: "https://api.example.com/v1/app-config/version?platform=ios&current_version=\(currentVersion)")!

    URLSession.shared.dataTask(with: url) { data, response, error in
        guard let data = data else { return }

        if let json = try? JSONDecoder().decode(VersionCheckResponse.self, from: data) {
            if json.needsUpdate {
                DispatchQueue.main.async {
                    if json.forceUpdate {
                        self.showForceUpdateAlert(message: json.message, storeUrl: json.storeUrl)
                    } else {
                        self.showOptionalUpdateAlert(message: json.message, storeUrl: json.storeUrl)
                    }
                }
            }
        }
    }.resume()
}
```

### Android (Kotlin) 예시
```kotlin
suspend fun checkAppVersion() {
    val packageInfo = packageManager.getPackageInfo(packageName, 0)
    val currentVersion = packageInfo.versionName // 예: "1.4.0"

    val response = apiService.checkVersion(
        platform = "android",
        currentVersion = currentVersion
    )

    if (response.needsUpdate) {
        if (response.forceUpdate) {
            showForceUpdateDialog(
                message = response.message,
                storeUrl = response.storeUrl
            )
        } else {
            showOptionalUpdateDialog(
                message = response.message,
                storeUrl = response.storeUrl
            )
        }
    }
}
```

---

## 5. 운영 가이드

### 새 버전 배포 시 절차

**1. Django Admin에서 새 버전 등록**
```
1. /admin/app_config/appversion/add/ 접속
2. 플랫폼 선택 (iOS 또는 Android)
3. 버전 입력 (예: 1.4.1)
4. 빌드 번호 입력 (예: 51)
5. 최소 지원 버전 설정 (예: 1.0.0)
6. 강제 업데이트 여부 선택
7. 업데이트 메시지 입력
8. 스토어 URL 입력
9. is_active 체크
10. 저장
```

**2. 기존 버전 비활성화**
- 이전 버전의 `is_active`를 False로 변경
- 가장 최신의 활성 버전만 API에서 반환됨

### 버전 관리 전략

**일반 업데이트 (force_update: False)**
- 새 기능 추가
- UI 개선
- 비중요 버그 수정
- 사용자가 업데이트 시기 선택 가능

**강제 업데이트 (force_update: True)**
- 중요한 보안 패치
- 크리티컬 버그 수정
- API 호환성 변경
- 서버 정책 변경으로 인한 필수 업데이트

**minimum_version 관리**
- 최소 지원 버전보다 낮으면 자동으로 강제 업데이트
- 너무 낮게 설정하면 오래된 버전 지원 부담 증가
- 너무 높게 설정하면 사용자 이탈 위험

---

## 6. 테스트

### 수동 테스트
**1. API 직접 호출**
```bash
# 최신 버전 (업데이트 불필요)
curl "http://localhost:8000/v1/app-config/version?platform=ios&current_version=1.4.1"

# 구버전 (업데이트 권장)
curl "http://localhost:8000/v1/app-config/version?platform=ios&current_version=1.4.0"

# 매우 오래된 버전 (강제 업데이트)
curl "http://localhost:8000/v1/app-config/version?platform=ios&current_version=1.0.0"
```

**2. 자동 테스트 실행**
```bash
# 버전 체크 API 테스트
uv run python manage.py test app_config.tests.test_api.AppVersionAPITest --keepdb

# 전체 app_config 테스트
uv run python manage.py test app_config --keepdb
```

### 테스트 커버리지
- ✅ 최신 버전 사용 중 (업데이트 불필요)
- ✅ 구버전 사용 중 (업데이트 권장)
- ✅ 강제 업데이트 필요 (minimum_version 미만)
- ✅ 파라미터 누락 에러 처리
- ✅ 활성 버전 없을 때 404 에러

---

## 7. 문제 해결

### Q1. API 호출 시 404 에러
**원인**: 활성화된 버전 정보가 없음
**해결**: Django Admin에서 해당 플랫폼의 버전을 `is_active=True`로 설정

### Q2. 항상 업데이트 필요 응답
**원인**: 버전 형식 불일치 (1.4.0 vs 1.4.0.1)
**해결**: 클라이언트와 서버 버전 형식 통일 (major.minor.patch)

### Q3. 강제 업데이트가 작동하지 않음
**원인 1**: minimum_version이 너무 낮게 설정됨
**원인 2**: force_update=False로 설정됨
**해결**: AppVersion 설정 확인 및 수정

---

## 8. 향후 개선 사항

### 제안 사항
1. **점진적 롤아웃**: 특정 비율의 사용자에게만 업데이트 권장
2. **A/B 테스트**: 업데이트 메시지 효과 측정
3. **업데이트 통계**: 버전별 사용자 분포 추적
4. **알림 빈도 제한**: 하루 1회만 업데이트 알림 표시
5. **다국어 지원**: 업데이트 메시지 다국어 제공

---

## 9. 참고 자료

### 파일 위치
- 모델: `app_config/models.py` (59-122줄)
- API: `app_config/api.py` (46-110줄)
- 스키마: `app_config/schemas.py` (41-48줄)
- 테스트: `app_config/tests/test_api.py` (107-198줄)
- Admin: `app_config/admin.py`

### API 문서
Swagger UI에서 API 문서 확인:
```
http://localhost:8000/v1/docs
```

### 관련 문서
- Django Ninja 공식 문서: https://django-ninja.dev
- Semantic Versioning: https://semver.org
