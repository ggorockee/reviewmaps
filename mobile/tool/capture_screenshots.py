"""부팅된 iOS 시뮬레이터에서 store_screenshots_app.dart의 5개 화면을 캡처한다.

먼저 한 번 빌드한다:
  flutter build ios --simulator --debug -t tool/store_screenshots_app.dart

사용법 (mobile 디렉터리에서):
  python3 tool/capture_screenshots.py <UDID> <출력하위폴더>
  Android는 에뮬레이터 시리얼과 android_phone|android_tablet (먼저 flutter build apk --debug -t tool/store_screenshots_app.dart)
예:
  python3 tool/capture_screenshots.py DAC52F08-DD09-47F6-97BA-682D20659377 phone
  python3 tool/capture_screenshots.py 6C3D6DFC-2309-47D1-B574-11F241435A8B tablet
"""

import json
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

SLIDES = [
    ("01_map", 12.0),      # 지도 타일 + 성수 이동 + 검색 결과 패널
    ("02_feed", 10.0),     # 운영 API 응답과 이미지 로딩
    ("03_alerts", 4.0),
    ("04_stay", 8.0),
    ("05_keywords", 8.0),
]
BUNDLE_ID = "com.reviewmaps.mobile"


def wait_ready(timeout: float = 180.0) -> None:
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with urllib.request.urlopen("http://127.0.0.1:18941/ready", timeout=2) as r:
                if r.status == 200:
                    return
        except Exception:
            time.sleep(1.0)
    raise TimeoutError("store_screenshots_app 제어 서버(18941) 연결 시간 초과")


def simctl(*args: str, check: bool = True) -> None:
    subprocess.run(["xcrun", "simctl", *args], check=check)


def use_korean(udid: str) -> None:
    """지도 지명·상태바 날짜가 한국어로 나오도록 시뮬레이터 언어를 바꾼다 (바꿨으면 재부팅)."""
    current = subprocess.run(
        ["xcrun", "simctl", "spawn", udid, "defaults", "read", "-g", "AppleLocale"],
        capture_output=True, text=True,
    ).stdout.strip()
    if current == "ko_KR":
        return
    simctl("spawn", udid, "defaults", "write", "-g", "AppleLanguages", "-array", "ko-KR")
    simctl("spawn", udid, "defaults", "write", "-g", "AppleLocale", "ko_KR")
    simctl("shutdown", udid)
    simctl("boot", udid)
    simctl("bootstatus", udid, "-b")


def capture(kind: str, out_dir: Path, shoot, on_switch=lambda: None) -> None:
    wait_ready()
    for name, settle in SLIDES:
        with urllib.request.urlopen(f"http://127.0.0.1:18941/slide/{name}", timeout=10) as r:
            print(f"[{kind}] switched -> {r.read().decode()}")
        time.sleep(1.0)
        on_switch()
        time.sleep(settle)
        with urllib.request.urlopen("http://127.0.0.1:18941/errors", timeout=10) as r:
            errors = json.load(r)
        if errors:
            raise SystemExit(f"[{kind}] 화면 오류 {len(errors)}건, 첫 번째:\n{errors[0]}")
        dest = out_dir / f"{name}.png"
        shoot(dest)
        print(f"[{kind}] saved {dest} ({dest.stat().st_size // 1024}KB)")


def android(serial: str, kind: str, root: Path, out_dir: Path) -> None:
    adb_bin = str(Path.home() / "Library" / "Android" / "sdk" / "platform-tools" / "adb")

    def adb(*args: str, check: bool = True, **kw):
        return subprocess.run([adb_bin, "-s", serial, *args], check=check, **kw)

    if not serial.startswith("emulator-"):
        raise SystemExit("Android 촬영은 에뮬레이터에서만 한다 (실기기의 설치본을 지우지 않게)")
    adb("uninstall", BUNDLE_ID, check=False)
    adb("install", str(root / "build" / "app" / "outputs" / "flutter-apk" / "app-debug.apk"))
    # 지도 지명이 한국어로 나오도록 앱 언어 지정 (Android 13+)
    adb("shell", "cmd", "locale", "set-app-locales", BUNDLE_ID, "--locales", "ko-KR", check=False)
    for perm in ("ACCESS_FINE_LOCATION", "ACCESS_COARSE_LOCATION", "POST_NOTIFICATIONS"):
        adb("shell", "pm", "grant", BUNDLE_ID, f"android.permission.{perm}", check=False)
    # 에뮬레이터 위치를 성수역으로 (홈 화면은 기기 위치를 직접 읽는다). 경도, 위도 순서
    def fix_location() -> None:
        adb("emu", "geo", "fix", "127.0560", "37.5445", stdout=subprocess.DEVNULL)

    fix_location()
    # 상태바 고정 (데모 모드)
    adb("shell", "settings", "put", "global", "sysui_demo_allowed", "1")
    demo = ("shell", "am", "broadcast", "-a", "com.android.systemui.demo", "-e", "command")
    adb(*demo, "clock", "-e", "hhmm", "0941")
    adb(*demo, "battery", "-e", "level", "100", "-e", "plugged", "false")
    adb(*demo, "network", "-e", "wifi", "show", "-e", "level", "4")
    adb(*demo, "notifications", "-e", "visible", "false")
    adb("forward", "tcp:18941", "tcp:18941")
    adb("shell", "am", "force-stop", BUNDLE_ID)
    adb("shell", "am", "start", "-n", f"{BUNDLE_ID}/.MainActivity")

    def shoot(dest: Path) -> None:
        with dest.open("wb") as f:
            adb("exec-out", "screencap", "-p", stdout=f)

    try:
        # 에뮬레이터는 위치를 요청할 때 새 값이 들어와야 응답하므로 화면을 바꿀 때마다 다시 보낸다
        capture(kind, out_dir, shoot, on_switch=fix_location)
    finally:
        adb("shell", "am", "force-stop", BUNDLE_ID, check=False)
        adb("forward", "--remove", "tcp:18941", check=False)


def main() -> None:
    udid = sys.argv[1]
    kind = sys.argv[2]
    root = Path(__file__).resolve().parent.parent
    out_dir = root / "build" / "store_screenshots" / kind
    out_dir.mkdir(parents=True, exist_ok=True)

    if kind.startswith("android"):
        android(udid, kind, root, out_dir)
        return

    use_korean(udid)
    # 이전 설치본을 지워 남아 있는 권한 팝업을 없앤 뒤 새로 설치
    simctl("terminate", udid, BUNDLE_ID, check=False)
    simctl("uninstall", udid, BUNDLE_ID, check=False)
    simctl("install", udid, str(root / "build" / "ios" / "iphonesimulator" / "Runner.app"))
    simctl("privacy", udid, "grant", "location", BUNDLE_ID)
    simctl("location", udid, "set", "37.5445,127.0560")
    # 상태바 고정 (9:41, 배터리 100%, 신호 만칸)
    simctl(
        "status_bar", udid, "override",
        "--time", "9:41",
        "--dataNetwork", "wifi", "--wifiMode", "active", "--wifiBars", "3",
        "--cellularMode", "active", "--cellularBars", "4",
        "--batteryState", "charged", "--batteryLevel", "100",
        check=False,
    )
    # --screenshots: AppDelegate가 알림 권한 팝업을 띄우지 않는다 (시뮬레이터 전용)
    simctl("launch", udid, BUNDLE_ID, "--screenshots")

    try:
        capture(kind, out_dir, lambda dest: simctl("io", udid, "screenshot", str(dest)))
    finally:
        # 두 시뮬레이터가 같은 포트를 쓰므로 끝나면 종료
        simctl("terminate", udid, BUNDLE_ID, check=False)


if __name__ == "__main__":
    main()
