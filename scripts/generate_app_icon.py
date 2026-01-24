#!/usr/bin/env python3
"""
Generate a simple Apple-style app icon (rounded square + waveform).
Outputs a .icns file via iconutil.
"""

import os
import math
import zlib
from pathlib import Path


def write_png(path, width, height, pixels):
    """Write RGBA PNG from flat byte array (len = width*height*4)."""
    # PNG file header
    png_sig = b"\x89PNG\r\n\x1a\n"
    # IHDR chunk
    ihdr = bytearray()
    ihdr += width.to_bytes(4, "big")
    ihdr += height.to_bytes(4, "big")
    ihdr += b"\x08"  # bit depth
    ihdr += b"\x06"  # color type RGBA
    ihdr += b"\x00"  # compression
    ihdr += b"\x00"  # filter
    ihdr += b"\x00"  # interlace
    ihdr_chunk = chunk(b"IHDR", ihdr)

    # IDAT chunk (zlib-compressed scanlines)
    raw = bytearray()
    stride = width * 4
    for y in range(height):
        raw.append(0)  # filter type 0
        start = y * stride
        raw.extend(pixels[start:start + stride])
    compressed = zlib.compress(bytes(raw), level=9)
    idat_chunk = chunk(b"IDAT", compressed)

    # IEND chunk
    iend_chunk = chunk(b"IEND", b"")

    with open(path, "wb") as f:
        f.write(png_sig)
        f.write(ihdr_chunk)
        f.write(idat_chunk)
        f.write(iend_chunk)


def chunk(chunk_type, data):
    length = len(data).to_bytes(4, "big")
    crc = zlib.crc32(chunk_type + data).to_bytes(4, "big")
    return length + chunk_type + data + crc


def color(hex_str, alpha=255):
    hex_str = hex_str.lstrip("#")
    r = int(hex_str[0:2], 16)
    g = int(hex_str[2:4], 16)
    b = int(hex_str[4:6], 16)
    return (r, g, b, alpha)


def draw_icon(size):
    width = height = size
    pixels = bytearray(width * height * 4)

    # Colors
    top = color("#2C2F38")
    bottom = color("#12151B")
    wave = color("#E8EEF6")

    # Rounded rect parameters
    radius = int(size * 0.2)

    def set_px(x, y, rgba):
        idx = (y * width + x) * 4
        pixels[idx:idx + 4] = bytes(rgba)

    # Background with vertical gradient
    for y in range(height):
        t = y / (height - 1)
        r = int(top[0] * (1 - t) + bottom[0] * t)
        g = int(top[1] * (1 - t) + bottom[1] * t)
        b = int(top[2] * (1 - t) + bottom[2] * t)
        row_color = (r, g, b, 255)
        for x in range(width):
            # Check rounded rect mask
            inside = True
            if x < radius and y < radius:
                dx = radius - x
                dy = radius - y
                inside = (dx * dx + dy * dy) <= radius * radius
            elif x >= width - radius and y < radius:
                dx = x - (width - radius - 1)
                dy = radius - y
                inside = (dx * dx + dy * dy) <= radius * radius
            elif x < radius and y >= height - radius:
                dx = radius - x
                dy = y - (height - radius - 1)
                inside = (dx * dx + dy * dy) <= radius * radius
            elif x >= width - radius and y >= height - radius:
                dx = x - (width - radius - 1)
                dy = y - (height - radius - 1)
                inside = (dx * dx + dy * dy) <= radius * radius

            if inside:
                set_px(x, y, row_color)
            else:
                set_px(x, y, (0, 0, 0, 0))

    # Waveform bars
    bar_count = 5
    bar_width = int(size * 0.09)
    bar_spacing = int(size * 0.06)
    bar_heights = [0.35, 0.6, 0.82, 0.6, 0.35]

    total_width = bar_count * bar_width + (bar_count - 1) * bar_spacing
    start_x = (width - total_width) // 2
    center_y = height // 2
    cap_radius = bar_width // 2

    for i in range(bar_count):
        h = int(size * bar_heights[i])
        x0 = start_x + i * (bar_width + bar_spacing)
        x1 = x0 + bar_width - 1
        y0 = center_y - h // 2
        y1 = center_y + h // 2

        # Draw bar rectangle
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                set_px(x, y, wave)

        # Rounded caps
        cx = x0 + bar_width // 2
        for y in range(y0 - cap_radius, y0 + cap_radius + 1):
            for x in range(cx - cap_radius, cx + cap_radius + 1):
                dx = x - cx
                dy = y - y0
                if dx * dx + dy * dy <= cap_radius * cap_radius:
                    if 0 <= x < width and 0 <= y < height:
                        set_px(x, y, wave)
        for y in range(y1 - cap_radius, y1 + cap_radius + 1):
            for x in range(cx - cap_radius, cx + cap_radius + 1):
                dx = x - cx
                dy = y - y1
                if dx * dx + dy * dy <= cap_radius * cap_radius:
                    if 0 <= x < width and 0 <= y < height:
                        set_px(x, y, wave)

    return pixels


def generate_iconset(output_dir):
    output_dir.mkdir(parents=True, exist_ok=True)
    sizes = [16, 32, 64, 128, 256, 512, 1024]

    for size in sizes:
        pixels = draw_icon(size)
        write_png(output_dir / f"icon_{size}x{size}.png", size, size, pixels)
        if size <= 512:
            # @2x
            pixels2x = draw_icon(size * 2)
            write_png(output_dir / f"icon_{size}x{size}@2x.png", size * 2, size * 2, pixels2x)


def main():
    script_dir = Path(__file__).resolve().parent
    iconset_dir = script_dir / "Remix.iconset"
    icns_path = script_dir / "Remix.icns"

    if iconset_dir.exists():
        for f in iconset_dir.iterdir():
            f.unlink()
    else:
        iconset_dir.mkdir(parents=True, exist_ok=True)

    generate_iconset(iconset_dir)

    # Convert iconset to icns
    os.system(f"iconutil -c icns \"{iconset_dir}\" -o \"{icns_path}\"")


if __name__ == "__main__":
    main()
