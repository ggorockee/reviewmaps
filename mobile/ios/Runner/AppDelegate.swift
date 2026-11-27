import Flutter
import UIKit
import Firebase
import FirebaseMessaging

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    FirebaseApp.configure()

    // 스토어 캡처(tool/capture_screenshots.py)는 시뮬레이터에서만. 실기기 빌드는 항상 false
    #if targetEnvironment(simulator)
    let isScreenshotMode = ProcessInfo.processInfo.arguments.contains("--screenshots")
    #else
    let isScreenshotMode = false
    #endif

    // iOS 푸시 알림 등록 (스크린샷 캡처 모드에서는 권한 시스템 알림창 생략)
    if !isScreenshotMode {
      if #available(iOS 10.0, *) {
        UNUserNotificationCenter.current().delegate = self

        let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
        UNUserNotificationCenter.current().requestAuthorization(
          options: authOptions,
          completionHandler: { _, _ in }
        )
      } else {
        let settings: UIUserNotificationSettings =
          UIUserNotificationSettings(types: [.alert, .badge, .sound], categories: nil)
        application.registerUserNotificationSettings(settings)
      }

      application.registerForRemoteNotifications()
    }

    // Firebase Messaging 델리게이트 설정
    Messaging.messaging().delegate = self

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // APNS 토큰 수신 시 Firebase에 전달
  override func application(_ application: UIApplication,
                          didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    Messaging.messaging().apnsToken = deviceToken
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }
}

// Firebase Messaging Delegate
extension AppDelegate: MessagingDelegate {
  func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
    print("🔔 FCM 토큰 (AppDelegate): \(fcmToken ?? "nil")")
    // Flutter 측에서 토큰을 처리하므로 여기서는 로그만 출력
  }
}
