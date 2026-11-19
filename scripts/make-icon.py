#!/usr/bin/env python3
"""Draws the 1024x1024 app icon (felt, a card back and a card with a diamond) with no dependencies."""
import struct
import sys
import zlib

SIZE = 1024
SS = 2  # supersampling per axis


def rounded_rect(x, y, cx, cy, w, h, r):
    dx = max(abs(x - cx) - (w / 2 - r), 0)
    dy = max(abs(y - cy) - (h / 2 - r), 0)
    return abs(x - cx) <= w / 2 and abs(y - cy) <= h / 2 and dx * dx + dy * dy <= r * r


def rotate(x, y, cx, cy, cos_a, sin_a):
    x, y = x - cx, y - cy
    return cx + x * cos_a + y * sin_a, cy - x * sin_a + y * cos_a


def colour(x, y):
    # Back card, tilted.
    bx, by = rotate(x, y, 430, 520, 0.966, 0.259)
    front = rounded_rect(x, y, 590, 540, 440, 616, 48)
    if front:
        if abs(x - 590) / 150 + abs(y - 540) / 205 <= 1:
            return (200, 26, 38)
        if rounded_rect(x, y, 590, 540, 440 - 8, 616 - 8, 44):
            return (250, 250, 250)
        return (40, 40, 40)
    if rounded_rect(bx, by, 430, 520, 440, 616, 48):
        if rounded_rect(bx, by, 430, 520, 360, 536, 30) and not rounded_rect(bx, by, 430, 520, 340, 516, 22):
            return (120, 150, 210)
        return (30, 60, 140)
    d = ((x - 512) ** 2 + (y - 512) ** 2) ** 0.5 / 724
    return (int(26 - 18 * d), int(128 - 52 * d), int(72 - 30 * d))


def main(path):
    rows = []
    for py in range(SIZE):
        row = bytearray([0])
        for px in range(SIZE):
            r = g = b = 0
            for sy in range(SS):
                for sx in range(SS):
                    c = colour(px + (sx + 0.5) / SS, py + (sy + 0.5) / SS)
                    r += c[0]; g += c[1]; b += c[2]
            n = SS * SS
            row += bytes((r // n, g // n, b // n))
        rows.append(bytes(row))

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(b"".join(rows), 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "App/Assets.xcassets/AppIcon.appiconset/icon-1024.png")
