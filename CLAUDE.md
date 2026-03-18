# Voxa — Offline Voice-to-Text for Mac

## What is this?

Voxa is a native macOS menu bar app that captures voice via a global hotkey, transcribes it locally using WhisperKit (Apple Neural Engine), cleans up text with a local LLM (Ollama), and pastes the result into the active app. Entirely offline — no data leaves the machine.

## Tech Stack

- **Language:** Swift + SwiftUI
- **Target:** macOS 14+ (Sonoma), Apple Silicon only
- **STT:** WhisperKit (SPM) — models: distil-large-v3.5 / large-v3-turbo
- **LLM Cleanup:** Ollama (llama3.2:3b-instruct-q4_K_M) via HTTP API on localhost:11434
- **Audio:** AVAudioEngine (16kHz, Float32 PCM, mono)
- **Global Hotkeys:** CGEvent tap (Accessibility API), default Option+Space
- **Text Injection:** NSPasteboard + CGEvent (Cmd+V)
- **Floating UI:** NSPanel overlay
- **Auto-update:** Sparkle framework
- **Launch at login:** SMAppService

## Project Structure

```
Voxa/
├── VoxaApp.swift                 # Entry point, MenuBarExtra
├── Info.plist
├── Voxa.entitlements
├── Core/                         # Pipeline components
│   ├── AudioEngine.swift         # Mic capture, PCM buffers
│   ├── TranscriptionEngine.swift # WhisperKit wrapper
│   ├── TextCleanupEngine.swift   # Ollama LLM client
│   ├── TextInjector.swift        # Pasteboard + CGEvent paste
│   └── HotkeyManager.swift      # Global hotkey registration
├── Models/                       # Data/config managers
│   ├── ModelManager.swift        # Download, cache, select STT models
│   ├── DictionaryManager.swift   # Personal dictionary
│   └── ShortcutManager.swift     # Voice shortcuts
├── Modes/                        # Dictation modes
│   ├── PushToTalkMode.swift      # Hold-to-dictate (default)
│   ├── FlowMode.swift            # Continuous hands-free with VAD
│   └── CommandMode.swift         # Highlight + voice command
├── UI/
│   ├── MenuBarView.swift
│   ├── FloatingIndicator.swift
│   ├── SettingsView.swift
│   ├── OnboardingView.swift
│   └── ModelDownloadView.swift
├── Utilities/
│   ├── OllamaClient.swift        # HTTP client for Ollama API
│   ├── AudioUtils.swift          # PCM conversion helpers
│   ├── PermissionManager.swift   # Mic + Accessibility checks
│   └── Constants.swift
└── Resources/
    ├── Assets.xcassets
    └── Sounds/ (start.aiff, stop.aiff)
```

## SPM Dependencies

- **WhisperKit** — `https://github.com/argmaxinc/WhisperKit` (on-device STT)
- **Sparkle** — `https://github.com/sparkle-project/Sparkle` (auto-updates)
- **KeyboardShortcuts** — `https://github.com/sindresorhus/KeyboardShortcuts` (hotkey recording UI)

## Pipeline Flow

```
Hotkey press → AudioEngine (record) → Hotkey release →
  TranscriptionEngine (WhisperKit) → raw transcript →
  TextCleanupEngine (Ollama) → clean text →
  TextInjector (paste into active app)
```

## Key Design Decisions

- App is `LSUIElement = YES` (menu bar only, no dock icon)
- Info.plist requires `NSMicrophoneUsageDescription` and Accessibility usage description
- Ollama is optional — if not running, skip cleanup and use raw transcript
- TextInjector saves/restores pasteboard contents around injection
- STT models stored at `~/Library/Application Support/Voxa/Models/`
- Personal dictionary at `~/Library/Application Support/Voxa/dictionary.json`
- Ollama cleanup has a 500ms timeout — skip if too slow

## Build & Run

This is an Xcode project (`Voxa.xcodeproj`). Open in Xcode and build for macOS.

## Testing

Tests live in `VoxaTests/`. Key test files:
- `AudioEngineTests.swift`
- `TranscriptionEngineTests.swift`
- `TextCleanupEngineTests.swift`
- `TextInjectorTests.swift`
- `OllamaClientTests.swift`

## Current Phase

The project is being built in phases:
1. Project Skeleton & Audio Capture
2. Offline Transcription (WhisperKit)
3. LLM Text Cleanup (Ollama)
4. Text Injection & Core UX
5. Modes & Advanced Features
6. Settings & Polish

See `PROJECT_PLAN.md` for full phase details and task checklists.
