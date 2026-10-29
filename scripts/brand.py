"""Generate every logo/icon file from design/brand/mark.svg: python scripts/brand.py

The SVG is the single source (neon gamepad app icon, brand name only, no domain).
Rasters are rendered with headless Chrome so the glow and gradients match browsers exactly.
"""
import shutil, subprocess, tempfile
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'design/brand/mark.svg'
CHROME = shutil.which('google-chrome') or shutil.which('chromium') or '/opt/google/chrome/chrome'
BG, INK, ACCENT, MUTED = (0x06, 0x07, 0x0d), (0xee, 0xf0, 0xff), (0x38, 0xbd, 0xf8), (0x9b, 0xa1, 0xc6)
FONT = ROOT / 'design/fonts/ChakraPetch-Bold.ttf'
BODY = ROOT / 'design/fonts/BeVietnamPro-Medium.ttf'


def render(size=1024):
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / 'mark.png'
        subprocess.run([CHROME, '--headless', '--disable-gpu', '--no-sandbox', '--hide-scrollbars',
                        '--default-background-color=00000000', f'--force-device-scale-factor={size / 512}',
                        '--window-size=512,512', f'--screenshot={out}', SOURCE.as_uri()],
                       check=True, capture_output=True)
        return Image.open(out).convert('RGBA')


def lockup(mark, width, height, mark_size, title_size, tagline=None):
    """Icon + "ThuêTab" wordmark on the brand background (social preview / banners)."""
    img = Image.new('RGBA', (width, height), BG + (255,))
    d = ImageDraw.Draw(img)
    title = ImageFont.truetype(str(FONT), title_size)
    tw = d.textlength('ThuêTab', font=title)
    gap = mark_size // 4
    x = (width - (mark_size + gap + tw)) // 2
    y = (height - mark_size) // 2 - (title_size // 3 if tagline else 0)
    m = mark.resize((mark_size, mark_size), Image.LANCZOS)
    img.alpha_composite(m, (int(x), int(y)))
    tx = x + mark_size + gap
    ty = y + (mark_size - title_size) // 2 - title_size // 8
    d.text((tx, ty), 'Thuê', font=title, fill=INK)
    d.text((tx + d.textlength('Thuê', font=title), ty), 'Tab', font=title, fill=ACCENT)
    if tagline:
        body = ImageFont.truetype(str(BODY), title_size // 4)
        d.text((width // 2, y + mark_size + title_size // 2), tagline, font=body, fill=MUTED, anchor='mt')
    return img


def main():
    mark = render(1024)
    for path in ('web/public/favicon.svg', 'web/public/logo.svg', 'icon.svg'):
        shutil.copyfile(SOURCE, ROOT / path)
    flat = Image.new('RGBA', mark.size, BG + (255,))
    flat.alpha_composite(mark)
    sizes = {
        'design/brand/mark-1024.png': (mark, 1024),
        'web/public/icons/icon-192.png': (mark, 192),
        'web/public/icons/icon-512.png': (mark, 512),
        # Maskable / iOS icons must be opaque: the launcher applies its own corner mask.
        'web/public/icons/maskable-512.png': (flat, 512),
        'web/public/icons/apple-touch-icon.png': (flat, 180),
        'icon.png': (mark, 512),
        'native/icons/app_icon.png': (mark, 256),
        'native/icons/custom.png': (mark, 128),
    }
    for path, (img, size) in sizes.items():
        img.resize((size, size), Image.LANCZOS).save(ROOT / path)
    lockup(mark, 1200, 630, 260, 140, 'Treo game Java 24/24 · Điều khiển từ mọi thiết bị').save(ROOT / 'web/public/og.png')
    lockup(mark, 1280, 360, 260, 140).save(ROOT / 'design/brand/logo-horizontal.png')
    print('\n'.join(['web/public/favicon.svg', 'web/public/logo.svg', 'icon.svg', *sizes, 'web/public/og.png', 'design/brand/logo-horizontal.png']))


if __name__ == '__main__':
    main()
