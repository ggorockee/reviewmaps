# 리뷰맵 2.0.0 업데이트 노트

## App Store Connect 제출용 (한국어)

### 이번 업데이트의 새로운 기능

**주요 업데이트**

- 회원 가입 및 로그인 기능 추가
  - 이메일 회원가입 및 로그인 지원
  - Google, Apple, Kakao 소셜 로그인 지원
  - 비밀번호 찾기 기능

- 개인화된 사용자 경험
  - 사용자 프로필 관리
  - 로그인 후 맞춤형 서비스 제공
  - 사용자별 캠페인 관리

- 안정성 및 성능 개선
  - 앱 안정성 향상
  - 사용자 경험 개선
  - 버그 수정 및 최적화

---

## App Store Connect 제출용 (영어)

### What's New in This Version

**Major Updates**

- Sign Up and Login Features
  - Email registration and login support
  - Social login with Google, Apple, and Kakao
  - Password recovery feature

- Personalized User Experience
  - User profile management
  - Customized services after login
  - User-specific campaign management

- Stability and Performance Improvements
  - Enhanced app stability
  - Improved user experience
  - Bug fixes and optimizations

---

## 개발 문서용 상세 변경사항

### 버전 정보
- 버전: 2.0.0+1
- 이전 버전: 1.4.0+62
- 빌드 번호 초기화: 2.0.0 메이저 업데이트로 인해 빌드 번호를 1로 리셋

### 주요 기능 추가

#### 1. 인증 시스템
- 이메일 기반 회원가입/로그인
- 소셜 로그인 통합
  - Google Sign-In (google_sign_in: ^6.2.2)
  - Apple Sign-In (sign_in_with_apple: ^6.1.4)
  - Kakao Login (kakao_flutter_sdk_user: ^1.9.6)
- 비밀번호 찾기 및 재설정
- JWT 기반 토큰 인증
- Flutter Secure Storage를 통한 안전한 토큰 저장

#### 2. Firebase 서비스 통합
- Firebase Core (firebase_core: ^3.8.0)
- Firebase Analytics (firebase_analytics: ^11.3.4)
  - 사용자 행동 분석
  - 화면 조회 추적
  - 검색 이벤트 추적
- Firebase Crashlytics (firebase_crashlytics: ^4.1.4)
  - 충돌 보고서 수집
  - 비치명적 오류 추적
- Firebase Performance (firebase_performance: ^0.10.1+1)
  - 앱 성능 모니터링
- Firebase Remote Config (firebase_remote_config: ^5.1.4)
  - 원격 기능 플래그
  - A/B 테스트 지원
- Firebase Cloud Messaging (firebase_messaging: ^15.1.4)
  - 푸시 알림
  - 백그라운드 알림 처리

#### 3. 광고 시스템
- Google Mobile Ads (google_mobile_ads: ^6.0.0)
  - 배너 광고
  - 네이티브 광고
  - 리워드 광고
  - 앱 오픈 광고
- App Tracking Transparency (app_tracking_transparency: ^2.0.6+1)
  - iOS 14.5+ ATT 프레임워크 지원
  - 사용자 추적 권한 요청

#### 4. 사용자 인터페이스 개선
- 로그인 화면 (LoginScreen)
- 회원가입 화면 (SignUpScreen)
- 비밀번호 재설정 화면 (PasswordResetScreen)
- 프로필 화면 업데이트
- 로딩 상태 UI 개선
- 친화적인 에러 메시지

#### 5. 상태 관리
- Riverpod 3.0 도입 (flutter_riverpod: ^3.0.0-dev.17)
- AuthProvider: 인증 상태 관리
- LocationProvider: 위치 정보 관리
- 전역 상태 관리 개선

#### 6. 보안 강화
- Flutter Secure Storage (flutter_secure_storage: ^9.2.4)
  - 액세스 토큰 안전 저장
  - 리프레시 토큰 암호화 저장
- HTTPS 통신
- 토큰 자동 갱신 로직

### 기술적 개선사항

#### 의존성 업데이트
- Flutter SDK: ^3.8.1
- 주요 패키지 최신 버전 적용
- iOS 최소 지원 버전: iOS 12.0

#### 아키텍처 개선
- 서비스 레이어 분리
  - AuthService: 인증 관련 로직
  - FirebaseService: Firebase 통합 관리
  - AdService: 광고 관리
  - FCMService: 푸시 알림 관리
- Provider 패턴 적용
- 코드 재사용성 향상

#### 성능 최적화
- 앱 초기화 프로세스 개선
- 메모리 사용 최적화
- 네트워크 요청 최적화
- 이미지 로딩 개선

### 권한 추가
- NSUserTrackingUsageDescription: 광고 추적
- NSLocationWhenInUseUsageDescription: 위치 기반 서비스
- NSCameraUsageDescription: 리뷰 사진 촬영
- NSPhotoLibraryUsageDescription: 리뷰 사진 선택

### 개인정보 처리방침
- 개인정보 처리방침 URL: https://review-maps.com/privacy
- App Store 개인정보 보호 레이블 업데이트
- PrivacyInfo.xcprivacy 파일 추가

### 알려진 이슈
- 없음

### 다음 버전 계획
- 리뷰 작성 기능 고도화
- 즐겨찾기 기능
- 사용자 알림 센터
- 앱 내 설정 화면

---

## 마이그레이션 가이드

### 1.4.0 → 2.0.0

#### 기존 사용자 데이터
- 로컬 저장소 데이터는 유지됩니다
- 기존 사용자는 로그인하여 계정과 연동 필요
- 검색 기록 및 설정은 자동 마이그레이션

#### 개발자용
- AuthService를 통한 인증 필수
- Firebase 초기화 필수
- 환경 변수 설정 필요 (.env 파일)
- iOS Info.plist 권한 설정 확인

---

## 테스트 완료 항목

- [x] 이메일 로그인/회원가입
- [x] Google 로그인
- [x] Apple 로그인 (iOS)
- [x] Kakao 로그인
- [x] 비밀번호 찾기
- [x] 토큰 자동 갱신
- [x] Firebase Analytics 연동
- [x] Firebase Crashlytics 연동
- [x] 푸시 알림 수신
- [x] 광고 표시
- [x] ATT 권한 요청
- [x] 위치 권한 요청
- [x] 앱 초기화 프로세스
- [x] 로그아웃
- [x] 계정 삭제



