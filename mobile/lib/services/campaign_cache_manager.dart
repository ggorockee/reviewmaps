import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile/config/config.dart';
import 'package:mobile/models/store_model.dart';
import 'package:mobile/services/campaign_service.dart';

/// 캠페인 데이터 캐시 매니저
/// - 싱글톤 패턴으로 앱 전역에서 캐시 공유
/// - 스플래시 화면에서 프리로딩하여 홈 화면 즉시 표시
/// - TTL 기반 캐시 만료 관리
class CampaignCacheManager {
  static final CampaignCacheManager _instance = CampaignCacheManager._internal();
  static CampaignCacheManager get instance => _instance;

  CampaignCacheManager._internal();

  final CampaignService _campaignService = CampaignService(
    AppConfig.reviewMapBaseUrl,
    apiKey: AppConfig.reviewMapApiKey,
  );

  // 캐시 데이터
  List<Store>? _recommendedCache;
  List<Store>? _nearestCache;
  Position? _cachedPosition;

  // 캐시 타임스탬프
  DateTime? _recommendedCacheTime;
  DateTime? _nearestCacheTime;

  // 캐시 TTL (분)
  static const int _recommendedCacheTtlMinutes = 5;
  static const int _nearestCacheTtlMinutes = 3;

  // 로딩 상태 (중복 요청 방지)
  Completer<List<Store>>? _recommendedLoadingCompleter;
  Completer<List<Store>>? _nearestLoadingCompleter;

  // 프리로드 완료 여부
  bool _isPreloadComplete = false;
  bool get isPreloadComplete => _isPreloadComplete;

  // 가까운 캠페인 프리로드 완료 여부
  bool _isNearestPreloadComplete = false;
  bool get isNearestPreloadComplete => _isNearestPreloadComplete;

  /// 추천 캠페인 프리로드 (스플래시에서 호출)
  /// 백그라운드에서 데이터를 미리 로드하여 캐시에 저장
  Future<void> preloadRecommended({int limit = 20}) async {
    try {
      debugPrint('[CacheManager] 추천 캠페인 프리로드 시작...');
      final stopwatch = Stopwatch()..start();

      // 이미 로딩 중이면 기다림
      if (_recommendedLoadingCompleter != null) {
        await _recommendedLoadingCompleter!.future;
        return;
      }

      // 캐시가 유효하면 스킵
      if (_isRecommendedCacheValid()) {
        debugPrint('[CacheManager] 캐시 유효 - 프리로드 스킵');
        _isPreloadComplete = true;
        return;
      }

      _recommendedLoadingCompleter = Completer<List<Store>>();

      final data = await _campaignService.fetchPage(
        limit: limit,
        offset: 0,
        sort: '-created_at',
      );

      // 셔플하여 다양성 확보
      data.shuffle();

      _recommendedCache = data;
      _recommendedCacheTime = DateTime.now();
      _isPreloadComplete = true;

      _recommendedLoadingCompleter!.complete(data);
      _recommendedLoadingCompleter = null;

      stopwatch.stop();
      debugPrint('[CacheManager] 프리로드 완료: ${data.length}개, ${stopwatch.elapsedMilliseconds}ms');
    } catch (e) {
      debugPrint('[CacheManager] 프리로드 실패: $e');
      _recommendedLoadingCompleter?.completeError(e);
      _recommendedLoadingCompleter = null;
      // 실패해도 앱 실행에 영향 없음
    }
  }

  /// 추천 캠페인 가져오기 (캐시 우선)
  Future<List<Store>> getRecommended({
    int limit = 20,
    bool forceRefresh = false,
  }) async {
    // 강제 새로고침이 아니고 캐시가 유효하면 캐시 반환
    if (!forceRefresh && _isRecommendedCacheValid()) {
      debugPrint('[CacheManager] 캐시 히트 - 추천 캠페인');
      return List.from(_recommendedCache!);
    }

    // 이미 로딩 중이면 기다림
    if (_recommendedLoadingCompleter != null) {
      return await _recommendedLoadingCompleter!.future;
    }

    _recommendedLoadingCompleter = Completer<List<Store>>();

    try {
      final data = await _campaignService.fetchPage(
        limit: limit,
        offset: 0,
        sort: '-created_at',
      );

      data.shuffle();

      _recommendedCache = data;
      _recommendedCacheTime = DateTime.now();

      _recommendedLoadingCompleter!.complete(data);
      return data;
    } catch (e) {
      _recommendedLoadingCompleter!.completeError(e);
      rethrow;
    } finally {
      _recommendedLoadingCompleter = null;
    }
  }

  /// 가까운 캠페인 가져오기 (캐시 우선)
  Future<List<Store>> getNearest({
    required double lat,
    required double lng,
    int limit = 10,
    bool forceRefresh = false,
  }) async {
    // 강제 새로고침이 아니고 캐시가 유효하면 캐시 반환
    if (!forceRefresh && _isNearestCacheValid(lat, lng)) {
      debugPrint('[CacheManager] 캐시 히트 - 가까운 캠페인');
      return List.from(_nearestCache!);
    }

    // 이미 로딩 중이면 기다림
    if (_nearestLoadingCompleter != null) {
      return await _nearestLoadingCompleter!.future;
    }

    _nearestLoadingCompleter = Completer<List<Store>>();

    try {
      final data = await _campaignService.fetchNearest(
        lat: lat,
        lng: lng,
        limit: limit,
      );

      _nearestCache = data;
      _nearestCacheTime = DateTime.now();
      _cachedPosition = Position(
        latitude: lat,
        longitude: lng,
        timestamp: DateTime.now(),
        accuracy: 0,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );

      _nearestLoadingCompleter!.complete(data);
      return data;
    } catch (e) {
      _nearestLoadingCompleter!.completeError(e);
      rethrow;
    } finally {
      _nearestLoadingCompleter = null;
    }
  }

  /// 캐시된 추천 캠페인 즉시 반환 (null 가능)
  List<Store>? getCachedRecommended() {
    if (_isRecommendedCacheValid()) {
      return List.from(_recommendedCache!);
    }
    return null;
  }

  /// 캐시된 가까운 캠페인 즉시 반환 (null 가능)
  List<Store>? getCachedNearest() {
    if (_nearestCache != null && _nearestCacheTime != null) {
      final age = DateTime.now().difference(_nearestCacheTime!);
      if (age.inMinutes < _nearestCacheTtlMinutes) {
        return List.from(_nearestCache!);
      }
    }
    return null;
  }

  /// 추천 캐시 유효성 검사
  bool _isRecommendedCacheValid() {
    if (_recommendedCache == null || _recommendedCacheTime == null) {
      return false;
    }
    final age = DateTime.now().difference(_recommendedCacheTime!);
    return age.inMinutes < _recommendedCacheTtlMinutes;
  }

  /// 가까운 캐시 유효성 검사 (위치 변화 고려)
  bool _isNearestCacheValid(double lat, double lng) {
    if (_nearestCache == null || _nearestCacheTime == null || _cachedPosition == null) {
      return false;
    }

    // 시간 체크
    final age = DateTime.now().difference(_nearestCacheTime!);
    if (age.inMinutes >= _nearestCacheTtlMinutes) {
      return false;
    }

    // 위치 변화 체크 (500m 이상 이동하면 무효화)
    final distance = Geolocator.distanceBetween(
      _cachedPosition!.latitude,
      _cachedPosition!.longitude,
      lat,
      lng,
    );
    return distance < 500;
  }

  /// 캐시 무효화 (수동 새로고침 시)
  void invalidateRecommended() {
    _recommendedCache = null;
    _recommendedCacheTime = null;
    debugPrint('[CacheManager] 추천 캐시 무효화');
  }

  void invalidateNearest() {
    _nearestCache = null;
    _nearestCacheTime = null;
    _cachedPosition = null;
    debugPrint('[CacheManager] 가까운 캐시 무효화');
  }

  void invalidateAll() {
    invalidateRecommended();
    invalidateNearest();
  }

  /// 추가 페이지 로드 (무한 스크롤용)
  Future<List<Store>> fetchMoreRecommended({
    required int offset,
    int limit = 20,
  }) async {
    return await _campaignService.fetchPage(
      limit: limit,
      offset: offset,
      sort: '-created_at',
    );
  }

  /// 가까운 캠페인 프리로드 (스플래시에서 호출)
  /// 위치 권한이 있는 경우에만 백그라운드에서 미리 로드
  Future<void> preloadNearest({int limit = 10}) async {
    try {
      debugPrint('[CacheManager] 가까운 캠페인 프리로드 시작...');
      final stopwatch = Stopwatch()..start();

      // 이미 로딩 중이면 기다림
      if (_nearestLoadingCompleter != null) {
        await _nearestLoadingCompleter!.future;
        return;
      }

      // 캐시가 유효하면 스킵
      if (_nearestCache != null && _nearestCacheTime != null) {
        final age = DateTime.now().difference(_nearestCacheTime!);
        if (age.inMinutes < _nearestCacheTtlMinutes) {
          debugPrint('[CacheManager] 가까운 캐시 유효 - 프리로드 스킵');
          _isNearestPreloadComplete = true;
          return;
        }
      }

      // 위치 권한 확인
      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        debugPrint('[CacheManager] 위치 권한 없음 - 프리로드 스킵');
        return;
      }

      // 위치 서비스 확인
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('[CacheManager] 위치 서비스 비활성화 - 프리로드 스킵');
        return;
      }

      _nearestLoadingCompleter = Completer<List<Store>>();

      // 마지막 알려진 위치 우선 사용 (빠른 응답)
      Position? position = await Geolocator.getLastKnownPosition();

      // 캐시된 위치가 없으면 현재 위치 가져오기 (타임아웃 3초)
      position ??= await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium, // 빠른 응답을 위해 medium 사용
        ),
      ).timeout(
        const Duration(seconds: 3),
        onTimeout: () => throw Exception('위치 조회 타임아웃'),
      );

      final data = await _campaignService.fetchNearest(
        lat: position.latitude,
        lng: position.longitude,
        limit: limit,
      );

      _nearestCache = data;
      _nearestCacheTime = DateTime.now();
      _cachedPosition = position;
      _isNearestPreloadComplete = true;

      _nearestLoadingCompleter!.complete(data);
      _nearestLoadingCompleter = null;

      stopwatch.stop();
      debugPrint('[CacheManager] 가까운 프리로드 완료: ${data.length}개, ${stopwatch.elapsedMilliseconds}ms');
    } catch (e) {
      debugPrint('[CacheManager] 가까운 프리로드 실패: $e');
      _nearestLoadingCompleter?.completeError(e);
      _nearestLoadingCompleter = null;
      // 실패해도 앱 실행에 영향 없음
    }
  }

  /// 추천 + 가까운 캠페인 병렬 프리로드 (스플래시에서 호출)
  Future<void> preloadAll({int recommendedLimit = 20, int nearestLimit = 10}) async {
    await Future.wait([
      preloadRecommended(limit: recommendedLimit),
      preloadNearest(limit: nearestLimit),
    ]);
  }
}
