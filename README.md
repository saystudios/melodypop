# Say Piano

Say Piano (code name MelodyPop) is a piano-learning app for iPhone and iPad by Say Studios LLC. Students learn with any of three play modes, all driven by the same lesson engine, scoring and progress tracking:

| Mode | In the app | How it works |
|---|---|---|
| **Real Piano** | *Listen to My Piano* | Microphone + on-device YIN pitch detection. Reliable for **one note at a time**. |
| **MIDI Piano** | *Connect My Keyboard* | Core MIDI — USB (class-compliant) or Bluetooth LE MIDI keyboards. Exact notes, chords, velocity and sustain pedal. |
| **Virtual Piano** | *Play on Screen* | 88-key multitouch keyboard rendered with UIKit, played through AVAudioEngine. |

Students can switch modes inside any lesson; the lesson pauses, switches input, and resumes where it left off.

## Requirements

- Xcode 16 or later (the project uses Xcode 16 folder-synchronized groups)
- iOS / iPadOS 17.0 or later
- An Apple ID (a free one works for running on your own devices)

## Run it on a physical iPhone or iPad

1. Clone the repo and open `MelodyPop.xcodeproj` in Xcode.
2. Select the **MelodyPop** project in the navigator → **MelodyPop** target → **Signing & Capabilities**.
3. Under *Team*, choose your Apple ID team (Xcode → Settings → Accounts to add one).
4. If Xcode reports the bundle ID is taken, change **Bundle Identifier** from `com.saystudios.melodypop` to something unique, e.g. `com.yourname.melodypop`.
5. Connect the iPhone or iPad with a cable (or pair it over Wi-Fi in Window → Devices and Simulators) and pick it in the run destination menu at the top of Xcode.
6. On the device, turn on **Developer Mode** the first time: Settings → Privacy & Security → Developer Mode → On, then restart when asked.
7. Press **Run** (⌘R). With a free Apple ID you may need to trust the developer on the device: Settings → General → VPN & Device Management → your Apple ID → Trust.

### Trying each play mode on a device

- **Listen to My Piano** – allow microphone access when asked. Put the device on the music stand, stay quiet for the first second while MelodyPop measures the room, then play single notes. The Parent Dashboard has a *Sensitivity* slider for quiet pianos or noisy rooms.
- **Connect My Keyboard (USB)** – connect a class-compliant MIDI keyboard with a USB-C cable (USB-C iPhone/iPad) or Apple's Lightning to USB 3 Camera Adapter. It appears automatically.
- **Connect My Keyboard (Bluetooth)** – tap *Pair Bluetooth* in the mode banner, then select the keyboard in the list. Once paired it connects automatically.
- **Play on Screen** – works everywhere, including the Simulator. Landscape gives the most keys; *Key size* is in the volume popover.

### In-app purchase (Say Piano Plus)

Lessons 1–10 and six songs are free; *Say Piano Plus* (`com.saystudios.melodypop.plus`, non-consumable) unlocks lessons 11–30 and every song. Purchasing is only offered in the Parent Dashboard behind a parental gate.

- **Local testing:** the shared scheme points at `MelodyPop.storekit`. If purchases don't show when you Run from Xcode, open *Product → Scheme → Edit Scheme → Run → Options → StoreKit Configuration* and select `MelodyPop.storekit`.
- **Release:** create the same product ID in App Store Connect before submitting.

## Build for TestFlight on GitHub (no Mac needed)

The **Build iPhone app** workflow (`.github/workflows/ios-app.yml`) builds Say Piano on GitHub's Mac runners and uploads it to TestFlight. It needs **only the App Store Connect API key** — no .p12 certificate or provisioning profile. The app is signed with Apple's cloud-managed distribution certificate, so nothing is created or revoked on your Apple account.

One-time setup:
1. In the repo on GitHub: **Settings → Secrets and variables → Actions**. Make sure these four secrets exist: `APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (the same values as Say Math). The API key needs **Admin** access. (Optional: `BUNDLE_ID` — defaults to `com.saystudios.melodypop`.) The old `APPLE_DISTRIBUTION_P12_*` and `APP_STORE_PROFILE_BASE64` secrets are no longer used.
2. In **App Store Connect → Apps → + → New App**: platform iOS, name Say Piano, bundle ID `com.saystudios.melodypop`, any SKU. (The workflow registers the bundle ID for you if it's missing.)

Each build: **Actions → Build iPhone app → Run workflow**, enter the version (e.g. `1.0`). After about 15–30 minutes the build appears in App Store Connect → TestFlight. Add yourself as an internal tester, install the **TestFlight** app on your iPhone/iPad, and install Say Piano from there.

## Tests

- `Packages/MelodyPopKit` – engine unit tests (`swift test` in that folder, or the package scheme in Xcode): pitch detection on synthetic and recorded piano tones, MIDI/UMP parsing, keyboard hit-testing, synth rendering, lesson scoring in both modes, mode switching, curriculum validation, games, rewards.
- `MelodyPopTests` – runs inside the app: real sample loading, rendered-audio pitch checks, microphone pipeline on recorded piano audio, SwiftData progress, input routing, Lesson 1 end-to-end with a mid-lesson mode switch.
- `MelodyPopUITests` – onboarding and mode selection, virtual piano (play, octave shift, record, playback, save), Lesson 1 with the on-screen piano including a mode switch.

Run everything with ⌘U. GitHub Actions runs the same suites on iPhone and iPad simulators for every push.

**What only a real device can verify:** true simultaneous multitouch, audio latency, microphone detection with a real acoustic piano in a real room, and USB/Bluetooth MIDI hardware.

## Project layout

```
MelodyPop/                 App target (SwiftUI)
  Audio/                   AVAudioEngine piano, audio session
  Input/                   Microphone, MIDI and touch inputs + PlayModeController
  Keyboard/                88-key multitouch keyboard, navigator, controls
  Practice/                Shared practice screen, sheet music, mode selector
  Screens/                 Journey, Free Play, Songs, Me, onboarding, mode selection
  Games/                   Piano Games
  Parents/                 Parental gate, Parent Dashboard
  Store/                   StoreKit 2
  Data/                    SwiftData models, progress & rewards
  Resources/PianoSamples/  Salamander Grand Piano samples (CC BY 3.0)
Packages/MelodyPopKit/     Platform-independent engine + tests
```

## Microphone limits (by design)

The microphone hears sound, not keys. MelodyPop therefore:

- reports a note-on when a stable pitch with confidence ≥ the sensitivity threshold is heard for two analysis frames (~45 ms);
- treats a note as *ended* when its sound fades or a different note takes over — it cannot know when a key was lifted, and the sustain pedal hides releases entirely, so note length is never graded in this mode;
- follows one note at a time. Several strings sounding together produce one (usually the strongest) pitch, so lessons with chords or both hands together ask for *Connect My Keyboard* or *Play on Screen*. In other pieces, any chord falls back to grading only its top note.

## Credits

- Piano sound: **Salamander Grand Piano V3** by Alexander Holm, [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/). Two velocity layers, sampled every minor third, trimmed and converted to mono for the app. License: `MelodyPop/Resources/PianoSamples/SALAMANDER_LICENSE.txt`.
- Songs are traditional or public-domain melodies arranged by Say Studios LLC.

© Say Studios LLC · SayStudiosllc@yahoo.com
