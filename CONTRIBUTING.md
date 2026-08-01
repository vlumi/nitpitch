# Contributing to Tuner

Thanks for your interest! The full contributor guide — project layout, build &
test commands, code style, and conventions — lives in **[AGENTS.md](AGENTS.md)**,
which is the single canonical source for both humans and AI coding agents. This
file just points you there so it's easy to find.

Quick orientation:

- **Build & run / tests:** see [AGENTS.md](AGENTS.md) (or the
  [README's Development section](README.md#development)). In short: Xcode 16+ and
  XcodeGen; `make test` runs the logic tests, `make run-iphone` / `make run-mac`
  build and launch.
- **What's planned:** [ROADMAP.md](ROADMAP.md). **What's changed:**
  [CHANGELOG.md](CHANGELOG.md).

Pull requests:

- Branch off `main`; keep the change focused.
- Match the surrounding code style. CI must stay green — SwiftLint +
  swift-format, the logic tests (with coverage), and both platform builds all run
  on CI; run `make test` and the linters locally before pushing.
- **Changes to the pitch detector need tests.** Wrong DSP produces *plausible*
  answers — a reading that's a few cents off, or an octave low, looks like a
  working tuner. `Packages/TunerCore/Tests` verifies against synthesized
  waveforms of known frequency; add a case there for anything you change.
- If your change is user-facing, add a bullet to `CHANGELOG.md` under
  `### Unreleased (next build)` in the same PR.
- Describe what changed and why in the PR body.

By contributing you agree your contributions are licensed under the repository's
[MIT License](LICENSE).
