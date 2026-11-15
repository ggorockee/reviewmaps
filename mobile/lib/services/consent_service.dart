import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_service.dart';
import 'app_open_ad_service.dart';

/// 광고 동의(Google UMP) 및 광고 SDK 초기화 관리
///
/// Google 정책: EEA·영국·스위스 사용자에게 광고를 게재하려면 인증된 CMP(UMP)로 동의를 받아야 하며,
/// [canRequestAds]가 true가 되기 전에는 광고를 요청하면 안 됩니다.
///
/// 흐름:
/// 1. main(): [requestConsentInfoUpdate] → [initializeAdsIfAllowed]
///    (비규제 지역 또는 이전에 동의한 사용자는 여기서 바로 광고 초기화)
/// 2. 스플래시: [showConsentFormIfRequired] → [initializeAdsIfAllowed]
///    (규제 지역 신규 사용자는 동의 양식 처리 후 광고 초기화)
/// 3. 설정 화면: [isPrivacyOptionsRequired]가 true면 [showPrivacyOptionsForm] 진입점 제공
///
/// 테스트: `--dart-define=UMP_DEBUG_EEA=true` (실기기는 `UMP_TEST_DEVICE_ID`에 로그의 해시 ID 지정)
class ConsentService {
  static final ConsentService _instance = ConsentService._internal();
  factory ConsentService() => _instance;
  ConsentService._internal();

  static const bool _debugEea = bool.fromEnvironment('UMP_DEBUG_EEA');
  static const String _testDeviceId = String.fromEnvironment('UMP_TEST_DEVICE_ID');

  /// 동의 정보 갱신 대기 최대 시간 (네트워크 지연 시 앱 시작을 막지 않도록)
  static const Duration _infoUpdateTimeout = Duration(seconds: 5);

  bool _adsInitialized = false;
  Future<void>? _initializing;

  /// 광고 SDK 초기화 완료 여부 (false면 광고 요청 금지)
  bool get isAdsInitialized => _adsInitialized;

  ConsentRequestParameters _buildParams() {
    if (kDebugMode && _debugEea) {
      return ConsentRequestParameters(
        consentDebugSettings: ConsentDebugSettings(
          debugGeography: DebugGeography.debugGeographyEea,
          testIdentifiers: _testDeviceId.isEmpty ? null : [_testDeviceId],
        ),
      );
    }
    return ConsentRequestParameters();
  }

  /// 동의 정보 갱신 (매 실행마다 호출 권장). 실패/타임아웃이어도 앱 시작은 계속 진행
  Future<void> requestConsentInfoUpdate() async {
    final completer = Completer<void>();
    try {
      ConsentInformation.instance.requestConsentInfoUpdate(
        _buildParams(),
        () {
          if (!completer.isCompleted) completer.complete();
        },
        (FormError error) {
          debugPrint('[Consent] 동의 정보 갱신 실패: ${error.errorCode} ${error.message}');
          if (!completer.isCompleted) completer.complete();
        },
      );
    } catch (e) {
      debugPrint('[Consent] 동의 정보 갱신 오류: $e');
      if (!completer.isCompleted) completer.complete();
    }

    await completer.future.timeout(_infoUpdateTimeout, onTimeout: () {
      debugPrint('[Consent] 동의 정보 갱신 타임아웃 - 이전 동의 상태로 진행');
    });
  }

  /// 동의가 필요한 사용자(EEA 등)에게만 동의 양식 표시. 사용자가 닫을 때까지 대기
  Future<void> showConsentFormIfRequired() async {
    final completer = Completer<void>();
    try {
      await ConsentForm.loadAndShowConsentFormIfRequired((FormError? error) {
        if (error != null) {
          debugPrint('[Consent] 동의 양식 오류: ${error.errorCode} ${error.message}');
        }
        if (!completer.isCompleted) completer.complete();
      });
    } catch (e) {
      debugPrint('[Consent] 동의 양식 표시 오류: $e');
      if (!completer.isCompleted) completer.complete();
    }
    await completer.future;
  }

  /// 현재 동의 상태로 광고 요청이 가능한지
  Future<bool> canRequestAds() async {
    try {
      return await ConsentInformation.instance.canRequestAds();
    } catch (e) {
      debugPrint('[Consent] canRequestAds 확인 실패: $e');
      return false;
    }
  }

  /// 광고 요청이 허용된 경우에만 광고 SDK 및 앱 오프닝 광고 초기화 (1회만 실행)
  Future<void> initializeAdsIfAllowed() async {
    if (_adsInitialized) return;
    if (_initializing != null) return _initializing;

    if (!await canRequestAds()) {
      debugPrint('[Consent] 동의 전이므로 광고 초기화 보류');
      return;
    }

    _initializing = _initializeAds();
    try {
      await _initializing;
    } finally {
      _initializing = null;
    }
  }

  Future<void> _initializeAds() async {
    // MobileAds.instance.initialize()는 AdService.initialize() 내부에서 호출
    await AdService().initialize();

    if (kDebugMode) {
      // DEBUG 모드에서는 테스트 광고 강제 사용
      await MobileAds.instance.updateRequestConfiguration(
        RequestConfiguration(testDeviceIds: ['d032385e-b579-421a-ae28-2bd485f4b306']),
      );
    }

    await AppOpenAdService().initialize();
    _adsInitialized = true;
    debugPrint('[Consent] 광고 초기화 완료');
  }

  /// 설정 화면에 "광고 개인정보 설정" 진입점을 보여야 하는지 (규제 지역 사용자만 true)
  Future<bool> isPrivacyOptionsRequired() async {
    try {
      final status = await ConsentInformation.instance.getPrivacyOptionsRequirementStatus();
      return status == PrivacyOptionsRequirementStatus.required;
    } catch (e) {
      debugPrint('[Consent] 개인정보 옵션 필요 여부 확인 실패: $e');
      return false;
    }
  }

  /// 광고 개인정보 설정(동의 변경) 양식 표시
  Future<void> showPrivacyOptionsForm() async {
    final completer = Completer<void>();
    try {
      await ConsentForm.showPrivacyOptionsForm((FormError? error) {
        if (error != null) {
          debugPrint('[Consent] 개인정보 옵션 양식 오류: ${error.errorCode} ${error.message}');
        }
        if (!completer.isCompleted) completer.complete();
      });
    } catch (e) {
      debugPrint('[Consent] 개인정보 옵션 양식 표시 오류: $e');
      if (!completer.isCompleted) completer.complete();
    }
    await completer.future;
    // 동의를 새로 한 경우 광고 초기화
    await initializeAdsIfAllowed();
  }
}
