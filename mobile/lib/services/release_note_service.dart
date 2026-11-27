import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_version.dart';
import '../models/release_note.dart';
import '../models/version_check_models.dart';
import 'remote_config_service.dart';

/// 업데이트 안내 내용과 "언제 보여줄지"를 정한다. 화면은 다루지 않는다.
class ReleaseNoteService {
  ReleaseNoteService({
    this.currentVersion = AppVersion.current,
    Future<String> Function()? loadBundled,
    String Function()? remoteSource,
  }) : _loadBundled = loadBundled ?? (() => rootBundle.loadString(assetPath)),
       _remoteSource = remoteSource ?? (() => RemoteConfigService().releaseNoteSource);

  static const String assetPath = 'asset/release_notes.json';
  static const String seenVersionKey = 'release_note_seen_version';

  /// 홈 화면이 첫 실행 때 저장하는 값. 있으면 이전부터 쓰던 사용자다.
  static const String firstRunKey = 'first_run_done';

  final String currentVersion;
  final Future<String> Function() _loadBundled;
  final String Function() _remoteSource;

  /// 앱 시작 때, 홈 화면이 만들어지기 **전에** 호출한다.
  /// 새로 설치한 사용자는 이 버전을 본 것으로 기록해 "새로워진 점"을 띄우지 않는다.
  Future<void> recordFirstInstall() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(seenVersionKey) == null && !prefs.containsKey(firstRunKey)) {
      await prefs.setString(seenVersionKey, currentVersion);
    }
  }

  /// 업데이트한 뒤 보여줄 안내. 보여줄 것이 없으면 null.
  Future<ReleaseNote?> pendingAfterUpdate() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getString(seenVersionKey);
    if (seen != null && !AppVersion.isLowerThan(seen, currentVersion)) return null;
    return remoteNote(currentVersion) ?? await bundledNote(currentVersion);
  }

  Future<void> markSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(seenVersionKey, currentVersion);
  }

  /// Remote Config의 안내. [version]용이 아니거나 장이 없으면 null.
  ReleaseNote? remoteNote(String version) => _matching(ReleaseNote.tryParse(_remoteSource()), version);

  /// 앱에 든 안내. [version]용이 아니거나 장이 없으면 null.
  Future<ReleaseNote?> bundledNote(String version) async {
    try {
      return _matching(ReleaseNote.tryParse(await _loadBundled()), version);
    } catch (e) {
      debugPrint('[ReleaseNote] 앱에 든 안내를 읽지 못함: $e');
      return null;
    }
  }

  /// 업데이트하기 전 안내. 새 버전용 원격 안내가 없으면 한 장짜리 기본 안내.
  ReleaseNote beforeUpdate(VersionCheckResponse policy, {required bool forced}) =>
      remoteNote(policy.latestVersion) ??
      ReleaseNote(
        version: policy.latestVersion,
        pages: [
          ReleaseNotePage(
            title: policy.messageTitle ?? (forced ? '업데이트가 필요해요' : '새 버전이 있어요'),
            body: policy.messageBody ??
                (forced ? '최신 버전으로 업데이트한 뒤 이용해 주세요.' : '더 나은 서비스 이용을 위해 업데이트를 추천드려요.'),
            icon: 'update',
          ),
        ],
      );

  static ReleaseNote? _matching(ReleaseNote? note, String version) =>
      note != null && note.version == version && note.pages.isNotEmpty ? note : null;
}
