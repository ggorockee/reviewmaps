import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/config/app_version.dart';

/// 업데이트 안내는 AppVersion.current 로 판단한다.
/// pubspec.yaml 만 올리면 새 버전 사용자에게도 업데이트 안내가 계속 뜬다.
void main() {
  test('AppVersion.current 는 pubspec.yaml 의 version 이름과 같아야 한다', () {
    final match = RegExp(r'^version:\s*([0-9.]+)', multiLine: true)
        .firstMatch(File('pubspec.yaml').readAsStringSync());

    expect(match, isNotNull, reason: 'pubspec.yaml 에서 version 을 찾지 못함');
    expect(AppVersion.current, match!.group(1));
  });
}
