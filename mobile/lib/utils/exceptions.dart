/// 사용자 친화적 에러 메시지를 위한 커스텀 Exception
///
/// Dart의 기본 Exception은 자동으로 "Exception: " 접두어를 추가하지만,
/// 이 클래스는 접두어 없이 메시지만 전달하여 사용자 친화적인 에러 표시가 가능합니다.
class UserFriendlyException implements Exception {
  final String message;

  UserFriendlyException(this.message);

  @override
  String toString() => message;
}
