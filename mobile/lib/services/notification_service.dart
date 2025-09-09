// lib/services/notification_service.dart
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_service.dart';

/// NotificationService
/// ------------------------------------------------------------
/// Firebase Cloud Messaging 알림을 처리하는 서비스
/// - 포그라운드/백그라운드 알림 처리
/// - 알림 클릭 시 화면 이동
/// - 로컬 알림 표시
class NotificationService {
  static NotificationService? _instance;
  static NotificationService get instance => _instance ??= NotificationService._internal();
  
  NotificationService._internal();

  bool _isInitialized = false;

  /// 알림 서비스 초기화
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // 포그라운드 메시지 리스너 설정
      FirebaseService.instance.setupForegroundMessageListener(_onForegroundMessage);
      
      // 백그라운드에서 앱이 열린 경우 메시지 리스너 설정
      FirebaseService.instance.setupBackgroundMessageListener(_onMessageOpenedApp);
      
      // 앱이 종료된 상태에서 알림을 통해 열린 경우 처리
      final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
      if (initialMessage != null) {
        _handleNotificationTap(initialMessage);
      }

      _isInitialized = true;
      debugPrint('🔔 Notification service initialized');
    } catch (e) {
      debugPrint('❌ Notification service initialization failed: $e');
    }
  }

  /// 포그라운드에서 메시지 수신 시 처리
  void _onForegroundMessage(RemoteMessage message) {
    debugPrint('🔔 Foreground message received: ${message.messageId}');
    
    // Firebase Analytics에 알림 수신 이벤트 기록
    FirebaseService.instance.logEvent('notification_received', {
      'message_id': message.messageId ?? '',
      'title': message.notification?.title ?? '',
      'body': message.notification?.body ?? '',
      'data': message.data.toString(),
    });

    // 포그라운드에서는 스낵바로 알림 표시
    _showInAppNotification(message);
  }

  /// 백그라운드에서 알림 클릭으로 앱이 열린 경우 처리
  void _onMessageOpenedApp(RemoteMessage message) {
    debugPrint('🔔 Background message opened app: ${message.messageId}');
    
    // Firebase Analytics에 알림 클릭 이벤트 기록
    FirebaseService.instance.logEvent('notification_opened', {
      'message_id': message.messageId ?? '',
      'title': message.notification?.title ?? '',
      'body': message.notification?.body ?? '',
      'data': message.data.toString(),
    });

    _handleNotificationTap(message);
  }

  /// 알림 클릭 시 처리 (화면 이동 등)
  void _handleNotificationTap(RemoteMessage message) {
    final data = message.data;
    
    // 알림 데이터에 따라 적절한 화면으로 이동
    if (data.containsKey('screen')) {
      final screen = data['screen'];
      final campaignId = data['campaign_id'];
      
      switch (screen) {
        case 'campaign_detail':
          if (campaignId != null) {
            _navigateToCampaignDetail(campaignId);
          }
          break;
        case 'search_results':
          final query = data['query'] ?? '';
          _navigateToSearchResults(query);
          break;
        case 'home':
        default:
          _navigateToHome();
          break;
      }
    }
  }

  /// 인앱 알림 표시 (스낵바)
  void _showInAppNotification(RemoteMessage message) {
    final context = _getCurrentContext();
    if (context == null) return;

    final title = message.notification?.title ?? '알림';
    final body = message.notification?.body ?? '';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            if (body.isNotEmpty)
              Text(
                body,
                style: const TextStyle(color: Colors.white),
              ),
          ],
        ),
        backgroundColor: Colors.blue.shade600,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: '보기',
          textColor: Colors.white,
          onPressed: () => _handleNotificationTap(message),
        ),
      ),
    );
  }

  /// 캠페인 상세 화면으로 이동
  void _navigateToCampaignDetail(String campaignId) {
    final context = _getCurrentContext();
    if (context == null) return;

    // TODO: 캠페인 상세 화면 구현 시 추가
    debugPrint('🔔 Navigate to campaign detail: $campaignId');
    
    // 임시로 홈 화면으로 이동
    _navigateToHome();
  }

  /// 검색 결과 화면으로 이동
  void _navigateToSearchResults(String query) {
    final context = _getCurrentContext();
    if (context == null) return;

    debugPrint('🔔 Navigate to search results: $query');
    
    // 검색 결과 화면으로 이동 (실제 구현 시 적절한 Navigator 사용)
    // Navigator.of(context).pushNamed('/search', arguments: {'query': query});
  }

  /// 홈 화면으로 이동
  void _navigateToHome() {
    final context = _getCurrentContext();
    if (context == null) return;

    debugPrint('🔔 Navigate to home');
    
    // 홈 화면으로 이동 (실제 구현 시 적절한 Navigator 사용)
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  /// 현재 컨텍스트 가져오기
  BuildContext? _getCurrentContext() {
    // 실제 구현에서는 NavigatorKey나 다른 방법으로 현재 컨텍스트를 가져와야 함
    // 여기서는 임시로 null 반환
    return null;
  }

  /// 알림 권한 요청
  Future<bool> requestPermission() async {
    final messaging = FirebaseMessaging.instance;
    
    final settings = await messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    final isGranted = settings.authorizationStatus == AuthorizationStatus.authorized;
    
    // Firebase Analytics에 권한 요청 결과 기록
    FirebaseService.instance.logEvent('notification_permission_requested', {
      'granted': isGranted.toString(),
      'authorization_status': settings.authorizationStatus.toString(),
    });

    return isGranted;
  }

  /// FCM 토큰 가져오기 및 서버 전송
  Future<void> updateFCMToken() async {
    try {
      final token = await FirebaseService.instance.getFCMToken();
      if (token != null) {
        debugPrint('🔔 FCM Token: $token');
        
        // TODO: 서버에 토큰 전송 로직 추가
        // await _sendTokenToServer(token);
        
        // Firebase Analytics에 토큰 업데이트 이벤트 기록
        FirebaseService.instance.logEvent('fcm_token_updated', {
          'token_length': token.length.toString(),
        });
      }
    } catch (e) {
      debugPrint('❌ FCM token update failed: $e');
      FirebaseService.instance.recordError(
        e, 
        StackTrace.current, 
        reason: 'FCM token update failed'
      );
    }
  }

  /// 서버에 FCM 토큰 전송 (구현 예정)
  // Future<void> _sendTokenToServer(String token) async {
  //   // API 호출로 서버에 토큰 전송
  // }

  /// 알림 서비스 상태 확인
  bool get isInitialized => _isInitialized;
}
