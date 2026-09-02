#!/usr/bin/env python3
"""Generate the on-screen keyboard's note samples (assets/audio/note_<midi>.wav).

The original synthesis script was never committed. This one was reverse
engineered from the shipped files in 2026-09 and reproduces every note from
MIDI 48 to 72 **bit for bit** (`--verify` proves it), so it is safe to extend
the range without disturbing what is already in the app.

Two voices, because the files were made in two batches:

  low  (MIDI <= 72)  6 harmonics, 4 ms attack, 40 ms release
  high (MIDI >= 73)  5 harmonics, 5 ms attack, 20 ms release, darker spectrum

The high voice is the one the Jam Mode range (up to F5) was built with, so
notes above it continue that voice rather than jumping back to the brighter
one. Everything else is shared: additive sine partials with phase 0, each
partial decaying exponentially a little faster than the one below it, a linear
attack ramp, a linear release fade, then peak normalisation.

Usage
  python3 tool/gen_note_samples.py --verify          # check 48-72 byte-exactly
  python3 tool/gen_note_samples.py --missing         # write only absent files
  python3 tool/gen_note_samples.py --range 40 95     # write (overwrite) a range

Standard library only. Run from the repo root.
"""

import argparse
import math
import os
import struct
import sys
import wave

SAMPLE_RATE = 22050
DURATION_S = 1.1
NUM_SAMPLES = int(SAMPLE_RATE * DURATION_S)  # 24255
PEAK = 0.82 * 32767  # every file normalises to this, then truncates

# The app's playable range. Keep in sync with NotePlayer.lowMidi / highMidi.
# 40 is the guitar's low E. 95 is the highest note any drill can ask for: an
# Inversion Running cycle on B Major 7th tops out at 94, and the Voicings
# drill can transpose a full-width saved shape to 95 (see
# test/note_range_test.dart, which pins both ends).
LOW_MIDI = 40
HIGH_MIDI = 95

# Partials decay faster the higher they are, by this much per partial.
HARMONIC_DECAY_STEP = 0.90

# (harmonic weights, attack s, release s, decay at the split note, decay per semitone)
LOW_VOICE = ([1.0, 0.55, 0.32, 0.20, 0.12, 0.07], 0.004, 0.040, 48, 3.00, 0.090)
HIGH_VOICE = ([1.0, 0.501, 0.269, 0.156, 0.086], 0.005, 0.020, 73, 5.55, 0.125)
VOICE_SPLIT = 73  # first MIDI note that uses the high voice


def voice_for(midi):
    return LOW_VOICE if midi < VOICE_SPLIT else HIGH_VOICE


def render(midi):
    """One note as a list of int16 sample values."""
    weights, attack_s, release_s, ref_midi, ref_decay, decay_per_semi = voice_for(midi)
    f0 = 440.0 * 2.0 ** ((midi - 69) / 12.0)
    decay = ref_decay + decay_per_semi * (midi - ref_midi)

    samples = [0.0] * NUM_SAMPLES
    for i, weight in enumerate(weights):
        harmonic = i + 1
        freq = f0 * harmonic
        if freq >= SAMPLE_RATE / 2:  # never aliases in the shipped range
            continue
        k = decay + HARMONIC_DECAY_STEP * (harmonic - 1)
        w = 2.0 * math.pi * freq
        for n in range(NUM_SAMPLES):
            t = n / SAMPLE_RATE
            samples[n] += weight * math.sin(w * t) * math.exp(-k * t)

    for n in range(NUM_SAMPLES):
        t = n / SAMPLE_RATE
        env = min(t / attack_s, 1.0) * min((DURATION_S - t) / release_s, 1.0)
        samples[n] *= max(env, 0.0)

    scale = PEAK / max(abs(s) for s in samples)
    return [int(s * scale) for s in samples]  # int() truncates, as the originals do


def write_wav(path, samples):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SAMPLE_RATE)
        w.writeframes(struct.pack("<%dh" % len(samples), *samples))


def read_wav(path):
    with wave.open(path, "rb") as w:
        return list(struct.unpack("<%dh" % w.getnframes(), w.readframes(w.getnframes())))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default="assets/audio")
    ap.add_argument("--verify", action="store_true",
                    help="compare against the files on disk instead of writing")
    ap.add_argument("--missing", action="store_true",
                    help="write only notes that have no file yet")
    ap.add_argument("--range", nargs=2, type=int, metavar=("LOW", "HIGH"),
                    default=[LOW_MIDI, HIGH_MIDI])
    args = ap.parse_args()

    lo, hi = args.range
    failures = 0
    for midi in range(lo, hi + 1):
        path = os.path.join(args.dir, "note_%d.wav" % midi)
        if args.verify:
            if not os.path.exists(path):
                print("MISSING %s" % path)
                failures += 1
                continue
            got, want = render(midi), read_wav(path)
            worst = max(abs(a - b) for a, b in zip(got, want)) if len(got) == len(want) else -1
            status = "exact" if worst == 0 else "DIFFERS by %d" % worst
            print("note_%d.wav  %s" % (midi, status))
            if worst != 0:
                failures += 1
            continue
        if args.missing and os.path.exists(path):
            continue
        write_wav(path, render(midi))
        print("wrote %s" % path)

    if args.verify:
        print("\n%d of %d differ" % (failures, hi - lo + 1))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
