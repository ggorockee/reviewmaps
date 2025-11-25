import '../config/app_version.dart';

/// 버전 체크 API 응답 모델
///
/// 서버에서 받은 버전 정책 정보를 담는 모델입니다.
/// 클라이언트에서 논리 버전과 비교하여 업데이트 필요 여부를 판단합니다.
class VersionCheckResponse {
  /// 서버에서 정의한 최신 버전
  final String latestVersion;

  /// 서버에서 정의한 최소 지원 버전
  final String minVersion;

  /// 강제 업데이트 여부 (서버 정책)
  final bool forceUpdate;

  /// 앱 스토어 다운로드 URL
  final String storeUrl;

  /// 업데이트 안내 제목 (서버에서 제공, 없으면 기본값 사용)
  final String? messageTitle;

  /// 업데이트 안내 본문 (서버에서 제공, 없으면 기본값 사용)
  final String? messageBody;

  VersionCheckResponse({
    required this.latestVersion,
    required this.minVersion,
    required this.forceUpdate,
    required this.storeUrl,
    this.messageTitle,
    this.messageBody,
  });

  factory VersionCheckResponse.fromJson(Map<String, dynamic> json) {
    return VersionCheckResponse(
      latestVersion: json['latest_version'] as String,
      minVersion: json['min_version'] as String,
      forceUpdate: json['force_update'] as bool,
      storeUrl: json['store_url'] as String,
      messageTitle: json['message_title'] as String?,
      messageBody: json['message_body'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'latest_version': latestVersion,
      'min_version': minVersion,
      'force_update': forceUpdate,
      'store_url': storeUrl,
      'message_title': messageTitle,
      'message_body': messageBody,
    };
  }

  /// 업데이트 필요 여부 (클라이언트에서 계산)
  ///
  /// 현재 앱 버전이 최신 버전보다 낮으면 업데이트 필요
  bool get needsUpdate => AppVersion.currentIsLowerThan(latestVersion);

  /// 강제 업데이트 필요 여부 (클라이언트에서 계산)
  ///
  /// 현재 앱 버전이 최소 지원 버전보다 낮으면 강제 업데이트 필요
  bool get requiresForceUpdate => AppVersion.currentIsLowerThan(minVersion);

  /// 업데이트 유형 결정
  UpdateType get updateType {
    if (requiresForceUpdate) {
      return UpdateType.force;
    } else if (needsUpdate) {
      return UpdateType.recommended;
    } else {
      return UpdateType.none;
    }
  }

  @override
  String toString() {
    return 'VersionCheckResponse('
        'latestVersion: $latestVersion, '
        'minVersion: $minVersion, '
        'forceUpdate: $forceUpdate, '
        'storeUrl: $storeUrl, '
        'messageTitle: $messageTitle, '
        'messageBody: $messageBody, '
        'needsUpdate: $needsUpdate, '
        'requiresForceUpdate: $requiresForceUpdate)';
  }
}

/// 업데이트 유형
enum UpdateType {
  /// 업데이트 불필요 (최신 버전 사용 중)
  none,

  /// 권장 업데이트 (사용자 선택 가능)
  recommended,

  /// 강제 업데이트 (필수)
  force,
}
