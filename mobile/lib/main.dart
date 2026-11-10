/*
 * main.dart
 * --------------------------------------------
 * 앱 엔트리 포인트. 배포(Release) 기준으로 불필요한 로깅/코드 제거.
 * - .env 로드 (flutter_dotenv)
 * - Naver Map SDK 초기화 (FlutterNaverMap)
 * - 화면 대응 유틸(ScreenUtil) 초기화
 * - MaterialApp 테마 및 루트 위젯(MainScreen) 구성
 *
 * 🔐 보안 메모:
 *  - .env는 런타임에서 읽히므로 "절대적인" 보안 저장소가 아님.z  
 *    서버 비밀키/토큰은 넣지 말 것. (클라이언트 공개 키/ID 정도만 허용)
 *  - 안드로이드/ iOS 빌드 시 .env 파일이 포함될 수 있으니, 민감정보는 백엔드를 통해 주고받는 구조 권장.
 */

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';           // kDebugMode 사용을 위해 추가
import 'package:flutter_dotenv/flutter_dotenv.dart';         // .env 환경변수 로드
import 'package:flutter_naver_map/flutter_naver_map.dart';   // 네이버 지도 SDK 플러그인
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart'; // 반응형 사이즈/폰트 유틸

import 'package:mobile/config/config.dart';      // AppConfig: .env를 읽어 상수로 노출
import 'package:mobile/const/colors.dart';       // primaryColor 등 앱 공통 컬러
import 'package:mobile/screens/splash_screen.dart'; // 스플래시 화면
import 'package:mobile/screens/auth/login_screen.dart'; // 로그인 화면
import 'package:mobile/screens/auth/sign_up_screen.dart'; // 회원가입 화면
import 'package:mobile/services/ad_service.dart'; // 광고 서비스
import 'package:mobile/services/app_open_ad_service.dart'; // App Open Ad 서비스
import 'package:mobile/services/interstitial_ad_manager.dart'; // 전면광고 매니저
import 'package:mobile/services/firebase_service.dart'; // Firebase 통합 서비스
import 'package:mobile/services/remote_config_service.dart'; // Firebase Remote Config 서비스
import 'package:mobile/services/fcm_service.dart'; // FCM 푸시 알림 서비스
import 'package:mobile/providers/auth_provider.dart'; // AuthProvider

import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';

/// 글로벌 네비게이터 키 (FCM 알림 탭 등에서 사용)
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// 비동기 초기화가 필요하므로 main을 async로 선언
Future<void> main() async {
  // 플러그인 채널 바인딩. runApp 이전에 비동기 초기화(예: dotenv, 지도 SDK)를 안전하게 수행하기 위해 필요
  WidgetsFlutterBinding.ensureInitialized();

  // 1) Firebase 초기화
  try {
    await Firebase.initializeApp();
    // FCM 백그라운드 메시지 핸들러 등록 (Firebase 초기화 직후 설정)
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  } catch (e) {
    debugPrint('Firebase 초기화 실패: $e');
  }

  // 2) AdMob 초기화
  try {
    await MobileAds.instance.initialize();
    if (kDebugMode) {
      // DEBUG 모드에서는 테스트 광고 강제 사용
      final configuration = RequestConfiguration(
        testDeviceIds: ['d032385e-b579-421a-ae28-2bd485f4b306'],
      );
      MobileAds.instance.updateRequestConfiguration(configuration);
    }
  } catch (e) {
    debugPrint('AdMob 초기화 실패: $e');
  }

  // 3) 광고 서비스 초기화
  try {
    await AdService().initialize();
  } catch (e) {
    debugPrint('광고 서비스 초기화 실패: $e');
  }

  // 4) App Open Ad 서비스 초기화
  try {
    await AppOpenAdService().initialize();
  } catch (e) {
    debugPrint('App Open Ad 초기화 실패: $e');
  }

  // 5) 전면광고 매니저 초기화
  try {
    await InterstitialAdManager().initialize();
  } catch (e) {
    debugPrint('전면광고 매니저 초기화 실패: $e');
  }

  // 6) .env 로드
  // - pubspec.yaml의 assets에 .env 등록되어 있어야 함.
  // - 예:
  //   flutter:
  //     assets:
  //       - .env
  await dotenv.load(fileName: ".env");

  // 7) Kakao SDK 초기화
  try {
    KakaoSdk.init(nativeAppKey: AppConfig.kakaoNativeAppKey);
  } catch (e) {
    debugPrint('Kakao SDK 초기화 실패: $e');
  }

  // 8) Naver Map SDK 초기화
  // - clientId는 AppConfig에서 가져옴(AppConfig가 .env를 읽어 제공)
  // - onAuthFailed는 배포용에서 불필요한 콘솔 로그를 남기지 않도록 비워둠
  await FlutterNaverMap().init(
    clientId: AppConfig.naverMapClientId,
    onAuthFailed: (_) {}, // 배포: 로깅/예외 토스트 등 UI 노이즈 최소화(필요시 Sentry 등으로 전환)
  );

  // 8) Firebase 서비스 초기화
  try {
    await FirebaseService.instance.initialize();

  } catch (e) {
    // Firebase 초기화 실패해도 앱은 계속 실행
    debugPrint('Firebase initialization failed, continuing: $e');
  }

  // 9) Firebase Remote Config 초기화
  try {
    await RemoteConfigService().initialize();
  } catch (e) {
    debugPrint('Firebase Remote Config 초기화 실패: $e');
  }

  // 10) FCM 푸시 알림 서비스 초기화
  // Provider 방식으로 변경하기 위해 runApp 이후로 이동

  // 11) Flutter 앱 실행
  runApp(
    // ProviderScope를 추가하여 앱 전체에서 Riverpod Provider를 사용
    const ProviderScope(
      child: MyApp(),
    )
  );
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  // Phase 6: 로그인 화면 이동 중복 방지 플래그
  bool _isNavigatingToLogin = false;

  @override
  Widget build(BuildContext context) {
    // authProvider 상태 변화 감지: 로그인 만료 시 자동 로그인 화면 이동
    ref.listen<AuthState>(authProvider, (previous, next) {
      // 로그인 상태에서 비로그인 상태로 변경된 경우 (401 에러 발생)
      if (previous != null &&
          previous.isAuthenticated &&
          !next.isAuthenticated) {

        debugPrint('[MyApp] 로그인 만료 감지 - 로그인 화면으로 이동');

        // Phase 6: 이미 로그인 화면 이동 중이면 중복 실행 방지
        if (_isNavigatingToLogin) {
          debugPrint('[MyApp] 로그인 화면 이동 이미 진행 중 - 중복 방지');
          return;
        }

        // 현재 컨텍스트가 유효한지 확인
        final currentContext = navigatorKey.currentContext;
        if (currentContext != null && currentContext.mounted) {
          // 현재 경로 추출 (named route가 있는 경우)
          final currentRoute = ModalRoute.of(currentContext)?.settings.name;

          debugPrint('[MyApp] 현재 경로: $currentRoute');

          // Phase 6: 네비게이션 중복 방지 플래그 설정
          _isNavigatingToLogin = true;

          // 스낵바 표시: "로그인이 만료되었습니다"
          ScaffoldMessenger.of(currentContext).showSnackBar(
            const SnackBar(
              content: Text('로그인이 만료되었습니다. 다시 로그인해 주세요.'),
              duration: Duration(seconds: 3),
              backgroundColor: Colors.red,
            ),
          );

          // 로그인 화면으로 이동 (모든 스택 제거)
          // returnRoute를 전달하여 로그인 성공 후 복귀 가능하도록 함
          Navigator.of(currentContext).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (context) => LoginScreen(
                returnRoute: currentRoute,
              ),
            ),
            (route) => false,
          ).then((_) {
            // Phase 6: 네비게이션 완료 후 플래그 초기화
            _isNavigatingToLogin = false;
          });
        }
      }
    });

    // ScreenUtilInit:
    //  - 디자인 시안 기준 해상도 지정(여기서는 375x812, iPhone X 계열 기준)
    //  - .w/.h/.sp 단위를 통해 다양한 해상도/비율에서 일관된 UI 제공
    return ScreenUtilInit(
      designSize: const Size(375, 812), // 기준 해상도(디자인 시안 픽셀)
      minTextAdapt: true,               // 작은 화면에서 텍스트 자동 축소 허용
      splitScreenMode: true,            // 분할화면/태블릿 등 대응 향상
      // builder 내부에서 MaterialApp을 구성하고, child를 home으로 넘겨 성능/재빌드 최소화
      builder: (context, child) {
        return MaterialApp(
          // 글로벌 네비게이터 키 설정
          navigatorKey: navigatorKey,

          // 릴리즈에서 디버그 배너 제거
          debugShowCheckedModeBanner: false,
          title: 'Review Schedule',

          // 라우팅 설정
          routes: {
            '/login': (context) => const LoginScreen(),
            '/signup': (context) => const SignUpScreen(),
          },

          // 전역 테마
          theme: ThemeData(
            // AppBar: 흰 배경 + 그림자 제거 (스크롤 시 M3 기본 음영도 제거)
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.white,
              elevation: 0,
              scrolledUnderElevation: 0,
            ),

            // BottomNavigationBar: 흰 배경 (아이콘/라벨 컬러는 ColorScheme에 따름)
            bottomNavigationBarTheme: const BottomNavigationBarThemeData(
              backgroundColor: Colors.white,
            ),

            // primaryColor는 M3에서 직접적 사용 빈도 낮지만, 레거시/서드파티 대응 겸 유지
            primaryColor: primaryColor,

            // ColorScheme: 시드 기반. primary 등 핵심 톤이 일관되게 파생됨
            colorScheme: ColorScheme.fromSeed(
              seedColor: primaryColor,
              primary: primaryColor,
            ),

            // Scaffold 기본 배경 흰색
            scaffoldBackgroundColor: Colors.white,

            // Material 3 활성화
            useMaterial3: true,
          ),

          // ScreenUtilInit의 child를 home으로 전달 → 불필요한 재빌드 방지
          home: child,
        );
      },

      // 여기서 루트 위젯을 지정하면, 위 builder의 home으로 전달됨.
      // const로 고정해 불필요한 리빌드를 줄여 성능/배터리 소모 최소화.
      child: const SplashScreen(),
    );
  }
}
