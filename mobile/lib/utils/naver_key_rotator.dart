import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/config.dart'; // AppConfig 가져오기

class _KeyPair {
  final String id;
  final String secret;
  _KeyPair(this.id, this.secret);
}

class NaverSearchKeyRotator {
  static const _prefsIndexKey = 'naver_search_key_index';
  static const _prefsCooldownPrefix = 'naver_search_key_cooldown_'; // + index

  static final NaverSearchKeyRotator instance = NaverSearchKeyRotator._();
  NaverSearchKeyRotator._();

  final List<_KeyPair> _keys = [
    _KeyPair(AppConfig.NAVER_APP_SEARCH_CLIENT_ID_1, AppConfig.NAVER_APP_SEARCH_CLIENT_SECRET_1),
    _KeyPair(AppConfig.NAVER_APP_SEARCH_CLIENT_ID_2, AppConfig.NAVER_APP_SEARCH_CLIENT_SECRET_2),
    _KeyPair(AppConfig.NAVER_APP_SEARCH_CLIENT_ID_3, AppConfig.NAVER_APP_SEARCH_CLIENT_SECRET_3),
    _KeyPair(AppConfig.NAVER_APP_SEARCH_CLIENT_ID_4, AppConfig.NAVER_APP_SEARCH_CLIENT_SECRET_4),
    _KeyPair(AppConfig.NAVER_APP_SEARCH_CLIENT_ID_5, AppConfig.NAVER_APP_SEARCH_CLIENT_SECRET_5),
    _KeyPair(AppConfig.NAVER_APP_SEARCH_CLIENT_ID_6, AppConfig.NAVER_APP_SEARCH_CLIENT_SECRET_6),
    _KeyPair(AppConfig.NAVER_APP_SEARCH_CLIENT_ID_7, AppConfig.NAVER_APP_SEARCH_CLIENT_SECRET_7),
    _KeyPair(AppConfig.NAVER_APP_SEARCH_CLIENT_ID_8, AppConfig.NAVER_APP_SEARCH_CLIENT_SECRET_8),
    _KeyPair(AppConfig.NAVER_APP_SEARCH_CLIENT_ID_9, AppConfig.NAVER_APP_SEARCH_CLIENT_SECRET_9),
    _KeyPair(AppConfig.NAVER_APP_SEARCH_CLIENT_ID_10, AppConfig.NAVER_APP_SEARCH_CLIENT_SECRET_10),
    _KeyPair(AppConfig.NAVER_APP_SEARCH_CLIENT_ID_11, AppConfig.NAVER_APP_SEARCH_CLIENT_SECRET_11),
    _KeyPair(AppConfig.NAVER_APP_SEARCH_CLIENT_ID_12, AppConfig.NAVER_APP_SEARCH_CLIENT_SECRET_12),
    _KeyPair(AppConfig.NAVER_APP_SEARCH_CLIENT_ID_13, AppConfig.NAVER_APP_SEARCH_CLIENT_SECRET_13),
    _KeyPair(AppConfig.NAVER_APP_SEARCH_CLIENT_ID_14, AppConfig.NAVER_APP_SEARCH_CLIENT_SECRET_14),
    _KeyPair(AppConfig.NAVER_APP_SEARCH_CLIENT_ID_15, AppConfig.NAVER_APP_SEARCH_CLIENT_SECRET_15),
    _KeyPair(AppConfig.NAVER_APP_SEARCH_CLIENT_ID_16, AppConfig.NAVER_APP_SEARCH_CLIENT_SECRET_16),
    _KeyPair(AppConfig.NAVER_APP_SEARCH_CLIENT_ID_17, AppConfig.NAVER_APP_SEARCH_CLIENT_SECRET_17),
  ];

  int _index = 0;
  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
    _index = _prefs!.getInt(_prefsIndexKey) ?? 0;
    if (_index < 0 || _index >= _keys.length) _index = 0;
  }

  Future<void> _saveIndex() async {
    await _prefs?.setInt(_prefsIndexKey, _index);
  }

  Future<void> _setCooldown(int idx, Duration dur) async {
    final until = DateTime.now().millisecondsSinceEpoch + dur.inMilliseconds;
    await _prefs?.setInt('$_prefsCooldownPrefix$idx', until);
  }

  bool _isOnCooldown(int idx) {
    final until = _prefs?.getInt('$_prefsCooldownPrefix$idx');
    if (until == null) return false;
    return DateTime.now().millisecondsSinceEpoch < until;
  }


  Map<String, String> _headersFor(int idx) {
    final k = _keys[idx];
    return {
      'X-Naver-Client-Id': k.id,
      'X-Naver-Client-Secret': k.secret,
    };
  }

  /// 네이버 Local Search 요청을 키 로테이션/쿨다운/재시도로 감싸서 실행
  /// [request] : headers를 받아 http.Response를 리턴하는 콜백
  Future<http.Response> runWithRotation(
      Future<http.Response> Function(Map<String, String> headers) request, {
        int maxTriesPerCall = 17, // 키 전체 1바퀴
        Duration baseBackoff = const Duration(milliseconds: 300),
      }) async {
    await init();

    int tries = 0;

    while (tries < maxTriesPerCall) {
      final idx = (_index + tries) % _keys.length;

      // 쿨다운이면 스킵
      if (_isOnCooldown(idx)) {
        tries++;
        continue;
      }

      final headers = _headersFor(idx);
      try {
        final resp = await request(headers);

        if (resp.statusCode == 200) {
          // 성공 → 다음 키로 인덱스 이동(라운드로빈)
          _index = (idx + 1) % _keys.length;
          await _saveIndex();
          return resp;
        }

        if (resp.statusCode == 429) {
          // 할당량 초과 → Retry-After 또는 기본 5분 쿨다운
          final retryAfter = resp.headers['retry-after'];
          Duration cd = const Duration(minutes: 5);
          if (retryAfter != null) {
            final secs = int.tryParse(retryAfter);
            if (secs != null && secs > 0) cd = Duration(seconds: secs);
          }
          await _setCooldown(idx, cd);
          tries++;
          // 다음 키로 계속
          continue;
        }

        if (resp.statusCode == 401 || resp.statusCode == 403) {
          // 키 문제 → 길게 쿨다운(1시간)
          await _setCooldown(idx, const Duration(hours: 1));
          tries++;
          continue;
        }

        if (resp.statusCode >= 500) {
          // 서버 불안정 → 짧은 쿨다운 후 다음 키
          await _setCooldown(idx, const Duration(minutes: 1));
          tries++;
          // 지수 백오프(살짝)
          final delay = baseBackoff * (1 << (tries.clamp(0, 4)));
          await Future.delayed(delay);
          continue;
        }

        // 그 외 4xx는 그냥 오류 반환
        return resp;
      } catch (_) {
        // 네트워크 예외 → 다음 키, 짧은 백오프
        await _setCooldown(idx, const Duration(seconds: 10));
        tries++;
        final delay = baseBackoff * (1 << (tries.clamp(0, 4)));
        await Future.delayed(delay);
      }
    }

    // 전부 실패
    throw Exception('일시적으로 사용 불가합니다. 잠시 후 다시 시도해주세요.');
  }
}
