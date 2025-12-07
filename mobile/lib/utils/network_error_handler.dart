import 'dart:async';
import 'dart:io';

/// 네트워크 에러 처리 유틸리티
/// - 네이버 스타일의 사용자 친화적 한글 에러 메시지 제공
/// - 에러 타입별 적절한 안내 메시지 반환
class NetworkErrorHandler {
  /// 에러를 사용자 친화적 메시지로 변환
  static String getErrorMessage(dynamic error) {
    // 이미 사용자 친화적 메시지인 경우 그대로 반환
    if (error is Exception) {
      final message = error.toString().replaceFirst('Exception: ', '');
      if (_isUserFriendlyMessage(message)) {
        return message;
      }
    }

    // 네트워크 연결 오류
    if (error is SocketException) {
      return '인터넷 연결을 확인해 주세요.';
    }

    // 타임아웃 오류
    if (error is TimeoutException) {
      return '서버 응답이 늦어지고 있어요.\n잠시 후 다시 시도해 주세요.';
    }

    // SSL/TLS 핸드셰이크 오류
    if (error is HandshakeException) {
      return '보안 연결에 실패했어요.\n네트워크 환경을 확인해 주세요.';
    }

    // HTTP 오류
    if (error is HttpException) {
      return '서버와 통신 중 문제가 생겼어요.\n잠시 후 다시 시도해 주세요.';
    }

    // FormatException (JSON 파싱 오류 등)
    if (error is FormatException) {
      return '데이터를 처리하는 중 문제가 생겼어요.';
    }

    // 문자열 에러 메시지 분석
    final errorString = error.toString().toLowerCase();

    if (errorString.contains('socketexception') ||
        errorString.contains('network is unreachable') ||
        errorString.contains('connection refused') ||
        errorString.contains('no address associated') ||
        errorString.contains('failed host lookup')) {
      return '인터넷 연결을 확인해 주세요.';
    }

    if (errorString.contains('timeout')) {
      return '서버 응답이 늦어지고 있어요.\n잠시 후 다시 시도해 주세요.';
    }

    if (errorString.contains('handshake') ||
        errorString.contains('certificate')) {
      return '보안 연결에 실패했어요.\n네트워크 환경을 확인해 주세요.';
    }

    // 기본 메시지
    return '일시적인 오류가 발생했어요.\n잠시 후 다시 시도해 주세요.';
  }

  /// HTTP 상태 코드에 따른 에러 메시지
  static String getHttpErrorMessage(int statusCode, {String? serverMessage}) {
    // 서버에서 메시지를 제공한 경우 사용자 친화적으로 변환
    if (serverMessage != null && serverMessage.isNotEmpty) {
      return _transformServerMessage(serverMessage);
    }

    switch (statusCode) {
      case 400:
        return '요청 정보를 확인해 주세요.';
      case 401:
        return '로그인이 만료되었어요.\n다시 로그인해 주세요.';
      case 403:
        return '접근 권한이 없어요.';
      case 404:
        return '이미 삭제되었거나 존재하지 않는 항목이에요.';
      case 409:
        return '이미 처리된 요청이에요.';
      case 422:
        return '입력 정보를 확인해 주세요.';
      case 429:
        return '요청이 너무 많아요.\n잠시 후 다시 시도해 주세요.';
      case 500:
        return '서버에 일시적인 문제가 생겼어요.\n잠시 후 다시 시도해 주세요.';
      case 502:
      case 503:
      case 504:
        return '서버 점검 중이거나 접속이 원활하지 않아요.\n잠시 후 다시 시도해 주세요.';
      default:
        if (statusCode >= 500) {
          return '서버에 문제가 생겼어요.\n잠시 후 다시 시도해 주세요.';
        }
        return '요청을 처리할 수 없어요.\n잠시 후 다시 시도해 주세요.';
    }
  }

  /// 네트워크 연결 오류인지 확인
  static bool isNetworkError(dynamic error) {
    if (error is SocketException) return true;
    if (error is TimeoutException) return true;

    final errorString = error.toString().toLowerCase();
    return errorString.contains('socketexception') ||
        errorString.contains('network is unreachable') ||
        errorString.contains('connection refused') ||
        errorString.contains('no address associated') ||
        errorString.contains('failed host lookup') ||
        errorString.contains('timeout');
  }

  /// 재시도 가능한 오류인지 확인
  static bool isRetryableError(dynamic error) {
    if (error is SocketException) return true;
    if (error is TimeoutException) return true;
    if (error is HttpException) return true;

    final errorString = error.toString().toLowerCase();
    return errorString.contains('timeout') ||
        errorString.contains('connection') ||
        errorString.contains('network');
  }

  /// 서버 메시지를 사용자 친화적 메시지로 변환
  static String _transformServerMessage(String message) {
    // 서버 메시지 → 사용자 친화적 메시지 매핑
    const messageMap = {
      '이미 등록된 키워드입니다.': '이 키워드는 이미 등록되어 있어요.',
      '이미 등록된 키워드입니다': '이 키워드는 이미 등록되어 있어요.',
      '키워드를 찾을 수 없습니다.': '해당 키워드를 찾을 수 없어요.',
      '키워드를 찾을 수 없습니다': '해당 키워드를 찾을 수 없어요.',
    };

    // 매핑된 메시지가 있으면 변환
    if (messageMap.containsKey(message)) {
      return messageMap[message]!;
    }

    // 매핑이 없으면 원본 메시지 반환
    return message;
  }

  /// 사용자 친화적 메시지인지 확인
  static bool _isUserFriendlyMessage(String message) {
    // 한글이 포함되어 있고, 기술적 용어가 없는 경우
    final hasKorean = RegExp(r'[가-힣]').hasMatch(message);
    final hasTechnicalTerms = message.toLowerCase().contains('exception') ||
        message.toLowerCase().contains('error:') ||
        message.contains('null') ||
        message.contains('undefined');

    return hasKorean && !hasTechnicalTerms;
  }
}
