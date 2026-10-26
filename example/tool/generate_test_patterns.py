"""Generates the aspect-ratio test pattern videos in example/assets/videos/.

Each clip shows a red border (to spot cropping), a 10x10 grid, a circle (it
turns into an ellipse if the player distorts the picture), a label with the
intended display shape, and ffmpeg's moving testsrc2 pattern behind it.

Requirements: ffmpeg 7+ on PATH (for -display_rotation), and Pillow 10.1+
(`pip install pillow`).
Run from anywhere:  python3 example/tool/generate_test_patterns.py
"""

import pathlib
import subprocess
import tempfile

from PIL import Image, ImageDraw, ImageFont

OUT = pathlib.Path(__file__).resolve().parent.parent / 'assets' / 'videos'
FONT = '/System/Library/Fonts/Helvetica.ttc'  # macOS; falls back elsewhere
SECONDS = 6

# (file name, label, display width, display height, extra)
# Display sizes are even so H.264 4:2:0 can encode them.
# extra: 'rotate' stores the clip sideways with a 90 degree rotation flag (like
# phone recordings); 'anamorphic' stores it squeezed with non-square pixels.
PATTERNS = [
    ('ratio_1x3.mp4', '1:3', 240, 720, None),
    ('ratio_3x1.mp4', '3:1', 720, 240, None),
    ('ratio_5x7.mp4', '5:7', 500, 700, None),
    ('ratio_13x5.mp4', '13:5', 650, 250, None),
    ('ratio_17x11.mp4', '17:11', 680, 440, None),
    ('ratio_2_37x1.mp4', '2.37:1', 852, 360, None),
    ('rotated_9x16.mp4', '9:16 rotated', 360, 640, 'rotate'),
    ('anamorphic_16x9.mp4', '16:9 anamorphic', 640, 360, 'anamorphic'),
]


def overlay(path, label, w, h):
    """Transparent PNG: border, grid, circle and label at display size."""
    img = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for i in range(1, 10):
        d.line([(w * i // 10, 0), (w * i // 10, h)], fill=(255, 255, 255, 70))
        d.line([(0, h * i // 10), (w, h * i // 10)], fill=(255, 255, 255, 70))
    border = max(2, min(w, h) // 60)
    d.rectangle([0, 0, w - 1, h - 1], outline=(255, 40, 40, 255), width=border)
    r = min(w, h) * 0.32
    cx, cy = w / 2, h / 2
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=(255, 220, 0, 255),
              width=max(2, border))
    text = f'{label}\n{w}x{h}'
    size = max(10, int(min(w, h) * 0.12))
    label_font = font(size)
    box = d.multiline_textbbox((0, 0), text, font=label_font, align='center')
    tw, th = box[2] - box[0], box[3] - box[1]
    pad = size // 3
    d.rectangle([cx - tw / 2 - pad, cy - th / 2 - pad, cx + tw / 2 + pad,
                 cy + th / 2 + pad], fill=(0, 0, 0, 170))
    d.multiline_text((cx - tw / 2 - box[0], cy - th / 2 - box[1]), text,
                     font=label_font, fill='white', align='center')
    # "TOP" marker so a wrong rotation is obvious.
    d.text((cx, border * 3), 'TOP', font=font(size * 2 // 3),
           fill=(255, 40, 40, 255), anchor='mt')
    img.save(path)


def font(size):
    try:
        return ImageFont.truetype(FONT, size)
    except OSError:
        return ImageFont.load_default(size=size)


def ffmpeg(*args):
    subprocess.run(['ffmpeg', '-v', 'error', '-y', *args], check=True)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        for name, label, w, h, extra in PATTERNS:
            png = pathlib.Path(tmp) / f'{name}.png'
            overlay(png, label, w, h)
            source = f'testsrc2=size={w}x{h}:rate=24:duration={SECONDS}'
            graph = '[0:v][1:v]overlay'
            if extra == 'rotate':
                # Store sideways; the rotation flag below turns it upright.
                graph += ',transpose=clock'
            elif extra == 'anamorphic':
                # Squeeze 640 wide into 480 pixels that are 4:3 wide each.
                graph += f',scale={w * 3 // 4}:{h},setsar=4/3'
            encoded = pathlib.Path(tmp) / name
            ffmpeg('-f', 'lavfi', '-i', source, '-i', str(png),
                   '-filter_complex', graph, '-c:v', 'libx264',
                   '-profile:v', 'main', '-pix_fmt', 'yuv420p', '-crf', '30',
                   '-movflags', '+faststart', '-an', str(encoded))
            target = OUT / name
            if extra == 'rotate':
                ffmpeg('-display_rotation', '90', '-i', str(encoded),
                       '-c', 'copy', '-movflags', '+faststart', str(target))
            else:
                target.write_bytes(encoded.read_bytes())
            print(f'{target.name}: {target.stat().st_size // 1024} KB')


if __name__ == '__main__':
    main()
