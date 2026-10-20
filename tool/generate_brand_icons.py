"""Resize the supplied D2F artwork into Android launcher resources."""
from pathlib import Path
from PIL import Image

root = Path(__file__).resolve().parents[1]
source = Image.open(root / 'assets/images/d2f_2.png').convert('RGB')
res = root / 'android/app/src/main/res'
for density, size in [('mdpi',48),('hdpi',72),('xhdpi',96),('xxhdpi',144),('xxxhdpi',192)]:
    target = res / f'mipmap-{density}'
    target.mkdir(parents=True, exist_ok=True)
    source.resize((size,size), Image.Resampling.LANCZOS).save(target / 'ic_launcher.png')
foreground = Image.open(root / 'assets/images/d2f_3.png').convert('RGB')
foreground.resize((432,432), Image.Resampling.LANCZOS).save(res / 'drawable/d2f_launcher_foreground.png')
(res / 'mipmap-anydpi-v26').mkdir(exist_ok=True)
(res / 'mipmap-anydpi-v26/ic_launcher.xml').write_text('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@android:color/white" />
    <foreground><inset android:drawable="@drawable/d2f_launcher_foreground" android:inset="14dp" /></foreground>
</adaptive-icon>
''')
