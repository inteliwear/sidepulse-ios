"""Install rendered Dot PNGs and regenerate artwork review sheets (requires Pillow)."""
import argparse
import json
import shutil
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

parser = argparse.ArgumentParser()
parser.add_argument('renders', type=Path)
args = parser.parse_args()
root = args.renders
assets = Path(__file__).resolve().parents[1] / 'SidePulse/Assets.xcassets'
colors = ['Red', 'Green', 'Blue', 'Purple', 'Aqua', 'Ember']
for mode in ['Pulse', 'Breathe']:
    for color in colors:
        name = f'Shortcut{mode}Dot{color}'
        src = root / f'{name}.png'
        im = Image.open(src)
        assert im.size == (512, 512) and im.mode == 'RGBA'
        assert im.getextrema()[-1][0] == 0
        folder = assets / f'{name}.imageset'
        shutil.copy2(src, folder / f'{name}.png')
        (folder / 'Contents.json').write_text(json.dumps({
            'images': [{'filename': f'{name}.png', 'idiom': 'universal'}],
            'info': {'author': 'xcode', 'version': 1}}, indent=2) + '\n')

font = '/System/Library/Fonts/SFNS.ttf'
label = ImageFont.truetype(font, 24)
heading = ImageFont.truetype(font, 32)
small = ImageFont.truetype(font, 18)
for theme, bg, panel, fg in [('light', '#ffffff', '#f2f2f7', '#17191d'),
                             ('dark', '#161618', '#252527', '#f4f4f7')]:
    sheet = Image.new('RGB', (1380, 690), bg)
    d = ImageDraw.Draw(sheet)
    d.text((36, 24), 'SidePulse · Shortcut artwork', font=heading, fill=fg)
    d.text((36, 70), 'Blender renders · transparent background · six action colors', font=small, fill=fg)
    for row, mode in enumerate(['Pulse', 'Breathe']):
        y = 115 + row * 280
        d.rounded_rectangle((24, y, 1356, y + 254), radius=24, fill=panel)
        d.text((48, y + 15), 'Blink' if mode == 'Pulse' else 'Breathe', font=label, fill=fg)
        for col, color in enumerate(colors):
            x = 48 + col * 218
            im = Image.open(root / f'Shortcut{mode}Dot{color}.png').resize((172, 172), Image.Resampling.LANCZOS)
            sheet.paste(im, (x, y + 47), im)
            d.text((x + 86, y + 210), color, anchor='mt', font=label, fill=fg)
    sheet.save(root / f'shortcut-preview-{theme}.png')
sheet = Image.new('RGB', (720, 200), '#f2f2f7')
d = ImageDraw.Draw(sheet)
d.text((24, 14), 'Small-size check · 64 px artwork', font=small, fill='#17191d')
for i, color in enumerate(colors):
    im = Image.open(root / f'ShortcutPulseDot{color}.png').resize((64, 64), Image.Resampling.LANCZOS)
    sheet.paste(im, (28 + i * 116, 64), im)
    d.text((60 + i * 116, 144), color, anchor='mt', font=small, fill='#17191d')
sheet.save(root / 'shortcut-size-check.png')
im = Image.new('RGB', (1600, 800))
for i, name in enumerate(['dot-top.png', 'dot-angled.png']):
    im.paste(Image.open(root / name).convert('RGB').resize((800, 800), Image.Resampling.LANCZOS), (i * 800, 0))
im.save(root / 'studio-views.jpg', quality=95)
print('Installed 12 PNG assets and regenerated all review sheets.')
