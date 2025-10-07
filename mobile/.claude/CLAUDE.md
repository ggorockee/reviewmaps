# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ReviewMaps는 Flutter 기반의 모바일 앱으로, 네이버 지도를 활용한 리뷰 정보 제공 서비스입니다. iOS와 Android를 모두 지원하며, Firebase 통합, AdMob 광고, 위치 기반 서비스를 포함합니다.

## Development Commands

### 의존성 관리
```bash
flutter pub get                    # 패키지 설치
flutter pub upgrade               # 패키지 업데이트
```

### 빌드 및 실행
```bash
flutter run                       # 디버그 모드 실행
flutter run --release            # 릴리즈 모드 실행

# iOS 빌드
flutter build ios --release      # iOS 릴리즈 빌드
flutter build ipa               # App Store 배포용 IPA 생성

# Android 빌드
flutter build apk --release     # Android APK 생성
flutter build appbundle         # Google Play 배포용 AAB 생성
```

### 코드 품질
```bash
flutter analyze                  # 정적 분석 실행
dart fix --apply                # 자동 수정 적용
flutter test                    # 테스트 실행
```

### 버전 관리
- pubspec.yaml의 version 필드 수정 (현재: iOS 1.3.2+2, Android 주석처리 1.3.1+44)
- iOS와 Android 버전을 별도로 관리 중 (pubspec.yaml:21-24 참조)

## Architecture

### 엔트리 포인트 (lib/main.dart)
앱의 진입점으로 다음 초기화를 순차적으로 수행:
1. Firebase Core 초기화
2. AdMob 초기화
3. 광고 서비스 초기화 (AdService, InterstitialAdManager)
4. .env 환경변수 로드
5. 네이버 지도 SDK 초기화
6. Firebase 서비스 초기화 (Analytics, Crashlytics, Performance)
7. Remote Config 초기화
8. ScreenUtil 설정 (디자인 기준: 375x812)

### 상태 관리 (Riverpod)
- **Provider 위치**: `lib/providers/`
- **주요 Provider**:
  - `locationProvider`: 위치 권한 및 GPS 좌표 관리 (LocationNotifier)
  - `categoryProvider`: 카테고리 선택 상태 관리

### 핵심 서비스 (lib/services/)
- **FirebaseService**: Firebase 통합 싱글톤 (Analytics, Crashlytics, Performance, Remote Config)
- **AdService**: AdMob 배너/네이티브 광고 관리
- **InterstitialAdManager**: 전면 광고 타이밍 제어
- **RemoteConfigService**: Firebase Remote Config 설정 관리
- **CampaignService**: 캠페인 데이터 관리

### 화면 구조
- **MainScreen**: 하단 탭 네비게이션 (IndexedStack으로 상태 보존)
  - 홈 탭: HomeScreen
  - 지도 탭: MapScreen (탭 전환 시 lazy loading)
- **SplashScreen**: 앱 초기 로딩 화면
- **SearchScreen/SearchResultsScreen**: 검색 기능
- **MapSearchScreen**: 지도 기반 검색
- **CampaignListScreen**: 캠페인 목록

### 환경 설정 (lib/config/config.dart)
.env 파일에서 환경변수를 로드하여 관리:
- API 엔드포인트: `REVIEWMAPS_BASE_URL`, `REVIEWMAPS_X_API_KEY`
- 네이버 지도 API 키: 17개의 검색 API 키 로테이션 지원
- AdMob ID: Android/iOS 플랫폼별 광고 단위 ID
- 디버그 모드 플래그: `DEBUG_MODE`

**중요**: .env 파일은 절대 git에 커밋하지 말 것 (.gitignore 확인 필수)

## Key Technical Decisions

### 위치 권한 처리
- MainScreen initState에서 `locationProvider` 초기화
- MapScreen은 탭 전환 시 lazy loading하여 앱 시작 시 권한 팝업 방지
- Geolocator 패키지 사용 (권한 요청, GPS 좌표 획득)

### 광고 전략
- **안전 설정** (config.dart:78-79):
  - `INTERSTITIAL_ON_ENTRY = false`: 앱 진입 직후 전면광고 금지
  - `NATIVE_ON_EXIT = false`: 종료 시 네이티브 광고 금지
- 뒤로가기 시 리워드 광고 다이얼로그 표시 (ExitRewardDialog)

### 네이버 API 키 로테이션
- 17개의 검색 API 키를 순환 사용하여 API 쿼터 제한 우회
- NaverKeyRotator 서비스로 관리 (lib/utils/naver_key_rotator.dart)

### Firebase 통합
- **초기화 실패 허용**: Firebase 초기화가 실패해도 앱 실행 계속
- **Crashlytics**: Flutter/Platform 에러 자동 리포팅
- **Remote Config**: 기능 플래그, 점검 모드, 최소 버전 체크 지원
- **Performance**: HTTP 요청 및 커스텀 트레이스 모니터링

### 반응형 UI
- ScreenUtil 사용 (디자인 기준: 375x812)
- .w/.h/.sp 단위로 다양한 해상도 대응
- 태블릿 감지: `MediaQuery.of(context).size.shortestSide >= 600`
- ClampTextScale로 최대 폰트 배율 제한 (휴대폰: 1.30, 태블릿: 1.10)

## Testing Strategy

- 테스트 파일 위치: `test/` 디렉토리
- 단위 테스트: `flutter test`
- 통합 테스트는 현재 구현되지 않음

## Platform-Specific Notes

### iOS
- 버전: 1.3.2+2 (pubspec.yaml:21)
- App ID: 6751343880
- Bundle ID: com.reviewmaps.mobile
- CocoaPods 의존성 관리 (ios/Podfile)
- 앱 업데이트 체크: iTunes API 활용 (MainScreen._checkAppStoreUpdate)

### Android
- 버전: 1.3.1+44 (주석처리, pubspec.yaml:24)
- minSdkVersion: 21 (pubspec.yaml:129)
- AAB 빌드: `flutter build appbundle`

## Firebase Configuration

모든 Firebase 서비스는 FirebaseService 싱글톤을 통해 접근:
- `FirebaseService.instance.logScreenView(screenName)`: 화면 조회 추적
- `FirebaseService.instance.logSearch(searchTerm)`: 검색 이벤트
- `FirebaseService.instance.recordError(exception, stackTrace)`: 에러 리포팅
- `FirebaseService.instance.getBool('feature_name')`: Remote Config 값 조회

## Assets

pubspec.yaml의 assets 섹션 참조:
- 아이콘: `asset/icons/`
- 로고: `asset/image/logo/`, `asset/image/logo/application/`
- 배너: `asset/image/banner/`
- 환경변수: `.env`

## Important Files

- `.env`: 환경변수 (절대 커밋 금지)
- `lib/config/config.dart`: 앱 전역 설정
- `lib/main.dart`: 앱 엔트리 포인트
- `lib/screens/main_screen.dart`: 하단 탭 네비게이션 컨테이너
- `lib/services/firebase_service.dart`: Firebase 통합 관리
- `lib/providers/location_provider.dart`: 위치 상태 관리
- `pubspec.yaml`: 의존성 및 버전 관리
