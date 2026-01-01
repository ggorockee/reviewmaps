# 알림 히스토리 이동 문제 진단 보고서

## 문제 요약

**증상:**
1. **안드로이드**: 알림 클릭 시 히스토리로 이동하지 않음
2. **iOS**: 알림 클릭 시 히스토리로 이동하지만 알림 내역이 표시되지 않음 (새로고침해도 안 나옴)

## 근본 원인 분석

### 1. 안드로이드 문제 (Navigation 실패)

**위치**: `mobile/lib/services/fcm_service.dart:183-214`

**문제점**:
- `_onNotificationTapped` 메서드가 **로컬 알림** 탭 시에만 호출됨
- FCM에서 보낸 **시스템 알림**(백그라운드/종료 상태)은 다른 핸들러가 처리
- 안드로이드에서는 `onMessageOpenedApp`이 제대로 동작하지만, **인증 체크 타이밍** 문제 발생 가능

**코드 흐름**:
| 상태 | 핸들러 | 동작 |
|------|--------|------|
| 포그라운드 | `onMessage` → 로컬 알림 표시 | ✅ 정상 |
| 백그라운드 | `onMessageOpenedApp` | ⚠️ 네비게이션 실행되나 인증 체크 누락 |
| 종료 상태 | `getInitialMessage` | ⚠️ 500ms 딜레이 후 네비게이션 |

**핵심 문제**:
```dart
// fcm_service.dart:194-213
Future<void> _navigateToNotificationScreen() async {
  final navigator = main_app.navigatorKey.currentState;
  if (navigator == null) {
    debugPrint('⚠️ 네비게이터를 찾을 수 없습니다.');
    return;  // ← 여기서 실패하면 조용히 종료
  }

  navigator.pushAndRemoveUntil(
    MaterialPageRoute(
      builder: (context) => const MainScreen(
        initialTabIndex: 2,           // 알림 탭으로 이동
        openAlertHistoryTab: true,     // 히스토리 탭 활성화 플래그
      ),
    ),
    (route) => false,
  );
}
```

**안드로이드 실패 원인**:
1. **Navigator Key 초기화 타이밍**: 앱 콜드 스타트 시 `navigatorKey.currentState`가 null일 수 있음
2. **인증 체크 누락**: `MainScreen`으로 직접 이동하므로 `_onItemTapped`의 인증 체크를 우회
3. **에러 처리 부족**: Navigator가 null이면 로그만 남기고 조용히 실패

### 2. iOS 문제 (데이터 동기화 실패)

**위치**: `mobile/lib/screens/notification_screen.dart:165-197`

**문제점**:
- 알림 히스토리 화면으로는 이동하지만, 서버에서 알림 데이터를 불러오지 못함
- `_loadAlerts()` 호출 타이밍 문제

**코드 분석**:
```dart
// notification_screen.dart:54-67
@override
void initState() {
  super.initState();
  _tabController = TabController(
    length: 2,
    vsync: this,
    initialIndex: widget.initialTabIndex,  // ← 1로 설정됨 (알림 기록 탭)
  );
  _tabController.addListener(_onTabChanged);
  _loadKeywords();  // ← 키워드만 로드
  _getUserLocation();  // ← 비동기로 위치 가져온 후 _loadAlerts() 호출

  FcmService.instance.addNotificationListener(_onFcmNotificationReceived);
}
```

```dart
// notification_screen.dart:104-137
Future<void> _getUserLocation() async {
  try {
    // ... 위치 정보 가져오기 ...
    if (mounted) {
      setState(() {
        _userLat = position.latitude;
        _userLng = position.longitude;
      });
      _loadAlerts();  // ← 여기서 호출
    }
  } catch (e) {
    // 기본값 사용
    _userLat = 37.5666805;
    _userLng = 126.9784147;
    _loadAlerts();  // ← 또는 여기서 호출
  }
}
```

**iOS 실패 원인**:
1. **탭 변경 리스너 로직**:
   ```dart
   // notification_screen.dart:89-102
   void _onTabChanged() {
     setState(() {
       if (_isSelectionMode) {
         _isSelectionMode = false;
         _selectedAlertIds.clear();
       }
     });

     if (_tabController.index == 1 && _alerts.isEmpty && !_isAlertsLoading) {
       _loadAlerts();  // ← 조건: alerts가 비어있고 로딩 중이 아닐 때만
     }
   }
   ```

2. **경쟁 조건 (Race Condition)**:
   - `initialTabIndex=1`로 알림 기록 탭에서 시작
   - `_getUserLocation()`이 비동기로 실행 중
   - `_onTabChanged()`는 초기 탭에서는 호출되지 않음 (탭 "변경"이 아니므로)
   - `_getUserLocation()` 완료 전에 화면이 렌더링되면 `_isAlertsLoading=false` 상태로 빈 화면 표시

3. **iOS 위치 권한 처리**:
   - iOS는 위치 권한 요청 다이얼로그가 더 엄격함
   - 권한 거부 또는 지연 시 기본값(서울시청)으로 `_loadAlerts()` 호출
   - 하지만 이미 `_isAlertsLoading=true`인 상태면 중복 호출 방지 로직 때문에 무시됨

### 3. 공통 문제

**문제**: 알림 데이터 새로고침 타이밍
- FCM 알림 수신 → 서버에 알림 저장 → 사용자가 알림 클릭 → 앱 실행
- 서버 저장과 앱 실행 사이에 **시간 차이** 발생 가능 (네트워크 지연)
- 앱이 서버보다 먼저 API를 호출하면 알림이 없는 것으로 표시됨

## 수정 방안

### Fix 1: Android Navigation 안정화

**파일**: `mobile/lib/services/fcm_service.dart`

**수정 내용**:
| 항목 | 현재 | 수정 후 |
|------|------|---------|
| Navigator 체크 | null이면 조용히 실패 | 재시도 로직 추가 (최대 3초) |
| 인증 체크 | 없음 | MainScreen에서 자동 처리하도록 유지 |
| 에러 로깅 | 단순 debugPrint | 구조화된 로깅 + 에러 추적 |

### Fix 2: iOS 데이터 로딩 보장

**파일**: `mobile/lib/screens/notification_screen.dart`

**수정 내용**:
| 항목 | 현재 | 수정 후 |
|------|------|---------|
| 초기 로딩 | `_getUserLocation()` 완료 후 | `initState`에서 즉시 기본값으로 로드 |
| 탭 초기화 | `initialTabIndex`만 설정 | 탭 인덱스가 1이면 `_loadAlerts()` 명시적 호출 |
| 위치 업데이트 | 위치 획득 후 재로드 | 위치 획득 후 **재로드** (이미 로딩된 경우도) |

### Fix 3: 서버 동기화 대기

**파일**: `mobile/lib/services/fcm_service.dart`

**수정 내용**:
- 알림 히스토리로 이동 전 **짧은 지연** 추가 (500ms)
- 서버의 알림 저장 완료를 기다림
- 또는 폴링 방식으로 알림이 나타날 때까지 재시도

## 구현 우선순위

| 우선순위 | 수정 사항 | 영향 범위 | 난이도 |
|---------|----------|-----------|--------|
| 1 | iOS 데이터 로딩 보장 (Fix 2) | iOS만 | 쉬움 |
| 2 | Android Navigation 안정화 (Fix 1) | Android만 | 중간 |
| 3 | 서버 동기화 대기 (Fix 3) | iOS & Android | 쉬움 |

## 테스트 시나리오

### 안드로이드
| 시나리오 | 기대 동작 |
|---------|----------|
| 앱 포그라운드 상태에서 알림 수신 → 로컬 알림 탭 | 알림 히스토리로 이동 + 데이터 표시 |
| 앱 백그라운드 상태에서 알림 수신 → 시스템 알림 탭 | 알림 히스토리로 이동 + 데이터 표시 |
| 앱 종료 상태에서 알림 수신 → 시스템 알림 탭 | 앱 실행 + 알림 히스토리로 이동 + 데이터 표시 |
| 비로그인 상태에서 알림 탭 | 로그인 화면으로 이동 |

### iOS
| 시나리오 | 기대 동작 |
|---------|----------|
| 앱 포그라운드 상태에서 알림 수신 → 로컬 알림 탭 | 알림 히스토리로 이동 + 데이터 표시 |
| 앱 백그라운드 상태에서 알림 수신 → 시스템 알림 탭 | 알림 히스토리로 이동 + 데이터 표시 |
| 앱 종료 상태에서 알림 수신 → 시스템 알림 탭 | 앱 실행 + 알림 히스토리로 이동 + 데이터 표시 |
| 위치 권한 거부 상태에서 알림 탭 이동 | 기본 위치(서울)로 알림 목록 표시 |
| 새로고침 버튼 탭 | 최신 알림 목록 다시 로드 |

## 참고 코드 위치

| 파일 | 라인 | 설명 |
|------|------|------|
| `fcm_service.dart` | 183-214 | `_onNotificationTapped`, `_navigateToNotificationScreen` |
| `fcm_service.dart` | 105-118 | `getInitialMessage` 처리 |
| `fcm_service.dart` | 298-307 | `_handleMessageOpenedApp` |
| `notification_screen.dart` | 54-67 | `initState` - 초기화 로직 |
| `notification_screen.dart` | 89-102 | `_onTabChanged` - 탭 변경 리스너 |
| `notification_screen.dart` | 165-197 | `_loadAlerts` - 알림 목록 로딩 |
| `main_screen.dart` | 59-96 | `initState` - 초기 탭 설정 |
