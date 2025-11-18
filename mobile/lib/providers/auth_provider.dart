import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/auth_service.dart';
import '../models/auth_models.dart';

/// 인증 상태
/// - 로그인 여부, 익명 사용자 여부, 사용자 정보 관리
class AuthState {
  final bool isAuthenticated;
  final bool isAnonymous;
  final UserInfo? userInfo;
  final AnonymousUserInfo? anonymousUserInfo;

  const AuthState({
    this.isAuthenticated = false,
    this.isAnonymous = false,
    this.userInfo,
    this.anonymousUserInfo,
  });

  /// 일반 회원 여부 (익명이 아닌 정식 회원)
  bool get isRegularUser => isAuthenticated && !isAnonymous;

  /// 인증된 사용자 (일반 회원 또는 익명 사용자)
  bool get hasAuth => isAuthenticated || isAnonymous;

  AuthState copyWith({
    bool? isAuthenticated,
    bool? isAnonymous,
    UserInfo? userInfo,
    AnonymousUserInfo? anonymousUserInfo,
  }) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isAnonymous: isAnonymous ?? this.isAnonymous,
      userInfo: userInfo ?? this.userInfo,
      anonymousUserInfo: anonymousUserInfo ?? this.anonymousUserInfo,
    );
  }
}

/// 인증 상태 관리 노티파이어
class AuthNotifier extends Notifier<AuthState> {
  final AuthService _authService = AuthService();

  @override
  AuthState build() {
    // 초기 상태는 비인증
    return const AuthState();
  }

  /// 인증 상태 확인 및 업데이트
  /// - 앱 시작 시 또는 필요 시 호출하여 로그인 상태 복원
  Future<void> checkAuthStatus() async {
    try {
      final isLoggedIn = await _authService.isLoggedIn();
      final isAnonymousUser = await _authService.isAnonymous();

      if (isLoggedIn) {
        // 일반 회원 로그인
        try {
          final userInfo = await _authService.getUserInfo();
          state = AuthState(
            isAuthenticated: true,
            isAnonymous: false,
            userInfo: userInfo,
          );
        } catch (e) {
          // 사용자 정보 조회 실패 시 로그아웃 처리
          await logout();
        }
      } else if (isAnonymousUser) {
        // 익명 사용자
        try {
          final anonymousInfo = await _authService.getAnonymousUserInfo();
          state = AuthState(
            isAuthenticated: false,
            isAnonymous: true,
            anonymousUserInfo: anonymousInfo,
          );
        } catch (e) {
          // 익명 사용자 정보 조회 실패 시 비인증 상태로
          state = const AuthState();
        }
      } else {
        // 비인증 상태
        state = const AuthState();
      }
    } catch (e) {
      // 오류 발생 시 비인증 상태로
      state = const AuthState();
    }
  }

  /// 로그인 성공 후 상태 업데이트
  Future<void> updateAfterLogin(UserInfo userInfo) async {
    state = AuthState(
      isAuthenticated: true,
      isAnonymous: false,
      userInfo: userInfo,
    );
  }

  /// 익명 로그인 성공 후 상태 업데이트
  Future<void> updateAfterAnonymousLogin(AnonymousUserInfo anonymousInfo) async {
    state = AuthState(
      isAuthenticated: false,
      isAnonymous: true,
      anonymousUserInfo: anonymousInfo,
    );
  }

  /// 로그아웃
  Future<void> logout() async {
    await _authService.logout();
    state = const AuthState();
  }

  /// 리소스 정리
  void dispose() {
    _authService.dispose();
  }
}

/// AuthProvider 선언
final authProvider = NotifierProvider<AuthNotifier, AuthState>(
  () => AuthNotifier(),
);
