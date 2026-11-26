# Dictora

AI-assisted dictation for macOS and iOS, built entirely on Apple's native frameworks.

**Website and download: https://dictora-mac-site.web.app**

The marketing site lives in [`Website/`](Website) (Firebase Hosting); see [`docs/website.md`](docs/website.md) for how to deploy it and ship a new download.

---

## Product overview

You speak, Dictora listens, and you get back text that reads the way you wanted to write it.

1. You activate dictation.
2. Dictora captures microphone audio.
3. Apple's on-device Speech framework converts it to text.
4. The transcript is rewritten according to your configured writing style.
5. The polished text is returned to you.

For example, dictating:

> hey naveen i fixed that issue you can check latest build

with the **Professional** style produces:

> Hey Naveen, I've fixed the issue. You can check it in the latest build.

### Writing styles

| Style | What it does |
| --- | --- |
| Grammar Only | Fixes grammar, punctuation, capitalization and obvious speech-recognition mistakes. |
| Professional | Rewrites your dictation to sound clear, concise and professional. |
| Developer | Preserves technical terminology and developer language while improving readability. |
| Natural | Cleans up your speech while keeping your natural tone. |
| Custom | Transforms your dictation exactly as you describe. |

Separately from the style, **additional instructions** layer on top of *any* style, and a
**transformation strength** (Minimal / Balanced / Rewrite) controls how far the rewriter may
stray from your original phrasing.

---

## Architecture

```
Dictora/
├── App/
│   ├── Shared/      DictoraAppState, AppEnvironment, DependencyContainer
│   ├── macOS/       DictoraMacApp, MacAppModel, MacRootView, MacWelcomeView,
│   │                MacSettingsView, MenuBarContentView
│   └── iOS/         DictoraiOSApp, IOSRootView, IOSHomeView
├── Core/
│   ├── Models/      WritingStyle, TransformationStrength, DictationState/Result/Error
│   ├── Dictation/   DictationManager, AudioCaptureService, SpeechRecognitionService,
│   │                SpeechRecognitionProtocol, DictationPermissions
│   ├── AI/          TextProcessorProtocol, PromptBuilder, TextProcessingService,
│   │                FoundationModelTextProcessor, LocalFallbackTextProcessor
│   ├── Settings/    UserPreferences, PreferencesStore
│   └── Utilities/   Clipboard, SoundFeedback, DictoraLog
├── Features/
│   ├── Common/      WritingStyleCard, card modifiers
│   ├── Onboarding/  5-step first-run flow
│   ├── Dictation/   DictationView, DictationButton, TranscriptView, ProcessingIndicator
│   └── Settings/    General / Writing / Privacy / Shortcut sections, iOS SettingsView
├── Platform/
│   ├── macOS/       SystemDictationCoordinator, MacPlatformServices,
│   │                GlobalHotkeyManager, AccessibilityManager, TextInsertionManager,
│   │                ActiveApplicationManager, MenuBarManager,
│   │                DictationOverlayController/View
│   └── iOS/         IOSIntegrationService
├── Resources/       Assets.xcassets, Localizable.xcstrings
└── Configuration/   Info plists, entitlements, Shared.xcconfig
```

### Principles this codebase follows

- **Shared by default, platform-specific by exception.** `App/Shared`, `Core`, `Features` and
  `Resources` compile into *both* targets. `Platform/macOS` and `Platform/iOS` compile into one
  target each. Nothing in `Core` or `Features` imports AppKit or UIKit outside a `#if`.
- **Protocols at every system boundary.** `SpeechRecognizing`, `AudioCapturing`,
  `TextProcessorProtocol`, `PreferencesStoring` and `DictationPermissionsProviding` all have
  real and substitutable implementations, so tests never touch a microphone.
- **One place decides what this OS supports.** `DependencyContainer` picks
  `SpeechRecognitionService` vs `UnsupportedSpeechRecognizer` and `FoundationModelTextProcessor`
  vs `LocalFallbackTextProcessor`. Everything else sees only protocols.
- **Dependency injection, not singletons.** `AppEnvironment` is assembled once at launch and
  injected via the SwiftUI environment. There is no shared mutable global anywhere in the app.
- **The state machine is the manager's only job.** `DictationManager` owns `DictationState` and
  delegates each stage — capture, recognition, rewriting — to a separate service.
- **Behaviour lives outside views when it must outlive them.** `MacPlatformServices` is a
  container of capabilities; `SystemDictationCoordinator` is the behaviour that combines them.
  The coordinator is owned by `MacAppModel` (the `App`), not by a view, because dictating from
  another application has to keep working while Dictora's window is closed.

### The dictation pipeline

```
AudioCaptureService          SpeechRecognitionService        TextProcessingService
  AVCaptureSession     →       SpeechAnalyzer +          →     FoundationModelTextProcessor
  + format conversion          SpeechTranscriber               ↓ (unavailable or failed)
        ↓                            ↓                         LocalFallbackTextProcessor
   AsyncStream<AudioChunk>    AsyncThrowingStream<TranscriptionUpdate>
                    ↘                ↙
                   DictationManager  →  DictationResult
```

`DictationState` moves through `idle → requestingPermission → listening → transcribing →
processing → completed`, with `failed(DictationError)` reachable from any stage.

### Why capture uses `AVCaptureSession`, not `AVAudioEngine`

Starting an `AVAudioEngine` runs its entire graph, output node included, so it opens the
*speakers* as well as the microphone — even though Dictora never plays anything through it.
Holding the output device open forces the system to re-negotiate it, and other audio audibly
degrades: music drops into the thin, processed sound you get during a call.

`AVCaptureSession` is capture-only and leaves the output device alone. The difference is
measurable, and `Scripts/verify-audio-capture.swift` measures it:

```
AVAudioEngine     mic:OPEN  speakers:OPEN     ← degrades other audio
AVCaptureSession  mic:OPEN  speakers:closed
```

The trade-off is that a capture session does not report its audio format until buffers start
arriving, so `BufferConverter` is built lazily on the first buffer rather than up front.

### Choosing a shortcut

`ShortcutPreset` offers a fixed list rather than a free-form recorder, because the options are
not equivalent. Fn / Globe is the default and feels best — one key, nothing to reach for — but a
lone modifier cannot be registered as a system hotkey, so it has to be watched through a
`CGEvent` tap, and that needs Accessibility. Every other preset is an ordinary chord registered
through Carbon, which works with no permissions at all.

When the chosen shortcut cannot be registered, `SystemDictationCoordinator` falls back to
⌥Space rather than leaving the user with nothing, and both Settings and the main window say
which shortcut is actually listening and why it differs.

### Dictating into other apps (macOS)

```
Shortcut        →  remember the frontmost app (ActiveApplicationManager)
                →  dictate (the pipeline above), floating overlay follows the state
                →  TextInsertionManager:  Accessibility write
                                          ↓ element not editable / not writable
                                          clipboard + synthetic ⌘V, clipboard restored
                                          ↓ no Accessibility permission
                                          leave on clipboard and say so
```

`SystemDictationCoordinator` observes dictation state and preferences through a single
`Observations` loop rather than SwiftUI's `onChange`, so the overlay and the shortcut
registration stay correct with no window on screen. Changing the activation mode or toggling the
shortcut in Settings re-registers the hotkey automatically.

The target application is captured *before* dictation starts. Carbon hotkeys don't activate
Dictora and the overlay is a non-activating panel, so the user's app normally stays frontmost;
the coordinator only re-activates it if focus moved in the meantime.

### Text processing

`PromptBuilder` is the only place prompt text exists. Every request — regardless of style or
strength — carries the same invariant rules: preserve meaning, never add facts the user did not
say, correct obvious transcription errors, never answer the text, and preserve names and
technical identifiers. A unit test asserts that all of them survive every style/strength
combination.

If Apple Intelligence is unavailable, or a generation fails, `TextProcessingService` falls back
to `LocalFallbackTextProcessor`, which only makes edits that cannot change meaning (whitespace,
capitalization, filler-word removal, terminal punctuation). Results carry a `TextProcessorKind`
so the UI can tell you honestly which one ran.

---

## macOS vs iOS capabilities

**System-wide text insertion is a macOS-only capability, and it is not implemented the same way
on iOS — because it cannot be.** iOS gives no app the ability to type into another app's text
field. Dictora does not pretend otherwise.

| Capability | macOS | iOS |
| --- | --- | --- |
| Microphone capture | Yes | Yes |
| On-device speech recognition | Yes | Yes |
| Writing-style rewriting | Yes | Yes |
| Settings + onboarding | Yes | Yes |
| Copy / share result | Yes | Yes |
| Menu bar app (`MenuBarExtra`) | Yes | N/A |
| Global keyboard shortcut | Yes — five presets, Fn by default, hold or double-tap | Not possible |
| Floating listening overlay | Yes | N/A |
| Foreground-app detection | Yes (`NSWorkspace`) | Not possible |
| Insert into another app's focused field | Yes — Accessibility, clipboard fallback | **Not possible** |

On iOS, polished text leaves Dictora only when you copy or share it. `IOSIntegrationService`
reserves the seams for a future custom keyboard and Share Extension; neither extension exists
yet and the App Group is deliberately not enabled.

---

## Requirements

Detected and verified on this machine:

| Tool | Version |
| --- | --- |
| Xcode | 26.6 (build 17F113) |
| Swift | 6.3.3 |
| macOS SDK | 26.5 |
| iOS SDK | 26.5 |
| XcodeGen | 2.46.0 |

**Deployment targets: macOS 26.0 and iOS 26.0.**

These were chosen deliberately, not defensively. macOS 26 / iOS 26 are the first releases with
both frameworks Dictora is built around:

- **`SpeechAnalyzer` / `SpeechTranscriber`** (`@available(macOS 26.0, iOS 26.0, *)`) — the modern
  streaming transcription API, used instead of the older `SFSpeechRecognizer` request API.
  `SFSpeechRecognizer` is still used for the authorization prompt, which is unchanged.
- **`FoundationModels`** — Apple's on-device language model, used for rewriting.

There is no limitation to document from a lower toolchain: the installed SDK supports every API
Dictora uses. The code is nonetheless written defensively — `SpeechRecognitionService` is
`@available`-annotated with an `UnsupportedSpeechRecognizer` alternative, and
`FoundationModelTextProcessor` sits behind `#if canImport(FoundationModels)` — so lowering the
deployment target degrades the app gracefully instead of breaking the build.

Apple Intelligence hardware is **not** required. On a device where the system model is
unavailable, the app reports the reason in Settings › Privacy and uses the local fallback.

---

## Running

### Prerequisites

- macOS 26 with [Xcode](https://developer.apple.com/xcode/) 26+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- An Apple Development certificate and your Team ID in
  `Dictora/Configuration/Shared.xcconfig` (`DEVELOPMENT_TEAM`) — see
  [Things you must configure manually in Xcode](#things-you-must-configure-manually-in-xcode)

### First-time setup

```bash
# Generate Dictora.xcodeproj from project.yml (the source of truth)
xcodegen generate
```

`Dictora.xcodeproj` is gitignored because it is generated. Re-run `xcodegen generate` after
pulling changes that touch `project.yml` or add files.

### Run from Xcode

```bash
open Dictora.xcodeproj
```

1. Select the **DictoraMac** scheme (menu bar app + main window) or **DictoraiOS**.
2. Choose a destination: **My Mac** for macOS, or an iPhone simulator / device for iOS.
3. Press **⌘R** (Product › Run).

On first launch, complete onboarding and grant Microphone, Speech Recognition, and (on macOS)
Accessibility if you want Dictora to type into other apps.

### Debug logs

Dictora logs to Apple’s unified logging under subsystem **`com.dictora.app`**.

**Live stream in Terminal** (best while reproducing a bug):

```bash
log stream --predicate 'subsystem == "com.dictora.app"' --level debug --style compact
```

Useful categories you’ll see: `DictationManager`, `AudioCapture`, `SpeechRecognition`,
`SystemDictation`, `TextInsertion`.

**Console.app**

1. Open **Console** (Spotlight → Console).
2. Select your Mac in the sidebar.
3. In the search field, enter: `subsystem:com.dictora.app`
4. Enable **Action › Include Debug Messages** and **Include Info Messages**.
5. Start/stop dictation and watch session lines (`Session … listening`, `audio chunks=…`,
   `raw transcript`, `completed → …`).

**From Xcode**

1. Run **DictoraMac** with **⌘R**.
2. Open the **Debug area** (⌘⇧Y) — some `Logger` lines also appear there when attached.
3. For the full stream, keep the `log stream` command above running in a side terminal.

### Build and run from the command line

**macOS**

```bash
xcodegen generate

xcodebuild -project Dictora.xcodeproj -scheme DictoraMac \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath ./.derivedData \
  build

open ./.derivedData/Build/Products/Debug/Dictora.app
```

**iOS Simulator**

```bash
xcodegen generate

xcodebuild -project Dictora.xcodeproj -scheme DictoraiOS \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath ./.derivedData \
  build

xcrun simctl boot "iPhone 17 Pro" 2>/dev/null || true
open -a Simulator
xcrun simctl install booted ./.derivedData/Build/Products/Debug-iphonesimulator/Dictora.app
xcrun simctl launch booted com.dictora.app.ios
```

`.derivedData/` is a local build folder (safe to delete). Omit `-derivedDataPath` to use
Xcode’s default DerivedData location instead.

### Tests

```bash
xcodebuild -project Dictora.xcodeproj -scheme DictoraMac \
  -destination 'platform=macOS' test
```

See [Tests](#tests) for more detail.

---

## Permissions

| Permission | Platform | Why | Status |
| --- | --- | --- | --- |
| Microphone | Both | "Dictora uses your microphone to turn your voice into text." | Requested during onboarding |
| Speech Recognition | Both | "Dictora uses speech recognition to transcribe your dictation." | Requested during onboarding |
| Accessibility | macOS | Required to type into another app's focused text field | Prompted from the main window and Settings › Anywhere |

Both usage descriptions live in `Dictora/Configuration/Info-macOS.plist` and `Info-iOS.plist`.
Accessibility has no Info.plist key — macOS grants it through System Settings. Dictora prompts
for it with a banner in the main window whenever automatic insertion is enabled but access is
missing, and from Settings › Anywhere. If it is refused, dictation still works and the result is
left on the clipboard with an explanation.

---

## Current implementation status

### Implemented

- Five-step onboarding: welcome, microphone/speech permission request, writing-style selection,
  custom + additional instructions, completion. Persists `hasCompletedOnboarding`.
- Writing-style model with display names, descriptions, symbols and base instructions.
- Transformation strength (Minimal / Balanced / Rewrite).
- Preferences persisted to `UserDefaults` as a single JSON blob, tolerant of missing keys and
  corrupt data.
- Microphone capture via `AVCaptureSession`, with sample-rate conversion to the transcriber's
  format.
- Streaming transcription via `SpeechAnalyzer` + `SpeechTranscriber`, including on-device model
  asset download for the user's locale, and live volatile results.
- Dictation state machine orchestrating capture → recognition → rewriting → result.
- `FoundationModelTextProcessor` with runtime availability checks and permissive content
  transformation guardrails.
- `LocalFallbackTextProcessor`, used whenever the model is unavailable or generation fails.
- `PromptBuilder` with enforced invariant safety rules.
- iOS home screen: branding, current style, large dictation button, live transcript, polished
  result, copy and share.
- macOS main window and `MenuBarExtra` (status, start/stop, writing-style submenu, copy last
  result, settings, quit).
- Settings with General, Writing, Privacy and — on macOS — Anywhere sections.

**Dictate anywhere on the Mac (Phase 2):**

- Five preset global shortcuts, defaulting to Fn / Globe, with automatic fallback to ⌥Space when
  the chosen one cannot be registered. Works with Dictora's window closed.
- Both activation modes: double-tap to start (single tap to stop while listening), or hold to talk. Switching mode or preset
  in Settings re-registers the shortcut automatically.
- Rephrase text you already have: pick a style and tone, rewrite whatever is on the clipboard,
  either from the window's Rephrase tab or straight from the menu bar.
- Floating non-activating `NSPanel` overlay following the dictation state, positioned on the
  display the pointer is on, and reporting the delivery outcome when finished.
- Accessibility text insertion into the focused field of the app you dictated from, checking the
  element is actually writable before using it.
- Clipboard + synthetic ⌘V fallback for apps with no editable Accessibility element, restoring
  your previous clipboard contents afterwards.
- Graceful degradation: without Accessibility permission the text is left on the clipboard with
  an explanation, and the main window offers to request access.
- 59 unit tests on macOS (50 on iOS, which skips the macOS-only suites).

### Scaffolded

- **`IOSIntegrationService`** — copy/share works; the reserved identifiers for a future keyboard
  and Share Extension are unused.
- **`launchAtLogin`** preference — stored, but no `SMAppService` registration yet.
- **`Localizable.xcstrings`** — present and configured; strings are not yet extracted into it.

### Future

- Free-form shortcut recorder, beyond the five presets.
- Accessibility step in macOS onboarding, rather than only the in-app prompt.
- iOS custom keyboard and Share Extension.
- Per-application writing styles, personal dictionary, smarter developer mode.
- Optional advanced AI providers.

---

## Things you must configure manually in Xcode

1. **The macOS app must be signed with a real certificate, not ad-hoc.**
   `DEVELOPMENT_TEAM` in `Dictora/Configuration/Shared.xcconfig` is not a nicety you can leave
   blank — change it to your own Team ID. iOS uses automatic signing and needs the same team
   before it will run on a device (the Simulator does not).

   macOS records an Accessibility grant against the app's *code-signing
   requirement*. For an ad-hoc signature that requirement is the binary's code
   hash, so every rebuild invalidates the grant — and does so invisibly: System
   Settings still lists Dictora with its switch on, while `AXIsProcessTrusted()`
   returns false, which in turn kills the Fn key and text insertion. You can see
   which kind you have:

   ```bash
   codesign -d -r- /path/to/Dictora.app
   # ad-hoc  → designated => cdhash H"…"                 ← grant dies on rebuild
   # signed  → designated => identifier "com.dictora.app" and … certificate …
   ```

   With a certificate the requirement is identity-based, so the grant survives
   rebuilds. `Scripts/make-dmg.sh` refuses to package an ad-hoc build for this
   reason. If a stale grant is already recorded, the switch cannot repair it —
   the entry has to be removed first, which is what the **Repair** button in
   Dictora does (`tccutil reset Accessibility com.dictora.app`).

2. **The App Sandbox is off on macOS, deliberately.**
   A sandboxed app cannot use the Accessibility API on another process, so typing into another
   app's focused field is impossible under the sandbox. Phase 2 needs that, so
   `Dictora-macOS.entitlements` no longer requests `com.apple.security.app-sandbox`.

   Consequences you should know about:

   - **Dictora cannot ship on the Mac App Store.** Distribute with Developer ID, notarised.
   - The Hardened Runtime is still enabled, and `com.apple.security.device.audio-input` is still
     requested — that is the only entitlement Dictora asks for. No file, network, or
     Apple Events access is requested.
   - Users must grant Accessibility access manually, and macOS ties that grant to the app's code
     signature. Re-signing with a different identity resets it, so during development you may
     need to remove and re-add Dictora in System Settings › Privacy & Security › Accessibility.

   If you later decide the Mac App Store matters more than dictating into other apps, re-add
   `com.apple.security.app-sandbox` — everything except `TextInsertionManager`'s Accessibility
   path keeps working, and that path already degrades to the clipboard with a clear explanation.

3. **App icon.** Artwork is in place and generated from a single source. If you replace it with
   final brand artwork, drop a 1024×1024 full-bleed square PNG at `Design/AppIcon-master.png`
   and re-run:

   ```bash
   swift Scripts/generate-app-icon.swift
   ```

   That renders every catalog slot and rewrites both `Contents.json` files, so the sizes never
   drift out of sync with the artwork. It produces:

   - `AppIcon.appiconset` — the iOS 1024 (opaque, no alpha channel, which App Store validation
     requires) plus the ten macOS slots, each clipped to Apple's icon grid: an 824/1024 body on
     a superellipse, leaving the transparent margin the Dock uses for optical sizing.
   - `Logo.imageset` — the same mark at 1x/2x/3x for use inside the app, via the shared
     `AppLogo` view in onboarding and the window headers.

   `AccentColor.colorset` carries light and dark variants tuned to the icon's indigo; update
   both if you change the artwork.

4. **Menu-bar-only mode.** `LSUIElement` is `false` in `Info-macOS.plist`, so Dictora has a Dock
   icon and a main window alongside its menu bar item. Set it to `true` for a pure menu bar app.

5. **Bundle identifiers.** `com.dictora.app` and `com.dictora.app.ios` are placeholders. Change
   `DICTORA_BUNDLE_ID_BASE` in `Shared.xcconfig` — everything else derives from it.

---

## Project roadmap

**Phase 1 — foundation** *(done)*
- Onboarding
- Microphone capture
- Speech-to-text
- Writing styles
- Local rewriting
- Settings

**Phase 2 — dictate anywhere on macOS** *(this milestone)*
- Global shortcut triggering dictation from any app
- Floating dictation UI driven by the shortcut
- Accessibility text insertion
- Clipboard fallback

**Phase 3 — smarter rewriting**
- Per-application writing styles
- Personal dictionary
- Smarter developer mode

**Phase 4 — reach**
- iOS keyboard and Share Extension integrations
- Optional advanced AI providers

---

## Tests

```bash
xcodebuild -project Dictora.xcodeproj -scheme DictoraMac \
  -destination 'platform=macOS,arch=arm64' test
```

The same `Tests/` directory is compiled into both `DictoraMacTests` and `DictoraiOSTests`, so
shared logic is verified on both platforms; macOS-only suites are excluded from the iOS run with
`#if os(macOS)`. Coverage is deliberately narrow and behavioural: writing-style instructions,
prompt construction and its safety invariants, preferences storage and forward-compatible
decoding of older payloads, the local fallback processor, shortcut rendering, and text-insertion
outcomes. There are no UI tests yet.
