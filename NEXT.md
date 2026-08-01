# Where this left off

Written 2026-08-01, at the end of the scaffolding session. Delete this file once
its contents are stale — it's a handoff note, not permanent documentation.

## State

The scaffold is complete and fully green:

- 31 tests passing (`make test`, ~0.07 s)
- SwiftLint and swift-format both clean **when run from the repo root**
- Both app targets build (`xcodebuild` iOS simulator + macOS)
- `make run-mac` verified launching a real app with real microphone capture
- 8 commits on `main`, clean tree, **no git remote configured yet**

Nothing has been tested against an actual instrument.

## Do these first

1. **Wire the remote.** The GitHub repo exists but isn't connected:

   ```sh
   git remote add origin git@github.com:vlumi/nitpitch.git
   git push -u origin main
   ```

   CI (`.github/workflows/ci.yml`) will run on first push. It expects a
   `CODECOV_TOKEN` secret; without it the coverage upload soft-fails
   (`fail_ci_if_error: false`), so the build stays green either way.

2. **Rename `Tuner` → `Nitpitch`.** Mechanical; ROADMAP § 1 lists every place it
   touches. Verify with `make test`, both linters from the repo root, and both
   `xcodebuild build` targets. Worth doing before there's any history to
   conflict with.

3. **Take it to a real violin.** `make run-mac` is the fastest loop. This is the
   highest-value unknown in the project — everything is currently proven against
   synthesized tones only. Specifically watch:
   - Does the clarity gate (`Detection.clarityThreshold`, 0.9) survive real bow
     noise, or does it flicker?
   - How does the smoothing feel during vibrato?
   - Does the needle read as responsive or laggy?

   Any of these may send you into `Packages/TunerCore/Sources/TunerCore/DSP/`
   to retune constants. They're all in `Detection.swift`, deliberately.

## Things that will bite you

- **SourceKit reports `No such module 'TunerCore'`** for unindexed files. These
  are false. `swift build` / `swift test` / `xcodebuild` are authoritative.
- **Run SwiftLint from the repo root.** Its `excluded:` paths are relative to
  the invocation directory, so running it inside `Packages/TunerCore` lints the
  generated `.build` tree and reports ~55 false violations.
- **The iOS simulator has no usable microphone** — it reports a device and
  delivers silence. Use the Mac app or a real device for anything audio.
- **The built-in Mac mic is voice-processed**, and macOS has no `.measurement`
  equivalent to opt out. Don't tune thresholds against it; use an external mic
  or interface, then confirm on a phone.

## Don't do these

- **Don't create App Store Connect records.** The user does that.
- **Don't make `PitchDetector` polyphonic.** Double-stop fifths (ROADMAP § 3)
  need a *separate* detector; MPM returns one lag and flickers on two notes.
- **Don't "simplify" the DSP** without running the detector tests. Three
  invariants there each produce plausible-but-wrong readings when broken — they
  are documented in AGENTS.md under "How detection works, and why".

## Two fixes owed upstream to donpa

Found while porting its scaffold; fixed here, still broken there:

1. `Scripts/embed-commit-sha.sh` fails the build on a repo with no commits yet
   (fresh `git init`), not just on a non-git checkout.
2. The SwiftLint invocation-directory trap above is worth a line in donpa's
   AGENTS.md too.
