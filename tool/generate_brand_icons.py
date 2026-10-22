"""Fit the supplied D2F wordmark into legacy and adaptive Android icons."""
from pathlib import Path
from PIL import Image, ImageChops

root = Path(__file__).resolve().parents[1]
source = Image.open(root / 'design/02_D2F_Wordmark.png').convert('RGB')
# Remove the source's white margins without changing the wordmark proportions.
difference = ImageChops.difference(source, Image.new('RGB', source.size, 'white'))
bounds = difference.convert('L').point(lambda value: 255 if value > 15 else 0).getbbox()
if bounds is None:
    raise ValueError('The wordmark image is empty')
wordmark = source.crop(bounds)
res = root / 'android/app/src/main/res'


def centered_icon(size, artwork_width, background):
    canvas = Image.new('RGBA', (size, size), background)
    artwork_height = round(artwork_width * wordmark.height / wordmark.width)
    artwork = wordmark.resize((artwork_width, artwork_height), Image.Resampling.LANCZOS)
    canvas.paste(artwork, ((size - artwork_width) // 2, (size - artwork_height) // 2))
    return canvas


for density, size in [('mdpi',48),('hdpi',72),('xhdpi',96),('xxhdpi',144),('xxxhdpi',192)]:
    target = res / f'mipmap-{density}'
    target.mkdir(parents=True, exist_ok=True)
    centered_icon(size, round(size * 0.84), 'white').convert('RGB').save(target / 'ic_launcher.png')

# A 108dp adaptive layer has a central 66dp safe circle. A 60dp-wide
# wordmark (including its corners) fits inside it on every launcher mask.
foreground_dir = res / 'drawable-nodpi'
foreground_dir.mkdir(exist_ok=True)
centered_icon(432, 240, (255, 255, 255, 0)).save(foreground_dir / 'd2f_launcher_foreground.png')
# Remove the previous density-dependent foreground so Android has one source.
(res / 'drawable/d2f_launcher_foreground.png').unlink(missing_ok=True)
(res / 'mipmap-anydpi-v26').mkdir(exist_ok=True)
(res / 'mipmap-anydpi-v26/ic_launcher.xml').write_text('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@android:color/white" />
    <foreground android:drawable="@drawable/d2f_launcher_foreground" />
</adaptive-icon>
''')
