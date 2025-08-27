import 'package:flutter/material.dart';
import 'package:mobile/screens/home_screen.dart';
import 'package:mobile/screens/map_screen.dart';

/// MainScreen
/// ------------------------------------------------------
/// 하단 탭 내비게이션 컨테이너.
/// - 탭: 홈 / 지도
/// - 상태 보존: IndexedStack 사용 → 탭 전환 시 각 화면의 상태(스크롤, 지도 컨트롤러 등) 유지
/// - 배포: 미사용 import/코드 제거, 최소 로직
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  /// 현재 선택된 탭 인덱스
  int _selectedIndex = 0;

  /// 탭별 루트 화면
  /// - const 생성자로 만들어 불필요한 리빌드 방지
  late List<Widget?> _tabs;

  bool _isTablet(BuildContext context) =>
      MediaQuery.of(context).size.shortestSide >= 600;


  @override
  void initState() {
    super.initState();
    _tabs = [
      const HomeScreen(),
      null, // MapScreen은 아직 생성하지 않음 → 권한 팝업 안뜸
      // const MyPageScreen(),
    ];
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
  }

  @override
  Widget build(BuildContext context) {
    final bool isTab = _isTablet(context);
    return Scaffold(
      // ✅ IndexedStack: 현재 탭만 보이되, 나머지 탭도 트리에 남아 상태 보존
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _tabs[0]!,
          _tabs[1] ?? const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed, // 탭 3개 이상일 때도 안정
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: '홈'),
          BottomNavigationBarItem(icon: Icon(Icons.map_outlined), label: '지도'),
          // BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: '마이'),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Theme.of(context).primaryColor,
        onTap: _onItemTapped,
        showUnselectedLabels: true,

        // 📌 태블릿에서만 키움
        iconSize: isTab ? 32.0 : 24.0,             // 아이콘 크기
        selectedFontSize: isTab ? 25.0 : 12.0,     // 선택된 라벨 폰트
        unselectedFontSize: isTab ? 25.0 : 12.0,   // 선택 안된 라벨 폰트
      ),
    );
  }
}
