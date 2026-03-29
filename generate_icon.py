#!/usr/bin/env python3
"""Generate myClaude app icon - a Claude-inspired design using pure Python."""
import struct
import zlib
import math
import os

def create_png(width, height, pixels):
    """Create a PNG file from RGBA pixel data."""
    def make_chunk(chunk_type, data):
        chunk = chunk_type + data
        return struct.pack('>I', len(data)) + chunk + struct.pack('>I', zlib.crc32(chunk) & 0xffffffff)

    header = b'\x89PNG\r\n\x1a\n'
    ihdr = make_chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0))

    raw_data = b''
    for y in range(height):
        raw_data += b'\x00'  # filter: none
        for x in range(width):
            idx = (y * width + x) * 4
            raw_data += bytes(pixels[idx:idx+4])

    idat = make_chunk(b'IDAT', zlib.compress(raw_data, 9))
    iend = make_chunk(b'IEND', b'')

    return header + ihdr + idat + iend


def lerp(a, b, t):
    return a + (b - a) * t


def draw_icon(size):
    pixels = [0] * (size * size * 4)

    cx, cy = size / 2, size / 2
    radius = size / 2

    for y in range(size):
        for x in range(size):
            idx = (y * size + x) * 4
            dx = x - cx
            dy = y - cy
            dist = math.sqrt(dx * dx + dy * dy)

            # Rounded rectangle mask with large corner radius
            corner_r = size * 0.22
            in_rect = True
            # Check corners
            for cx2, cy2 in [(corner_r, corner_r), (size - corner_r, corner_r),
                             (corner_r, size - corner_r), (size - corner_r, size - corner_r)]:
                if ((x < corner_r or x > size - corner_r) and
                    (y < corner_r or y > size - corner_r)):
                    cdist = math.sqrt((x - cx2) ** 2 + (y - cy2) ** 2)
                    if cdist > corner_r:
                        in_rect = False

            if not in_rect:
                pixels[idx:idx+4] = [0, 0, 0, 0]
                continue

            # Background: warm Claude-like gradient (peach/terracotta)
            t = y / size
            bg_r = int(lerp(235, 200, t))
            bg_g = int(lerp(160, 110, t))
            bg_b = int(lerp(120, 80, t))

            r, g, b, a = bg_r, bg_g, bg_b, 255

            # Draw Claude-inspired starburst/sparkle shape
            # 6-pointed star with rounded feel
            angle = math.atan2(dy, dx)
            norm_dist = dist / (size * 0.35)

            # Star shape: 6 points
            star_r = 0.45 + 0.55 * abs(math.cos(3 * angle))
            # Inner glow
            inner_r = 0.2

            if norm_dist < star_r:
                # Sparkle body - white/cream
                fade = 1.0
                if norm_dist > star_r * 0.7:
                    fade = 1.0 - (norm_dist - star_r * 0.7) / (star_r * 0.3)
                fade = max(0, min(1, fade))

                sr = int(lerp(r, 255, fade))
                sg = int(lerp(g, 250, fade))
                sb = int(lerp(b, 245, fade))
                r, g, b = sr, sg, sb

            # Center dot
            if norm_dist < 0.15:
                fade = 1.0 - norm_dist / 0.15
                fade = fade ** 0.5
                r = int(lerp(r, 255, fade))
                g = int(lerp(g, 255, fade))
                b = int(lerp(b, 255, fade))

            # "my" text indicator: small "m" mark at bottom
            # Simple pixel pattern for a tiny "m" near bottom center

            pixels[idx] = max(0, min(255, r))
            pixels[idx+1] = max(0, min(255, g))
            pixels[idx+2] = max(0, min(255, b))
            pixels[idx+3] = a

    return pixels


def main():
    sizes = [16, 32, 64, 128, 256, 512, 1024]
    out_dir = 'MyClaude/Resources/Assets.xcassets/AppIcon.appiconset'
    os.makedirs(out_dir, exist_ok=True)

    for size in sizes:
        print(f"Generating {size}x{size}...")
        pixels = draw_icon(size)
        png_data = create_png(size, size, pixels)
        with open(f'{out_dir}/icon_{size}x{size}.png', 'wb') as f:
            f.write(png_data)

    # Contents.json for the asset catalog
    images = []
    icon_sizes = [
        (16, 1), (16, 2),
        (32, 1), (32, 2),
        (128, 1), (128, 2),
        (256, 1), (256, 2),
        (512, 1), (512, 2),
    ]
    for sz, scale in icon_sizes:
        actual = sz * scale
        images.append({
            "filename": f"icon_{actual}x{actual}.png",
            "idiom": "mac",
            "scale": f"{scale}x",
            "size": f"{sz}x{sz}"
        })

    import json
    contents = {"images": images, "info": {"author": "xcode", "version": 1}}
    with open(f'{out_dir}/Contents.json', 'w') as f:
        json.dump(contents, f, indent=2)

    print("Done! Icons generated.")


if __name__ == '__main__':
    main()
