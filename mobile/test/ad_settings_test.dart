import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/services/app_open_ad_service.dart';
import 'package:mobile/services/remote_config_service.dart';

/// 앱 오프닝 광고 조건과 Remote Config 값 보정 테스트
void main() {
  group('앱 오프닝 광고 최소 간격', () {
    final now = DateTime(2026, 11, 26, 12);
    bool elapsed(DateTime? lastShown) => AppOpenAdService.intervalElapsed(
          lastShown: lastShown,
          now: now,
          minInterval: const Duration(hours: 4),
        );

    test('표시한 적이 없으면 가능', () => expect(elapsed(null), isTrue));
    test('간격 안이면 불가', () => expect(elapsed(now.subtract(const Duration(hours: 3, minutes: 59))), isFalse));
    test('간격이 정확히 지나면 가능', () => expect(elapsed(now.subtract(const Duration(hours: 4))), isTrue));
  });

  group('Remote Config 값 보정', () {
    test('간격이 없거나 1시간 미만이면 4시간', () {
      expect(RemoteConfigService.appOpenIntervalHours(null), 4);
      expect(RemoteConfigService.appOpenIntervalHours(0), 4);
      expect(RemoteConfigService.appOpenIntervalHours(6), 6);
    });

    test('대기 시간이 0~4초 밖이면 2초', () {
      expect(RemoteConfigService.appOpenWaitMs(null), 2000);
      expect(RemoteConfigService.appOpenWaitMs(-1), 2000);
      expect(RemoteConfigService.appOpenWaitMs(60000), 2000);
      expect(RemoteConfigService.appOpenWaitMs(0), 0);
    });

    test('Firebase를 쓸 수 없으면 광고는 켜진 상태', () {
      final config = RemoteConfigService();
      expect([config.showBannerAd, config.showNativeAd, config.showAppOpenAd], everyElement(isTrue));
    });
  });
}
