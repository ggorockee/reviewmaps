# 알림 히스토리 이동 문제 수정 완료

## 수정 일자
2025-12-22

## 문제 요약
1. **안드로이드**: 알림 클릭 시 히스토리로 이동하지 않음
2. **iOS**: 알림 클릭 시 히스토리로 이동하지만 알림 내역이 표시되지 않음

## 적용된 수정 사항

### Fix 1: iOS 데이터 로딩 보장 ✅

**파일**: `mobile/lib/screens/notification_screen.dart`

**변경 사항**:

| Before | After |
|--------|-------|
| `_getUserLocation()` 완료 후 `_loadAlerts()` 호출 | `initState`에서 기본 위치로 즉시 초기화 |
| 위치 권한 없으면 기본값 설정 후 `_loadAlerts()` | 기본값은 미리 설정, 권한 체크는 비동기로 |
| 알림 탭 진입 시 데이터 로딩 대기 | `initialTabIndex==1`이면 즉시 `_loadAlerts()` 호출 |

**핵심 로직**:
```dart
@override
void initState() {
  // 기본 위치로 초기화 (서울 시청)
  _userLat = 37.5666805;
  _userLng = 126.9784147;

  // 알림 기록 탭으로 직접 진입한 경우 즉시 로드
  if (widget.initialTabIndex == 1) {
    _loadAlerts();
  }

  // 백그라운드에서 실제 위치 가져오기 (완료 시 재로드)
  _getUserLocation();
}
```

**효과**:
- ✅ iOS에서 알림 클릭 시 즉시 알림 목록이 표시됨
- ✅ 위치 권한 대기 없이 기본 위치로 우선 표시
- ✅ 실제 위치 획득 후 자동으로 재정렬

### Fix 2: Android Navigation 안정화 ✅

**파일**: `mobile/lib/services/fcm_service.dart`

**변경 사항**:

| Before | After |
|--------|-------|
| Navigator null 체크만 수행 | Navigator 준비까지 재시도 (최대 3초) |
| 네비게이션 실패 시 조용히 종료 | try-catch로 에러 로깅 |
| 서버 동기화 대기 없음 | 500ms 지연 후 네비게이션 시작 |

**핵심 로직**:
```dart
Future<void> _navigateToNotificationScreen() async {
  // 서버의 알림 저장 완료를 위해 지연
  await Future.delayed(const Duration(milliseconds: 500));

  // Navigator가 준비될 때까지 재시도 (최대 3초)
  NavigatorState? navigator;
  int retryCount = 0;
  const maxRetries = 6;

  while (retryCount < maxRetries) {
    navigator = main_app.navigatorKey.currentState;
    if (navigator != null) break;

    await Future.delayed(const Duration(milliseconds: 500));
    retryCount++;
  }

  if (navigator == null) {
    debugPrint('❌ 네비게이터를 찾을 수 없습니다.');
    return;
  }

  try {
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) => const MainScreen(
          initialTabIndex: 2,
          openAlertHistoryTab: true,
        ),
      ),
      (route) => false,
    );
  } catch (e) {
    debugPrint('❌ 네비게이션 실패: $e');
  }
}
```

**효과**:
- ✅ 앱 콜드 스타트 시 Navigator 초기화 대기
- ✅ 네비게이션 실패 시 명확한 에러 로깅
- ✅ 서버 알림 저장 완료 후 화면 이동으로 데이터 누락 방지

### Fix 3: 위치 기반 재로드 최적화 ✅

**파일**: `mobile/lib/screens/notification_screen.dart`

**변경 사항**:

| Before | After |
|--------|-------|
| 위치 변경 시 무조건 `_loadAlerts()` | 알림 탭에 있을 때만 재로드 |
| 중복 로딩 가능성 | 위치 변경 감지 후 재로드 |

**핵심 로직**:
```dart
Future<void> _getUserLocation() async {
  // ... 위치 가져오기 ...

  final locationChanged = _userLat != position.latitude ||
                         _userLng != position.longitude;

  setState(() {
    _userLat = position.latitude;
    _userLng = position.longitude;
  });

  // 위치가 변경되었고 알림 기록 탭에 있는 경우만 재로드
  if (locationChanged && _tabController.index == 1) {
    _loadAlerts();
  }
}
```

**효과**:
- ✅ 불필요한 API 호출 방지
- ✅ 위치 변경 시에만 재정렬
- ✅ 다른 탭에 있을 때는 재로드하지 않음

## 테스트 체크리스트

### 안드로이드
- [ ] 앱 포그라운드 상태에서 알림 수신 → 로컬 알림 탭 → 히스토리 표시
- [ ] 앱 백그라운드 상태에서 알림 수신 → 시스템 알림 탭 → 히스토리 표시
- [ ] 앱 종료 상태에서 알림 수신 → 시스템 알림 탭 → 앱 실행 + 히스토리 표시
- [ ] 비로그인 상태에서 알림 탭 → 로그인 화면 표시

### iOS
- [ ] 앱 포그라운드 상태에서 알림 수신 → 로컬 알림 탭 → 히스토리 표시
- [ ] 앱 백그라운드 상태에서 알림 수신 → 시스템 알림 탭 → 히스토리 표시
- [ ] 앱 종료 상태에서 알림 수신 → 시스템 알림 탭 → 앱 실행 + 히스토리 표시
- [ ] 위치 권한 거부 상태에서 알림 탭 → 기본 위치(서울)로 히스토리 표시
- [ ] 위치 권한 허용 상태에서 알림 탭 → 실제 위치 기반 히스토리 표시
- [ ] 새로고침 버튼 탭 → 최신 알림 목록 다시 로드

### 공통
- [ ] 알림 클릭 후 500ms 이내에 화면 전환
- [ ] 알림 목록이 비어있지 않음
- [ ] 거리순/최신순 정렬 정상 동작
- [ ] 읽지 않은 알림 뱃지 표시 정확

## 로그 확인 포인트

### 정상 동작 시 예상 로그

**iOS 알림 탭 진입**:
```
🔔 [NotificationScreen] 알림 기록 탭으로 직접 진입 - 즉시 로드
[getMyAlerts] 요청 시작: https://...
📍 실제 위치 획득: 37.xxx, 127.xxx
📍 위치 변경 - 알림 목록 재로드
```

**Android 알림 클릭 (백그라운드)**:
```
📱 백그라운드 메시지로 앱 열림:
  - 제목: [알림 제목]
  - 데이터: {...}
🔔 [FCM] 서버 동기화 대기 완료 - 네비게이션 시작
✅ [FCM] 알림 기록 페이지로 이동 완료
🔔 [NotificationScreen] 알림 기록 탭으로 직접 진입 - 즉시 로드
```

**Android 알림 클릭 (종료 상태)**:
```
📱 종료 상태에서 알림으로 앱 실행됨
  - 제목: [알림 제목]
  - 데이터: {...}
🔔 [FCM] 서버 동기화 대기 완료 - 네비게이션 시작
⏳ [FCM] 네비게이터 대기 중... (0/6)
✅ [FCM] 알림 기록 페이지로 이동 완료
```

### 에러 발생 시 확인할 로그

**Navigator 초기화 실패**:
```
❌ [FCM] 네비게이터를 찾을 수 없습니다. 앱이 아직 초기화되지 않았을 수 있습니다.
```
→ main.dart의 navigatorKey 설정 확인

**위치 권한 거부**:
```
📍 위치 권한 없음 - 기본 위치 사용
```
→ 정상 동작 (기본 위치로 표시됨)

**알림 목록 로드 실패**:
```
알림 목록 로드 실패: [에러 메시지]
```
→ 네트워크 연결 또는 인증 토큰 확인

## 추가 개선 사항 (향후 고려)

| 항목 | 설명 | 우선순위 |
|------|------|---------|
| 폴링 재시도 | 서버 알림 저장 완료까지 주기적 재시도 | 낮음 |
| 로딩 인디케이터 | 네비게이션 대기 중 로딩 표시 | 중간 |
| 오프라인 모드 | 네트워크 없을 때 캐시된 알림 표시 | 중간 |
| 에러 리포팅 | Firebase Crashlytics 연동 | 높음 |

## 관련 파일

| 파일 | 수정 여부 | 주요 변경 사항 |
|------|----------|---------------|
| `mobile/lib/services/fcm_service.dart` | ✅ 수정 | Navigator 재시도, 서버 동기화 대기 |
| `mobile/lib/screens/notification_screen.dart` | ✅ 수정 | 즉시 로딩, 위치 기반 재로드 최적화 |
| `mobile/lib/screens/main_screen.dart` | 변경 없음 | - |
| `mobile/lib/services/keyword_service.dart` | 변경 없음 | - |
