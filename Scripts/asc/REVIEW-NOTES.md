# App Review notes

Paste into **App Review Information ▸ Notes** in App Store Connect — the iOS block on the iOS app record's version, the macOS block on the Mac's. Kept here so they aren't rewritten from memory each release (lattice's pattern — its Nearby mode drew reviewer questions that plain notes preempt). Nitpitch's reviewer-confusers are just as predictable: a tuner shows nothing without an instrument, sync is deliberately off, and on iOS the watch app works alone.

## iOS (covers the embedded watch app)

```
Nitpitch is an instrument tuner. It listens to the microphone, analyzes the audio on-device, and shows how far the note is from in tune. No account, no server, no data collection — audio is analyzed in memory and discarded, never recorded or transmitted.

TO TEST: the app needs a musical note to show a reading — a real instrument, or any tuner/tone app on another device playing a steady tone (e.g. 440 Hz). In a quiet room with no note sounding, every screen correctly shows "Play a note"; that is the designed idle state, not a malfunction.

iCloud sync is OFF by default and optional. The switch is in Settings; enabling it moves only the user's own instrument setups (names, tunings, presets, favorites) through iCloud Key-Value Storage in the user's own account. Everything is fully testable without it.

The watch app is included and also installable standalone from the watch App Store. It runs its own microphone and detection on the watch — no phone required. Its haptics tap at the rate the note is out of tune; silence means in tune. It is testable the same way: any steady tone near the watch.

The microphone permission is requested because hearing the instrument is the app's entire function.
```

## macOS

```
Nitpitch is an instrument tuner. It listens to the microphone (or any selected audio input, such as an audio interface with an electric instrument plugged in), analyzes the audio on-device, and shows how far the note is from in tune. No account, no server, no data collection — audio is analyzed in memory and discarded, never recorded or transmitted.

TO TEST: the app needs a musical note to show a reading — a real instrument, or any tuner/tone app or website playing a steady tone (e.g. 440 Hz) through nearby speakers. In a quiet room with no note sounding, every screen correctly shows "Play a note"; that is the designed idle state, not a malfunction.

iCloud sync is OFF by default and optional. The switch is in Settings (Cmd-comma); enabling it moves only the user's own instrument setups (names, tunings, presets, favorites) through iCloud Key-Value Storage in the user's own account. Everything is fully testable without it.

The app runs in the App Sandbox with only the audio-input and iCloud Key-Value Storage entitlements — it has no network entitlement at all, so it cannot open a connection even in principle; iCloud sync is performed by the system's own daemon.

The microphone permission is requested because hearing the instrument is the app's entire function.
```
