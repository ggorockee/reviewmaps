import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/version_check_models.dart';

/// Firebase Remote Config를 관리하는 서비스 클래스
///
/// 앱 전체에서 Remote Config 초기화(setDefaults / setConfigSettings)는
/// 이 서비스에서만 수행합니다. 여러 곳에서 setDefaults를 호출하면
/// 나중 호출이 기본값 맵 전체를 덮어쓰므로 반드시 한 곳에서 관리해야 합니다.
///
/// 관리 키:
/// - 공지사항: notice_visible, notice_title, notice_body, notice_id
/// - 앱 버전 정책 (플랫폼별 접두사 ios_ / android_):
///   {platform}_latest_version, {platform}_min_version,
///   {platform}_force_update, {platform}_store_url
/// - 업데이트 안내 문구 (공통): update_message_title, update_message_body
class RemoteConfigService {
  static final RemoteConfigService _instance = RemoteConfigService._internal();
  factory RemoteConfigService() => _instance;
  RemoteConfigService._internal();

  /// 버전 정책 기본값: 콘솔에 값이 없거나 fetch 실패 시 업데이트 안내를 띄우지 않음
  static const String _noVersion = '0.0.0';

  static const String _iosStoreUrl = 'https://apps.apple.com/app/id6751343880';
  static const String _androidStoreUrl =
      'https://play.google.com/store/apps/details?id=com.reviewmaps.mobile';

  FirebaseRemoteConfig? _remoteConfig;
  SharedPreferences? _prefs;

  /// Remote Config 초기화
  Future<void> initialize() async {
    try {
      _remoteConfig = FirebaseRemoteConfig.instance;
      _prefs = await SharedPreferences.getInstance();

      // 기본값 설정 (앱에서 사용하는 모든 키를 이곳에 등록)
      await _remoteConfig!.setDefaults({
        // 공지사항
        'notice_visible': false,
        'notice_title': '',
        'notice_body': '',
        'notice_id': '',
        // 앱 버전 정책
        'ios_latest_version': _noVersion,
        'ios_min_version': _noVersion,
        'ios_force_update': false,
        'ios_store_url': _iosStoreUrl,
        'android_latest_version': _noVersion,
        'android_min_version': _noVersion,
        'android_force_update': false,
        'android_store_url': _androidStoreUrl,
        'update_message_title': '',
        'update_message_body': '',
      });

      // 캐시 만료 시간 설정
      // - 버전 정책 변경이 빠르게 반영되도록 프로덕션 15분 (시간당 최대 4회 fetch로 스로틀링 범위 내)
      await _remoteConfig!.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 10),
          minimumFetchInterval:
              kDebugMode ? const Duration(seconds: 10) : const Duration(minutes: 15),
        ),
      );

      // 원격 설정 가져오기 및 활성화
      await fetchAndActivate();
    } catch (e) {
      debugPrint('Remote Config 초기화 오류: $e');
    }
  }

  /// 원격 설정 가져오기 및 활성화
  Future<void> fetchAndActivate() async {
    try {
      if (_remoteConfig != null) {
        await _remoteConfig!.fetchAndActivate();
      }
    } catch (e) {
      debugPrint('Remote Config fetchAndActivate 오류: $e');
    }
  }

  // ==================== 앱 버전 정책 ====================

  /// 현재 플랫폼의 버전 정책 조회
  ///
  /// Throws:
  /// - StateError: Remote Config가 초기화되지 않은 경우
  VersionCheckResponse getVersionPolicy() {
    final remoteConfig = _remoteConfig;
    if (remoteConfig == null) {
      throw StateError('Remote Config가 초기화되지 않았습니다');
    }

    final prefix = Platform.isIOS ? 'ios' : 'android';
    final defaultStoreUrl = Platform.isIOS ? _iosStoreUrl : _androidStoreUrl;

    final storeUrl = remoteConfig.getString('${prefix}_store_url').trim();
    final messageTitle = remoteConfig.getString('update_message_title').trim();
    final messageBody = remoteConfig.getString('update_message_body').trim();

    return VersionCheckResponse(
      latestVersion: _versionOrDefault(remoteConfig.getString('${prefix}_latest_version')),
      minVersion: _versionOrDefault(remoteConfig.getString('${prefix}_min_version')),
      forceUpdate: remoteConfig.getBool('${prefix}_force_update'),
      storeUrl: storeUrl.isEmpty ? defaultStoreUrl : storeUrl,
      // 빈 문자열이면 null로 넘겨 다이얼로그 기본 문구 사용
      messageTitle: messageTitle.isEmpty ? null : messageTitle,
      messageBody: messageBody.isEmpty ? null : messageBody,
    );
  }

  String _versionOrDefault(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? _noVersion : trimmed;
  }

  // ==================== 공지사항 ====================

  /// 공지사항 표시 여부 확인
  bool get isNoticeVisible {
    return _remoteConfig?.getBool('notice_visible') ?? false;
  }

  /// 공지사항 제목 가져오기
  String get noticeTitle {
    return _remoteConfig?.getString('notice_title') ?? '';
  }

  /// 공지사항 내용 가져오기
  String get noticeBody {
    return _remoteConfig?.getString('notice_body') ?? '';
  }

  /// 공지사항 ID 가져오기
  String get noticeId {
    return _remoteConfig?.getString('notice_id') ?? '';
  }

  /// 마지막으로 본 공지사항 ID 가져오기
  String get lastViewedNoticeId {
    return _prefs?.getString('last_viewed_notice_id') ?? '';
  }

  /// 마지막으로 본 공지사항 ID 저장
  Future<void> saveLastViewedNoticeId(String noticeId) async {
    if (_prefs != null) {
      await _prefs!.setString('last_viewed_notice_id', noticeId);
    }
  }

  /// 공지사항을 다시 보지 않기로 설정
  Future<void> setDoNotShowAgain(String noticeId) async {
    if (_prefs != null) {
      await _prefs!.setString('do_not_show_notice_id', noticeId);
    }
  }

  /// 다시 보지 않기로 설정된 공지사항 ID 확인
  String get doNotShowNoticeId {
    return _prefs?.getString('do_not_show_notice_id') ?? '';
  }

  /// 공지사항 팝업을 표시해야 하는지 확인
  bool shouldShowNotice() {
    // 공지사항이 비활성화되어 있으면 표시하지 않음
    if (!isNoticeVisible) return false;

    // 제목이나 내용이 비어있으면 표시하지 않음
    if (noticeTitle.isEmpty || noticeBody.isEmpty) return false;

    // 공지사항 ID가 비어있으면 표시하지 않음
    if (noticeId.isEmpty) return false;

    // 다시 보지 않기로 설정된 공지사항이면 표시하지 않음
    if (doNotShowNoticeId == noticeId) return false;

    // 마지막으로 본 공지사항과 다른 경우에만 표시
    return lastViewedNoticeId != noticeId;
  }
}
