import 'package:flutter/material.dart';

/// ClampTextScale
/// ------------------------------------------------------------
/// 화면(혹은 특정 서브트리)에 적용되는 **텍스트 스케일 상한/하한**을 고정합니다.
/// - 접근성(폰트 크기 확대)을 존중하되, 레이아웃 깨짐을 방지.
/// - 기본값은 기존 동작과 동일하게 '상한만 1.3'을 적용합니다.
/// - 한 앱에서 **단 한 곳**(ex. 최상위 Scaffold 위쪽)에서만 래핑하세요.
///   여러 파일에 중복 정의/중복 적용하면 예측이 어려워져요.
class ClampTextScale extends StatelessWidget {
  final Widget child;

  /// 최대 스케일 (기본 1.3: 기존 코드 호환)
  final double max;

  /// 최소 스케일 (선택, 지정 안 하면 하한 제한 없음)
  final double? min;

  const ClampTextScale({
    super.key,
    required this.child,
    this.max = 1.3,
    this.min,
  });

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);

    // 디바이스(접근성) 스케일 값을 가져와 상/하한으로 클램프
    final clamped = (min == null)
        ? MediaQuery.textScalerOf(context).clamp(maxScaleFactor: max)
        : MediaQuery.textScalerOf(context).clamp(
      minScaleFactor: min!,
      maxScaleFactor: max,
    );

    return MediaQuery(
      data: mq.copyWith(textScaler: clamped),
      child: child,
    );
  }
}

/// showFriendlySnack
/// ------------------------------------------------------------
/// 친근한 스낵바 한 줄로 띄우기.
/// - 기본적으로 기존 스낵바를 **대체**(replace=true)하여 줄줄이 쌓임 방지.
/// - 액션 라벨/콜백이 모두 있을 때만 버튼 노출.
void showFriendlySnack(
    BuildContext ctx,
    String message, {
      String? actionLabel,
      VoidCallback? onAction,
      Duration duration = const Duration(seconds: 3),

      /// true면 기존 스낵바를 숨기고 이번 것만 보여줍니다.
      bool replace = true,
    }) {
  final messenger = ScaffoldMessenger.of(ctx);

  if (replace) {
    messenger.hideCurrentSnackBar();
    messenger.clearSnackBars();
  }

  final bar = SnackBar(
    content: Text(message),
    behavior: SnackBarBehavior.floating,
    duration: duration,
    action: (actionLabel != null && onAction != null)
        ? SnackBarAction(label: actionLabel, onPressed: onAction)
        : null,
  );

  messenger.showSnackBar(bar);
}
