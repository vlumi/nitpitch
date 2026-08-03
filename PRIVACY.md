# Privacy Policy

**Nitpitch does not collect, store, or transmit any personal data.**

Last updated: 1 August 2026.

## What the app does with the microphone

Nitpitch needs microphone access for the only reason a tuner could: to hear the
note you are playing and show you how far off it is.

Audio is analyzed **as it arrives, in memory, on your device**, and then
discarded. At any instant the app holds at most a fraction of a second of sound
— a small fixed buffer that is continuously overwritten by whatever comes next.

Specifically, the app does **not**:

- record audio, or write any sound to a file;
- keep a history of what you played, or of any reading;
- transmit audio, or anything derived from it, anywhere.

Nothing you play is ever saved or sent. There is no point at which a recording
exists.

## What is stored on your device

Three settings, kept so the app opens the way you left it:

- the reference pitch (for example A=440 or A=442),
- the selected instrument,
- the note-naming convention.

These live in the app's own preferences on your device. They are not personal
information, they are not transmitted, and they are removed when you delete the
app.

## Network access

**The app makes no network connections of any kind.**

On macOS this is enforced rather than merely promised: Nitpitch runs in the App
Sandbox without the network entitlement, so the operating system itself will not
permit it to open a connection. The only capability it requests is audio input.

On iOS the app requests no entitlements at all beyond the microphone permission
you are asked for directly.

## No tracking, no accounts, no third parties

- No analytics, telemetry, crash reporting, or usage measurement.
- No advertising, and no advertising identifiers.
- No accounts, and no sign-in.
- **No third-party code.** Nitpitch is built entirely on frameworks that ship
  with the operating system (AVFoundation, Accelerate, SwiftUI). There is no
  SDK from any other company in the app, so there is no one else to receive
  data even in principle.

## Children

The app collects no data from anyone, of any age.

## Your rights

Because no personal data is collected, there is nothing to request access to,
correct, export, or delete. Removing the app removes the three settings listed
above, and that is the entirety of what it leaves behind.

## Verifying any of this

Nitpitch is open source under the MIT license. Every claim on this page can be
checked in the code at <https://github.com/vlumi/nitpitch> — the entitlements
files show exactly which capabilities the app requests, and the audio path in
`AudioInput.swift` shows the buffer being overwritten rather than retained.

## Changes

If this policy ever changes, the revision will be published in this file, with
its history visible in the repository. Any change that affected what the app
does with your data would ship alongside the app version that made it.

## Contact

Questions about privacy in Nitpitch: <ville@misaki.fi>, or open an issue at
<https://github.com/vlumi/nitpitch/issues>.
