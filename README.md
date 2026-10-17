# SHOO

Turns a spare iPhone into a pest sentry. It watches through the camera, identifies the animal on-device and plays a deterrent chosen for that species. Every visit is logged with a snapshot. It makes no network calls and has no cloud.

## Run

```sh
brew install xcodegen   # once
xcodegen generate
open Shoo.xcodeproj
```

In Xcode, choose your team under *Signing & Capabilities*, plug in the phone and run. iOS 18+.

## The bot

The Watch screen is led by a 29×13 dot-matrix bot face. It has eight moods (idle, suspicious, angry, surprised, happy, smug, sleepy and dead) and speaks in short typed lines. Its eyes follow whatever is in the detection box. See `docs/bot-and-sprites.png`.

## Modes

The user chooses **GENTLE / STEADY / FIERCE**. Each one sets four numbers: certainty, patience, rest and loudness (`Tuning` in `SentrySettings.swift`). *Fine-tune* in Config edits those numbers directly. The mode switches to CUSTOM, and back to a preset if the numbers match one again.

## Ask tab — search, ask, spot, act

Everything runs on the phone. The on-device language model (Apple Intelligence, iOS 26+, plus vision on iOS 27) makes it smarter. Without it, the tab falls back to keyword logic.

- **Search hours of footage.** Recording is rolling 5-minute HEVC segments (about 0.5 GB per hour; keep 2–72 h). An index stores labels, motion and thumbnails every 1–4 s, plus a vision caption whenever something is happening. Type "every pigeon today" and tap a result to play it.
- **Ask what happened.** For example "What happened overnight?" The question sets a time window and keywords, and the model answers from the activity log and key frames.
- **Spotted.** Visits, people, pets, unexplained movement and light changes, built from the index.
- **When → then rules.** For example "If a fox comes at night, flash the lamp and tell me." Actions: DETER, LAMP, NOTIFY, WEBHOOK (POST JSON to a URL you name, such as Home Assistant).

## How it decides

1. The camera runs at 720p, about 15 fps. Detection runs about 4 fps and backs off when the phone gets hot.
2. **Apple Vision's** built-in classifier scores `pigeon`, `dove`, `gull`, `fox`, `rat`, `rodent` and `squirrel`.
3. A species has to stay above the threshold for N consecutive frames (*Confirm frames*).
4. **Hold fire**: nothing plays if a person, cat, dog or hedgehog is in frame.
5. If armed and outside quiet hours, it plays a freshly randomised sound. A cooldown then stops it repeating.
6. Each visit is logged to SwiftData, with a JPEG saved in Application Support.

| Voice | Sound | Default for |
|---|---|---|
| HAWK | Descending raptor screech, 2–3.4 kHz | Pigeon, gull |
| CLAP | Irregular broadband transients | Fox |
| SWEEP | Chirps from 15 to 19.8 kHz | Rat |
| PULSE | Alternating beeps at 17.5 and 19 kHz | Squirrel |
| MIX | A random voice each time | — |

## Custom model

To use your own detector, add `PestDetector.mlmodel` to `Shoo/`. You can train one with Create ML (Object Detection) or export a YOLO model to Core ML. Its labels should be `pigeon`, `gull`, `fox`, `rat`, `squirrel`, `person`, `cat`, `dog` and `hedgehog`. The app picks it up automatically, and the badge in the viewport changes to `CUSTOM MODEL`.

## Mounting

- Keep it plugged in. The screen stays on, so use **DIM** to drop brightness to about 2%.
- At night, use the **LAMP** (torch) or an external IR light. The phone's camera does poorly in the dark.
- Turn the system volume up. iOS doesn't let apps set it.
- Phone speakers stop at around 20 kHz. For real ultrasound, use a USB-C DAC at 96 kHz or higher with a piezo tweeter.
