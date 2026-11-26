# Flutter Play Core - 선택적 의존성이므로 경고 무시
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.SplitInstallException
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManager
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManagerFactory
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest$Builder
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest
-dontwarn com.google.android.play.core.splitinstall.SplitInstallStateUpdatedListener
-dontwarn com.google.android.play.core.tasks.OnFailureListener
-dontwarn com.google.android.play.core.tasks.OnSuccessListener
-dontwarn com.google.android.play.core.tasks.Task

# WorkManager(google_mobile_ads가 사용)의 Room 데이터베이스는 리플렉션으로 기본 생성자를 부른다.
# AGP 9의 R8은 규칙에 없는 생성자를 지우는데 Room 2.2.5의 기본 규칙에는 생성자가 없어
# 릴리스 앱이 실행 직후 종료된다 (Failed to create an instance of androidx.work.impl.WorkDatabase).
# 2.2.1까지는 Unity Ads SDK의 규칙이 이를 가려 주었고, 2.2.2에서 Unity를 빼며 드러났다 (Play 출시 전 보고서).
-keep class * extends androidx.room.RoomDatabase { <init>(); }

# Google Mobile Ads
-keep class com.google.android.gms.ads.** { *; }
-dontwarn com.google.android.gms.ads.**
