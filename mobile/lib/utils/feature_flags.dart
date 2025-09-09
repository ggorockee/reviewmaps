// lib/utils/feature_flags.dart
import '../services/firebase_service.dart';

/// FeatureFlags
/// ------------------------------------------------------------
/// Firebase Remote Config를 활용한 기능 플래그 관리
/// - A/B 테스트
/// - 점진적 기능 출시
/// - 긴급 기능 비활성화
class FeatureFlags {
  static final FirebaseService _firebase = FirebaseService.instance;

  /// 검색 제안 기능 활성화 여부
  static bool get isSearchSuggestionsEnabled {
    return _firebase.isFeatureEnabled('search_suggestions');
  }

  /// 다크 모드 기능 활성화 여부
  static bool get isDarkModeEnabled {
    return _firebase.isFeatureEnabled('dark_mode');
  }

  /// 새로운 UI 디자인 활성화 여부
  static bool get isNewUIEnabled {
    return _firebase.isFeatureEnabled('new_ui_design');
  }

  /// 고급 필터 기능 활성화 여부
  static bool get isAdvancedFiltersEnabled {
    return _firebase.isFeatureEnabled('advanced_filters');
  }

  /// 소셜 로그인 기능 활성화 여부
  static bool get isSocialLoginEnabled {
    return _firebase.isFeatureEnabled('social_login');
  }

  /// 즐겨찾기 기능 활성화 여부
  static bool get isFavoritesEnabled {
    return _firebase.isFeatureEnabled('favorites');
  }

  /// 리뷰 작성 기능 활성화 여부
  static bool get isReviewWritingEnabled {
    return _firebase.isFeatureEnabled('review_writing');
  }

  /// 지도 클러스터링 기능 활성화 여부
  static bool get isMapClusteringEnabled {
    return _firebase.isFeatureEnabled('map_clustering');
  }

  /// 최대 검색 결과 개수
  static int get maxSearchResults {
    return _firebase.getInt('max_search_results');
  }

  /// 배너 텍스트 (공지사항 등)
  static String get bannerText {
    return _firebase.getString('banner_text');
  }

  /// 배너 색상
  static String get bannerColor {
    return _firebase.getString('banner_color');
  }

  /// 배너 표시 여부 (텍스트가 있으면 표시)
  static bool get shouldShowBanner {
    return bannerText.isNotEmpty;
  }

  /// 점검 모드 여부
  static bool get isMaintenanceMode {
    return _firebase.isMaintenanceMode();
  }

  /// 점검 메시지
  static String get maintenanceMessage {
    return _firebase.getMaintenanceMessage();
  }

  /// 앱 버전 지원 여부 확인
  static bool isAppVersionSupported(String currentVersion) {
    return _firebase.isAppVersionSupported(currentVersion);
  }

  /// Remote Config 새로고침
  static Future<void> refresh() async {
    await _firebase.refreshConfig();
  }

  /// 모든 기능 플래그 상태를 Map으로 반환 (디버깅용)
  static Map<String, dynamic> getAllFlags() {
    return {
      'search_suggestions': isSearchSuggestionsEnabled,
      'dark_mode': isDarkModeEnabled,
      'new_ui_design': isNewUIEnabled,
      'advanced_filters': isAdvancedFiltersEnabled,
      'social_login': isSocialLoginEnabled,
      'favorites': isFavoritesEnabled,
      'review_writing': isReviewWritingEnabled,
      'map_clustering': isMapClusteringEnabled,
      'max_search_results': maxSearchResults,
      'banner_text': bannerText,
      'banner_color': bannerColor,
      'maintenance_mode': isMaintenanceMode,
      'maintenance_message': maintenanceMessage,
    };
  }
}
