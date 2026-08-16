# Privacy Policy

**Nitpitch does not collect, store, or transmit any personal data.** Nothing
ever reaches the developer or any third party. If you enable iCloud sync — an
opt-in switch, off by default — your instrument setups travel between your own
devices through your Apple iCloud account, and that is the only thing that
ever leaves the device.

Last updated: 16 August 2026.

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

Your setup, kept so the app opens the way you left it: the instruments you
own (their names, tunings, reference pitches and locks), your saved presets,
your favorites and pins, and display preferences such as the note-naming
convention.

These live in the app's own preferences on your device. They are not
transmitted anywhere — unless you enable iCloud sync, below — and they are
removed when you delete the app.

## iCloud sync — opt-in, and what it moves

A switch in Settings (off by default, and off until
you touch it) syncs your instruments, presets and favorites between your own
devices signed in to the same iCloud account.

- **What moves:** the setup data listed above — instrument names, tunings,
  reference pitches, presets, favorites and pins.
- **What never moves:** audio, or anything derived from it. The microphone
  path is untouched by sync.
- **Where it goes:** Apple's iCloud Key-Value Storage, inside your own
  iCloud account — the same place your other apps' settings sync. It is not
  a server of ours; we have none, and no ability to read what syncs.
- **Turning it off** stops all syncing from that device. Data already synced
  remains in your iCloud account and on your other devices until changed or
  deleted there.

While the switch is off, the app behaves exactly as it always has: nothing
leaves the device.

## Network access

**The app itself makes no network connections of any kind.** Even with iCloud
sync enabled, the app writes to a local store and the operating system's own
iCloud daemon does the moving — outside the app, under Apple's iCloud terms.

On macOS this is enforced rather than merely promised: Nitpitch runs in the App
Sandbox without the network entitlement, so the operating system itself will
not permit it to open a connection. The capabilities it requests are audio
input and iCloud Key-Value Storage.

On iOS the app requests the iCloud Key-Value Storage entitlement and the
microphone permission you are asked for directly — nothing else.

## No tracking, no accounts, no third parties

- No analytics, telemetry, crash reporting, or usage measurement.
- No advertising, and no advertising identifiers.
- No accounts, and no sign-in. iCloud sync uses the account your device is
  already signed in to; the app never sees its credentials, and works fully
  without one.
- **No third-party code.** Nitpitch is built entirely on frameworks that ship
  with the operating system (AVFoundation, Accelerate, SwiftUI). There is no
  SDK from any other company in the app, so there is no one else to receive
  data even in principle.

## Children

The app collects no data from anyone, of any age.

## Your rights

Because no data ever reaches the developer, there is nothing to request access
to, correct, export, or delete from anyone but your own devices. Removing the
app removes everything it stored locally. If you used iCloud sync, the synced
copy lives in your own iCloud account: turn the switch off before removing the
app, or manage the data from another synced device.

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
