import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile/screens/home_screen.dart';
import 'package:mobile/screens/map_screen.dart';
import 'package:mobile/screens/my_page_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectIndex = 0;

  final List<Widget> _screens = [
    const HomeScreen(),
    const MapScreen(),
    // const MyPageScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectIndex],
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: '홈'),
          BottomNavigationBarItem(icon: Icon(Icons.map_outlined), label: "지도"),
          // BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: "마이페이지"),
        ],
        currentIndex: _selectIndex,
        selectedItemColor: Theme.of(context).primaryColor,
        onTap: _onItemTapped,
      ),
    );
  }
}
