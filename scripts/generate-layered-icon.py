from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
MEDIA_DIR = ROOT / "harmony" / "AppScope" / "resources" / "base" / "media"
DOCS_DIR = ROOT / "docs" / "assets"
SIZE = 1024
SUPERSAMPLE = 4
BACKGROUND = "#4176E6"
FOREGROUND = "#FFFFFF"
ACCENT = "#7FE0C7"


def cubic(
    start: tuple[float, float],
    control_a: tuple[float, float],
    control_b: tuple[float, float],
    end: tuple[float, float],
    steps: int = 36,
) -> list[tuple[float, float]]:
    points = []
    for index in range(1, steps + 1):
        t = index / steps
        inverse = 1 - t
        x = (
            inverse**3 * start[0]
            + 3 * inverse**2 * t * control_a[0]
            + 3 * inverse * t**2 * control_b[0]
            + t**3 * end[0]
        )
        y = (
            inverse**3 * start[1]
            + 3 * inverse**2 * t * control_a[1]
            + 3 * inverse * t**2 * control_b[1]
            + t**3 * end[1]
        )
        points.append((x, y))
    return points


def scaled(points: list[tuple[float, float]]) -> list[tuple[int, int]]:
    scale = SIZE * SUPERSAMPLE / 192
    return [(round(x * scale), round(y * scale)) for x, y in points]


def render_masks() -> tuple[Image.Image, Image.Image]:
    outer = [(56, 48), (90, 48)]
    outer.extend(cubic((90, 48), (128, 48), (147, 65), (147, 96)))
    outer.extend(cubic((147, 96), (147, 127), (128, 144), (90, 144)))
    outer.append((56, 144))

    inner = [(80, 70), (80, 122), (92, 122)]
    inner.extend(cubic((92, 122), (113, 122), (123, 114), (123, 96)))
    inner.extend(cubic((123, 96), (123, 78), (113, 70), (92, 70)))

    white_mask = Image.new("L", (SIZE * SUPERSAMPLE, SIZE * SUPERSAMPLE), 0)
    draw = ImageDraw.Draw(white_mask)
    draw.polygon(scaled(outer), fill=255)
    draw.polygon(scaled(inner), fill=0)
    white_mask = white_mask.resize((SIZE, SIZE), Image.Resampling.LANCZOS)

    accent_mask = Image.new("L", (SIZE * SUPERSAMPLE, SIZE * SUPERSAMPLE), 0)
    accent_draw = ImageDraw.Draw(accent_mask)
    scale = SIZE * SUPERSAMPLE / 192
    radius = round(14 * scale)
    center = (round(147 * scale), round(146 * scale))
    accent_draw.ellipse(
        (
            center[0] - radius,
            center[1] - radius,
            center[0] + radius,
            center[1] + radius,
        ),
        fill=255,
    )
    accent_mask = accent_mask.resize((SIZE, SIZE), Image.Resampling.LANCZOS)
    return white_mask, accent_mask


def write_png(path: Path, image: Image.Image) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, format="PNG", optimize=True)


def validate(foreground: Image.Image, background: Image.Image) -> None:
    if foreground.size != (SIZE, SIZE) or foreground.mode != "RGBA":
        raise RuntimeError("foreground must be a 1024 x 1024 RGBA PNG")
    if background.size != (SIZE, SIZE) or background.mode != "RGB":
        raise RuntimeError("background must be a 1024 x 1024 RGB PNG")
    if foreground.getpixel((0, 0))[3] != 0:
        raise RuntimeError("foreground corners must be transparent")
    alpha = foreground.getchannel("A")
    if alpha.getextrema() != (0, 255):
        raise RuntimeError("foreground must contain transparent and opaque regions")
    if background.getextrema() != ((65, 65), (118, 118), (230, 230)):
        raise RuntimeError("background must be the solid #4176E6 color")


def main() -> None:
    white_mask, accent_mask = render_masks()

    foreground = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    foreground.paste(FOREGROUND, mask=white_mask)
    foreground.paste(ACCENT, mask=accent_mask)

    background = Image.new("RGB", (SIZE, SIZE), BACKGROUND)
    preview = Image.alpha_composite(background.convert("RGBA"), foreground)

    validate(foreground, background)

    write_png(MEDIA_DIR / "app_icon_foreground.png", foreground)
    write_png(MEDIA_DIR / "app_icon_background.png", background)
    write_png(DOCS_DIR / "dsh-harmony-app-icon-1024.png", preview.convert("RGB"))

    layered_image = {
        "layered-image": {
            "background": "$media:app_icon_background",
            "foreground": "$media:app_icon_foreground",
        }
    }
    (MEDIA_DIR / "app_layered_image.json").write_text(
        json.dumps(layered_image, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )

    print("Layered icon resources generated and validated")


if __name__ == "__main__":
    main()
