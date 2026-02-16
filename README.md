# VibeScrib

A tiny macOS menu bar app for push-to-talk transcription with Deepgram.

## What this gives you
- Menu bar status item with start/stop
- Minimal settings window (API key)
- Push-to-talk hotkey (hold to record)
- Recording overlay
- WebSocket streaming to Deepgram
- Logs tab for connection/debugging
- Auto-paste transcript on release (requires Accessibility permission)

## Requirements
- macOS 13+
- Xcode or the Swift toolchain that ships with your current macOS

## Run
```bash
swift run
```

## Setup
1. Launch the app (it appears in the menu bar).
2. Open the main window and paste your Deepgram API key.
3. Hold the push-to-talk hotkey to start streaming.

## Permissions
- Microphone access is required.
- For global hotkeys, macOS may prompt for Input Monitoring or Accessibility permissions.

## Customization
- Hotkey: `Sources/VibeScrib/HotkeyListener.swift`
- Overlay UI: `Sources/VibeScrib/UI/OverlayView.swift`
- Deepgram model (Nova 3 + `language=multi`): `Sources/VibeScrib/DeepgramClient.swift`

## Notes
This is intentionally minimal to keep the architecture easy to extend. The API key is stored in `UserDefaults` in plaintext for convenience.
