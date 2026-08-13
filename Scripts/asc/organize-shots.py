#!/usr/bin/env python3
"""Rename a folder of raw screenshots to the canonical set, by CAPTURE ORDER —
so you shoot in the listed order, dump the files in one folder, and this names
them without you having to look at each image.

The order is the SCREENSHOTS.md shot list. Every platform captures the same
set.

  # print the order to shoot in (do this first):
  Scripts/asc/organize-shots.py iphone --list

  # after dumping raw shots into <dir> (sorted by filename = capture order):
  Scripts/asc/organize-shots.py iphone <dir>
  Scripts/asc/organize-shots.py ipad   <dir>
  Scripts/asc/organize-shots.py mac    <dir>

Sorted by filename ascending — macOS names shots "Screenshot … at H.MM.SS",
Simulator names them by timestamp too, so lexical sort == capture order. Pass
--by-mtime if your names don't sort chronologically.

Multiple languages in ONE folder: shoot each language's full set back-to-back,
dump all into <dir>, and pass the order with --langs. The files split into
per-language subfolders, canonically named (en-only today; the flag is for
when the deferred localization lands):

  Scripts/asc/organize-shots.py iphone <dir> --langs=en
  # → <dir>/en/grid-iphone.png, <dir>/en/string-view-iphone.png, …

Expects exactly (shots × languages) files; the first chunk is the first
language, and so on.
"""
import os
import sys

# Canonical shots in CAPTURE order (see SCREENSHOTS.md — the recommended STORE
# order differs; arrange at upload). Each: (name, launch-args, what-to-capture).
# The launch args stage exact readings via -demo-pose (the demo IS the real
# pipeline on a synthesized signal, so a pose is simply what "plays");
# consecutive shots with identical args share one app session, which is also
# what lets grid-dark reuse grid's staging and `launch` keep its in-app
# staging alive through `presets` and `share`.
# Poses are in A=440 EQUAL cents, but the violin defaults to PURE fifths —
# its D target sits 1.955¢ below equal D — so "D dead on its target" is
# 62@-2, not 62. Chosen by looking at the rendered pixels: D earns the slim
# centred needle at 0¢, A reads −4¢ (green, visibly left, one amber dot lit)
# and the pair beats at 2.0/s. One string done, one settling: the story.
SHOTS = [
    ("grid",
     "-demo-open violin -demo-pose 62@-2,69@-4",
     "The violin grid, D and A genuinely sounding together: D dead on its "
     "pure target (0¢, slim needle), A 4¢ low, the interval lane beating "
     "at 2.0/s. Frame and shoot."),
    ("grid-dark",
     "-demo-open violin -demo-pose 62@-2,69@-4",
     "The SAME grid in Dark: flip the in-app Appearance to Dark, re-frame, "
     "capture, flip back to Light. The dark-mode taster."),
    ("reference",
     "-demo-open violin -demo-pose 62@-2,69@-4",
     "Still on the grid: open the tuning menu, step the reference to A=442, "
     "temperament on Pure — the orchestra story in one frame. (The dials "
     "behind go honestly amber-flat: you raised the A on them.)"),
    ("string-view",
     "-demo-open violin -demo-pose 69@2",
     "Tap the A string's dial: the single-string view holding 2¢ sharp — "
     "big dial just off centre, the strobe band awake. Frame and shoot."),
    ("launch",
     "-demo-pose 69@-3",
     "The chromatic tuner over the instrument rack: A4 green at −3¢, the "
     "readout doing the talking. Stage first: star the violin and a guitar "
     "in the chooser, pin Drop D on the guitar so a preset chip shows."),
    ("presets",
     "-demo-pose 69@-3",
     "All presets… from the launch screen: the browser with the seeded "
     "tunings (Drop D, DADGAD, Open G…), instrument filter visible."),
    ("share",
     "-demo-pose 69@-3",
     "Share Drop D from the browser: the QR + link sheet. 'Hand a tuning "
     "to a bandmate' in one image."),
]


def rename_set(d, raw_files, names, platform, subdir=None):
    """Rename `raw_files` (already in capture order) to canonical names, into
    `d`/`subdir` when a subdir (a language) is given."""
    out = os.path.join(d, subdir) if subdir else d
    os.makedirs(out, exist_ok=True)
    for src, name in zip(raw_files, names):
        dst = f"{name}-{platform}.png"
        os.rename(os.path.join(d, src), os.path.join(out, dst))
        print(f"  {src}  →  {os.path.join(subdir, dst) if subdir else dst}")


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    flags = [a for a in sys.argv[1:] if a.startswith("--")]
    flagset = {f.split("=", 1)[0] for f in flags}
    langs = next(
        (f.split("=", 1)[1].split(",") for f in flags if f.startswith("--langs=")), None)
    if not args or args[0] not in ("iphone", "ipad", "mac"):
        sys.exit(
            "usage: organize-shots.py <iphone|ipad|mac> "
            "[<dir> | --list] [--by-mtime] [--langs=en]")
    platform = args[0]
    names = [name for name, _, _ in SHOTS]

    if "--plain" in flagset:  # machine-readable, for Scripts/shoot.sh
        for name, launch_args, desc in SHOTS:
            print(f"{name}\t{launch_args}\t{desc}")
        return

    if "--list" in flagset or len(args) < 2:
        print(f"Capture these {len(SHOTS)} shots for {platform}, in this order:\n")
        for i, (name, launch_args, desc) in enumerate(SHOTS, 1):
            print(f"  {i}. {name}-{platform}.png   (launch: {launch_args})")
            print(f"     {desc}")
        print("\nShots 1 (grid, Light) and 2 (grid-dark) are the same staged "
              "screen:\nshoot 1, flip Appearance to Dark in-app, shoot 2, flip "
              "back to Light,\nthen carry on. Everything else is Light.")
        print("\nDrop the raw files in a folder, then:\n"
              f"  Scripts/asc/organize-shots.py {platform} <dir>")
        return

    d = args[1]
    raw = [f for f in os.listdir(d)
           if f.lower().endswith((".png", ".jpg", ".jpeg")) and not f.startswith(".")]
    key = (
        (lambda f: os.path.getmtime(os.path.join(d, f)))
        if "--by-mtime" in flagset else str.lower)
    raw.sort(key=key)

    # One flat set, or several equal-size language sets back-to-back.
    groups = langs or [None]
    expected = len(names) * len(groups)
    if len(raw) != expected:
        print(f"⚠ found {len(raw)} images but expected {expected} for {platform}"
              + (f" ({len(names)} shots × {len(groups)} languages)" if langs else "") + ".")
        print("  Files (sorted):", raw)
        sys.exit("Fix the folder (one image per shot, in capture order) and re-run.")

    for i, lang in enumerate(groups):
        chunk = raw[i * len(names):(i + 1) * len(names)]
        rename_set(d, chunk, names, platform, subdir=lang)
    print(f"\nRenamed {expected} shot(s) for {platform}"
          + (f" across {len(groups)} languages." if langs else "."))


if __name__ == "__main__":
    main()
