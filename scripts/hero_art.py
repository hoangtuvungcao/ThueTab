"""Draw the original pixel-art game scene used in the landing-page mock: python scripts/hero_art.py

Rendered at native J2ME resolution (240x320 portrait, 320x240 landscape) and upscaled with
nearest-neighbour so it stays crisp. Original artwork, no third-party game assets.
"""
import random
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
FONT = ROOT / 'design/fonts/BeVietnamPro-SemiBold.ttf'
DISPLAY = ROOT / 'design/fonts/ChakraPetch-Bold.ttf'


def lerp(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def sky(d, w, h, horizon):
    stops = [(0, (12, 10, 38)), (0.45, (46, 26, 92)), (0.8, (164, 64, 112)), (1, (250, 150, 90))]
    for y in range(horizon):
        t = y / horizon
        for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
            if t0 <= t <= t1:
                d.line([(0, y), (w, y)], fill=lerp(c0, c1, (t - t0) / (t1 - t0)))
                break


def stars(d, w, h, rnd):
    for _ in range(w * h // 900):
        x, y = rnd.randrange(w), rnd.randrange(int(h * 0.45))
        d.point((x, y), fill=rnd.choice([(255, 255, 255), (200, 220, 255), (255, 240, 200)]))
    for _ in range(4):
        x, y = rnd.randrange(8, w - 8), rnd.randrange(8, int(h * 0.3))
        for dx, dy in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)):
            d.point((x + dx, y + dy), fill=(255, 255, 255))


def moon(img, cx, cy, r):
    glow = Image.new('RGBA', img.size, (0, 0, 0, 0))
    g = ImageDraw.Draw(glow)
    for i in range(r * 3, r, -2):
        a = int(70 * (1 - (i - r) / (2 * r)))
        g.ellipse((cx - i, cy - i, cx + i, cy + i), fill=(255, 220, 160, max(a // 4, 2)))
    img.alpha_composite(glow)
    d = ImageDraw.Draw(img)
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(255, 236, 190))
    d.ellipse((cx - r // 3, cy - r // 2, cx, cy - r // 6), fill=(240, 214, 165))
    d.ellipse((cx + r // 5, cy + r // 6, cx + r // 2, cy + r // 2), fill=(240, 214, 165))


def ridge(d, w, base, amp, color, rnd, step=6, snow=None):
    pts, x, y = [(0, base)], 0, base
    while x <= w:
        y = max(base - amp, min(base + amp // 3, y + rnd.randint(-amp // 2, amp // 2)))
        pts.append((x, y))
        if snow and y < base - amp * 0.55:
            d.polygon([(x - 4, y + 5), (x, y), (x + 4, y + 5)], fill=snow)
        x += step
    d.polygon(pts + [(w, 400), (0, 400)], fill=color)


def castle(d, x, y):
    stone, dark, lit = (40, 30, 70), (28, 20, 52), (255, 200, 90)
    d.rectangle((x, y, x + 46, y + 30), fill=stone)
    for tx in (x - 6, x + 40):
        d.rectangle((tx, y - 14, tx + 12, y + 30), fill=dark)
        d.polygon([(tx - 2, y - 14), (tx + 6, y - 26), (tx + 14, y - 14)], fill=(120, 40, 80))
    d.rectangle((x + 16, y - 22, x + 30, y + 30), fill=stone)
    d.polygon([(x + 14, y - 22), (x + 23, y - 36), (x + 32, y - 22)], fill=(150, 50, 90))
    d.line([(x + 23, y - 36), (x + 23, y - 44)], fill=(200, 200, 220))
    d.polygon([(x + 23, y - 44), (x + 31, y - 41), (x + 23, y - 38)], fill=(56, 189, 248))
    for wx, wy in ((x + 21, y - 14), (x + 6, y + 8), (x + 36, y + 8), (x - 2, y - 6), (x + 44, y - 6), (x + 21, y + 4)):
        d.rectangle((wx, wy, wx + 3, wy + 4), fill=lit)
    d.rectangle((x + 19, y + 20, x + 27, y + 30), fill=(16, 10, 30))


def pine(d, x, y, s, c1, c2):
    for i in range(3):
        top = y - s * 2 + i * s // 2
        d.polygon([(x, top), (x - s // 2 - i * 2, top + s // 1.4), (x + s // 2 + i * 2, top + s // 1.4)], fill=c1 if i % 2 else c2)
    d.rectangle((x - 1, y - 2, x + 1, y + 2), fill=(50, 30, 30))


def ground(d, w, h, top):
    for y in range(top, h):
        t = (y - top) / max(1, h - top)
        d.line([(0, y), (w, y)], fill=lerp((46, 160, 90), (18, 70, 50), t))
    rnd = random.Random(7)
    for _ in range(w * 2):
        x, y = rnd.randrange(w), rnd.randrange(top, h)
        d.point((x, y), fill=rnd.choice([(70, 190, 110), (30, 110, 70), (90, 210, 120)]))
    for x in range(0, w, 3):
        d.line([(x, top), (x + 1, top - 2)], fill=(110, 220, 130))
    # Dirt path towards the castle.
    d.polygon([(w * 0.44, top), (w * 0.56, top), (w * 0.8, h), (w * 0.2, h)], fill=(150, 110, 70))
    for _ in range(60):
        x, y = rnd.randrange(int(w * 0.25), int(w * 0.75)), rnd.randrange(top + 4, h)
        d.point((x, y), fill=(120, 85, 55))


def hero(d, x, y):
    skin, hair, armor, cape = (255, 210, 170), (40, 30, 60), (56, 189, 248), (230, 60, 90)
    d.polygon([(x + 2, y + 9), (x - 3, y + 22), (x + 11, y + 22), (x + 9, y + 9)], fill=cape)
    d.rectangle((x + 2, y + 9, x + 9, y + 18), fill=armor)
    d.rectangle((x + 3, y + 18, x + 4, y + 23), fill=(40, 40, 70))
    d.rectangle((x + 7, y + 18, x + 8, y + 23), fill=(40, 40, 70))
    d.rectangle((x + 2, y + 1, x + 9, y + 8), fill=skin)
    d.rectangle((x + 1, y - 1, x + 10, y + 3), fill=hair)
    d.rectangle((x + 6, y + 4, x + 7, y + 5), fill=(20, 20, 40))
    d.rectangle((x + 4, y + 13, x + 9, y + 14), fill=(255, 200, 80))
    # Raised sword with a slash trail.
    d.line([(x + 10, y + 11), (x + 19, y + 1)], fill=(230, 240, 255), width=2)
    d.line([(x + 9, y + 12), (x + 12, y + 9)], fill=(160, 110, 60), width=2)
    d.arc((x + 6, y - 8, x + 34, y + 20), 280, 20, fill=(140, 240, 255), width=2)


def slime(d, x, y, c, eye=(20, 20, 40)):
    d.ellipse((x, y, x + 18, y + 14), fill=c)
    d.rectangle((x, y + 7, x + 18, y + 14), fill=c)
    d.ellipse((x + 3, y + 2, x + 8, y + 6), fill=(255, 255, 255))
    d.rectangle((x + 5, y + 5, x + 7, y + 7), fill=eye)
    d.rectangle((x + 11, y + 5, x + 13, y + 7), fill=eye)
    d.point((x + 4, y + 3), fill=(255, 255, 255))


def coin(d, x, y):
    d.ellipse((x, y, x + 6, y + 6), fill=(250, 200, 60))
    d.rectangle((x + 2, y + 2, x + 3, y + 4), fill=(255, 240, 150))


def text(d, xy, s, size, fill, font=FONT, stroke=(10, 10, 25), anchor='la'):
    f = ImageFont.truetype(str(font), size)
    d.text(xy, s, font=f, fill=fill, stroke_width=1, stroke_fill=stroke, anchor=anchor)


def bar(d, x, y, w, frac, c, label):
    d.rectangle((x, y, x + w, y + 5), fill=(20, 16, 40), outline=(10, 8, 20))
    d.rectangle((x + 1, y + 1, x + 1 + int((w - 2) * frac), y + 4), fill=c)
    d.line([(x + 1, y + 1), (x + int((w - 2) * frac), y + 1)], fill=lerp(c, (255, 255, 255), 0.45))
    text(d, (x + w + 3, y - 3), label, 8, (230, 235, 255))


def hud(d, w, h):
    d.rounded_rectangle((4, 4, 26, 26), 4, fill=(20, 16, 44), outline=(56, 189, 248))
    d.rectangle((10, 9, 19, 18), fill=(255, 210, 170))
    d.rectangle((9, 7, 20, 11), fill=(40, 30, 60))
    d.rectangle((15, 13, 16, 14), fill=(20, 20, 40))
    text(d, (15, 27), 'Lv.68', 7, (255, 220, 120), anchor='mt')
    bar(d, 31, 7, 70, 0.82, (240, 60, 80), '8.2k')
    bar(d, 31, 16, 70, 0.6, (56, 160, 248), '3.1k')
    text(d, (w - 5, 4), '1.250.000', 8, (255, 220, 120), anchor='ra')
    coin(d, w - 60, 7)
    # Quest tracker.
    d.rounded_rectangle((w - 92, 22, w - 4, 46), 3, fill=(10, 8, 30))
    text(d, (w - 88, 24), 'Nhiệm vụ', 7, (56, 189, 248))
    text(d, (w - 88, 34), 'Diệt Slime 18/20', 7, (230, 235, 255))


def skills(d, w, h):
    y = h - 34
    colors = [(240, 80, 80), (56, 189, 248), (52, 211, 153), (250, 200, 60)]
    for i, c in enumerate(colors):
        x = w // 2 - 46 + i * 24
        d.rounded_rectangle((x, y, x + 20, y + 20), 4, fill=(16, 12, 38), outline=(90, 90, 140))
        d.rectangle((x + 5, y + 5, x + 15, y + 15), fill=c)
        d.rectangle((x + 7, y + 7, x + 9, y + 9), fill=lerp(c, (255, 255, 255), 0.6))
        text(d, (x + 18, y + 13), str(i + 1), 7, (255, 255, 255))
    d.rectangle((0, h - 11, w, h), fill=(8, 6, 22))
    text(d, (4, h - 11), 'Menu', 8, (230, 235, 255))
    text(d, (w - 4, h - 11), 'Túi đồ', 8, (230, 235, 255), anchor='ra')
    text(d, (w // 2, h - 11), 'Tự đánh: BẬT', 8, (52, 211, 153), anchor='ma')


def scene(w, h, seed=3):
    rnd = random.Random(seed)
    img = Image.new('RGBA', (w, h), (0, 0, 0, 255))
    d = ImageDraw.Draw(img)
    horizon = int(h * 0.62)
    sky(d, w, h, horizon + 10)
    stars(d, w, h, rnd)
    # Keep the moon clear of the quest panel in the top-right corner.
    moon(img, int(w * (0.76 if h > w else 0.6)), int(h * (0.2 if h > w else 0.26)), max(10, min(w, h) // 14))
    d = ImageDraw.Draw(img)
    ridge(d, w, int(h * 0.5), int(h * 0.12), (70, 40, 110), rnd, step=8, snow=(220, 220, 255))
    castle(d, int(w * 0.5) - 23, int(h * 0.5) - 6)
    ridge(d, w, int(h * 0.58), int(h * 0.06), (44, 28, 84), rnd, step=5)
    for i in range(0, w + 12, 11):
        pine(d, i + rnd.randint(-2, 2), horizon + rnd.randint(-3, 2), rnd.randint(9, 13), (24, 70, 70), (30, 92, 80))
    ground(d, w, h, horizon + 4)
    gy = horizon + int((h - horizon) * 0.45)
    hero(d, int(w * 0.3), gy - 6)
    slime(d, int(w * 0.58), gy + 2, (120, 220, 120))
    slime(d, int(w * 0.75), gy + 8, (240, 120, 200))
    for cx, cy in ((int(w * 0.5), gy + 18), (int(w * 0.53), gy + 22), (int(w * 0.66), gy + 24)):
        coin(d, cx, cy)
    text(d, (int(w * 0.62), gy - 16), '-1.288', 11, (255, 220, 80), font=DISPLAY)
    text(d, (int(w * 0.6), gy - 28), 'CHÍ MẠNG!', 8, (255, 120, 120))
    d.rounded_rectangle((int(w * 0.08), gy - 30, int(w * 0.08) + 82, gy - 16), 4, fill=(255, 255, 255))
    d.polygon([(int(w * 0.3) - 2, gy - 17), (int(w * 0.3) + 6, gy - 17), (int(w * 0.3) + 4, gy - 9)], fill=(255, 255, 255))
    text(d, (int(w * 0.08) + 41, gy - 29), 'Treo máy 24/24!', 8, (30, 30, 60), stroke=(255, 255, 255), anchor='ma')
    hud(d, w, h)
    skills(d, w, h)
    return img


def main():
    out = ROOT / 'web/public/art'
    out.mkdir(parents=True, exist_ok=True)
    for name, (w, h) in {'game-portrait': (240, 320), 'game-landscape': (320, 240)}.items():
        img = scene(w, h)
        img.convert('RGB').save(out / f'{name}.png')
        img.resize((w * 3, h * 3), Image.NEAREST).convert('RGB').save(out / f'{name}@3x.png')
        print(out / f'{name}@3x.png')


if __name__ == '__main__':
    main()
