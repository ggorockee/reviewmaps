/// 인증 관련 모델 클래스들
/// - API 요청/응답 데이터 구조 정의
/// - JSON 직렬화/역직렬화 지원

/// 회원가입 요청 데이터
class SignUpRequest {
  final String email;
  final String password;

  SignUpRequest({
    required this.email,
    required this.password,
  });

  Map<String, dynamic> toJson() => {
    'email': email,
    'password': password,
  };
}

/// 로그인 요청 데이터
class LoginRequest {
  final String email;
  final String password;

  LoginRequest({
    required this.email,
    required this.password,
  });

  Map<String, dynamic> toJson() => {
    'email': email,
    'password': password,
  };
}

/// 토큰 갱신 요청 데이터
class RefreshTokenRequest {
  final String refreshToken;

  RefreshTokenRequest({
    required this.refreshToken,
  });

  Map<String, dynamic> toJson() => {
    'refresh_token': refreshToken,
  };
}

/// 익명 사용자 전환 요청 데이터
class ConvertAnonymousRequest {
  final String sessionToken;
  final String email;
  final String password;

  ConvertAnonymousRequest({
    required this.sessionToken,
    required this.email,
    required this.password,
  });

  Map<String, dynamic> toJson() => {
    'session_token': sessionToken,
    'email': email,
    'password': password,
  };
}

/// 인증 응답 데이터 (access_token, refresh_token)
class AuthResponse {
  final String accessToken;
  final String refreshToken;

  AuthResponse({
    required this.accessToken,
    required this.refreshToken,
  });

  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    return AuthResponse(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
    'access_token': accessToken,
    'refresh_token': refreshToken,
  };
}

/// 익명 로그인 응답 데이터 (session_token)
class AnonymousResponse {
  final String sessionToken;

  AnonymousResponse({
    required this.sessionToken,
  });

  factory AnonymousResponse.fromJson(Map<String, dynamic> json) {
    return AnonymousResponse(
      sessionToken: json['session_token'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
    'session_token': sessionToken,
  };
}

/// 사용자 정보 응답 데이터
class UserInfo {
  final String id;
  final String email;
  final String? name;
  final bool isAnonymous;

  UserInfo({
    required this.id,
    required this.email,
    this.name,
    required this.isAnonymous,
  });

  factory UserInfo.fromJson(Map<String, dynamic> json) {
    return UserInfo(
      id: json['id'].toString(), // int 또는 String을 안전하게 String으로 변환
      email: json['email'] as String,
      name: json['name'] as String?,
      isAnonymous: json['is_anonymous'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'name': name,
    'is_anonymous': isAnonymous,
  };
}
