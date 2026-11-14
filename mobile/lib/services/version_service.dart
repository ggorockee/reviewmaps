import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_version.dart';
import '../models/version_check_models.dart';
import 'remote_config_service.dart';

/// 버전 체크 서비스
///
/// Firebase Remote Config의 버전 정책을 읽어 앱 업데이트 필요 여부를 확인합니다.
/// - 버전 정책은 Firebase 콘솔 > Remote Config에서 관리 ({platform}_min_version 등)
/// - 논리 버전(Logical Version) 기반 비교
/// - 클라이언트에서 버전 비교 로직 수행
/// - 권장 업데이트 시 "나중에" 선택 후 일정 기간 재표시 방지
class VersionService {
  /// SharedPreferences 키: 권장 업데이트 스킵 시간
  static const String _skipUntilKey = 'update_skip_until';

  /// 권장 업데이트 스킵 기간 (일)
  static const int skipDays = 3;

  /// Remote Config에서 버전 정책 조회
  ///
  /// 앱 시작 시(main.dart) RemoteConfigService가 이미 fetch/activate를 마친 값을 사용합니다.
  ///
  /// Returns:
  /// - VersionCheckResponse: 버전 정책 정보
  ///
  /// Throws:
  /// - Exception: Remote Config 미초기화 등 조회 실패 시
  Future<VersionCheckResponse> checkVersion() async {
    try {
      return RemoteConfigService().getVersionPolicy();
    } catch (e) {
      throw Exception('Failed to check app version: $e');
    }
  }

  /// 권장 업데이트를 표시해야 하는지 확인
  ///
  /// "나중에" 선택 후 [skipDays]일 동안은 false를 반환합니다.
  Future<bool> shouldShowRecommendedUpdate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final skipUntilMs = prefs.getInt(_skipUntilKey);

      if (skipUntilMs == null) {
        return true; // 스킵 기록 없음 -> 표시
      }

      final skipUntil = DateTime.fromMillisecondsSinceEpoch(skipUntilMs);
      final now = DateTime.now();

      if (now.isAfter(skipUntil)) {
        // 스킵 기간 만료 -> 기록 삭제 후 표시
        await prefs.remove(_skipUntilKey);
        return true;
      }

      return false; // 스킵 기간 내 -> 표시하지 않음
    } catch (e) {
      debugPrint('Error checking update skip status: $e');
      return true; // 오류 시 기본적으로 표시
    }
  }

  /// 권장 업데이트 "나중에" 선택 시 호출
  ///
  /// [skipDays]일 동안 권장 업데이트 다이얼로그를 표시하지 않습니다.
  Future<void> skipRecommendedUpdate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final skipUntil = DateTime.now().add(Duration(days: skipDays));
      await prefs.setInt(_skipUntilKey, skipUntil.millisecondsSinceEpoch);
      debugPrint('Update skipped until: $skipUntil');
    } catch (e) {
      debugPrint('Error saving update skip: $e');
    }
  }

  /// 스킵 기록 초기화 (테스트/디버그용)
  Future<void> clearSkipRecord() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_skipUntilKey);
    } catch (e) {
      debugPrint('Error clearing skip record: $e');
    }
  }

  /// 버전 체크 및 업데이트 안내 (콜백 방식)
  ///
  /// Parameters:
  /// - onForceUpdate: 강제 업데이트 필요 시 호출
  /// - onRecommendedUpdate: 권장 업데이트 필요 시 호출
  /// - onLatest: 최신 버전일 때 호출
  /// - onError: 에러 발생 시 호출
  Future<void> checkAndNotify({
    required Function(VersionCheckResponse response) onForceUpdate,
    required Function(VersionCheckResponse response) onRecommendedUpdate,
    required Function() onLatest,
    required Function(String error) onError,
  }) async {
    try {
      final result = await checkVersion();

      // 디버그 로그 출력
      debugPrint('═══════════════════════════════════════');
      debugPrint('📱 [Version Check] 버전 체크 결과');
      debugPrint('═══════════════════════════════════════');
      debugPrint('📌 현재 앱 버전: ${AppVersion.current}');
      debugPrint('📌 최소 지원 버전 (minVersion): ${result.minVersion}');
      debugPrint('📌 최신 버전 (latestVersion): ${result.latestVersion}');
      debugPrint('📌 forceUpdate 플래그: ${result.forceUpdate}');
      debugPrint('───────────────────────────────────────');
      debugPrint('🔍 현재버전 < minVersion: ${result.requiresForceUpdate}');
      debugPrint('🔍 현재버전 < latestVersion: ${result.needsUpdate}');
      debugPrint('🔍 최종 updateType: ${result.updateType}');
      debugPrint('═══════════════════════════════════════');

      switch (result.updateType) {
        case UpdateType.force:
          debugPrint('🚨 [Version Check] 강제 업데이트 팝업 표시');
          onForceUpdate(result);
          break;
        case UpdateType.recommended:
          // 권장 업데이트는 스킵 기간 확인
          if (await shouldShowRecommendedUpdate()) {
            debugPrint('💡 [Version Check] 권장 업데이트 팝업 표시');
            onRecommendedUpdate(result);
          } else {
            debugPrint('⏭️ [Version Check] 권장 업데이트 스킵 기간 내 - 팝업 X');
            onLatest(); // 스킵 기간 내면 최신 버전처럼 처리
          }
          break;
        case UpdateType.none:
          debugPrint('✅ [Version Check] 업데이트 불필요 - 팝업 X');
          onLatest();
          break;
      }
    } catch (e) {
      debugPrint('❌ [Version Check] 에러 발생: $e');
      onError(e.toString());
    }
  }

  /// 현재 앱 버전 반환
  String get currentVersion => AppVersion.current;
}
