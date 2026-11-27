"""업데이트 안내 카드에 넣을 설명 그림을 만든다 (asset/image/release_notes/).

캡처 앱을 iOS 시뮬레이터용으로 빌드·설치한 뒤 실행한다:
  flutter build ios --simulator --debug -t tool/store_screenshots_app.dart
  python3 tool/make_note_images.py <iPhone 시뮬레이터 UDID>
"""

import sys
import time
import urllib.request
from pathlib import Path

from capture_screenshots import BUNDLE_ID, simctl, wait_ready

IMAGES = {"note_stay": ("note.png", "stay_days.png")}


def main() -> None:
    udid = sys.argv[1]
    root = Path(__file__).resolve().parent.parent
    out = root / "asset" / "image" / "release_notes"
    out.mkdir(parents=True, exist_ok=True)
    simctl("terminate", udid, BUNDLE_ID, check=False)
    simctl("install", udid, str(root / "build" / "ios" / "iphonesimulator" / "Runner.app"))
    simctl("launch", udid, BUNDLE_ID, "--screenshots")
    try:
        wait_ready()
        for slide, (endpoint, name) in IMAGES.items():
            urllib.request.urlopen(f"http://127.0.0.1:18941/slide/{slide}", timeout=10).read()
            time.sleep(4)
            png = urllib.request.urlopen(f"http://127.0.0.1:18941/{endpoint}", timeout=20).read()
            (out / name).write_bytes(png)
            print(f"saved {out / name} ({len(png) // 1024}KB)")
    finally:
        simctl("terminate", udid, BUNDLE_ID, check=False)


if __name__ == "__main__":
    main()
