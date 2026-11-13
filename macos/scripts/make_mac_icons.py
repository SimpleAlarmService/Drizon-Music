"""Builds the macOS AppIcon set from the iOS 1024px icon.

macOS does not round app icons for you: the PNG itself must carry the rounded
shape on a transparent canvas (824px body centred in 1024px, like Apple's
template), plus a soft drop shadow.  Run: python3 macos/scripts/make_mac_icons.py
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

root = Path(__file__).resolve().parents[2]
src = Image.open(root / 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png').convert('RGB')
out = root / 'macos/Runner/Assets.xcassets/AppIcon.appiconset'

S, BODY, SS = 1024, 824, 4
off = (S - BODY) // 2
radius = round(BODY * 0.2237)

mask = Image.new('L', (S * SS, S * SS), 0)
ImageDraw.Draw(mask).rounded_rectangle(
    [off * SS, off * SS, (off + BODY) * SS - 1, (off + BODY) * SS - 1], radius * SS, fill=255)
mask = mask.resize((S, S), Image.LANCZOS)

body = src.resize((BODY, BODY), Image.LANCZOS)
art = Image.new('RGBA', (S, S), (0, 0, 0, 0))
art.paste(body, (off, off))
art.putalpha(mask)

shadow = Image.new('RGBA', (S, S), (0, 0, 0, 0))
shadow.putalpha(mask.point(lambda v: int(v * 0.35)))
shadow = shadow.filter(ImageFilter.GaussianBlur(14))
shifted = Image.new('RGBA', (S, S), (0, 0, 0, 0))
shifted.paste(shadow, (0, 10))
icon = Image.alpha_composite(shifted, art)

for px in (16, 32, 64, 128, 256, 512, 1024):
    icon.resize((px, px), Image.LANCZOS).save(out / f'app_icon_{px}.png')
print('wrote', out)
