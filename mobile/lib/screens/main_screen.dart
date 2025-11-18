import 'package:flutter/material.dart';
import 'package:mobile/screens/home_screen.dart';
import 'package:mobile/screens/map_screen.dart';
import 'package:mobile/screens/notification_screen.dart';
import 'package:mobile/screens/profile_screen.dart';
import 'package:mobile/screens/auth/login_screen.dart';
import 'package:mobile/widgets/friendly.dart';
import 'package:mobile/widgets/auth_required_dialog.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile/providers/location_provider.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/services/version_service.dart';
import 'package:mobile/widgets/update_dialog.dart';


// import '../widgets/exit_reward_dialog.dart';
// import '../ads/rewarded_ad_service.dart';


/// MainScreen
/// ------------------------------------------------------
/// 하단 탭 내비게이션 컨테이너.
/// - 탭: 홈 / 지도 / 알림 / 내정보
/// - 상태 보존: IndexedStack 사용 → 탭 전환 시 각 화면의 상태(스크롤, 지도 컨트롤러 등) 유지
/// - 인증 체크: 알림/내정보 탭은 회원만 접근 가능
class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  /// 현재 선택된 탭 인덱스
  int _selectedIndex = 0;

  /// 이 세션(앱 실행 동안)에서 업데이트 체크를 이미 했는지
  bool _didCheckUpdateOnce = false;

  /// 버전 체크 서비스
  final _versionService = VersionService();

  /// 탭별 루트 화면
  /// - const 생성자로 만들어 불필요한 리빌드 방지
  late List<Widget?> _tabs;

  bool _isTablet(BuildContext context) =>
      MediaQuery.of(context).size.shortestSide >= 600;


  @override
  void initState() {
    super.initState();
    // 디버그 포함: 첫 프레임 이후, 홈 탭일 때 1회만 업데이트 체크
    // 리워드 광고 미리 로드 (비활성화)
    // RewardedAdService().loadAd();

    // 앱 시작 시 권한/위치 초기화 및 인증 상태 체크
    Future.microtask(() async{
      await ref.read(locationProvider.notifier).update();
      await ref.read(authProvider.notifier).checkAuthStatus();
    });

    _tabs = [
      const HomeScreen(),
      null, // MapScreen은 아직 생성하지 않음 → 권한 팝업 안뜸
      null, // NotificationScreen도 lazy loading
      null, // ProfileScreen도 lazy loading
    ];

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeCheckUpdateOnFirstHome();
    });
  }

  /// 하단탭 탭 이벤트 핸들러
  void _onItemTapped(int index) async {
    if (_selectedIndex == index) return; // 같은 탭 재터치 시 무시(깜빡임 방지)

    // 알림(2) 또는 내정보(3) 탭 클릭 시 인증 체크
    if (index == 2 || index == 3) {
      final authState = ref.read(authProvider);

      // 일반 회원이 아니면 (비회원 또는 익명 사용자)
      if (!authState.isRegularUser) {
        final confirmed = await AuthRequiredDialog.show(context);

        if (confirmed == true && mounted) {
          // 로그인 화면으로 이동
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => const LoginScreen(),
            ),
          );
        }
        return; // 탭 전환하지 않음
      }
    }

    setState(() {
      _selectedIndex = index;

      // Lazy loading
      if (index == 1 && _tabs[1] == null) {
        _tabs[1] = const MapScreen();
      }
      if (index == 2 && _tabs[2] == null) {
        _tabs[2] = const NotificationScreen();
      }
      if (index == 3 && _tabs[3] == null) {
        _tabs[3] = const ProfileScreen();
      }
    });

    // 탭 전환 시에는 업데이트 체크 트리거 금지 (홈 초회만)
  }

  /// 뒤로가기 버튼 처리 (리워드 광고 비활성화)
  Future<bool> _onWillPop() async {
    // 홈 탭이 아니면 홈으로 이동
    if (_selectedIndex != 0) {
      setState(() => _selectedIndex = 0);
      return false;
    }

    // 홈 탭에서 뒤로가기 시 바로 종료
    return true;

    // 리워드 광고 다이얼로그 표시 (비활성화)
    // final shouldExit = await ExitRewardDialog.show(
    //   context,
    //   onRewardEarned: () {
    //     // 보상 지급 로직 (예: 프리미엄 정보 해제, 쿠폰 지급 등)
    //     debugPrint('🎁 사용자가 리워드를 획득했습니다!');
    //   },
    // );
    // return shouldExit ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final bool isTab = _isTablet(context);
    final double maxScale = isTab ? 1.10 : 1.30;

    return ClampTextScale(
      max: maxScale,
      child: PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
      // ✅ IndexedStack: 현재 탭만 보이되, 나머지 탭도 트리에 남아 상태 보존
      body: Column(
        children: [
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: [
                _tabs[0]!,
                _tabs[1] ?? const SizedBox.shrink(),
                _tabs[2] ?? const SizedBox.shrink(),
                _tabs[3] ?? const SizedBox.shrink(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed, // 탭 4개일 때도 안정
        items: [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined, size: (isTab ? 32.0 : 24.0) * (1.0 + (MediaQuery.textScalerOf(context).textScaleFactor - 1.0) * 0.3).clamp(1.0, 1.2)),
            label: '홈'
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.map_outlined, size: (isTab ? 32.0 : 24.0) * (1.0 + (MediaQuery.textScalerOf(context).textScaleFactor - 1.0) * 0.3).clamp(1.0, 1.2)),
            label: '지도'
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.notifications_outlined, size: (isTab ? 32.0 : 24.0) * (1.0 + (MediaQuery.textScalerOf(context).textScaleFactor - 1.0) * 0.3).clamp(1.0, 1.2)),
            label: '알림'
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline, size: (isTab ? 32.0 : 24.0) * (1.0 + (MediaQuery.textScalerOf(context).textScaleFactor - 1.0) * 0.3).clamp(1.0, 1.2)),
            label: '내정보'
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Theme.of(context).primaryColor,
        onTap: _onItemTapped,
        showUnselectedLabels: true,

        // 📌 폰트 배율에 따른 동적 크기 조정
        iconSize: (isTab ? 32.0 : 24.0) * (1.0 + (MediaQuery.textScalerOf(context).textScaleFactor - 1.0) * 0.3).clamp(1.0, 1.2),
        selectedFontSize: (isTab ? 25.0 : 12.0) * (1.0 + (MediaQuery.textScalerOf(context).textScaleFactor - 1.0) * 0.5).clamp(1.0, 1.3),
        unselectedFontSize: (isTab ? 25.0 : 12.0) * (1.0 + (MediaQuery.textScalerOf(context).textScaleFactor - 1.0) * 0.5).clamp(1.0, 1.3),
      ),
      ),
    ),
    );
  }

  // ----------------------------------------------------------
  // App Store에서 최신 버전 조회 → 새 버전이면 배너/스낵바로 안내
  // ----------------------------------------------------------
  void _maybeCheckUpdateOnFirstHome() {
    if (_selectedIndex != 0) return; // 홈 탭이 아닐 때 무시
    if (_didCheckUpdateOnce) return; // 세션당 1회만
    _didCheckUpdateOnce = true;
    _checkAppVersion();
  }

  /// 백엔드 API를 통한 버전 체크
  ///
  /// - iOS와 Android 모두 지원
  /// - 서버에서 플랫폼별 최신 버전 정보 관리
  /// - 강제 업데이트 또는 선택적 업데이트 다이얼로그 표시
  Future<void> _checkAppVersion() async {
    try {
      final result = await _versionService.checkVersion();

      // 업데이트가 필요한 경우 다이얼로그 표시
      if (result.needsUpdate && mounted) {
        await UpdateDialog.show(context, result);
      }
    } catch (e) {
      // 버전 체크 실패 시 조용히 무시 (네트워크 이슈 등)
      debugPrint('Version check failed: $e');
    }
  }
}
