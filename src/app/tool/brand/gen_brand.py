# -*- coding: utf-8 -*-
"""Gyman 브랜드 이미지 생성기.

AI로 만든 원본 심볼(`icon_mark.png`) 하나를 기준으로 런처와 스플래시 자산을
만듭니다. 플랫폼별 PNG를 따로 편집하면 다음 아이콘 교체 때 일관성이 깨지므로,
크기와 안전 여백만 이 스크립트에서 조정합니다.
"""
import os

from PIL import Image, ImageDraw, ImageFont


INK = (0x16, 0x18, 0x1D, 255)
VOLT = (0xC6, 0xFF, 0x00, 255)
TRANSPARENT = (0, 0, 0, 0)

APP_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(APP_ROOT, "assets", "brand")
MARK_PATH = os.path.join(OUT, "icon_mark.png")
FONT_PATH = os.path.join(APP_ROOT, "assets", "fonts", "PretendardVariable.ttf")


def _load_mark(canvas_size, scale):
    """투명 여백을 제거한 심볼을 지정 비율로 중앙에 배치합니다."""
    if not os.path.exists(MARK_PATH):
        raise FileNotFoundError(f"브랜드 심볼을 찾을 수 없습니다: {MARK_PATH}")

    mark = Image.open(MARK_PATH).convert("RGBA")
    bounds = mark.getbbox()
    if bounds is None:
        raise ValueError("브랜드 심볼이 비어 있습니다.")

    mark = mark.crop(bounds)
    target_size = int(canvas_size * scale)
    mark.thumbnail((target_size, target_size), Image.LANCZOS)

    canvas = Image.new("RGBA", (canvas_size, canvas_size), TRANSPARENT)
    position = ((canvas_size - mark.width) // 2, (canvas_size - mark.height) // 2)
    canvas.alpha_composite(mark, position)
    return canvas


def make_icon_master(size=1024):
    """iOS와 구형 Android용: 잉크 배경 위에 새 브랜드 심볼을 합성합니다."""
    icon = Image.new("RGBA", (size, size), INK)
    icon.alpha_composite(_load_mark(size, 0.72))
    icon.save(os.path.join(OUT, "icon_master.png"))
    # iOS는 알파 채널 없는 정사각형 원본을 요구하므로 같은 결과를 RGB로 저장합니다.
    icon.convert("RGB").save(os.path.join(OUT, "icon_ios.png"))


def make_adaptive_foreground(size=1024):
    """Android 적응형 아이콘의 마스크 안전 영역에 맞춘 투명 전경입니다."""
    _load_mark(size, 0.64).save(os.path.join(OUT, "icon_foreground.png"))


def make_splash_mark(size=512):
    """Android 12 이상 스플래시에 쓰는 단일 심볼입니다."""
    _load_mark(size, 0.48).save(os.path.join(OUT, "splash_bolt.png"))


def make_splash_logo(width=1200):
    """심볼과 워드마크를 함께 보여 주는 앱 시작 화면용 로고입니다."""
    height = int(width * 0.84)
    image = Image.new("RGBA", (width, height), TRANSPARENT)
    mark = _load_mark(width, 0.34)
    mark_bounds = mark.getbbox()
    if mark_bounds is None:
        raise ValueError("스플래시용 브랜드 심볼을 만들 수 없습니다.")

    mark = mark.crop(mark_bounds)
    mark_x = (width - mark.width) // 2
    mark_y = int(height * 0.06)
    image.alpha_composite(mark, (mark_x, mark_y))

    draw = ImageDraw.Draw(image)
    font = ImageFont.truetype(FONT_PATH, size=int(width * 0.15))
    try:
        font.set_variation_by_axes([800])
    except Exception:
        # 고정 웨이트 폰트에서도 스플래시 생성이 계속되도록 합니다.
        pass

    text = "GYMAN"
    bbox = draw.textbbox((0, 0), text, font=font)
    text_width = bbox[2] - bbox[0]
    text_x = (width - text_width) // 2 - bbox[0]
    text_y = mark_y + mark.height + int(height * 0.04) - bbox[1]
    draw.text((text_x, text_y), text, font=font, fill=VOLT)
    image.save(os.path.join(OUT, "splash_logo.png"))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    make_icon_master()
    make_adaptive_foreground()
    make_splash_mark()
    make_splash_logo()
    print("브랜드 이미지 생성 완료")
