/// 버전 체크 API 응답 모델
class VersionCheckResponse {
  /// 업데이트 필요 여부 (false=최신, true=업데이트 필요)
  final bool needsUpdate;

  /// 강제 업데이트 여부 (true=필수 업데이트)
  final bool forceUpdate;

  /// 서버의 최신 버전
  final String latestVersion;

  /// 업데이트 안내 메시지
  final String? message;

  /// 앱 스토어 다운로드 URL
  final String storeUrl;

  VersionCheckResponse({
    required this.needsUpdate,
    required this.forceUpdate,
    required this.latestVersion,
    this.message,
    required this.storeUrl,
  });

  factory VersionCheckResponse.fromJson(Map<String, dynamic> json) {
    return VersionCheckResponse(
      needsUpdate: json['needs_update'] as bool,
      forceUpdate: json['force_update'] as bool,
      latestVersion: json['latest_version'] as String,
      message: json['message'] as String?,
      storeUrl: json['store_url'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'needs_update': needsUpdate,
      'force_update': forceUpdate,
      'latest_version': latestVersion,
      'message': message,
      'store_url': storeUrl,
    };
  }

  @override
  String toString() {
    return 'VersionCheckResponse(needsUpdate: $needsUpdate, forceUpdate: $forceUpdate, '
        'latestVersion: $latestVersion, message: $message, storeUrl: $storeUrl)';
  }
}
