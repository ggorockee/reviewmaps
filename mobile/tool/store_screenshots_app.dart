// 스토어 스크린샷 캡처 전용 진입점 (배포 빌드에 포함되지 않음)
// - 캠페인·지도는 운영 API의 실제 데이터를 그대로 보여준다
// - 위치는 성수역으로 고정, 광고는 끈다
// - 로그인해야 보이는 키워드·알림 화면만 예시 키워드를 쓰고, 알림 항목은 실제 캠페인으로 채운다
// 실행: python3 tool/capture_screenshots.py <UDID> <phone|tablet>
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile/config/config.dart';
import 'package:mobile/const/colors.dart';
import 'package:mobile/models/keyword_models.dart';
import 'package:mobile/models/release_note.dart';
import 'package:mobile/models/store_model.dart';
import 'package:mobile/providers/location_provider.dart';
import 'package:mobile/screens/campaign_list_screen.dart';
import 'package:mobile/screens/home_screen.dart';
import 'package:mobile/screens/map_screen.dart';
import 'package:mobile/screens/notification_screen.dart';
import 'package:mobile/services/campaign_service.dart';
import 'package:mobile/services/fcm_service.dart';
import 'package:mobile/services/keyword_service.dart';
import 'package:mobile/services/release_note_service.dart';
import 'package:mobile/services/remote_config_service.dart';
import 'package:mobile/utils/stay_availability.dart';
import 'package:mobile/widgets/friendly.dart';
import 'package:mobile/widgets/release_note_card.dart';
import 'package:mobile/widgets/stay_availability_badge.dart';

final ValueNotifier<String> _activeSlide = ValueNotifier<String>('01_map');

/// 업데이트 안내 카드에 넣을 설명 그림 영역
final GlobalKey _noteImageKey = GlobalKey();

/// 화면에 난 오류. 캡처 스크립트가 /errors 로 확인하고 하나라도 있으면 중단한다
final List<String> _errors = [];

const double _seongsuLat = 37.5445;
const double _seongsuLng = 127.0560;
const int _stayCategoryId = 3;

/// 예시 키워드. 알림 기록은 제목에 키워드가 들어간 실제 캠페인으로 만든다
const List<String> _keywords = ['성수', '강남', '풀빌라', '홍대', '오마카세'];

final Position _demoPosition = Position(
  latitude: _seongsuLat,
  longitude: _seongsuLng,
  timestamp: DateTime.now(),
  accuracy: 5,
  altitude: 20,
  altitudeAccuracy: 5,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

class _DemoLocationNotifier extends LocationNotifier {
  @override
  LocationState build() => LocationState(
    permission: LocationPermission.always,
    position: _demoPosition,
  );

  @override
  Future<void> update() async {
    state = LocationState(
      permission: LocationPermission.always,
      position: _demoPosition,
    );
  }
}

class _NoopFcmService implements FcmService {
  @override
  String? get currentToken => 'demo-token';

  @override
  bool get isInitialized => true;

  @override
  void addNotificationListener(OnNotificationReceived listener) {}

  @override
  void removeNotificationListener(OnNotificationReceived listener) {}

  @override
  Future<void> initialize() async {}

  @override
  Future<void> refreshToken() async {}

  @override
  Future<void> unregisterToken() async {}
}

class _DemoKeywordService implements KeywordService {
  final List<AlertInfo> alerts;

  _DemoKeywordService(this.alerts);

  @override
  String get baseUrl => '';

  @override
  void dispose() {}

  KeywordInfo _info(int id, String keyword) =>
      KeywordInfo(id: id, keyword: keyword, isActive: true, createdAt: DateTime.now().toIso8601String());

  @override
  Future<List<KeywordInfo>> getMyKeywords() async => [
    for (final (i, k) in _keywords.indexed) _info(i + 1, k),
  ];

  @override
  Future<AlertListResponse> getMyAlerts({
    bool? isRead,
    double? lat,
    double? lng,
    String sort = 'created_at',
  }) async => AlertListResponse(
    items: alerts,
    total: alerts.length,
    page: 1,
    limit: 20,
    totalPages: 1,
  );

  @override
  Future<KeywordInfo> registerKeyword(String keyword) async => _info(99, keyword);

  @override
  Future<void> deleteKeyword(int keywordId) async {}

  @override
  Future<void> deleteAlert(int alertId) async {}

  @override
  Future<void> markAlertsAsRead(List<int> alertIds) async {}

  @override
  Future<KeywordInfo> toggleKeyword(int keywordId) async => _info(keywordId, _keywords.first);

  @override
  Future<void> registerFcmToken(String fcmToken, String deviceType) async {}

  @override
  Future<void> unregisterFcmToken(String fcmToken) async {}
}

double? _distanceKm(Store s) => (s.lat == null || s.lng == null)
    ? null
    : Geolocator.distanceBetween(_seongsuLat, _seongsuLng, s.lat!, s.lng!) / 1000;

/// 실제 캠페인으로 알림 기록 예시를 만든다 (키워드마다 최대 1건)
Future<List<AlertInfo>> _buildAlerts(CampaignService service) async {
  final now = DateTime.now();
  final alerts = <AlertInfo>[];
  for (final (i, keyword) in _keywords.indexed) {
    final found = await service.searchCampaigns(query: keyword, limit: 50);
    final store = found
        .where((s) => s.title.contains(keyword) && s.lat != null && (s.offer ?? '').isNotEmpty)
        .firstOrNull;
    if (store == null) continue;
    alerts.add(
      AlertInfo(
        id: 500 + i,
        keyword: keyword,
        campaignId: store.id,
        campaignTitle: store.title,
        campaignCompany: store.title,
        campaignOffer: store.offer,
        campaignPlatform: store.platform,
        campaignApplyDeadline: store.applyDeadline,
        campaignContentLink: store.contentLink,
        campaignChannel: store.campaignChannel,
        campaignCategoryId: store.categoryId,
        campaignPossibleDays: store.possibleDays,
        campaignImpossibleDays: store.impossibleDays,
        matchedField: 'title',
        isRead: i >= 3,
        createdAt: now.subtract(Duration(hours: 2 + i * 3)).toIso8601String(),
        distance: _distanceKm(store),
      ),
    );
  }
  return alerts;
}

/// 숙박 목록: 앱이 요일 배지를 보여주는 공고만, 요일 띠(월~일)가 있는 것을 앞에 둔다
Future<List<Store>> _loadStayStores(CampaignService service) async {
  final stores = await service.fetchInBounds(
    south: 33.0,
    west: 124.0,
    north: 39.0,
    east: 132.0,
    categoryId: _stayCategoryId,
    limit: 200,
  );
  final badged = stores.where((s) => s.stayAvailability != null).toList();
  final strip = badged.where((s) => s.stayAvailability!.hasExplicitDays).toList();
  debugPrint('[capture] 숙박 ${stores.length}건, 요일 배지 ${badged.length}건 (요일 띠 ${strip.length}건)');
  if (badged.isEmpty) throw StateError('요일 배지가 보이는 숙박 공고가 없어 4번 화면을 만들 수 없음');
  return [...strip, ...badged.where((s) => !strip.contains(s))]
      .map((s) => s.copyWith(distance: _distanceKm(s)))
      .toList();
}

Future<void> _startControlServer() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 18941, shared: true);
  server.listen((HttpRequest req) async {
    final segs = req.uri.pathSegments;
    if (segs.length == 1 && segs[0] == 'errors') {
      req.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(_errors));
      await req.response.close();
      return;
    }
    if (segs.length == 1 && segs[0] == 'note.png') {
      final boundary = _noteImageKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      req.response
        ..headers.contentType = ContentType('image', 'png')
        ..add(png!.buffer.asUint8List());
      await req.response.close();
      return;
    }
    if (segs.length >= 2 && segs[0] == 'slide') {
      _activeSlide.value = segs[1];
    }
    req.response
      ..statusCode = 200
      ..write('ok:${_activeSlide.value}');
    await req.response.close();
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  RemoteConfigService().disableAdsForScreenshots = true;
  final present = FlutterError.onError;
  FlutterError.onError = (details) {
    final stack = details.stack.toString().split('\n').take(25).join('\n');
    _errors.add('[${_activeSlide.value}] ${details.exceptionAsString()}\n${details.context}\n$stack');
    present?.call(details);
  };

  // 광고·분석 위젯이 Firebase를 쓰므로 초기화하되, 캡처 실행이 운영 통계에 섞이지 않게 수집은 끈다
  await Firebase.initializeApp();
  await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(false);
  await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(false);

  await dotenv.load(fileName: '.env');
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('auto_show_nearest', true);
  await prefs.setBool('first_run_done', true);

  await FlutterNaverMap().init(
    clientId: AppConfig.naverMapClientId,
    onAuthFailed: (e) => debugPrint('[capture] 네이버 지도 인증 실패: $e'),
  );

  final service = CampaignService(AppConfig.reviewMapBaseUrl, apiKey: AppConfig.reviewMapApiKey);
  final alerts = await _buildAlerts(service);
  final stayStores = await _loadStayStores(service);

  await _startControlServer();

  // 화면을 바꿀 때마다 트리 전체를 새로 만든다 (이전 화면 상태가 섞이지 않게)
  runApp(
    ValueListenableBuilder<String>(
      valueListenable: _activeSlide,
      builder: (context, slide, _) => ProviderScope(
        key: ValueKey(slide),
        overrides: [
          locationProvider.overrideWith(() => _DemoLocationNotifier()),
          keywordServiceProvider.overrideWithValue(_DemoKeywordService(alerts)),
          fcmServiceProvider.overrideWithValue(_NoopFcmService()),
        ],
        child: _ScreenshotApp(slide: slide, stayStores: stayStores),
      ),
    ),
  );
}

class _ScreenshotApp extends StatelessWidget {
  final String slide;
  final List<Store> stayStores;

  const _ScreenshotApp({required this.slide, required this.stayStores});

  Widget _screen() => switch (slide) {
    '02_feed' => const _Shell(selectedIndex: 0, body: HomeScreen()),
    '03_alerts' => const _Shell(selectedIndex: 2, body: NotificationScreen(initialTabIndex: 1)),
    '04_stay' => _Shell(
      selectedIndex: 0,
      body: CampaignListScreen(
        title: '숙박 체험단',
        initialStores: stayStores,
        userPosition: _demoPosition,
        categoryId: _stayCategoryId,
      ),
    ),
    '05_keywords' => const _Shell(selectedIndex: 2, body: NotificationScreen(initialTabIndex: 0)),
    'note_stay' => const _NoteStayImage(),
    // 업데이트 안내 카드 모양 확인용 (card_after, card_optional, card_force)
    'card_after' => const _CardPreview(ReleaseCardType.afterUpdate),
    'card_optional' => const _CardPreview(ReleaseCardType.optionalUpdate),
    'card_force' => const _CardPreview(ReleaseCardType.forceUpdate),
    _ => const _Shell(selectedIndex: 1, body: MapScreen(autoSearchOnReady: true)),
  };

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(375, 812),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.white,
              elevation: 0,
              scrolledUnderElevation: 0,
            ),
            bottomNavigationBarTheme: const BottomNavigationBarThemeData(
              backgroundColor: Colors.white,
            ),
            primaryColor: primaryColor,
            colorScheme: ColorScheme.fromSeed(
              seedColor: primaryColor,
              primary: primaryColor,
            ),
            scaffoldBackgroundColor: Colors.white,
            useMaterial3: true,
          ),
          builder: (context, widget) {
            final isTab = MediaQuery.of(context).size.shortestSide >= 600;
            return ClampTextScale(
              max: isTab ? 1.15 : 1.30,
              child: widget ?? const SizedBox.shrink(),
            );
          },
          home: _screen(),
        );
      },
    );
  }
}

/// 업데이트 안내 카드의 "이용 가능 요일" 설명 그림. 숙소 이름은 예시이고 배지는 앱의 실제 위젯이다.
class _NoteStayImage extends StatelessWidget {
  const _NoteStayImage();

  static final List<(String, StayAvailability)> _examples = [
    ('예시 · 바다 앞 독채 펜션', StayAvailability.fromDetail(possibleDays: '월 / 화 / 수 / 목 / 일', impossibleDays: '금 / 토')!),
    ('예시 · 숲속 글램핑장', StayAvailability.parse('1박 2일 숙박권 (토요일 제외)')!),
    ('예시 · 마당 있는 한옥', StayAvailability.fromDetail(possibleDays: '화 / 수 / 목 / 금')!),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    body: Center(
      child: RepaintBoundary(
        key: _noteImageKey,
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.2)),
          child: Container(
            width: 300,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFF3F7F5), borderRadius: BorderRadius.circular(20)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (name, availability) in _examples)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.black87)),
                        const SizedBox(height: 8),
                        StayAvailabilityBadge(availability: availability, showDayStrip: true),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// 앱에 든 안내 내용으로 카드를 그대로 그린다
class _CardPreview extends StatelessWidget {
  const _CardPreview(this.type);

  final ReleaseCardType type;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      const _Shell(selectedIndex: 0, body: HomeScreen()),
      const ModalBarrier(color: Colors.black54, dismissible: false),
      FutureBuilder<String>(
        future: rootBundle.loadString(ReleaseNoteService.assetPath),
        builder: (context, snapshot) => snapshot.hasData
            ? ReleaseNoteCard(note: ReleaseNote.tryParse(snapshot.data!)!, type: type)
            : const SizedBox.shrink(),
      ),
    ],
  );
}

class _Shell extends StatelessWidget {
  final int selectedIndex;
  final Widget body;

  const _Shell({
    required this.selectedIndex,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final bool isTab = MediaQuery.of(context).size.shortestSide >= 600;
    return Scaffold(
      body: body,
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        items: [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined, size: isTab ? 30.0 : 24.0),
            label: '홈',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.map_outlined, size: isTab ? 30.0 : 24.0),
            label: '지도',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.notifications_outlined, size: isTab ? 30.0 : 24.0),
            label: '알림',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline, size: isTab ? 30.0 : 24.0),
            label: '내정보',
          ),
        ],
        currentIndex: selectedIndex,
        selectedItemColor: primaryColor,
        showUnselectedLabels: true,
        iconSize: isTab ? 30.0 : 24.0,
        selectedFontSize: isTab ? 16.0 : 12.0,
        unselectedFontSize: isTab ? 16.0 : 12.0,
      ),
    );
  }
}
