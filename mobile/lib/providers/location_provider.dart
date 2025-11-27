import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

class LocationState {
  final Position? position;
  final LocationPermission? permission;

  const LocationState({
    this.position,
    this.permission,
  });

  bool get isGranted => 
    permission == LocationPermission.always || 
    permission == LocationPermission.whileInUse;
}

/// 노티파이어
class LocationNotifier extends Notifier<LocationState> {
  @override
  LocationState build() {
    return const LocationState(
      permission: LocationPermission.denied,
    );
  }

  /// 권한/좌표 업데이트
  Future<void> update() async {
    // 권한 확인
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }

    Position? pos;
    if (perm == LocationPermission.always || 
        perm == LocationPermission.whileInUse) {
      pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
    }

    state = LocationState(permission: perm, position: pos);
  }

  /// 앱 설정 열기 유도 (deniedForever 등)
  Future<void> openAppSettings() async {
    await Geolocator.openAppSettings();
  }

  Future<void> openLocationSettings() async {
    await Geolocator.openLocationSettings();
  }
}

/// Provider 선언
final locationProvider = NotifierProvider<LocationNotifier, LocationState>(
  () => LocationNotifier(),
);