# -*- coding: utf-8 -*-
"""
Gyman 브랜드 에셋 생성기 (런처 아이콘 + 스플래시 소스 PNG).

왜 이 스크립트가 리포에 있나:
- `assets/brand/*.png`는 절차적으로 그린 결과물이라, 번개 모양/워드마크/색을 바꾸려면
  이 스크립트가 유일한 "소스"다. PNG만 남기면 나중에 수정할 근거가 사라진다.
- 오프라인·의존성 최소(Pillow만)로 어디서든 동일하게 재생성하기 위함.
  (SVG 래스터라이저 Inkscape/ImageMagick 불필요.)

디자인 근거(DESIGN.md):
- 무드 = "블랙 + 볼트 라임". 잉크 블랙(#16181D) 배경 위 볼트 라임(#C6FF00) 번개.
- 라임은 "어두운 배경 위" 에서만 대비가 안전 → 아이콘/스플래시 배경을 잉크로 고정.
- 워드마크는 앱 폰트와 동일하게 Pretendard(w800)로 렌더 → 브랜드 일관성.

실행:
    cd src/app && python tool/brand/gen_brand.py
그다음 네이티브 리소스로 반영:
    dart run flutter_launcher_icons
    dart run flutter_native_splash:create
"""
import os
from PIL import Image, ImageDraw, ImageFont

# ── 브랜드 색 ─────────────────────────────────────────────
INK = (0x16, 0x18, 0x1D, 255)   # 잉크 블랙
VOLT = (0xC6, 0xFF, 0x00, 255)  # 볼트 라임
TRANSPARENT = (0, 0, 0, 0)

# ── 경로(리포 상대) ───────────────────────────────────────
#  이 파일: src/app/tool/brand/gen_brand.py → 앱 루트 = 상위 3단계
APP_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(APP_ROOT, "assets", "brand")
FONT_PATH = os.path.join(APP_ROOT, "assets", "fonts", "PretendardVariable.ttf")
os.makedirs(OUT, exist_ok=True)

# 번개(bolt) 폴리곤 — 0..1 정규 좌표(x 오른쪽, y 아래). 날카로운 지그재그 = 스포티/에너제틱.
BOLT = [
    (0.62, 0.05),
    (0.30, 0.53),
    (0.48, 0.53),
    (0.38, 0.95),
    (0.72, 0.44),
    (0.53, 0.44),
]


def _supersample(size, draw_fn, scale=4):
    """계단현상 방지: 4배 크게 그린 뒤 LANCZOS 축소(안티에일리어싱)."""
    big = Image.new("RGBA", (size * scale, size * scale), TRANSPARENT)
    _draw = ImageDraw.Draw(big)
    draw_fn(_draw, size * scale)
    return big.resize((size, size), Image.LANCZOS)


def _bolt_at(size, w):
    """번개를 캔버스 중앙에 폭 w로 배치한 좌표 리스트."""
    x0 = y0 = (size - w) / 2
    return [(x0 + px * w, y0 + py * w) for px, py in BOLT]


def make_icon_master(size=1024):
    """런처 아이콘 마스터: 잉크 라운드 배경 + 중앙 번개(텍스트 없음).
    안드로이드 구버전(<26) 폴백 및 마케팅용. 작게 축소돼도 읽히도록 텍스트 배제."""
    def fn(d, s):
        d.rounded_rectangle([0, 0, s - 1, s - 1], radius=int(s * 0.22), fill=INK)
        d.polygon(_bolt_at(s, s * 0.60), fill=VOLT)
    _supersample(size, fn).save(os.path.join(OUT, "icon_master.png"))


def make_adaptive_foreground(size=1024):
    """Android adaptive foreground: 투명 배경 + 번개.
    런처가 원형 마스크 + ic_launcher.xml의 16% inset을 겹쳐 적용하므로,
    최종 가시 크기가 레거시 아이콘과 비슷해지도록 소스에서 크게(72%) 그린다."""
    def fn(d, s):
        d.polygon(_bolt_at(s, s * 0.72), fill=VOLT)
    _supersample(size, fn).save(os.path.join(OUT, "icon_foreground.png"))


def make_splash_bolt(size=512):
    """Android 12+ 스플래시용 마크(번개만, 투명 배경). OS가 원형 안에 넣는다."""
    def fn(d, s):
        d.polygon(_bolt_at(s, s * 0.52), fill=VOLT)
    _supersample(size, fn).save(os.path.join(OUT, "splash_bolt.png"))


def make_splash_logo(width=1200):
    """스플래시 로고: 번개 + GYMAN 워드마크(Pretendard w800), 투명 배경.
    스플래시 배경은 잉크라 볼트 라임 텍스트도 대비 안전."""
    scale = 4
    W = width * scale
    H = int(width * 0.95) * scale
    img = Image.new("RGBA", (W, H), TRANSPARENT)
    d = ImageDraw.Draw(img)

    # 번개(위쪽 중앙)
    bolt_w = W * 0.34
    bolt_x = (W - bolt_w) / 2
    bolt_y = H * 0.06
    d.polygon(
        [(bolt_x + px * bolt_w, bolt_y + py * bolt_w) for px, py in BOLT],
        fill=VOLT,
    )

    # 워드마크 GYMAN — Pretendard ExtraBold(wght 800)
    font = ImageFont.truetype(FONT_PATH, size=int(W * 0.16))
    try:
        font.set_variation_by_axes([800])  # 가변폰트 wght 축
    except Exception:
        pass  # 고정 weight 폰트면 무시
    text = "GYMAN"
    bbox = d.textbbox((0, 0), text, font=font)
    tw = bbox[2] - bbox[0]
    tx = (W - tw) / 2 - bbox[0]
    ty = bolt_y + bolt_w + H * 0.04 - bbox[1]
    d.text((tx, ty), text, font=font, fill=VOLT)

    # 콘텐츠 경계에 맞춰 크롭 + 균등 여백 → 네이티브 스플래시 중앙정렬 시 시각 중심이 맞음
    content = img.getbbox()
    if content:
        pad = int((content[2] - content[0]) * 0.06)
        img = img.crop((
            max(0, content[0] - pad), max(0, content[1] - pad),
            min(W, content[2] + pad), min(H, content[3] + pad),
        ))
    ratio = width / img.width
    img = img.resize((width, int(img.height * ratio)), Image.LANCZOS)
    img.save(os.path.join(OUT, "splash_logo.png"))


if __name__ == "__main__":
    make_icon_master()
    make_adaptive_foreground()
    make_splash_bolt()
    make_splash_logo()
    print("생성 완료 →", OUT)
    print("  ", sorted(f for f in os.listdir(OUT) if f.endswith(".png")))
