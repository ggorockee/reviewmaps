import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Firebase Remote Config를 관리하는 서비스 클래스
class RemoteConfigService {
  static final RemoteConfigService _instance = RemoteConfigService._internal();
  factory RemoteConfigService() => _instance;
  RemoteConfigService._internal();

  FirebaseRemoteConfig? _remoteConfig;
  SharedPreferences? _prefs;

  /// Remote Config 초기화
  Future<void> initialize() async {
    try {
      _remoteConfig = FirebaseRemoteConfig.instance;
      _prefs = await SharedPreferences.getInstance();

      // 기본값 설정
      await _remoteConfig!.setDefaults({
        'notice_visible': false,
        'notice_title': '',
        'notice_body': '',
        'notice_id': '',
      });

      // 캐시 만료 시간 설정 (1시간)
      await _remoteConfig!.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 10),
          minimumFetchInterval: const Duration(hours: 1),
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
