import 'package:flutter/material.dart';

/// 광고 제공자 인터페이스
/// DR(의존성 역전 원칙) 적용을 위한 추상화 계층
/// 
/// 이 인터페이스를 구현하여 다양한 광고 네트워크를 통합할 수 있습니다.
/// - AdMobProvider: Google AdMob 구현
/// - AdFitProvider: 카카오 AdFit 구현
abstract class IAdProvider {
  /// 광고 제공자 이름 (로깅용)
  String get providerName;

  /// 광고 제공자 초기화
  /// 
  /// Returns: 초기화 성공 여부
  Future<bool> initialize();

  /// 배너 광고 위젯 생성
  /// 
  /// [adUnitId] 광고 단위 ID
  /// [onAdLoaded] 광고 로드 완료 콜백
  /// [onAdFailedToLoad] 광고 로드 실패 콜백
  /// [onAdClicked] 광고 클릭 콜백
  /// 
  /// Returns: 배너 광고 위젯 (로드 실패 시 null)
  Future<Widget?> createBannerAd({
    required String adUnitId,
    VoidCallback? onAdLoaded,
    Function(String error)? onAdFailedToLoad,
    VoidCallback? onAdClicked,
  });

  /// 전면광고 로드
  /// 
  /// [adUnitId] 광고 단위 ID
  /// [onAdLoaded] 광고 로드 완료 콜백
  /// [onAdFailedToLoad] 광고 로드 실패 콜백
  /// 
  /// Returns: 로드 성공 여부
  Future<bool> loadInterstitialAd({
    required String adUnitId,
    VoidCallback? onAdLoaded,
    Function(String error)? onAdFailedToLoad,
  });

  /// 전면광고 표시
  /// 
  /// Returns: 표시 성공 여부
  Future<bool> showInterstitialAd({
    VoidCallback? onAdShown,
    VoidCallback? onAdDismissed,
    Function(String error)? onAdFailedToShow,
  });

  /// 네이티브 광고 위젯 생성
  /// 
  /// [adUnitId] 광고 단위 ID
  /// [onAdLoaded] 광고 로드 완료 콜백
  /// [onAdFailedToLoad] 광고 로드 실패 콜백
  /// [onAdClicked] 광고 클릭 콜백
  /// 
  /// Returns: 네이티브 광고 위젯 (로드 실패 시 null)
  Future<Widget?> createNativeAd({
    required String adUnitId,
    VoidCallback? onAdLoaded,
    Function(String error)? onAdFailedToLoad,
    VoidCallback? onAdClicked,
  });

  /// 광고 제공자 정리 (리소스 해제)
  void dispose();
}


