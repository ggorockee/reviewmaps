# 클라이언트 구현 가이드

## 📋 개요

앱 버전 관리 시스템의 클라이언트 구현 가이드입니다.
**current_version을 서버로 보낼 필요 없이**, 클라이언트가 자체적으로 버전 비교 및 업데이트 UI를 처리합니다.

## 🎯 설계 철학

### 왜 클라이언트에서 버전 비교를 하나요?

1. **불필요한 네트워크 전송 감소**: 클라이언트가 이미 알고 있는 자신의 버전을 서버로 보낼 필요 없음
2. **네트워크 독립성**: 오프라인에서도 버전 정보 캐싱 후 비교 가능
3. **유연성**: 클라이언트가 자체 로직으로 업데이트 타이밍 조절 가능
4. **단순한 API**: 서버는 설정만 제공, 클라이언트가 로직 담당

### 옵션: 서버에서 판단받기 (편의 기능)

서버로 `current_version`을 보내면 **서버가 대신 판단**해줍니다.
- 클라이언트 구현이 간단해짐
- 하지만 권장하지 않음 (불필요한 데이터 전송)

## 🔌 API 엔드포인트

### GET /api/v1/app-config/version

#### 요청 (current_version 없이)

```http
GET /api/v1/app-config/version?platform=android
```

#### 응답

```json
{
  "latest_version": "1.4.0",
  "min_version": "1.3.0",
  "force_update": false,
  "store_url": "https://play.google.com/store/apps/details?id=com.reviewmaps.mobile&pli=1",
  "message_title": "업데이트 안내",
  "message_body": "더 안정적이고 편리한 서비스 이용을 위해\n최신 버전으로 업데이트해 주세요."
}
```

#### 응답 필드

| 필드 | 타입 | 설명 |
|------|------|------|
| latest_version | string | 최신 버전 (예: "1.4.0") |
| min_version | string | 최소 지원 버전 (예: "1.3.0") |
| force_update | boolean | 서버 기본값 (false), current_version 없으면 무의미 |
| store_url | string | 스토어 URL |
| message_title | string | 기본 업데이트 메시지 제목 |
| message_body | string | 기본 업데이트 메시지 본문 |

## 📱 구현 예시

### Flutter/Dart

```dart
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class VersionCheckService {
  static const String apiUrl = 'https://api.reviewmaps.com/api/v1/app-config/version';

  /// 버전 비교 (Semantic Versioning)
  static int compareVersions(String v1, String v2) {
    final parts1 = v1.split('.').map(int.parse).toList();
    final parts2 = v2.split('.').map(int.parse).toList();

    for (int i = 0; i < 3; i++) {
      if (parts1[i] < parts2[i]) return -1;
      if (parts1[i] > parts2[i]) return 1;
    }
    return 0;
  }

  /// 버전 정보 조회 (current_version 없이)
  Future<VersionConfig> fetchVersionConfig(String platform) async {
    final response = await http.get(
      Uri.parse(apiUrl).replace(queryParameters: {
        'platform': platform,
      }),
    );

    if (response.statusCode == 200) {
      return VersionConfig.fromJson(json.decode(response.body));
    }

    throw Exception('버전 정보 조회 실패');
  }

  /// 업데이트 체크 및 UI 표시
  Future<void> checkAndShowUpdate(BuildContext context) async {
    // 1. 현재 앱 버전 가져오기 (로컬)
    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version; // 예: "1.3.0"

    // 2. 플랫폼 확인
    final platform = Platform.isAndroid ? 'android' : 'ios';

    // 3. 서버에서 버전 설정 조회 (current_version 없이!)
    final config = await fetchVersionConfig(platform);

    // 4. 클라이언트에서 버전 비교
    final needsUpdate = compareVersions(currentVersion, config.latestVersion) < 0;
    final forceUpdate = compareVersions(currentVersion, config.minVersion) < 0;

    // 5. 업데이트 UI 표시
    if (forceUpdate) {
      await _showForceUpdateDialog(context, config);
    } else if (needsUpdate) {
      await _showRecommendedUpdateDialog(context, config);
    }
    // else: 최신 버전, 아무 표시 안함
  }

  /// 강제 업데이트 모달 (닫기 버튼 없음)
  Future<void> _showForceUpdateDialog(BuildContext context, VersionConfig config) async {
    await showDialog(
      context: context,
      barrierDismissible: false, // 뒤로가기 버튼 막기
      builder: (context) => AlertDialog(
        title: Text('필수 업데이트 안내'),
        content: Text(
          '이전 버전은 더 이상 지원되지 않습니다.\n'
          '앱을 계속 사용하시려면 최신 버전으로 업데이트해 주세요.'
        ),
        actions: [
          TextButton(
            onPressed: () {
              launchUrl(Uri.parse(config.storeUrl), mode: LaunchMode.externalApplication);
            },
            child: Text('업데이트'),
          ),
        ],
      ),
    );
  }

  /// 권장 업데이트 모달 (나중에 버튼 있음)
  Future<void> _showRecommendedUpdateDialog(BuildContext context, VersionConfig config) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('업데이트 안내'),
        content: Text(config.messageBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('나중에'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              launchUrl(Uri.parse(config.storeUrl), mode: LaunchMode.externalApplication);
            },
            child: Text('업데이트'),
          ),
        ],
      ),
    );
  }
}

/// 버전 설정 모델
class VersionConfig {
  final String latestVersion;
  final String minVersion;
  final String storeUrl;
  final String messageTitle;
  final String messageBody;

  VersionConfig({
    required this.latestVersion,
    required this.minVersion,
    required this.storeUrl,
    required this.messageTitle,
    required this.messageBody,
  });

  factory VersionConfig.fromJson(Map<String, dynamic> json) {
    return VersionConfig(
      latestVersion: json['latest_version'],
      minVersion: json['min_version'],
      storeUrl: json['store_url'],
      messageTitle: json['message_title'],
      messageBody: json['message_body'],
    );
  }
}
```

### 사용 예시

```dart
// main.dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 앱 시작 시 버전 체크
  await VersionCheckService().checkAndShowUpdate(context);

  runApp(MyApp());
}
```

### React Native (TypeScript)

```typescript
import { Platform, Alert, Linking } from 'react-native';
import DeviceInfo from 'react-native-device-info';

interface VersionConfig {
  latest_version: string;
  min_version: string;
  store_url: string;
  message_title: string;
  message_body: string;
}

class VersionCheckService {
  private static readonly API_URL = 'https://api.reviewmaps.com/api/v1/app-config/version';

  /**
   * 버전 비교 (Semantic Versioning)
   */
  private static compareVersions(v1: string, v2: string): number {
    const parts1 = v1.split('.').map(Number);
    const parts2 = v2.split('.').map(Number);

    for (let i = 0; i < 3; i++) {
      if (parts1[i] < parts2[i]) return -1;
      if (parts1[i] > parts2[i]) return 1;
    }
    return 0;
  }

  /**
   * 버전 정보 조회 (current_version 없이)
   */
  private static async fetchVersionConfig(platform: string): Promise<VersionConfig> {
    const response = await fetch(`${this.API_URL}?platform=${platform}`);

    if (!response.ok) {
      throw new Error('버전 정보 조회 실패');
    }

    return await response.json();
  }

  /**
   * 업데이트 체크 및 UI 표시
   */
  static async checkAndShowUpdate(): Promise<void> {
    try {
      // 1. 현재 앱 버전 가져오기 (로컬)
      const currentVersion = DeviceInfo.getVersion(); // 예: "1.3.0"

      // 2. 플랫폼 확인
      const platform = Platform.OS === 'android' ? 'android' : 'ios';

      // 3. 서버에서 버전 설정 조회 (current_version 없이!)
      const config = await this.fetchVersionConfig(platform);

      // 4. 클라이언트에서 버전 비교
      const needsUpdate = this.compareVersions(currentVersion, config.latest_version) < 0;
      const forceUpdate = this.compareVersions(currentVersion, config.min_version) < 0;

      // 5. 업데이트 UI 표시
      if (forceUpdate) {
        this.showForceUpdateAlert(config);
      } else if (needsUpdate) {
        this.showRecommendedUpdateAlert(config);
      }
      // else: 최신 버전, 아무 표시 안함
    } catch (error) {
      console.error('버전 체크 실패:', error);
    }
  }

  /**
   * 강제 업데이트 알림 (닫기 버튼 없음)
   */
  private static showForceUpdateAlert(config: VersionConfig): void {
    Alert.alert(
      '필수 업데이트 안내',
      '이전 버전은 더 이상 지원되지 않습니다.\n앱을 계속 사용하시려면 최신 버전으로 업데이트해 주세요.',
      [
        {
          text: '업데이트',
          onPress: () => Linking.openURL(config.store_url),
        },
      ],
      { cancelable: false }, // 뒤로가기 막기
    );
  }

  /**
   * 권장 업데이트 알림 (나중에 버튼 있음)
   */
  private static showRecommendedUpdateAlert(config: VersionConfig): void {
    Alert.alert(
      '업데이트 안내',
      config.message_body,
      [
        {
          text: '나중에',
          style: 'cancel',
        },
        {
          text: '업데이트',
          onPress: () => Linking.openURL(config.store_url),
        },
      ],
    );
  }
}

export default VersionCheckService;
```

### 사용 예시

```typescript
// App.tsx
import React, { useEffect } from 'react';
import VersionCheckService from './services/VersionCheckService';

export default function App() {
  useEffect(() => {
    // 앱 시작 시 버전 체크
    VersionCheckService.checkAndShowUpdate();
  }, []);

  return <YourAppComponent />;
}
```

## 🧮 버전 비교 로직 상세

### Semantic Versioning 비교

```
버전 형식: major.minor.patch (예: 1.3.5)

비교 규칙:
1. major 비교 → 다르면 즉시 결과 반환
2. major 같으면 minor 비교 → 다르면 즉시 결과 반환
3. major, minor 같으면 patch 비교

예시:
- 1.3.5 < 1.4.0 (minor 차이)
- 1.3.5 < 2.0.0 (major 차이)
- 1.3.5 < 1.3.6 (patch 차이)
- 1.3.5 = 1.3.5 (동일)
```

### 업데이트 판단 플로우

```typescript
const currentVersion = "1.3.0";  // 현재 앱 버전
const latestVersion = "1.4.0";   // 서버 최신 버전
const minVersion = "1.3.0";      // 서버 최소 버전

// 1. 강제 업데이트 체크
if (compareVersions(currentVersion, minVersion) < 0) {
  // current < min_version → 강제 업데이트
  showForceUpdateDialog();
  return;
}

// 2. 권장 업데이트 체크
if (compareVersions(currentVersion, latestVersion) < 0) {
  // min_version ≤ current < latest → 권장 업데이트
  showRecommendedUpdateDialog();
  return;
}

// 3. 최신 버전
// current ≥ latest → 업데이트 안내 없음
```

## 💾 캐싱 전략 (선택사항)

### 로컬 캐싱

버전 정보를 로컬에 저장하여 오프라인에서도 체크 가능:

```dart
// Flutter 예시
import 'package:shared_preferences/shared_preferences.dart';

Future<void> cacheVersionConfig(VersionConfig config) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('cached_version_config', json.encode(config.toJson()));
  await prefs.setInt('cache_timestamp', DateTime.now().millisecondsSinceEpoch);
}

Future<VersionConfig?> getCachedVersionConfig() async {
  final prefs = await SharedPreferences.getInstance();
  final cached = prefs.getString('cached_version_config');
  final timestamp = prefs.getInt('cache_timestamp') ?? 0;

  // 캐시 유효기간: 24시간
  if (cached != null && DateTime.now().millisecondsSinceEpoch - timestamp < 86400000) {
    return VersionConfig.fromJson(json.decode(cached));
  }

  return null;
}
```

## 🎨 UI/UX 권장사항

### 1. 강제 업데이트 모달
- **닫기 버튼 없음**: 사용자가 반드시 업데이트해야 함
- **뒤로가기 막기**: Android의 뒤로가기 버튼 비활성화
- **명확한 메시지**: "필수 업데이트 안내" + 이유 설명

### 2. 권장 업데이트 모달
- **"나중에" 버튼 제공**: 사용자 선택권 존중
- **업데이트 혜택 강조**: 새 기능, 버그 수정 등
- **재표시 정책**: 하루 1회 또는 앱 실행 시마다

### 3. 업데이트 타이밍
```dart
// 앱 시작 시 체크 (권장)
void main() async {
  await VersionCheckService().checkAndShowUpdate();
  runApp(MyApp());
}

// 또는 홈 화면 진입 후
class HomeScreen extends StatefulWidget {
  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(seconds: 1), () {
      VersionCheckService().checkAndShowUpdate(context);
    });
  }
}
```

## 🔧 디버깅 팁

### 1. 버전 문자열 검증

```dart
// 잘못된 버전 형식 감지
bool isValidVersion(String version) {
  final regex = RegExp(r'^\d+\.\d+\.\d+$');
  return regex.hasMatch(version);
}

// 사용
if (!isValidVersion(currentVersion)) {
  print('Error: Invalid version format - $currentVersion');
}
```

### 2. 로깅

```dart
void checkAndShowUpdate(BuildContext context) async {
  final currentVersion = packageInfo.version;
  final config = await fetchVersionConfig(platform);

  print('[VersionCheck] Current: $currentVersion');
  print('[VersionCheck] Latest: ${config.latestVersion}');
  print('[VersionCheck] Min: ${config.minVersion}');

  final needsUpdate = compareVersions(currentVersion, config.latestVersion) < 0;
  final forceUpdate = compareVersions(currentVersion, config.minVersion) < 0;

  print('[VersionCheck] NeedsUpdate: $needsUpdate, ForceUpdate: $forceUpdate');

  // ...
}
```

## 📚 관련 문서

- [앱 버전 관리 명세서](APP_VERSION_MANAGEMENT_SPEC.md)
- [운영 가이드](../reports/APP_VERSION_OPERATION_GUIDE.md)
- [시스템 요약](../reports/APP_VERSION_SYSTEM_SUMMARY.md)
