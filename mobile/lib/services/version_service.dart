import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import '../config/config.dart';
import '../models/version_check_models.dart';

/// 버전 체크 서비스
///
/// 백엔드 API를 호출하여 앱 업데이트 필요 여부를 확인합니다.
/// - 현재 앱 버전과 플랫폼 정보를 서버에 전송
/// - 서버는 최신 버전 정보와 업데이트 필요 여부를 반환
/// - Semantic Versioning (major.minor.patch) 기반 비교
class VersionService {
  /// 버전 체크 API 호출
  ///
  /// Returns:
  /// - VersionCheckResponse: 업데이트 필요 여부 및 최신 버전 정보
  ///
  /// Throws:
  /// - Exception: API 호출 실패 시
  Future<VersionCheckResponse> checkVersion() async {
    try {
      // 1. 현재 앱 버전 정보 가져오기
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version; // 예: "1.4.0"

      // 2. 플랫폼 확인 (iOS 또는 Android)
      final platform = Platform.isIOS ? 'ios' : 'android';

      // 3. API 엔드포인트 URL 생성
      final url = Uri.parse('${AppConfig.ReviewMapbaseUrl}/app-config/version')
          .replace(queryParameters: {
        'platform': platform,
        'current_version': currentVersion,
      });

      // 4. API 호출
      final response = await http.get(
        url,
        headers: {
          'X-API-Key': AppConfig.ReviewMapApiKey,
          'Content-Type': 'application/json',
        },
      );

      // 5. 응답 상태 코드 확인
      if (response.statusCode != 200) {
        throw Exception(
          'Version check API failed with status: ${response.statusCode}',
        );
      }

      // 6. JSON 파싱 및 모델 변환
      final Map<String, dynamic> data = jsonDecode(response.body);
      return VersionCheckResponse.fromJson(data);
    } catch (e) {
      // 에러 발생 시 예외를 다시 던져서 호출자가 처리하도록 함
      throw Exception('Failed to check app version: $e');
    }
  }

  /// 버전 체크 및 업데이트 안내 (선택적 사용)
  ///
  /// 버전 체크를 수행하고 결과를 콜백으로 전달합니다.
  ///
  /// Parameters:
  /// - onUpdateNeeded: 업데이트 필요 시 호출될 콜백 (강제 업데이트 여부 포함)
  /// - onLatest: 최신 버전일 때 호출될 콜백
  /// - onError: 에러 발생 시 호출될 콜백
  Future<void> checkAndNotify({
    required Function(VersionCheckResponse response) onUpdateNeeded,
    required Function() onLatest,
    required Function(String error) onError,
  }) async {
    try {
      final result = await checkVersion();

      if (result.needsUpdate) {
        onUpdateNeeded(result);
      } else {
        onLatest();
      }
    } catch (e) {
      onError(e.toString());
    }
  }
}
