import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/auth_service.dart';
import '../services/fcm_service.dart';
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
  late final AuthService _authService;

  // Phase 6: 토큰 갱신 중 플래그 (경쟁 조건 방지)
  bool _isRefreshing = false;

  @override
  AuthState build() {
    // authServiceProvider를 통해 AuthService 인스턴스 가져오기
    // 이를 통해 401 에러 발생 시 authProvider.logout() 호출 가능
    _authService = ref.read(authServiceProvider);

    // 초기 상태는 비인증
    return const AuthState();
  }

  /// 인증 상태 확인 및 업데이트
  /// - 앱 시작 시 또는 필요 시 호출하여 로그인 상태 복원
  /// - iOS: 토큰 만료 시 자동 갱신 시도
  /// - Phase 6: 토큰 갱신 경쟁 조건 방지
  Future<void> checkAuthStatus() async {
    try {
      final isLoggedIn = await _authService.isLoggedIn();
      final isAnonymousUser = await _authService.isAnonymous();

      if (isLoggedIn) {
        // 일반 회원 로그인
        try {
          // getUserInfo() 내부에서 토큰 자동 갱신 처리됨
          final userInfo = await _authService.getUserInfo();
          state = AuthState(
            isAuthenticated: true,
            isAnonymous: false,
            userInfo: userInfo,
          );
        } catch (e) {
          // 401 에러인 경우 토큰 갱신 한 번 더 시도
          if (e.toString().contains('만료') || e.toString().contains('401')) {
            // Phase 6: 이미 토큰 갱신 중이면 대기
            if (_isRefreshing) {
              debugPrint('[AuthProvider] 토큰 갱신 이미 진행 중 - 대기');
              return;
            }

            _isRefreshing = true;
            try {
              await _authService.refreshToken();
              final userInfo = await _authService.getUserInfo();
              state = AuthState(
                isAuthenticated: true,
                isAnonymous: false,
                userInfo: userInfo,
              );
              return; // 갱신 성공
            } catch (refreshError) {
              // 갱신도 실패하면 로그아웃
              await logout();
            } finally {
              _isRefreshing = false;
            }
          } else {
            // 다른 에러도 로그아웃 처리
            await logout();
          }
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

    // FCM 토큰 서버에 재등록 (로그인 후 푸시 알림 수신을 위해 필수)
    // Phase 6: FCM 토큰 갱신 실패 시에도 로그인 상태는 유지 (순환 참조 방지)
    try {
      await ref.read(fcmServiceProvider).refreshToken();
    } catch (e) {
      debugPrint('[AuthProvider] FCM 토큰 재등록 실패 (로그인 상태는 유지): $e');
    }
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
  /// Phase 6: 토큰 갱신 중에는 로그아웃 방지 (경쟁 조건)
  Future<void> logout() async {
    // Phase 6: 토큰 갱신 중이면 로그아웃 스킵 (갱신 완료 대기)
    if (_isRefreshing) {
      debugPrint('[AuthProvider] 토큰 갱신 중 - 로그아웃 대기');
      return;
    }

    // FCM 토큰 서버에서 해제 (푸시 알림 중지)
    try {
      await ref.read(fcmServiceProvider).unregisterToken();
    } catch (e) {
      debugPrint('[AuthProvider] FCM 토큰 해제 실패 (로그아웃은 진행): $e');
    }

    await _authService.logout();
    state = const AuthState();
  }

  /// 회원 탈퇴
  Future<void> deleteAccount({String? reason}) async {
    // FCM 토큰 서버에서 해제 (푸시 알림 중지)
    await ref.read(fcmServiceProvider).unregisterToken();
    await _authService.deleteAccount(reason: reason);
    state = const AuthState();
  }

  /// 리소스 정리
  ///
  /// 참고: _authService는 authServiceProvider가 관리하므로
  /// Riverpod이 자동으로 dispose 처리함.
  /// 명시적 dispose 호출은 불필요하지만 호환성을 위해 유지.
  void dispose() {
    // authServiceProvider가 관리하는 인스턴스이므로
    // 실제로는 Riverpod이 자동 정리함
    // _authService.dispose();
  }
}

/// AuthProvider 선언
final authProvider = NotifierProvider<AuthNotifier, AuthState>(
  () => AuthNotifier(),
);
