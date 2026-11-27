import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/release_note.dart';
import '../models/version_check_models.dart';
import '../widgets/release_note_card.dart';
import 'firebase_service.dart';
import 'release_note_service.dart';
import 'version_service.dart';

/// 안내 카드를 띄우고 결과를 기록한다.
///
/// 이벤트: `update_card_shown`, `update_card_action`
class ReleaseNotePresenter {
  ReleaseNotePresenter({
    ReleaseNoteService? notes,
    VersionService? versions,
    Future<void> Function(String name, Map<String, Object> parameters)? logEvent,
    Future<bool> Function(Uri url)? openUrl,
  }) : _notes = notes ?? ReleaseNoteService(),
       _versions = versions ?? VersionService(),
       _logEvent = logEvent ?? FirebaseService.instance.logEvent,
       _openUrl = openUrl ?? ((url) => launchUrl(url, mode: LaunchMode.externalApplication));

  final ReleaseNoteService _notes;
  final VersionService _versions;
  final Future<void> Function(String, Map<String, Object>) _logEvent;
  final Future<bool> Function(Uri) _openUrl;

  /// 새 버전이 있을 때. "나중에"나 닫기를 누르면 일정 기간 다시 띄우지 않는다.
  Future<void> showUpdate(
    BuildContext context,
    VersionCheckResponse policy, {
    required bool forced,
  }) async {
    final note = _notes.beforeUpdate(policy, forced: forced);
    final type = forced ? ReleaseCardType.forceUpdate : ReleaseCardType.optionalUpdate;
    _log('update_card_shown', note, type, {'page_count': note.pages.length});

    final result = await ReleaseNoteCard.show(
      context,
      note: note,
      type: type,
      onOpenStore: () async {
        // 강제 업데이트 카드는 닫히지 않으므로 누른 순간 기록한다
        if (forced) _log('update_card_action', note, type, {'action': 'update'});
        try {
          return await _openUrl(Uri.parse(policy.storeUrl));
        } catch (e) {
          debugPrint('[ReleaseNote] 스토어 열기 실패: $e');
          return false;
        }
      },
    );
    if (result == null) return;
    _logResult(note, type, result);
    if (result.action != ReleaseCardAction.update) await _versions.skipRecommendedUpdate();
  }

  /// 업데이트한 뒤 첫 실행에 "새로워진 점"을 한 번 띄운다.
  Future<void> showWhatsNew(BuildContext context) async {
    final note = await _notes.pendingAfterUpdate();
    if (note == null || !context.mounted) return;
    const type = ReleaseCardType.afterUpdate;
    _log('update_card_shown', note, type, {'page_count': note.pages.length});

    final result = await ReleaseNoteCard.show(context, note: note, type: type);
    if (result == null) return; // 다른 화면 전환으로 사라졌으면 다음 실행에 다시
    await _notes.markSeen();
    _logResult(note, type, result);
  }

  void _logResult(ReleaseNote note, ReleaseCardType type, ReleaseCardResult result) => _log(
    'update_card_action',
    note,
    type,
    {'action': result.action.name, 'last_page': result.lastPage},
  );

  void _log(String name, ReleaseNote note, ReleaseCardType type, Map<String, Object> extra) {
    _logEvent(name, {
      'card_type': type.analyticsName,
      'note_version': note.version,
      ...extra,
    }).catchError((Object e) => debugPrint('[ReleaseNote] 이벤트 기록 실패: $e'));
  }
}
