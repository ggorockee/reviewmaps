import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart'; // ⬅️ 추가
import 'package:mobile/const/colors.dart';
import 'package:mobile/screens/main_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ⬇️ Naver Map SDK 초기화 (Client ID만 필요)
  await FlutterNaverMap().init(
    clientId: '4hxo8bmlh7',
    onAuthFailed: (ex) {
      // 선택: 인증 실패시 로깅
      debugPrint('NaverMap auth failed: $ex');
    },
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Review Schedule',
      theme: ThemeData(
        primaryColor: PRIMARY_COLOR,
        colorScheme: ColorScheme.fromSeed(
          seedColor: PRIMARY_COLOR,
          primary: PRIMARY_COLOR,
        ),
        useMaterial3: true,
      ),
      home: const MainScreen(),
    );
  }
}
