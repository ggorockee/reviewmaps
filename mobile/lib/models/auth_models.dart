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
  final String? expiresAt;
  final int? expireHours;

  AnonymousResponse({
    required this.sessionToken,
    this.expiresAt,
    this.expireHours,
  });

  factory AnonymousResponse.fromJson(Map<String, dynamic> json) {
    return AnonymousResponse(
      sessionToken: json['session_token'] as String,
      expiresAt: json['expires_at'] as String?,
      expireHours: json['expire_hours'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
    'session_token': sessionToken,
    if (expiresAt != null) 'expires_at': expiresAt,
    if (expireHours != null) 'expire_hours': expireHours,
  };
}

/// 일반 사용자 정보 응답 데이터
class UserInfo {
  final String id;
  final String email;
  final String? name;
  final bool isActive;
  final String? dateJoined;
  final String loginMethod; // email, google, apple, kakao, naver

  UserInfo({
    required this.id,
    required this.email,
    this.name,
    required this.isActive,
    this.dateJoined,
    required this.loginMethod,
  });

  factory UserInfo.fromJson(Map<String, dynamic> json) {
    return UserInfo(
      id: json['id'].toString(), // int 또는 String을 안전하게 String으로 변환
      email: json['email'] as String,
      name: json['name'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      dateJoined: json['date_joined'] as String?,
      loginMethod: json['login_method'] as String? ?? 'email',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    if (name != null) 'name': name,
    'is_active': isActive,
    if (dateJoined != null) 'date_joined': dateJoined,
    'login_method': loginMethod,
  };

  /// 로그인 방식을 한글로 변환
  String get loginMethodDisplayName {
    switch (loginMethod) {
      case 'email':
        return '이메일';
      case 'google':
        return 'Google';
      case 'apple':
        return 'Apple';
      case 'kakao':
        return '카카오';
      case 'naver':
        return '네이버';
      default:
        return '이메일';
    }
  }
}

/// 익명 사용자 정보 응답 데이터
class AnonymousUserInfo {
  final String sessionId;
  final String expiresAt;
  final double remainingHours;

  AnonymousUserInfo({
    required this.sessionId,
    required this.expiresAt,
    required this.remainingHours,
  });

  factory AnonymousUserInfo.fromJson(Map<String, dynamic> json) {
    return AnonymousUserInfo(
      sessionId: json['session_id'] as String,
      expiresAt: json['expires_at'] as String,
      remainingHours: (json['remaining_hours'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
    'session_id': sessionId,
    'expires_at': expiresAt,
    'remaining_hours': remainingHours,
  };

  /// 남은 시간을 사용자 친화적으로 표시
  String get remainingTimeDisplay {
    if (remainingHours < 1) {
      final minutes = (remainingHours * 60).round();
      return '$minutes분';
    } else if (remainingHours < 24) {
      return '${remainingHours.toStringAsFixed(1)}시간';
    } else {
      final days = (remainingHours / 24).floor();
      final hours = (remainingHours % 24).round();
      if (hours > 0) {
        return '$days일 $hours시간';
      }
      return '$days일';
    }
  }
}
