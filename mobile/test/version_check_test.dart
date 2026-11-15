import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/config/app_version.dart';
import 'package:mobile/models/version_check_models.dart';

/// 버전 비교 및 업데이트 유형 판정 테스트
///
/// Remote Config 값이 VersionCheckResponse로 변환된 이후의 판정 로직을 검증합니다.
void main() {
  group('AppVersion.compare', () {
    test('동일 버전은 0', () {
      expect(AppVersion.compare('2.1.4', '2.1.4'), 0);
    });

    test('자릿수가 달라도 숫자 기준으로 비교 (문자열 비교 아님)', () {
      expect(AppVersion.compare('2.1.10', '2.1.9'), 1);
      expect(AppVersion.compare('2.9.0', '2.10.0'), -1);
    });

    test('누락된 자리는 0으로 간주', () {
      expect(AppVersion.compare('2.1', '2.1.0'), 0);
      expect(AppVersion.compare('3', '2.9.9'), 1);
    });

    test('숫자가 아닌 자리는 0으로 간주 (예외 없음)', () {
      expect(AppVersion.compare('2.x.0', '2.0.0'), 0);
    });
  });

  group('VersionCheckResponse.updateType', () {
    VersionCheckResponse policy({
      required String minVersion,
      required bool forceUpdate,
    }) {
      return VersionCheckResponse(
        latestVersion: '99.0.0',
        minVersion: minVersion,
        forceUpdate: forceUpdate,
        storeUrl: 'https://example.com',
      );
    }

    test('Remote Config 기본값(0.0.0, false)이면 업데이트 안내 없음', () {
      expect(policy(minVersion: '0.0.0', forceUpdate: false).updateType, UpdateType.none);
    });

    test('forceUpdate=false면 현재 버전이 최소 버전보다 낮아도 안내 없음', () {
      expect(policy(minVersion: '99.0.0', forceUpdate: false).updateType, UpdateType.none);
    });

    test('forceUpdate=true이고 현재 버전 < 최소 버전이면 강제 업데이트', () {
      expect(policy(minVersion: '99.0.0', forceUpdate: true).updateType, UpdateType.force);
    });

    test('forceUpdate=true여도 현재 버전 >= 최소 버전이면 안내 없음', () {
      expect(
        policy(minVersion: AppVersion.current, forceUpdate: true).updateType,
        UpdateType.none,
      );
    });
  });
}
