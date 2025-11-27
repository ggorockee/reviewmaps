import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:mobile/services/keyword_service.dart';
import 'package:mobile/services/campaign_service.dart';
import 'package:mobile/config/config.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:mobile/main.dart' as main_app;

/// FCM 푸시 알림 서비스
/// - FCM 토큰 관리
/// - 푸시 알림 권한 요청
/// - 토큰 갱신 감지 및 서버 등록
/// - 포그라운드 알림 표시 (flutter_local_notifications)
class FcmService {
  static FcmService? _instance;
  static FcmService get instance => _instance ??= FcmService._internal();

  FcmService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final KeywordService _keywordService = KeywordService();
  final CampaignService _campaignService = CampaignService(
    AppConfig.reviewMapBaseUrl,
    apiKey: AppConfig.reviewMapApiKey,
  );
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  String? _currentToken;
  bool _isInitialized = false;

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
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

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
  void _onNotificationTapped(NotificationResponse response) async {
    debugPrint('🔔 알림 탭됨: ${response.payload}');
    
    if (response.payload == null || response.payload!.isEmpty) {
      debugPrint('⚠️ payload가 없습니다.');
      return;
    }

    try {
      final campaignId = int.parse(response.payload!);
      await _handleCampaignNavigation(campaignId);
    } catch (e) {
      debugPrint('❌ 알림 탭 처리 오류: $e');
    }
  }

  /// 캠페인 네비게이션 처리
  Future<void> _handleCampaignNavigation(int campaignId) async {
    final context = main_app.navigatorKey.currentContext;
    if (context == null) {
      debugPrint('⚠️ 네비게이터 컨텍스트를 찾을 수 없습니다.');
      return;
    }

    try {
      // 캠페인 정보 조회
      final campaign = await _campaignService.fetchCampaignById(campaignId);

      if (!context.mounted) return;

      if (campaign == null || campaign.contentLink == null || campaign.contentLink!.isEmpty) {
        // 삭제된 경우: 팝업 표시
        _showDeletedCampaignDialog(context);
      } else {
        // 존재하는 경우: 링크로 이동
        await _openCampaignLink(campaign.contentLink!);
      }
    } catch (e) {
      debugPrint('❌ 캠페인 조회 오류: $e');
      if (context.mounted) {
        _showDeletedCampaignDialog(context);
      }
    }
  }

  /// 삭제된 캠페인 다이얼로그 표시
  void _showDeletedCampaignDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        title: const Text(
          '알림',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1A1C1E),
          ),
        ),
        content: const Text(
          '체험단이 삭제되었거나 올바르지 않은 주소입니다.',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: Color(0xFF6C7278),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              '확인',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 캠페인 링크 열기
  Future<void> _openCampaignLink(String url) async {
    try {
      String link = url.trim();
      if (!link.startsWith('http://') && !link.startsWith('https://')) {
        link = 'https://$link';
      }
      final uri = Uri.parse(Uri.encodeFull(link));
      
      // 외부 브라우저로 우선 시도
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        // 실패 시 인앱 브라우저로 시도
        await launchUrl(uri);
      }
      
      debugPrint('✅ 캠페인 링크 열기 성공: $url');
    } catch (e) {
      debugPrint('❌ 캠페인 링크 열기 실패: $e');
    }
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
  void _handleMessageOpenedApp(RemoteMessage message) async {
    debugPrint('📱 백그라운드 메시지로 앱 열림:');
    debugPrint('  - 제목: ${message.notification?.title}');
    debugPrint('  - 데이터: ${message.data}');

    // 키워드 알림인 경우 해당 캠페인으로 이동
    if (message.data['type'] == 'keyword_alert') {
      final campaignIdStr = message.data['campaign_id'];
      if (campaignIdStr != null) {
        try {
          final campaignId = int.parse(campaignIdStr.toString());
          debugPrint('  - 캠페인 ID: $campaignId 로 이동');
          await _handleCampaignNavigation(campaignId);
        } catch (e) {
          debugPrint('❌ 캠페인 ID 파싱 오류: $e');
        }
      }
    }
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
}

/// 백그라운드 메시지 핸들러 (앱이 종료된 상태에서도 호출됨)
/// main.dart에서 등록 필요
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('📬 백그라운드 메시지 수신: ${message.notification?.title}');
  // 백그라운드에서는 최소한의 처리만 수행
}
