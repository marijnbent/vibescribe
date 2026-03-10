# VibeScribe

![Vibe Engineered](https://img.shields.io/badge/vibe_engineered-%E2%9C%A8-ff6ac1?style=flat-square&labelColor=0d0d1a)

![VibeScribe header](assets/readme-header.png)

VibeScribe is a macOS menu bar dictation app built in Swift. Hold or tap a configurable modifier key to record, stream audio to Deepgram for transcription, optionally run the result through OpenRouter, and paste the final text back into the active app.

## What It Does

- Streams microphone audio to Deepgram over WebSocket and shows live transcription state while you speak
- Supports multiple configurable global shortcuts with `Hold`, `Click`, and `Both` activation modes
- Auto-pastes the transcript into the frontmost app and restores the previous clipboard only after confirmed auto-paste
- Routes OpenRouter prompts per shortcut, with optional per-app overrides based on the active macOS app
- Shows a floating overlay with live audio level, recording/enhancing state, and active-app icon when an app override is used
- Keeps transcript history (`None`, `10`, or `100` entries) and a rolling in-app log (`1,000` entries)

## Requirements

- macOS 13+
- Swift 6.2 toolchain / Xcode with command line tools
- A [Deepgram API key](https://console.deepgram.com)
- An [OpenRouter API key](https://openrouter.ai) and model name if you want AI enhancement

## Quick Start

Run from source:

```bash
swift run
```

Build a normal `.app` bundle:

```bash
bash package_app.sh
```

That creates `VibeScribe.app` in the repo root. Move it to `/Applications` if you want a persistent install.

Version, bundle ID, app name, signing mode, and packaging metadata are controlled through [`version.env`](/Users/marijn/Projects/vibescribe/version.env) and environment variables consumed by [`package_app.sh`](/Users/marijn/Projects/vibescribe/package_app.sh).

## First-Run Setup

1. Launch the app. It runs as a menu bar app, not a Dock app.
2. Open `Settings` from the menu bar icon.
3. In `General`, enter your Deepgram API key.
4. Grant microphone permission for recording.
5. Grant accessibility permission for paste automation and global shortcut handling.
6. In `Shortcuts`, pick the modifier key(s) and activation mode(s) you want.
7. Optional: in `Enhancements`, add your OpenRouter API key and model, then create prompts and assign them to shortcuts.

The default shortcut is `Right Option` in `Both` mode.

## Configuration Overview

### General

- Deepgram API key
- Transcription language, including `Automatic`
- Escape-to-cancel toggle
- Sound effects toggle
- Mute-during-recording toggle
- Restore-clipboard-after-confirmed-auto-paste toggle
- Overlay position: `Top` or `Bottom`
- History retention: `None`, `10`, `100`

### Shortcuts

Supported keys:

- `Fn`
- `Left Control`
- `Left Command`
- `Right Command`
- `Right Option`

Activation modes:

- `Hold`: push-to-talk while the key is held
- `Click`: press once to start and again to stop
- `Both`: short press to latch, or hold for push-to-talk

### Enhancements

- OpenRouter API key
- OpenRouter model name
- Prompt library with editable named prompts
- Default prompt assignment per shortcut
- Per-app prompt overrides chosen from the currently running apps

When enhancement runs, the app appends the raw transcript inside `<transcription>...</transcription>` before sending the request to OpenRouter.

## How A Recording Flows

1. Press a configured shortcut to start recording.
2. Audio is captured locally and streamed to Deepgram.
3. The overlay shows recording state and live audio level.
4. Releasing the shortcut, pressing again, or cancelling with `Esc` ends the session depending on mode.
5. If a prompt is configured for that shortcut or active app, the transcript is sent to OpenRouter.
6. The final text is copied to the clipboard and pasted with `Cmd+V`.
7. If confirmed auto-paste clipboard restore is enabled, VibeScribe restores the previous clipboard only after it can verify the target app accepted the paste; otherwise it keeps the transcript on the clipboard so you can paste manually.
8. History and logs are updated in-app.

If OpenRouter enhancement fails, VibeScribe falls back to pasting the original transcript and records the failure in history/logs.

If the target field cannot be verified through Accessibility APIs, or the paste result does not exactly match the expected text and caret position, VibeScribe leaves the transcript on the clipboard instead of clearing it.

## Permissions

VibeScribe asks for:

- `Microphone`: required for recording
- `Accessibility`: required for paste automation and the app's global shortcut flow

The packaged app also includes an Input Monitoring usage string in `Info.plist`, but the in-app permission flow currently centers on microphone and accessibility.

## Development

Build:

```bash
swift build
```

Test:

```bash
swift test
```

The package has no external Swift dependencies. The main targets are:

- [`Sources/VibeScribe`](/Users/marijn/Projects/vibescribe/Sources/VibeScribe)
- [`Sources/VibeScribeCore`](/Users/marijn/Projects/vibescribe/Sources/VibeScribeCore)
- [`Tests/VibeScribeTests`](/Users/marijn/Projects/vibescribe/Tests/VibeScribeTests)

## Architecture

- [`VibeScribeApp.swift`](/Users/marijn/Projects/vibescribe/Sources/VibeScribeCore/VibeScribeApp.swift): app bootstrap, dependency wiring, menu bar setup
- [`RuntimeCoordinator.swift`](/Users/marijn/Projects/vibescribe/Sources/VibeScribeCore/RuntimeCoordinator.swift): coordinates shortcut, recording, paste, and overlay behavior
- [`Runtime/RecordingRuntime.swift`](/Users/marijn/Projects/vibescribe/Sources/VibeScribeCore/Runtime/RecordingRuntime.swift): recording lifecycle, Deepgram connection, reconnect/finalize logic
- [`Runtime/PasteRuntime.swift`](/Users/marijn/Projects/vibescribe/Sources/VibeScribeCore/Runtime/PasteRuntime.swift): OpenRouter enhancement, clipboard handling, auto-paste
- [`Runtime/PasteVerification.swift`](/Users/marijn/Projects/vibescribe/Sources/VibeScribeCore/Runtime/PasteVerification.swift): Accessibility-based auto-paste verification and UTF-16-safe paste matching
- [`SettingsStore.swift`](/Users/marijn/Projects/vibescribe/Sources/VibeScribeCore/SettingsStore.swift): persisted settings in `UserDefaults`
- [`PromptRoutingService.swift`](/Users/marijn/Projects/vibescribe/Sources/VibeScribeCore/PromptRoutingService.swift): shortcut-level and app-level prompt resolution
- [`UI/`](/Users/marijn/Projects/vibescribe/Sources/VibeScribeCore/UI): SwiftUI settings, history, logs, and overlay views

## Storage And Security Notes

- API keys and settings are stored in `UserDefaults`
- API keys are not currently stored in the macOS Keychain
- Transcript history and logs are kept in memory for the current app session

If this project is distributed beyond personal use, moving API key storage to Keychain would be the obvious next hardening step.

## Credits

- Current repo: [marijnbent/vibescribe](https://github.com/marijnbent/vibescribe)
- Forked from: [flatoy/vibescribe](https://github.com/flatoy/vibescribe)

## License

MIT. See [`LICENSE`](/Users/marijn/Projects/vibescribe/LICENSE).
