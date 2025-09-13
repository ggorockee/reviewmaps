import 'package:flutter/material.dart';
import '../services/remote_config_service.dart';

/// 공지사항 팝업 다이얼로그 위젯
class NoticeDialog extends StatelessWidget {
  const NoticeDialog({super.key});

  @override
  Widget build(BuildContext context) {
    // 이 위젯은 직접 사용되지 않고 show 메서드를 통해서만 사용됩니다
    return const SizedBox.shrink();
  }

  /// 공지사항 팝업 표시
  static Future<void> show(BuildContext context) async {
    final remoteConfigService = RemoteConfigService();
    
    // 공지사항을 표시해야 하는지 확인
    if (!remoteConfigService.shouldShowNotice()) {
      return;
    }

    return showDialog<void>(
      context: context,
      barrierDismissible: false, // 외부 터치로 닫기 방지
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.0),
          ),
          title: Row(
            children: [
              Icon(
                Icons.notifications_active,
                color: Theme.of(context).primaryColor,
                size: 24,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  remoteConfigService.noticeTitle,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Text(
              remoteConfigService.noticeBody,
              style: const TextStyle(
                fontSize: 16,
                height: 1.5,
              ),
            ),
          ),
          actions: [
            // 닫기 버튼
            TextButton(
              onPressed: () async {
                // 마지막으로 본 공지사항 ID 저장
                await remoteConfigService.saveLastViewedNoticeId(
                  remoteConfigService.noticeId,
                );
                Navigator.of(context).pop();
              },
              child: Text(
                '닫기',
                style: TextStyle(
                  color: Theme.of(context).primaryColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            // 다시 보지 않기 버튼
            ElevatedButton(
              onPressed: () async {
                // 다시 보지 않기로 설정
                await remoteConfigService.setDoNotShowAgain(
                  remoteConfigService.noticeId,
                );
                Navigator.of(context).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8.0),
                ),
              ),
              child: const Text(
                '다시 보지 않기',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        );
      },
    );
  }
}

/// 공지사항 팝업을 자동으로 표시하는 위젯
class NoticePopupWidget extends StatefulWidget {
  final Widget child;

  const NoticePopupWidget({
    super.key,
    required this.child,
  });

  @override
  State<NoticePopupWidget> createState() => _NoticePopupWidgetState();
}

class _NoticePopupWidgetState extends State<NoticePopupWidget> {
  @override
  void initState() {
    super.initState();
    // 위젯이 빌드된 후 공지사항 팝업 표시
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showNoticeIfNeeded();
    });
  }

  /// 필요한 경우 공지사항 팝업 표시
  Future<void> _showNoticeIfNeeded() async {
    if (mounted) {
      await NoticeDialog.show(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
