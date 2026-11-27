"""리뷰맵 스토어 등록용 이미지 생성.

입력 (tool/capture_screenshots.py 결과):
  build/store_screenshots/phone/*.png          (iPhone 16 Pro Max, 1320x2868)
  build/store_screenshots/tablet/*.png         (iPad Pro 13-inch M4, 2064x2752)
  build/store_screenshots/android_phone/*.png  (Android 에뮬레이터 휴대전화)
  build/store_screenshots/android_tablet/*.png (Android 에뮬레이터 태블릿 크기)

출력:
  store/ios/iphone_69/*.png (App Store iPhone 6.9", 1320x2868)
  store/ios/iphone_63/*.png (App Store iPhone 6.3", 1206x2622 — 기본 필수 슬롯)
  store/ios/ipad_13/*.png   (App Store iPad 13", 2064x2752)
  store/android/phone/*.png (Play 휴대전화 스크린샷, 1080x1920)
  store/android/tablet/*.png (Play 7인치·10인치 태블릿 스크린샷, 1600x2560)
  store/android/feature_graphic.png (Play 그래픽 이미지, 1024x500)
  store/android/icon_512.png        (Play 고해상도 아이콘, 512x512)

실행 (mobile 폴더에서):
  uv run --with pillow python tool/store_assets.py
"""

import io
from pathlib import Path

from PIL import Image, ImageCms, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
SHOTS = ROOT / "build" / "store_screenshots"

OUT_IOS_69 = ROOT / "store" / "ios" / "iphone_69"
OUT_IOS_63 = ROOT / "store" / "ios" / "iphone_63"
OUT_IOS_IPAD = ROOT / "store" / "ios" / "ipad_13"
OUT_ANDROID_PHONE = ROOT / "store" / "android" / "phone"
OUT_ANDROID_TABLET = ROOT / "store" / "android" / "tablet"
OUT_ANDROID_ROOT = ROOT / "store" / "android"

ICON = ROOT / "asset" / "image" / "logo" / "application" / "reviewmaps.png"

# 브랜드 컬러 팔레트 (lib/const/colors.dart #22A45D 기반 상하 그라데이션)
EMERALD_TOP = (23, 136, 76)     # #17884C (흰색 헤드라인 대비 강화)
EMERALD_BOTTOM = (34, 164, 93)  # #22A45D (앱 기본 primaryColor)
BADGE_BG = (13, 79, 43)         # #0D4F2B (부제 캡슐 배경)
MINT_TEXT = (236, 255, 244)     # #ECFFF4 (부제 텍스트)
SHADOW_INK = (9, 38, 22)

FONT = "/System/Library/Fonts/AppleSDGothicNeo.ttc"
FONT_BOLD = 6    # Bold
FONT_MEDIUM = 2  # Medium

# 문구 속 숫자·기능은 실제와 맞아야 한다 (2026-11-27 활성 캠페인 기준 플랫폼 23곳)
SLIDES = [
    ("01_map", "내 주변 체험단\n지도로 한눈에", "맛집·카페·뷰티·숙박을 동네 지도에서 바로 찾아요"),
    ("02_feed", "흩어진 체험단 공고\n한곳에 모았어요", "20곳 이상의 체험단 사이트를 한 번에"),
    ("03_alerts", "원하는 키워드\n올라오면 바로 알림", "키워드를 등록하면 새 체험단을 놓치지 않아요"),
    ("04_stay", "숙박 체험단\n가능 요일까지 한눈에", "요일 정보가 있는 공고는 목록에서 바로 확인해요"),
    ("05_keywords", "관심 키워드\n간편하게 관리", "동네·메뉴 키워드를 켜고 끄기만 하면 끝"),
]


def font(size: int, bold: bool = True) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(FONT, size, index=FONT_BOLD if bold else FONT_MEDIUM)


def gradient_canvas(width: int, height: int) -> Image.Image:
    """상단 EMERALD_TOP → 하단 EMERALD_BOTTOM 수직 그라데이션 캔버스 생성."""
    strip = Image.new("RGB", (1, height))
    pixels = strip.load()
    for y in range(height):
        t = y / max(height - 1, 1)
        r = round(EMERALD_TOP[0] + (EMERALD_BOTTOM[0] - EMERALD_TOP[0]) * t)
        g = round(EMERALD_TOP[1] + (EMERALD_BOTTOM[1] - EMERALD_TOP[1]) * t)
        b = round(EMERALD_TOP[2] + (EMERALD_BOTTOM[2] - EMERALD_TOP[2]) * t)
        pixels[0, y] = (r, g, b)
    return strip.resize((width, height), Image.BILINEAR).convert("RGBA")


def rounded(img: Image.Image, radius: int) -> Image.Image:
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, img.width - 1, img.height - 1), radius, fill=255)
    out = img.convert("RGBA")
    out.putalpha(mask)
    return out


def open_srgb(path: Path) -> Image.Image:
    """시뮬레이터 캡처(Display P3)를 표준 sRGB로 변환."""
    img = Image.open(path).convert("RGB")
    icc = img.info.get("icc_profile")
    if not icc:
        return img
    source = ImageCms.ImageCmsProfile(io.BytesIO(icc))
    return ImageCms.profileToProfile(img, source, ImageCms.createProfile("sRGB"))


def slide(shot: Path, title: str, subtitle: str, width: int, height: int, is_tablet: bool = False) -> Image.Image:
    """상단 타이틀/부제 + 하단 둥근 흰색 베젤 기기 화면 배치."""
    canvas = gradient_canvas(width, height)
    draw = ImageDraw.Draw(canvas)

    # 태블릿(3:4 / 10:16)과 휴대폰(9:19.5 / 9:16) 비율에 맞춘 스케일 기준
    if is_tablet:
        s = width / 2064
        title_size = round(122 * s)
        sub_size = round(54 * s)
        y_top = round(125 * s)
        line_spacing = round(28 * s)
        sub_gap = round(42 * s)
        device_gap = round(115 * s)
        device_w = round(width * 0.82)
        corner_r = round(56 * s)
        border = round(16 * s)
    else:
        s = width / 1320
        # 1080x1920처럼 세로 비율이 짧은 캔버스에서는 상단 여백을 살짝 컴팩트하게 조정
        compact_ratio = (height / width) < 1.95
        title_size = round((98 if compact_ratio else 106) * s)
        sub_size = round((44 if compact_ratio else 48) * s)
        y_top = round((110 if compact_ratio else 145) * s)
        line_spacing = round(24 * s)
        sub_gap = round((34 if compact_ratio else 42) * s)
        device_gap = round((115 if compact_ratio else 150) * s)
        device_w = round(width * (0.81 if compact_ratio else 0.82))
        corner_r = round(68 * s)
        border = round(14 * s)

    title_font = font(title_size, bold=True)
    sub_font = font(sub_size, bold=False)

    draw.multiline_text(
        (width / 2, y_top),
        title,
        font=title_font,
        fill="white",
        anchor="ma",
        align="center",
        spacing=line_spacing,
    )
    title_bottom = draw.multiline_textbbox(
        (width / 2, y_top), title, font=title_font, anchor="ma", spacing=line_spacing
    )[3]

    # 부제 캡슐 배지
    sub_y = title_bottom + sub_gap
    sub_bbox = draw.textbbox((width / 2, sub_y), subtitle, font=sub_font, anchor="ma")
    pad_x = round(32 * s)
    pad_y = round(14 * s)
    pill_box = (
        sub_bbox[0] - pad_x,
        sub_bbox[1] - pad_y,
        sub_bbox[2] + pad_x,
        sub_bbox[3] + pad_y,
    )
    pill_layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(pill_layer).rounded_rectangle(
        pill_box,
        radius=round((pill_box[3] - pill_box[1]) / 2),
        fill=(*BADGE_BG, 135),
    )
    canvas = Image.alpha_composite(canvas, pill_layer)
    draw = ImageDraw.Draw(canvas)
    draw.text((width / 2, sub_y), subtitle, font=sub_font, fill=MINT_TEXT, anchor="ma")

    screen = open_srgb(shot)
    screen_h = round(screen.height * device_w / screen.width)
    screen = screen.resize((device_w, screen_h), Image.LANCZOS)
    screen = rounded(screen, corner_r)

    top = round(pill_box[3]) + device_gap
    left = (width - device_w) // 2

    # 부드러운 기기 그림자
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        (left, top + round(22 * s), left + device_w, top + screen.height),
        corner_r,
        fill=(*SHADOW_INK, 115),
    )
    canvas = Image.alpha_composite(canvas, shadow.filter(ImageFilter.GaussianBlur(round(38 * s))))

    # 흰색 베젤 프레임
    frame = Image.new("RGBA", (device_w + border * 2, screen.height + border * 2), (0, 0, 0, 0))
    ImageDraw.Draw(frame).rounded_rectangle(
        (0, 0, frame.width - 1, frame.height - 1), corner_r + border, fill="white"
    )
    canvas.alpha_composite(frame, (left - border, top - border))
    canvas.alpha_composite(screen, (left, top))
    return canvas.convert("RGB")


def feature_graphic() -> Image.Image:
    """Google Play 그래픽 이미지 (1024x500): 앱 아이콘 카드 + 브랜드 타이틀 + 핵심 소개."""
    canvas = gradient_canvas(1024, 500)

    # 왼쪽: 둥근 흰색 앱 아이콘 카드 + 그림자
    icon_size = 300
    icon_x = 84
    icon_y = (500 - icon_size) // 2

    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        (icon_x, icon_y + 12, icon_x + icon_size, icon_y + icon_size + 12),
        68,
        fill=(*SHADOW_INK, 105),
    )
    canvas = Image.alpha_composite(canvas, shadow.filter(ImageFilter.GaussianBlur(22)))

    icon_img = open_srgb(ICON).resize((icon_size, icon_size), Image.LANCZOS)
    icon_card = rounded(icon_img, 68)
    canvas.alpha_composite(icon_card, (icon_x, icon_y))

    # 오른쪽: 상단 태그 배지 + 앱 이름 + 두 줄 설명
    text_x = 436
    pill = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    pill_draw = ImageDraw.Draw(pill)
    tag_font = font(24, bold=True)
    tag_text = "20곳+ 체험단 통합 지도"
    tb = pill_draw.textbbox((text_x + 18, 108), tag_text, font=tag_font, anchor="la")
    pill_draw.rounded_rectangle(
        (text_x, tb[1] - 9, tb[2] + 18, tb[3] + 9),
        radius=20,
        fill=(*BADGE_BG, 155),
    )
    canvas = Image.alpha_composite(canvas, pill)

    draw = ImageDraw.Draw(canvas)
    draw.text((text_x + 18, 108), tag_text, font=tag_font, fill=MINT_TEXT, anchor="la")
    draw.text((text_x, 162), "리뷰맵", font=font(96, bold=True), fill="white", anchor="la")
    draw.text(
        (text_x + 2, 294),
        "흩어진 블로그·SNS 체험단을",
        font=font(38, bold=False),
        fill=MINT_TEXT,
        anchor="la",
    )
    draw.text(
        (text_x + 2, 348),
        "내 주변 지도에서 한눈에 찾아요",
        font=font(38, bold=True),
        fill="white",
        anchor="la",
    )
    return canvas.convert("RGB")


def main() -> None:
    for d in (OUT_IOS_69, OUT_IOS_63, OUT_IOS_IPAD, OUT_ANDROID_PHONE, OUT_ANDROID_TABLET, OUT_ANDROID_ROOT):
        d.mkdir(parents=True, exist_ok=True)

    feature_graphic().save(OUT_ANDROID_ROOT / "feature_graphic.png", optimize=True)
    open_srgb(ICON).resize((512, 512), Image.LANCZOS).save(OUT_ANDROID_ROOT / "icon_512.png", optimize=True)

    # (캡처 폴더, 태블릿 여부, [(출력 폴더, 너비, 높이)]) — Android 이미지는 Android 캡처로만 만든다
    targets = [
        ("phone", False, [(OUT_IOS_69, 1320, 2868), (OUT_IOS_63, 1206, 2622)]),
        ("tablet", True, [(OUT_IOS_IPAD, 2064, 2752)]),
        ("android_phone", False, [(OUT_ANDROID_PHONE, 1080, 1920)]),
        ("android_tablet", True, [(OUT_ANDROID_TABLET, 1600, 2560)]),
    ]
    for kind, is_tablet, outputs in targets:
        for name, title, subtitle in SLIDES:
            shot = SHOTS / kind / f"{name}.png"
            if not shot.exists():
                print(f"캡처 없음, 건너뜀: {kind}/{name}")
                continue
            for out_dir, width, height in outputs:
                slide(shot, title, subtitle, width, height, is_tablet).save(out_dir / f"{name}.png", optimize=True)

    generated = sorted(
        p for p in (ROOT / "store").rglob("*.png")
    )
    for p in generated:
        with Image.open(p) as im:
            print(f"{p.relative_to(ROOT)}  {im.width}x{im.height}  {p.stat().st_size // 1024}KB")


if __name__ == "__main__":
    main()
