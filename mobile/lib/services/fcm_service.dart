import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:mobile/services/keyword_service.dart';
import 'package:mobile/main.dart' as main_app;
import 'package:mobile/screens/main_screen.dart';

/// FCM 알림 수신 콜백 타입
typedef OnNotificationReceived = void Function();

/// FCM 푸시 알림 서비스
/// - FCM 토큰 관리
/// - 푸시 알림 권한 요청
/// - 토큰 갱신 감지 및 서버 등록
/// - 포그라운드 알림 표시 (flutter_local_notifications)
/// - 알림 수신 시 콜백 지원 (실시간 UI 업데이트용)
class FcmService {
  static FcmService? _instance;
  static FcmService get instance => _instance ??= FcmService._internal();

  FcmService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final KeywordService _keywordService = KeywordService();
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  String? _currentToken;
  bool _isInitialized = false;

  /// 알림 수신 시 호출될 콜백 리스트
  final List<OnNotificationReceived> _notificationListeners = [];

  /// Android 알림 채널 ID
  static const String _androidChannelId = 'keyword_alerts';
  static const String _androidChannelName = '키워드 알림';
  static const String _androidChannelDescription = '관심 키워드와 매칭되는 캠페인 알림';

  /// FCM 서비스 초기화
  /// - 권한 요청
  /// - 토큰 획득 및 서버 등록
  /// - 토큰 갱신 리스너 설정
  /// - 로컬 알림 초기화
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // 1. 푸시 알림 권한 요청
      final settings = await _requestPermission();
      debugPrint('🔔 FCM 권한 상태: ${settings.authorizationStatus}');

      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        debugPrint('⚠️ 푸시 알림 권한이 거부되었습니다.');
        return;
      }

      // 2. 로컬 알림 초기화 (포그라운드 알림 표시용)
      await _initializeLocalNotifications();

      // 3. iOS의 경우 APNS 토큰 대기
      if (Platform.isIOS) {
        String? apnsToken = await _messaging.getAPNSToken();
        if (apnsToken == null) {
          // APNS 토큰이 없으면 잠시 대기 후 재시도
          debugPrint('⏳ APNS 토큰 대기 중...');
          await Future.delayed(const Duration(seconds: 3));
          apnsToken = await _messaging.getAPNSToken();
        }
        if (apnsToken != null) {
          debugPrint('🍎 APNS 토큰 획득: ${apnsToken.substring(0, 20)}...');
        } else {
          debugPrint('⚠️ APNS 토큰을 받지 못했습니다 (시뮬레이터에서는 정상)');
        }
      }

      // 4. FCM 토큰 획득
      _currentToken = await _messaging.getToken();
      if (_currentToken != null) {
        debugPrint('🔑 FCM 토큰 획득: ${_currentToken!.substring(0, 20)}...');
        // 디버그용: 전체 토큰 출력 (Firebase Console 테스트용)
        debugPrint('🔑 [DEBUG] FCM 전체 토큰: $_currentToken');
        await _registerTokenToServer(_currentToken!);
      } else {
        debugPrint('⚠️ FCM 토큰을 받지 못했습니다');
      }

      // 5. 토큰 갱신 리스너 설정
      _messaging.onTokenRefresh.listen((newToken) async {
        debugPrint('🔄 FCM 토큰 갱신됨');
        _currentToken = newToken;
        await _registerTokenToServer(newToken);
      });

      // 6. 포그라운드 메시지 핸들러 설정
      FirebaseMessaging.onMessage.listen((message) {
        debugPrint('🚨🚨🚨 FCM 메시지 수신됨! 🚨🚨🚨');
        _handleForegroundMessage(message);
      });

      // 7. 백그라운드에서 앱 열림 시 메시지 핸들러
      FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

      _isInitialized = true;
      debugPrint('✅ FCM 서비스 초기화 완료');
    } catch (e) {
      debugPrint('❌ FCM 서비스 초기화 실패: $e');
    }
  }

  /// 로컬 알림 초기화
  Future<void> _initializeLocalNotifications() async {
    // Android 설정
    const androidSettings = AndroidInitializationSettings('@mipmap/launcher_icon');

    // iOS 설정
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false, // FCM에서 이미 요청함
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // iOS 알림 권한 명시적 요청
    if (Platform.isIOS) {
      final iosImpl = _localNotifications
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      if (iosImpl != null) {
        final granted = await iosImpl.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        debugPrint('📱 iOS 로컬 알림 권한: $granted');
      }
    }

    // Android 알림 채널 생성 (Android 8.0+ 필수)
    if (Platform.isAndroid) {
      const androidChannel = AndroidNotificationChannel(
        _androidChannelId,
        _androidChannelName,
        description: _androidChannelDescription,
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      );

      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(androidChannel);

      debugPrint('📢 Android 알림 채널 생성 완료');
    }
  }

  /// 알림 탭 시 처리
  /// 푸시 알림을 탭하면 앱의 알림 기록 페이지로 이동
  void _onNotificationTapped(NotificationResponse response) async {
    debugPrint('🔔 알림 탭됨: ${response.payload}');

    // 푸시 알림 탭 시 알림 기록 페이지로 이동
    await _navigateToNotificationScreen();
  }

  /// 알림 기록 페이지로 이동
  /// 푸시 알림 탭 시 MainScreen의 알림 탭 → 알림 기록 탭으로 이동
  Future<void> _navigateToNotificationScreen() async {
    final navigator = main_app.navigatorKey.currentState;
    if (navigator == null) {
      debugPrint('⚠️ 네비게이터를 찾을 수 없습니다.');
      return;
    }

    // 기존 스택을 모두 제거하고 MainScreen의 알림 탭으로 이동
    // initialTabIndex: 2 (알림 탭), openAlertHistoryTab: true (알림 기록 탭)
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) => const MainScreen(
          initialTabIndex: 2,      // 하단 탭: 알림 (index 2)
          openAlertHistoryTab: true, // 내부 탭: 알림 기록 (index 1)
        ),
      ),
      (route) => false,
    );

    debugPrint('✅ 알림 기록 페이지로 이동 완료');
  }

  /// 푸시 알림 권한 요청
  Future<NotificationSettings> _requestPermission() async {
    return await _messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );
  }

  /// 서버에 FCM 토큰 등록
  Future<void> _registerTokenToServer(String token) async {
    try {
      final deviceType = Platform.isIOS ? 'ios' : 'android';
      await _keywordService.registerFcmToken(token, deviceType);
      debugPrint('✅ FCM 토큰 서버 등록 완료');
    } catch (e) {
      debugPrint('⚠️ FCM 토큰 서버 등록 실패: $e');
      // 실패해도 앱 실행에는 영향 없음
    }
  }

  /// 포그라운드 메시지 처리
  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('📬 포그라운드 메시지 수신:');
    debugPrint('  - 제목: ${message.notification?.title}');
    debugPrint('  - 내용: ${message.notification?.body}');
    debugPrint('  - 데이터: ${message.data}');

    // 포그라운드에서 로컬 알림 표시
    _showLocalNotification(message);

    // 알림 수신 리스너들에게 이벤트 전달 (UI 실시간 업데이트용)
    _notifyListeners();
  }

  /// 로컬 알림 표시 (포그라운드용)
  Future<void> _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    final androidDetails = AndroidNotificationDetails(
      _androidChannelId,
      _androidChannelName,
      channelDescription: _androidChannelDescription,
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      icon: '@mipmap/launcher_icon',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    // 캠페인 ID를 payload로 전달
    final payload = message.data['campaign_id'];

    await _localNotifications.show(
      message.hashCode, // 고유 ID
      notification.title,
      notification.body,
      details,
      payload: payload,
    );

    debugPrint('📢 로컬 알림 표시 완료');
  }

  /// 백그라운드에서 앱 열림 시 메시지 처리
  /// 푸시 알림을 탭하면 앱의 알림 기록 페이지로 이동
  void _handleMessageOpenedApp(RemoteMessage message) async {
    debugPrint('📱 백그라운드 메시지로 앱 열림:');
    debugPrint('  - 제목: ${message.notification?.title}');
    debugPrint('  - 데이터: ${message.data}');

    // 푸시 알림 탭 시 알림 기록 페이지로 이동
    await _navigateToNotificationScreen();
  }

  /// 현재 FCM 토큰 반환
  String? get currentToken => _currentToken;

  /// FCM 토큰 재등록 (로그인/로그아웃 시 호출)
  Future<void> refreshToken() async {
    if (_currentToken != null) {
      await _registerTokenToServer(_currentToken!);
    }
  }

  /// FCM 토큰 해제 (로그아웃 시 호출)
  Future<void> unregisterToken() async {
    if (_currentToken != null) {
      try {
        await _keywordService.unregisterFcmToken(_currentToken!);
        debugPrint('✅ FCM 토큰 해제 완료');
      } catch (e) {
        debugPrint('⚠️ FCM 토큰 해제 실패: $e');
      }
    }
  }

  /// 초기화 상태 확인
  bool get isInitialized => _isInitialized;

  /// 알림 수신 리스너 등록
  /// NotificationScreen 등에서 사용하여 실시간 업데이트 구현
  void addNotificationListener(OnNotificationReceived listener) {
    if (!_notificationListeners.contains(listener)) {
      _notificationListeners.add(listener);
      debugPrint('🔔 알림 리스너 등록됨 (총 ${_notificationListeners.length}개)');
    }
  }

  /// 알림 수신 리스너 해제
  void removeNotificationListener(OnNotificationReceived listener) {
    _notificationListeners.remove(listener);
    debugPrint('🔔 알림 리스너 해제됨 (총 ${_notificationListeners.length}개)');
  }

  /// 모든 리스너에게 알림 수신 이벤트 전달
  void _notifyListeners() {
    debugPrint('🔔 알림 리스너들에게 이벤트 전달 (${_notificationListeners.length}개)');
    for (final listener in _notificationListeners) {
      try {
        listener();
      } catch (e) {
        debugPrint('❌ 알림 리스너 호출 오류: $e');
      }
    }
  }
}

/// 백그라운드 메시지 핸들러 (앱이 종료된 상태에서도 호출됨)
/// main.dart에서 등록 필요
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('📬 백그라운드 메시지 수신: ${message.notification?.title}');
  // 백그라운드에서는 최소한의 처리만 수행
}
