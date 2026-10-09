#!/usr/bin/env python3
"""Exit 0 when two screenshots are the SAME to within a tolerance.

The settle check behind every capture script (`shoot.sh`, `watch-shots.sh`):
a tuner's dial is a live reading converging on its target and the strobe
band is an animation, so a fixed sleep captures whatever moment it lands
on — while exact equality never arrives, because a needle a pixel wide
keeps twitching and the signal bar breathes. Comparing by HOW MUCH of the
frame changed answers the question the scripts actually have: has the
layout arrived, with only the live parts still alive?

    frame-delta.py <a.png> <b.png> <tolerance-percent>

Reads PNGs directly rather than through an image library, so the capture
scripts need no Python environment of their own.

**On choosing a tolerance.** The comparison is over PNG-filtered bytes,
where most values encode deltas from neighbouring pixels — so a flat area
compresses to identical bytes whatever its colour, and the percentages run
far smaller than intuition suggests. Measured on real captures (2026-10):
consecutive SETTLED frames of a live dial differ by 0.008–0.028%, while
the same screen in Light vs Dark differs by 1.72%. Two orders of magnitude
apart, so 0.2% separates them with room on both sides. Do not reach for a
"reasonable-sounding" 2% — that calls Light and Dark the same screen.
"""
import struct
import sys
import zlib

# Sample every 97th byte of the decompressed stream: enough to see a layout
# change, cheap enough to run twice a second. 97 is prime, so the stride
# never aligns with the row stride and keeps sampling the same column.
STRIDE = 97


def pixels(path):
    """(width, height, decompressed image data) for a PNG."""
    data = open(path, "rb").read()
    position, width, height, raw = 8, 0, 0, b""
    while position < len(data):
        length, kind = struct.unpack(">I4s", data[position:position + 8])
        body = data[position + 8:position + 8 + length]
        if kind == b"IHDR":
            width, height = struct.unpack(">II", body[:8])
        elif kind == b"IDAT":
            raw += body
        elif kind == b"IEND":
            break
        position += length + 12
    return width, height, zlib.decompress(raw)


def main():
    if len(sys.argv) != 4:
        sys.exit("usage: frame-delta.py <a.png> <b.png> <tolerance-percent>")
    first_width, first_height, first = pixels(sys.argv[1])
    second_width, second_height, second = pixels(sys.argv[2])
    # A size change is a different screen, not a settled one.
    if (first_width, first_height) != (second_width, second_height):
        sys.exit(1)

    span = range(0, min(len(first), len(second)), STRIDE)
    sampled = max(1, len(span))
    differing = sum(1 for i in span if first[i] != second[i])
    sys.exit(0 if differing * 100 / sampled < float(sys.argv[3]) else 1)


main()
