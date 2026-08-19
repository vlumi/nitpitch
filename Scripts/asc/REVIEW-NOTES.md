# App Review notes

Paste into **App Review Information ▸ Notes** in App Store Connect. Kept here so it isn't rewritten from memory each release (lattice's pattern — its Nearby mode drew reviewer questions that plain notes preempt). Nitpitch's reviewer-confusers are different but just as predictable: a tuner shows nothing without an instrument, sync is deliberately off, and the watch app works alone.

---

```
Nitpitch is an instrument tuner. It listens to the microphone, analyzes the audio on-device, and shows how far the note is from in tune. No account, no server, no data collection — audio is analyzed in memory and discarded, never recorded or transmitted.

TO TEST: the app needs a musical note to show a reading — a real instrument, or any tuner/tone app on another device playing a steady tone (e.g. 440 Hz). In a quiet room with no note sounding, every screen correctly shows "Play a note"; that is the designed idle state, not a malfunction.

iCloud sync is OFF by default and optional. The switch is in Settings; enabling it moves only the user's own instrument setups (names, tunings, presets, favorites) through iCloud Key-Value Storage in the user's own account. Everything is fully testable without it.

The watch app is included and also installable standalone from the watch App Store. It runs its own microphone and detection on the watch — no phone required. Its haptics tap at the rate the note is out of tune; silence means in tune.

The microphone permission is requested because hearing the instrument is the app's entire function.
```
