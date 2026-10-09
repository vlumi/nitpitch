# App Review notes

Paste into **App Review Information ▸ Notes** in App Store Connect — the iOS block on the iOS app record's version, the macOS block on the Mac's. Kept here so they aren't rewritten from memory each release (lattice's pattern — its Nearby mode drew reviewer questions that plain notes preempt). Nitpitch's reviewer-confusers are just as predictable: a tuner shows nothing without an instrument, sync is deliberately off, preset links carry their payload in a URL fragment, and on iOS the watch app works alone.

**Keep these true.** Every factual claim below is checkable against the build — the entitlement lists, the "no network entitlement" line, the idle text. Verify them when they change rather than letting a reviewer find the drift.

## iOS (covers the embedded watch app)

```
Nitpitch is an instrument tuner. It listens to the microphone, analyzes the audio on-device, and shows how far the note is from in tune. No account, no server, no data collection — audio is analyzed frame by frame in memory and discarded, never recorded or transmitted.

TO TEST: the app needs a musical note to show a reading — a real instrument, or any tuner/tone app on another device playing a steady tone (e.g. 440 Hz). In a quiet room with no note sounding, every screen shows "Play a note"; that is the designed idle state, not a malfunction. Choosing an instrument (violin, guitar, bass…) gives each string its own dial, lit only by pitches near that string's own target.

If microphone access is denied, every tuning screen says so and offers a button to Settings; granting it and returning resumes immediately. There is no other state in which the app sits idle.

iCloud sync is OFF by default and optional. The switch is in Settings; enabling it moves only the user's own instrument setups (names, tunings, presets, favorites) through iCloud Key-Value Storage in the user's own account. Audio is never part of it, and everything is fully testable without it.

Preset sharing produces a link (https://nitpitch.app/t#… or nitpitch://). The shared tuning rides in the URL FRAGMENT, which browsers never send to a server — nitpitch.app is a static page that cannot learn what was shared. Opening such a link offers to load the tuning onto a matching instrument.

The watch app is included and also installable standalone from the watch App Store. It runs its own microphone and detection on the watch — no phone required. Its haptics tap at the rate the note is out of tune; silence means in tune. It is testable the same way: any steady tone near the watch.

The microphone permission is requested because hearing the instrument is the app's entire function.
```

## macOS

```
Nitpitch is an instrument tuner. It listens to the microphone (or any selected audio input, such as an audio interface with an electric instrument plugged in), analyzes the audio on-device, and shows how far the note is from in tune. No account, no server, no data collection — audio is analyzed frame by frame in memory and discarded, never recorded or transmitted.

TO TEST: the app needs a musical note to show a reading — a real instrument, or any tuner/tone app or website playing a steady tone (e.g. 440 Hz) through nearby speakers. In a quiet room with no note sounding, every screen shows "Play a note"; that is the designed idle state, not a malfunction. Choosing an instrument (violin, guitar, bass…) gives each string its own dial, lit only by pitches near that string's own target.

If microphone access is denied, every tuning screen says so and offers a button to the Microphone privacy pane; granting it and pressing Retry resumes immediately. A Mac with no input device at all says that instead, with the same Retry.

iCloud sync is OFF by default and optional. The switch is in Settings (Cmd-comma); enabling it moves only the user's own instrument setups (names, tunings, presets, favorites) through iCloud Key-Value Storage in the user's own account. Audio is never part of it, and everything is fully testable without it.

Preset sharing produces a link (https://nitpitch.app/t#… or nitpitch://). The shared tuning rides in the URL FRAGMENT, which browsers never send to a server — nitpitch.app is a static page that cannot learn what was shared. Opening such a link offers to load the tuning onto a matching instrument.

The app runs in the App Sandbox with exactly three entitlements: audio input, iCloud Key-Value Storage (for the opt-in sync), and associated domains (for the preset links above). There is NO network entitlement, so the app cannot open a connection even in principle; the iCloud sync is performed by the system's own daemon, outside the app.

The microphone permission is requested because hearing the instrument is the app's entire function.
```
