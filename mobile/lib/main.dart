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
 *  - .env는 런타임에서 읽히므로 "절대적인" 보안 저장소가 아님.
 *    서버 비밀키/토큰은 넣지 말 것. (클라이언트 공개 키/ID 정도만 허용)
 *  - 안드로이드/ iOS 빌드 시 .env 파일이 포함될 수 있으니, 민감정보는 백엔드를 통해 주고받는 구조 권장.
 */

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';         // .env 환경변수 로드
import 'package:flutter_naver_map/flutter_naver_map.dart';   // 네이버 지도 SDK 플러그인
import 'package:flutter_screenutil/flutter_screenutil.dart'; // 반응형 사이즈/폰트 유틸

import 'package:mobile/config/config.dart';      // AppConfig: .env를 읽어 상수로 노출
import 'package:mobile/const/colors.dart';       // PRIMARY_COLOR 등 앱 공통 컬러
import 'package:mobile/screens/main_screen.dart';// 앱 루트 화면

// 비동기 초기화가 필요하므로 main을 async로 선언
Future<void> main() async {
  // 플러그인 채널 바인딩. runApp 이전에 비동기 초기화(예: dotenv, 지도 SDK)를 안전하게 수행하기 위해 필요
  WidgetsFlutterBinding.ensureInitialized();

  // 1) .env 로드
  // - pubspec.yaml의 assets에 .env 등록되어 있어야 함.
  // - 예:
  //   flutter:
  //     assets:
  //       - .env
  await dotenv.load(fileName: ".env");

  // 2) Naver Map SDK 초기화
  // - clientId는 AppConfig에서 가져옴(AppConfig가 .env를 읽어 제공)
  // - onAuthFailed는 배포용에서 불필요한 콘솔 로그를 남기지 않도록 비워둠
  await FlutterNaverMap().init(
    clientId: AppConfig.NAVER_MAP_CLIENT_ID,
    onAuthFailed: (_) {}, // 배포: 로깅/예외 토스트 등 UI 노이즈 최소화(필요시 Sentry 등으로 전환)
  );

  // 3) Flutter 앱 실행
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
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
          // 릴리즈에서 디버그 배너 제거
          debugShowCheckedModeBanner: false,
          title: 'Review Schedule',

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
            primaryColor: PRIMARY_COLOR,

            // ColorScheme: 시드 기반. primary 등 핵심 톤이 일관되게 파생됨
            colorScheme: ColorScheme.fromSeed(
              seedColor: PRIMARY_COLOR,
              primary: PRIMARY_COLOR,
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
      child: const MainScreen(),
    );
  }
}
