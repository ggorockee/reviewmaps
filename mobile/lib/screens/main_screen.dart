import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/screens/home_screen.dart';
import 'package:mobile/screens/map_screen.dart';
import 'package:mobile/screens/my_page_screen.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:mobile/widgets/friendly.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile/providers/location_provider.dart';


// import '../widgets/exit_reward_dialog.dart';
// import '../ads/rewarded_ad_service.dart';


/// MainScreen
/// ------------------------------------------------------
/// 하단 탭 내비게이션 컨테이너.
/// - 탭: 홈 / 지도 / 내정보
/// - 상태 보존: IndexedStack 사용 → 탭 전환 시 각 화면의 상태(스크롤, 지도 컨트롤러 등) 유지
/// - 배포: 미사용 import/코드 제거, 최소 로직
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

  // 앱 정보
  static const String _iosAppId   = '6751343880';        // App Store Connect의 Apple ID (숫자)
  static const String _bundleId   = 'com.reviewmaps.mobile'; // 네 iOS 번들ID
  static const String _country    = 'kr';                // 스토어 국가코드

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

    // 앱 시작 시 권한/위치 초기화
    Future.microtask(() async{
      await ref.read(locationProvider.notifier).update();
    });

    _tabs = [
      const HomeScreen(),
      null, // MapScreen은 아직 생성하지 않음 → 권한 팝업 안뜸
      const MyPageScreen(),
    ];

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeCheckUpdateOnFirstHome();
    });
  }

  /// 하단탭 탭 이벤트 핸들러
  void _onItemTapped(int index) {
    if (_selectedIndex == index) return; // 같은 탭 재터치 시 무시(깜빡임 방지)
    setState(() {
      _selectedIndex = index;
      if (index == 1 && _tabs[1] == null) {
        _tabs[1] = const MapScreen(); // 여기서 최초 생성 → 자동 권한요청 방지
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
    // 전역 위치 상태 구독 (원한다면)
    final locationState = ref.watch(locationProvider);
    final bool isTab = _isTablet(context);
    final double maxScale = isTab ? 1.10 : 1.30;
    
    return ClampTextScale(
      max: maxScale,
      child: PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
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
                _tabs[2]!,
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed, // 탭 3개 이상일 때도 안정
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
    _checkAppStoreUpdate();
  }

  Future<void> _checkAppStoreUpdate() async {
    if (!Platform.isIOS) return; // iOS만 체크

    try {
      final info = await PackageInfo.fromPlatform();
      final current = info.version; // e.g. "1.0.3"

      final url = Uri.parse(
          'https://itunes.apple.com/lookup?bundleId=$_bundleId&country=$_country');

      final res = await http.get(url).timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return;

      final jsonMap = json.decode(res.body) as Map<String, dynamic>;
      final results = (jsonMap['results'] as List?) ?? [];
      if (results.isEmpty) return;

      final latest = (results.first['version'] as String?)?.trim();
      if (latest == null || latest.isEmpty) return;

      if (_isNewerVersion(latest, current)) {
        // 배너 or 스낵바—선호대로 골라써
        if (mounted) {
          // 업데이트 알림 로직은 필요시 추가
          debugPrint('새로운 버전 있음: $latest');
        }
      }
    } catch (_) {
      // 조용히 패스 (네트워크 이슈 등)
    }
  }

  bool _isNewerVersion(String remote, String local) {
    // 단순 세그먼트 비교: 1.2.10 vs 1.2.3
    List<int> toNums(String v) =>
        v.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final r = toNums(remote);
    final l = toNums(local);
    for (int i = 0; i < 3; i++) {
      final ri = i < r.length ? r[i] : 0;
      final li = i < l.length ? l[i] : 0;
      if (ri > li) return true;
      if (ri < li) return false;
    }
    return false;
  }


  Future<void> _openAppStoreUpdatePage() async {
    // 앱 상세 페이지로 이동 (업데이트 가능하면 버튼이 '업데이트'로 뜸)
    final uri = Uri.parse('itms-apps://apps.apple.com/$_country/app/id$_iosAppId');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
