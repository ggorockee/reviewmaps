# 리뷰맵 AdMob 점검 및 앱 버전 정책 정리

작성일: 2026-11-15

## 요약

AdMob 계정(pub-8516861197467665)과 리뷰맵 앱 설정은 정상입니다. GDPR 동의 메시지는 새로 게시했습니다. 남은 조치는 구버전(2.1.x) 강제 업데이트이며, Firebase Remote Config가 아니라 Django 어드민에서만 할 수 있습니다.

| 항목 | 결과 | 조치 |
|------|------|------|
| 앱 상태·정책 센터 | 정상, 위반 없음 | 없음 |
| app-ads.txt | 100% 승인 | 없음 |
| 코드의 앱·광고 단위 ID | 콘솔과 모두 일치 | 없음 |
| GDPR(UMP) 메시지 | 미생성 상태였음 → 2026-11-15 게시 완료 | 실기기 동작 확인 |
| iOS 배너 노출률 36% | 구버전(2.1.1, 2.1.2)이 원인으로 판단 | 2.2.0 보급 후 재확인 |
| 세금 정보 | 미입력(권장) | AdMob 콘솔에서 입력 |
| 구버전 강제 업데이트 | 미적용 | Django 어드민 `app_versions` 수정 |

## AdMob 점검 결과

계정·앱·정책·광고 단위 설정에는 문제가 없습니다. 점검한 계정은 woohalabs 계정(pub-8516861197467665)입니다.

| 항목 | 결과 |
|------|------|
| 앱 상태 | 리뷰맵 Android(`com.reviewmaps.mobile`), iOS(`6751343880`) 모두 "준비됨", 광고 게재 사용 설정됨 |
| 정책 센터 | 정책 위반 없음, 비승인 앱 없음 |
| app-ads.txt | `https://review-maps.com/app-ads.txt` 크롤링 정상, 쿼리 100% 승인 |
| 앱 ID·광고 단위 ID | `ad_service.dart`, `app_open_ad_service.dart`, `Info.plist`, `AndroidManifest.xml` 값이 콘솔과 일치 |
| iOS 설정 | `NSUserTrackingUsageDescription` 있음, Google SKAdNetwork ID(`cstr6suwn9`) 있음 |
| Android 설정 | `AD_ID` 권한 선언됨 |
| 지급 | 본인 확인·주소·은행 정보 완료, 세금 정보는 미입력(권장) |

최근 7일(2026-11-08~14) AdMob 네트워크 예상 수입은 US$0.72입니다(Android US$0.53, iOS US$0.19). 요청 422건, 노출 238건, 평균 eCPM은 US$3.02입니다.

전면광고와 Android `중단_배너` 요청은 이미 코드에서 제거된 광고 단위입니다. 업데이트하지 않은 구버전 앱에서 계속 들어오는 요청입니다.

## GDPR(UMP) 동의 메시지

2026-11-15에 AdMob "개인 정보 보호 및 메시지 > 유럽 규정" 메시지를 게시했습니다. 그 전에는 메시지가 없어서, 앱에 넣은 UMP 코드(`6b3e381`, `consent_service.dart`)가 띄울 양식이 없는 상태였습니다.

| 설정 | 값 |
|------|-----|
| 대상 앱 | 리뷰맵 Android, 리뷰맵 iOS |
| 개인정보처리방침 URL | `https://review-maps.com/privacy` |
| 기본 언어 | 영어(en) |
| 첫 화면 버튼 | 동의, 동의하지 않음(전 국가), 옵션 관리 |
| 닫기(동의하지 않음) | 사용 안 함 |

- **영향 범위**: EEA·영국·스위스 사용자에게만 적용됩니다. 한국 사용자의 광고 게재는 그대로입니다.
- **반영 시점**: 게시 후 앱에 뜨기까지 최대 1시간쯤 걸립니다.
- **테스트 방법**: `--dart-define=UMP_DEBUG_EEA=true`로 디버그 실행하면 EEA 사용자처럼 동작합니다. 실기기에서는 로그에 찍힌 해시 ID를 `UMP_TEST_DEVICE_ID`에 넣습니다.
- IDFA 설명(ATT 안내) 메시지는 만들지 않았습니다. 앱이 스플래시 화면에서 ATT 팝업을 직접 요청합니다.

## iOS 배너 노출률 분석

iOS 상단배너 노출률 36%(Android 98%)는 구버전 코드 때문으로 판단합니다. 그래서 현재 코드는 수정하지 않았습니다.

| 버전 | 플랫폼 | 상단배너 요청 | 노출률 |
|------|--------|---------------|--------|
| 2.2.0 | iOS | 0 | — |
| 2.1.2 | iOS | 32 | 34% |
| 2.1.1 | iOS | 34 | 38% |
| 2.1.1 ~ 2.1.5 | Android | 145 | 96~100% |

출처: AdMob 네트워크 보고서, 최근 7일, 앱 버전·광고 단위별.

- iOS 요청은 모두 2.1.1과 2.1.2에서 왔습니다. 이 버전의 배너는 고정 크기 `SizedBox(320x50)`를 `SafeArea`로 감싼 형태입니다.
- 배너 코드는 그 뒤 두 번 다시 작성됐습니다. `09a0854`(2.1.4)에서 고정형 적응형 배너로, `dd6d900`(2.1.5)에서 인라인 적응형 배너로 바뀌었습니다.
- 같은 옛 코드가 Android 2.1.1에서는 98%였습니다. 그래서 iOS에서만 생기는 레이아웃이나 노출 집계 문제로 추정합니다. 기기에서 재현해 보지는 않았습니다.
- 현재 코드에서 작은 개선점이 하나 있습니다. `banner.dart`의 `onAdLoaded`에서 `getPlatformAdSize()`가 `null`이면 배너가 표시되지 않고 50dp 빈 자리만 남습니다.

## 앱 버전 정책 (강제 업데이트)

앱 버전에 따라 버전 정책을 읽어 오는 곳이 다릅니다. 2.1.x 사용자는 Django 어드민으로만, 2.2.0 이상 사용자는 Firebase Remote Config로만 제어할 수 있습니다.

| 앱 버전 | 정책 위치 | 강제 업데이트 설정 |
|---------|-----------|-------------------|
| 2.2.0 이상 | Firebase Remote Config | `{platform}_force_update` = true로 두고 `{platform}_min_version`을 올림 |
| 2.1.x 이하 | Django 어드민 `app_versions` (서버 `/v1/app-config/version`) | `minimum_version`만 올리면 됨 |

### 판정 로직

- **앱**(`version_check_models.dart`): `force_update`가 true이고 **현재 버전 < `min_version`**일 때만 강제 업데이트 팝업을 띄웁니다. 2.1.1 앱도 같은 로직입니다.
- **서버**(`app_config.go`의 `CheckVersion`): 현재 버전이 `minimum_version`보다 낮으면 `force_update`를 true로 바꿔서 응답합니다. 그래서 어드민에서는 `minimum_version`만 올리면 됩니다.
- `latest_version`은 지금 판정에 쓰이지 않습니다. 권장 업데이트 팝업을 띄우는 경로가 코드에 없습니다.

### 현재 Remote Config 값 (2026-11-15 게시)

| 키 | 값 |
|----|-----|
| `android_force_update` / `ios_force_update` | true |
| `android_latest_version` / `ios_latest_version` | 2.2.0 |
| `android_min_version` / `ios_min_version` | 0.0.0 |

`min_version`이 0.0.0이라 **지금은 아무에게도 팝업이 뜨지 않습니다.** 다음 버전(예: 2.2.1)을 낼 때 `min_version`을 올리면 2.2.0 사용자가 강제 업데이트 대상이 됩니다.

### 주의사항

- **스토어 배포를 먼저 합니다.** 올린 버전이 해당 스토어에 실제로 배포된 뒤에 적용해야 합니다. 순서가 바뀌면 사용자가 업데이트를 받을 수 없어 앱을 쓰지 못합니다.
- **플랫폼마다 활성 행은 하나만** 둡니다. 서버는 `is_active=true`인 행 중 `First()`로 하나를 읽습니다.
- `store_url`이 올바른지 확인합니다.
- Remote Config에서 "인앱 기본값 사용"을 켜면 Firebase가 값을 보내지 않습니다. 이때는 앱 기본값(`force_update` false, `min_version` 0.0.0)이 쓰입니다.
- Remote Config 값은 기기마다 최대 15분 동안 캐시됩니다(`minimumFetchInterval`).

## 후속 작업

- [ ] 2.2.0 App Store·Play Store 배포 여부 확인
- [ ] 배포 후 Django 어드민 `app_versions`(ios, android)의 `minimum_version`을 2.2.0으로 상향
- [ ] UMP 동의 양식 실기기 확인 (`UMP_DEBUG_EEA=true`)
- [ ] AdMob 세금 정보 입력
- [ ] 1~2주 뒤 iOS 2.2.0 상단배너 노출률 재확인 (AdMob 보고서, 앱 버전·광고 단위별)
- [ ] (선택) `banner.dart`의 `getPlatformAdSize()` null 대비 처리
- [ ] (선택) 권장 업데이트 팝업을 쓸 경우 `updateType` 로직 수정
- [ ] 2.1.x 사용자가 없어지면 서버 `app_versions`와 `/v1/app-config/version` 정리
