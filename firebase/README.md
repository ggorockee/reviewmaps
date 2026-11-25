# 리뷰맵 Firebase Remote Config

`remoteconfig.template.json`이 원본입니다. 콘솔에서 직접 바꾸면 다음 배포 때 덮어써지므로 파일을 고친 뒤 이 폴더에서 배포합니다: `firebase deploy --only remoteconfig --project reviewmap-c03f1` (계정 woohalabs@gmail.com)

| 그룹 | 키 | 동작 | 적용 버전 |
|---|---|---|---|
| ads | show_banner_ad, show_native_ad, show_app_open_ad | 광고 종류별 켜기/끄기 | 2.2.1 이상 |
| ads | app_open_min_interval_hours, app_open_wait_ms | 앱 오프닝 광고 간격, 시작 화면 대기 시간 | 2.2.1 이상 |
| app_update | {platform}_min_version + {platform}_force_update | 현재 버전이 낮으면 강제 업데이트 (닫을 수 없음) | 2.2.0 이상 |
| app_update | {platform}_latest_version | 현재 버전이 낮으면 선택 업데이트 (나중에 선택 시 3일 뒤 다시) | 2.2.1 이상 |
| app_update | {platform}_store_url, update_message_title, update_message_body | 링크와 문구 | 2.2.0 이상 |

배포 순서: 스토어 공개 확인 → latest 올림 → 꼭 필요할 때만 min 올림. 스토어에 없는 버전으로 min을 올리면 사용자가 앱을 쓸 수 없습니다(알림 AppForceUpdateLockout).

현재 값과 변경은 Grafana `앱·광고·스토어 현황`(uid app-ads-overview)에서 확인합니다.
