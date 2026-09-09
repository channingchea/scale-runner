#!/usr/bin/env python3
"""Generate the metronome clicks (assets/audio/click.wav, click_accent.wav).

The original click was never committed with a script. Its recipe was
recovered in 2026-09 and `--verify` proves it reproduces the shipped file
byte for byte: a 1800 Hz sine, exponential decay of 120 /s, 0.8 full scale,
50 ms at 44.1 kHz mono 16-bit, truncated (not rounded) to integers.

The accent is the same click a perfect fifth higher (2700 Hz) with a slightly
longer tail (100 /s over 60 ms), so beat 1 of a bar reads as "the same
instrument, struck harder" rather than a different sound.

Usage
  python3 tool/gen_click_samples.py --verify   # click.wav is byte-identical
  python3 tool/gen_click_samples.py            # (re)write both files

Standard library only. Run from the repo root.
"""

import argparse
import math
import os
import struct
import sys
import wave

SAMPLE_RATE = 44100
PEAK = 0.8 * 32767

# (frequency Hz, decay per second, duration s)
CLICK = (1800.0, 120.0, 0.050)
ACCENT = (2700.0, 100.0, 0.060)

OUT_DIR = os.path.join('assets', 'audio')


def render(freq, decay, duration):
    n = int(SAMPLE_RATE * duration)
    out = bytearray()
    for i in range(n):
        t = i / SAMPLE_RATE
        v = PEAK * math.sin(2 * math.pi * freq * t) * math.exp(-decay * t)
        out += struct.pack('<h', int(v))  # int() truncates toward zero
    return bytes(out)


def write(path, frames):
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SAMPLE_RATE)
        w.writeframes(frames)


def read(path):
    with wave.open(path, 'rb') as w:
        return w.readframes(w.getnframes())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--verify', action='store_true',
                    help='check click.wav against the recipe without writing')
    args = ap.parse_args()

    click_path = os.path.join(OUT_DIR, 'click.wav')
    accent_path = os.path.join(OUT_DIR, 'click_accent.wav')

    if args.verify:
        ok = read(click_path) == render(*CLICK)
        print('click.wav', 'matches' if ok else 'DIFFERS')
        sys.exit(0 if ok else 1)

    write(click_path, render(*CLICK))
    write(accent_path, render(*ACCENT))
    print('wrote', click_path, 'and', accent_path)


if __name__ == '__main__':
    main()
