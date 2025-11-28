/// 앱 논리 버전 (Logical Version) 관리
///
/// 스토어 버전과 별개로 앱 내부에서 사용하는 논리적 버전입니다.
/// 서버의 버전 정책과 비교하여 강제/권장 업데이트를 결정합니다.
///
/// 사용 예시:
/// - 서버 min_version보다 낮으면 강제 업데이트
/// - 서버 latest_version보다 낮으면 권장 업데이트
/// - 서버 latest_version 이상이면 업데이트 안내 없음
class AppVersion {
  AppVersion._();

  /// 현재 앱의 논리 버전
  ///
  /// 새 버전 배포 시 이 값을 업데이트합니다.
  /// Semantic Versioning (major.minor.patch) 형식을 따릅니다.
  static const String current = '2.0.2';

  /// 버전 문자열을 파싱하여 비교 가능한 형태로 변환
  ///
  /// 예: "1.4.0" -> [1, 4, 0]
  static List<int> parse(String version) {
    final parts = version.split('.');
    return parts.map((part) => int.tryParse(part) ?? 0).toList();
  }

  /// 두 버전 문자열 비교
  ///
  /// Returns:
  /// - 음수: version1 < version2
  /// - 0: version1 == version2
  /// - 양수: version1 > version2
  static int compare(String version1, String version2) {
    final v1Parts = parse(version1);
    final v2Parts = parse(version2);

    // 가장 긴 버전 기준으로 비교
    final maxLength = v1Parts.length > v2Parts.length
        ? v1Parts.length
        : v2Parts.length;

    for (int i = 0; i < maxLength; i++) {
      final v1 = i < v1Parts.length ? v1Parts[i] : 0;
      final v2 = i < v2Parts.length ? v2Parts[i] : 0;

      if (v1 < v2) return -1;
      if (v1 > v2) return 1;
    }

    return 0; // 동일한 버전
  }

  /// version1이 version2보다 낮은지 확인
  static bool isLowerThan(String version1, String version2) {
    return compare(version1, version2) < 0;
  }

  /// version1이 version2 이상인지 확인
  static bool isGreaterOrEqual(String version1, String version2) {
    return compare(version1, version2) >= 0;
  }

  /// 현재 버전이 주어진 버전보다 낮은지 확인
  static bool currentIsLowerThan(String version) {
    return isLowerThan(current, version);
  }

  /// 현재 버전이 주어진 버전 이상인지 확인
  static bool currentIsGreaterOrEqual(String version) {
    return isGreaterOrEqual(current, version);
  }
}
