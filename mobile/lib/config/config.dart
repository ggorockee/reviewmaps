import 'package:flutter_dotenv/flutter_dotenv.dart';

/// AppConfig
/// --------------------------------------------
/// 앱 전체에서 공통으로 사용되는 설정 값들을 관리.
/// - .env 파일에서 불러와 런타임 환경별(개발/스테이징/운영)로 유연하게 전환 가능.
/// - 반드시 필요한 값은 없으면 `Exception`을 던져 앱 실행 시점에 즉시 감지.
/// - 민감정보는 절대 코드에 하드코딩하지 않고 .env 파일로만 관리.
/// --------------------------------------------
class AppConfig {
  // 📌 API 기본 URL
  // - 백엔드 서버 엔드포인트 (예: https://api.review-maps.com/v1)
  // - 앱의 모든 네트워크 요청이 이 URL을 기준으로 이루어짐.
  static final String ReviewMapbaseUrl = _getEnv('REVIEWMAPS_BASE_URL');

  // 📌 API 키
  // - 서버 인증/권한 확인에 사용되는 필수 키.
  // - 운영 환경에서는 절대 노출되지 않도록 주의.
  static final String ReviewMapApiKey = _getEnv('REVIEWMAPS_X_API_KEY');

  // 📌 네이버 지도 API 관련 키
  // - Naver Map SDK 초기화 시 clientId만 사용됨.
  // - REST API 호출 시 Client Secret / App Key 등이 필요할 수 있음.
  static final String NAVER_MAP_CLIENT_ID = _getEnv('NAVER_MAP_CLIENT_ID');
  static final String NAVER_MAP_CLIENT_SECRET = _getEnv('NAVER_MAP_CLIENT_SECRET');
  static final String NAVER_APP_KEY = _getEnv('NAVER_APP_KEY');
  static final String NAVER_APP_SECRET = _getEnv('NAVER_APP_SECRET');


  static final String NAVER_APP_SEARCH_CLIENT_ID_1 = _getEnv('NAVER_APP_SEARCH_CLIENT_ID_1');
  static final String NAVER_APP_SEARCH_CLIENT_ID_2 = _getEnv('NAVER_APP_SEARCH_CLIENT_ID_2');
  static final String NAVER_APP_SEARCH_CLIENT_ID_3 = _getEnv('NAVER_APP_SEARCH_CLIENT_ID_3');
  static final String NAVER_APP_SEARCH_CLIENT_ID_4 = _getEnv('NAVER_APP_SEARCH_CLIENT_ID_4');
  static final String NAVER_APP_SEARCH_CLIENT_ID_5 = _getEnv('NAVER_APP_SEARCH_CLIENT_ID_5');
  static final String NAVER_APP_SEARCH_CLIENT_ID_6 = _getEnv('NAVER_APP_SEARCH_CLIENT_ID_6');
  static final String NAVER_APP_SEARCH_CLIENT_ID_7 = _getEnv('NAVER_APP_SEARCH_CLIENT_ID_7');
  static final String NAVER_APP_SEARCH_CLIENT_ID_8 = _getEnv('NAVER_APP_SEARCH_CLIENT_ID_8');
  static final String NAVER_APP_SEARCH_CLIENT_ID_9 = _getEnv('NAVER_APP_SEARCH_CLIENT_ID_9');
  static final String NAVER_APP_SEARCH_CLIENT_ID_10 = _getEnv('NAVER_APP_SEARCH_CLIENT_ID_10');
  static final String NAVER_APP_SEARCH_CLIENT_ID_11 = _getEnv('NAVER_APP_SEARCH_CLIENT_ID_11');
  static final String NAVER_APP_SEARCH_CLIENT_ID_12 = _getEnv('NAVER_APP_SEARCH_CLIENT_ID_12');
  static final String NAVER_APP_SEARCH_CLIENT_ID_13 = _getEnv('NAVER_APP_SEARCH_CLIENT_ID_13');
  static final String NAVER_APP_SEARCH_CLIENT_ID_14 = _getEnv('NAVER_APP_SEARCH_CLIENT_ID_14');
  static final String NAVER_APP_SEARCH_CLIENT_ID_15 = _getEnv('NAVER_APP_SEARCH_CLIENT_ID_15');
  static final String NAVER_APP_SEARCH_CLIENT_ID_16 = _getEnv('NAVER_APP_SEARCH_CLIENT_ID_16');
  static final String NAVER_APP_SEARCH_CLIENT_ID_17 = _getEnv('NAVER_APP_SEARCH_CLIENT_ID_17');

  static final String NAVER_APP_SEARCH_CLIENT_SECRET_1 = _getEnv('NAVER_APP_SEARCH_CLIENT_SECRET_1');
  static final String NAVER_APP_SEARCH_CLIENT_SECRET_2 = _getEnv('NAVER_APP_SEARCH_CLIENT_SECRET_2');
  static final String NAVER_APP_SEARCH_CLIENT_SECRET_3 = _getEnv('NAVER_APP_SEARCH_CLIENT_SECRET_3');
  static final String NAVER_APP_SEARCH_CLIENT_SECRET_4 = _getEnv('NAVER_APP_SEARCH_CLIENT_SECRET_4');
  static final String NAVER_APP_SEARCH_CLIENT_SECRET_5 = _getEnv('NAVER_APP_SEARCH_CLIENT_SECRET_5');
  static final String NAVER_APP_SEARCH_CLIENT_SECRET_6 = _getEnv('NAVER_APP_SEARCH_CLIENT_SECRET_6');
  static final String NAVER_APP_SEARCH_CLIENT_SECRET_7 = _getEnv('NAVER_APP_SEARCH_CLIENT_SECRET_7');
  static final String NAVER_APP_SEARCH_CLIENT_SECRET_8 = _getEnv('NAVER_APP_SEARCH_CLIENT_SECRET_8');
  static final String NAVER_APP_SEARCH_CLIENT_SECRET_9 = _getEnv('NAVER_APP_SEARCH_CLIENT_SECRET_9');
  static final String NAVER_APP_SEARCH_CLIENT_SECRET_10 = _getEnv('NAVER_APP_SEARCH_CLIENT_SECRET_10');
  static final String NAVER_APP_SEARCH_CLIENT_SECRET_11 = _getEnv('NAVER_APP_SEARCH_CLIENT_SECRET_11');
  static final String NAVER_APP_SEARCH_CLIENT_SECRET_12 = _getEnv('NAVER_APP_SEARCH_CLIENT_SECRET_12');
  static final String NAVER_APP_SEARCH_CLIENT_SECRET_13 = _getEnv('NAVER_APP_SEARCH_CLIENT_SECRET_13');
  static final String NAVER_APP_SEARCH_CLIENT_SECRET_14 = _getEnv('NAVER_APP_SEARCH_CLIENT_SECRET_14');
  static final String NAVER_APP_SEARCH_CLIENT_SECRET_15 = _getEnv('NAVER_APP_SEARCH_CLIENT_SECRET_15');
  static final String NAVER_APP_SEARCH_CLIENT_SECRET_16 = _getEnv('NAVER_APP_SEARCH_CLIENT_SECRET_16');
  static final String NAVER_APP_SEARCH_CLIENT_SECRET_17 = _getEnv('NAVER_APP_SEARCH_CLIENT_SECRET_17');






  // 📌 디버그 모드 플래그
  // - .env에서 DEBUG_MODE=true 설정 시 true 반환.
  // - 로깅/테스트용 분기처리에 활용.
  static final bool isDebugMode = dotenv.env['DEBUG_MODE']?.toLowerCase() == 'true';

  /// 내부 함수: .env 값 조회
  /// --------------------------------------------
  /// [key]에 해당하는 환경 변수를 .env에서 읽어옴.
  /// 값이 존재하지 않으면 Exception을 발생시켜
  /// 앱 실행 시점에 바로 문제를 알 수 있도록 설계.
  ///
  /// ⚠️ 만약 "필수값은 아니지만 있으면 좋은 값"이라면
  /// 아래처럼 수정하는 것도 가능:
  /// ```dart
  /// static String? _getOptionalEnv(String key) => dotenv.env[key];
  /// ```
  static String _getEnv(String key) {
    final value = dotenv.env[key];
    if (value == null) {
      throw Exception('❌ Missing environment variable: $key');
    }
    return value;
  }
}
