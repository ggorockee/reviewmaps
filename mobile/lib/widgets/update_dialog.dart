import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/version_check_models.dart';

/// 앱 업데이트 안내 다이얼로그
///
/// 서버에서 받은 버전 정보를 바탕으로 사용자에게 업데이트를 안내합니다.
/// - 강제 업데이트: 닫기 버튼 없이 스토어로만 이동 가능
/// - 선택적 업데이트: "나중에" 버튼으로 닫을 수 있음
class UpdateDialog extends StatelessWidget {
  final VersionCheckResponse versionInfo;

  const UpdateDialog({
    super.key,
    required this.versionInfo,
  });

  /// 스토어 URL 열기
  Future<void> _openStore(BuildContext context) async {
    final url = Uri.parse(versionInfo.storeUrl);

    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(
          url,
          mode: LaunchMode.externalApplication,
        );
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('스토어를 열 수 없습니다')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('스토어 열기 실패: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 강제 업데이트일 경우 뒤로가기 버튼 비활성화
      canPop: !versionInfo.forceUpdate,
      child: AlertDialog(
        title: Text(
          versionInfo.forceUpdate ? '필수 업데이트' : '업데이트 안내',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 업데이트 메시지
            Text(
              versionInfo.message ?? '새로운 버전이 출시되었습니다.',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            // 버전 정보
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        '최신 버전: ',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.black54,
                        ),
                      ),
                      Text(
                        versionInfo.latestVersion,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                    ],
                  ),
                  if (versionInfo.forceUpdate) ...[
                    const SizedBox(height: 8),
                    const Text(
                      '⚠️ 계속 사용하려면 업데이트가 필요합니다',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.red,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        actions: [
          // 선택적 업데이트일 경우에만 "나중에" 버튼 표시
          if (!versionInfo.forceUpdate)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('나중에'),
            ),
          // 업데이트 버튼
          ElevatedButton(
            onPressed: () => _openStore(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: const Text('업데이트'),
          ),
        ],
      ),
    );
  }

  /// 다이얼로그 표시 헬퍼 함수
  ///
  /// 편리하게 다이얼로그를 띄울 수 있는 정적 메서드입니다.
  static Future<void> show(
    BuildContext context,
    VersionCheckResponse versionInfo,
  ) {
    return showDialog(
      context: context,
      barrierDismissible: !versionInfo.forceUpdate, // 강제 업데이트 시 바깥 영역 클릭으로 닫기 불가
      builder: (context) => UpdateDialog(versionInfo: versionInfo),
    );
  }
}
