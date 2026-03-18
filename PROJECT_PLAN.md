# Voxa — Offline Voice-to-Text for Mac

> Speak naturally. Get clean, formatted text in any app. Entirely offline.

## Vision

Voxa is a native macOS menu bar app that captures your voice via a global hotkey, transcribes it locally using WhisperKit (Apple Neural Engine), cleans up the text with a local LLM (Ollama), and injects the result into whatever app you're using — all without any data leaving your machine.

---

## Architecture

```
┌──────────────────────────────────────────────────────┐
│                   Voxa (SwiftUI)                     │
│                  Menu Bar App                        │
├──────────────┬──────────────┬────────────────────────┤
│ HotkeyManager│ AudioEngine  │ FloatingIndicator      │
│ (CGEvent tap)│ (AVAudioEngine│ (NSPanel overlay)     │
│              │  16kHz PCM)  │                        │
├──────────────┴──────┬───────┴────────────────────────┤
│                     │                                │
│  ┌─────────────────────────────────────┐             │
│  │  Stage 1: TranscriptionEngine       │             │
│  │  WhisperKit (CoreML / ANE)          │             │
│  │  Model: distil-large-v3.5           │             │
│  │  ~4 GB RAM, ~0.3s latency           │             │
│  └──────────────┬──────────────────────┘             │
│                 │ raw transcript                     │
│  ┌──────────────▼──────────────────────┐             │
│  │  Stage 2: TextCleanupEngine         │             │
│  │  Ollama (llama3.2:3b-instruct)      │             │
│  │  ~2 GB RAM, ~0.2s latency           │             │
│  └──────────────┬──────────────────────┘             │
│                 │ clean text                         │
│  ┌──────────────▼──────────────────────┐             │
│  │  TextInjector                       │             │
│  │  NSPasteboard + CGEvent Cmd+V       │             │
│  └─────────────────────────────────────┘             │
└──────────────────────────────────────────────────────┘
```

**Total footprint:** ~6 GB RAM, ~0.5s end-to-end latency on Apple Silicon with 24 GB.

---

## Tech Stack

| Component         | Technology                              |
|-------------------|-----------------------------------------|
| App framework     | Swift + SwiftUI                         |
| STT engine        | WhisperKit (SPM)                        |
| STT model         | distil-large-v3.5 / large-v3-turbo      |
| LLM cleanup       | Ollama (llama3.2:3b-instruct-q4_K_M)   |
| Audio capture     | AVAudioEngine (16kHz, Float32 PCM)      |
| Global hotkeys    | CGEvent tap (Accessibility API)         |
| Text injection    | NSPasteboard + CGEvent (Cmd+V)          |
| Floating UI       | NSPanel (overlay window)                |
| Auto-update       | Sparkle framework                       |
| Launch at login   | SMAppService                            |

---

## Phases

### Phase 1: Project Skeleton & Audio Capture ✅
**Goal:** App launches in menu bar, captures mic audio on hotkey press.

- [x] Create Xcode project (macOS App, SwiftUI, minimum deployment macOS 14)
- [x] Configure as menu bar app (LSUIElement = YES)
- [x] Add Info.plist keys:
  - `NSMicrophoneUsageDescription`
  - Accessibility usage description
- [x] Build `HotkeyManager` — register global hotkey (Option+Space default)
  - Use `CGEvent.tapCreate` with `.keyDown` / `.keyUp` events
  - Request Accessibility permission on first launch
- [x] Build `AudioEngine` class
  - Initialize `AVAudioEngine` with input node
  - Configure tap: 16kHz sample rate, Float32 PCM, mono
  - Buffer audio chunks into a ring buffer
  - Start/stop recording on hotkey press/release
- [x] Basic menu bar UI (SwiftUI `MenuBarExtra`)
  - Status: Idle / Listening / Processing
  - Quit button
- [x] Verify: press hotkey → see audio levels in console

**Deliverable:** App that captures audio on hotkey, logs waveform data.

---

### Phase 2: Offline Transcription (WhisperKit) ✅
**Goal:** Speak into mic → see transcribed text in console.

- [x] Add WhisperKit via SPM (`https://github.com/argmaxinc/WhisperKit`)
- [x] Build `ModelManager`
  - On first launch, download model to `~/Library/Application Support/Voxa/Models/`
  - Support model selection: tiny, base, small, distil-large-v3.5, large-v3-turbo
  - Show download progress in UI
- [x] Build `TranscriptionEngine`
  - Initialize WhisperKit with local model path
  - Accept PCM audio buffer from `AudioEngine`
  - Return transcription result (text + confidence + timestamps)
- [x] Wire up pipeline: hotkey release → send audio buffer → transcribe → log result
- [x] Add language selection (default: English, auto-detect option)
- [x] Verify: speak a sentence → see accurate transcript in console

**Deliverable:** End-to-end voice → text pipeline (console output only).

---

### Phase 3: LLM Text Cleanup (Ollama) ✅
**Goal:** Raw transcript gets cleaned up by a local LLM before output.

- [x] Build `OllamaClient`
  - HTTP client to communicate with Ollama's local API (`localhost:11434`)
  - `/api/generate` endpoint with non-streaming support
  - Timeout handling (500ms max — skip cleanup if LLM is slow)
  - `/api/pull` endpoint for downloading models with progress streaming
  - Separate download session with long timeouts for model pulls
- [x] Design cleanup prompt:
  ```
  Clean up this dictated text. Remove filler words (um, uh, like),
  fix grammar, add punctuation. Keep the meaning exactly the same.
  Output ONLY the cleaned text, nothing else.

  Input: {raw_transcript}
  ```
- [x] Build `TextCleanupEngine`
  - Accept raw transcript → send to Ollama → return cleaned text
  - Graceful fallback: if Ollama is not running, use raw transcript
  - TaskGroup-based timeout race (500ms) — falls back to raw if LLM is slow
  - Model download support with progress tracking in UI
- [x] Detect if Ollama is installed/running on app launch
  - Show status in menu bar (green/red/orange dot)
  - Provide toggle: "Use LLM cleanup" on/off
  - Show "Download LLM Model" button if model not installed
- [x] Verify: "um so I want to uh send john an email about tomorrow" → "Send John an email about tomorrow."

**Deliverable:** Two-stage pipeline producing clean, formatted text.

---

### Phase 4: Text Injection & Core UX ✅
**Goal:** Transcribed text appears in whatever app the user is typing in.

- [x] Build `TextInjector`
  - Save current pasteboard contents
  - Copy cleaned text to `NSPasteboard`
  - Simulate Cmd+V via `CGEvent` to paste into active app
  - Restore original pasteboard contents after a short delay (300ms)
- [x] Build `FloatingIndicator` (NSPanel)
  - Small, always-on-top, transparent overlay near cursor
  - States: recording (pulsing red dot) → processing (hourglass) → done (checkmark)
  - Auto-dismiss after injection (1s delay)
  - Draggable via `isMovableByWindowBackground`
- [x] Add audio feedback
  - System sounds: Tink (start), Pop (stop), Glass (done)
  - Toggleable via `SoundManager` with UserDefaults persistence
  - Toggle in menu bar UI
- [x] Wire full pipeline: hotkey → record → transcribe → cleanup → inject
- [x] Handle edge cases:
  - Empty transcription (silence) → dismiss indicator, do nothing
  - Very long dictation (>60s) → capped by AudioEngine's maxRecordingDuration
  - FloatingIndicator shows result if paste target unavailable
- [x] Verify: open any app → press hotkey → speak → text appears

**Deliverable:** Fully functional dictation tool that works in any app.

---

### Phase 5: Modes & Advanced Features ✅
**Goal:** Match Wispr Flow's key modes.

- [x] **Push-to-Talk Mode** (default)
  - Hold hotkey → record → release → process → inject
  - Extracted into `PushToTalkMode.swift` with shortcut/dictionary integration
- [x] **Flow Mode (hands-free)**
  - Toggle hotkey to start/stop continuous listening
  - Energy-based Voice Activity Detection (VAD) — 1.5s silence triggers chunk processing
  - Auto-transcribes and injects each speech chunk as it completes
- [x] **Command Mode**
  - User highlights text in any app → presses hotkey → speaks command
  - Read highlighted text via Cmd+C (simulated CGEvent)
  - Send to LLM: "Rewrite this text: {highlighted}. Instruction: {spoken command}"
  - Replace highlighted text with LLM output (5s timeout for rewrites)
  - Falls back to push-to-talk if no text is highlighted
- [x] **Personal Dictionary**
  - JSON file at `~/Library/Application Support/Voxa/dictionary.json`
  - Map of misheard → correct spelling (case-insensitive word boundary matching)
  - Applied as post-processing after LLM cleanup
  - CRUD methods for add/edit/remove entries
- [x] **Voice Shortcuts**
  - JSON config at `~/Library/Application Support/Voxa/shortcuts.json`
  - Trigger phrase → expansion text
  - Detected in transcript before cleanup — shortcuts bypass LLM
  - CRUD methods for add/remove shortcuts
- [x] **Mode System**
  - `DictationModeType` enum with Push-to-Talk, Flow, Command
  - Mode selector in menu bar dropdown
  - Mode persisted to UserDefaults across restarts
  - Hotkey dispatch routes to active mode

**Deliverable:** Multi-mode dictation app with power-user features.

---

### Phase 6: Settings & Polish ✅
**Goal:** Production-quality menu bar app.

- [x] **Settings Window** (SwiftUI) — 7-tab preferences window
  - General: launch at login (SMAppService), dictation mode picker, sound feedback toggle
  - Model: STT model selector with download status, storage path display
  - LLM: Ollama connection status with refresh, enable/disable, model download, timeout info
  - Dictionary: add/edit/remove personal dictionary entries with live list
  - Shortcuts: add/remove voice shortcuts with trigger + expansion
  - Audio: input device picker, recording config display, sound feedback toggle
  - About: version, credits, privacy statement
- [x] **Onboarding Flow** — 5-step guided setup
  - Step 1: Grant microphone permission
  - Step 2: Grant accessibility permission
  - Step 3: Download STT model (with progress)
  - Step 4: Check Ollama status (optional)
  - Step 5: Ready — shows hotkey and mode overview
  - Tracked via UserDefaults `onboardingComplete`
- [x] **Launch at Login** via `SMAppService.mainApp.register()`
- [ ] **Auto-Update** via Sparkle framework (deferred — requires code signing)
- [x] **Performance Tuning**
  - Pre-warm WhisperKit model on app launch (auto-load in init)
  - Ollama status checked on launch
- [x] **Error Handling**
  - Graceful fallback when Ollama unavailable/slow
  - Empty transcription guard
  - Permission status display with grant buttons
- [x] **Logging** — unified logging via `os.log` (`Log` enum with category-based loggers)

**Deliverable:** Polished, release-ready macOS app.

---

## File Structure

```
voxa/
├── Voxa.xcodeproj
├── Voxa/
│   ├── VoxaApp.swift                 # App entry point, MenuBarExtra
│   ├── Info.plist
│   ├── Voxa.entitlements
│   │
│   ├── Core/
│   │   ├── AudioEngine.swift         # Mic capture, PCM buffers
│   │   ├── TranscriptionEngine.swift # WhisperKit wrapper
│   │   ├── TextCleanupEngine.swift   # Ollama LLM client
│   │   ├── TextInjector.swift        # Pasteboard + CGEvent paste
│   │   └── HotkeyManager.swift      # Global hotkey registration
│   │
│   ├── Models/
│   │   ├── ModelManager.swift        # Download, cache, select models
│   │   ├── DictionaryManager.swift   # Personal dictionary
│   │   └── ShortcutManager.swift     # Voice shortcuts
│   │
│   ├── Modes/
│   │   ├── PushToTalkMode.swift      # Hold-to-dictate
│   │   ├── FlowMode.swift            # Continuous hands-free
│   │   └── CommandMode.swift         # Highlight + voice command
│   │
│   ├── UI/
│   │   ├── MenuBarView.swift         # Menu bar dropdown
│   │   ├── FloatingIndicator.swift   # Recording/processing overlay
│   │   ├── SettingsView.swift        # Preferences window
│   │   ├── OnboardingView.swift      # First-launch setup
│   │   └── ModelDownloadView.swift   # Model download progress
│   │
│   ├── Utilities/
│   │   ├── OllamaClient.swift        # HTTP client for Ollama API
│   │   ├── AudioUtils.swift          # PCM conversion helpers
│   │   ├── PermissionManager.swift   # Mic + Accessibility checks
│   │   └── Constants.swift           # App-wide constants
│   │
│   └── Resources/
│       ├── Assets.xcassets           # App icon, menu bar icons
│       └── Sounds/                   # Start/stop audio cues
│           ├── start.aiff
│           └── stop.aiff
│
├── VoxaTests/
│   ├── AudioEngineTests.swift
│   ├── TranscriptionEngineTests.swift
│   ├── TextCleanupEngineTests.swift
│   ├── TextInjectorTests.swift
│   └── OllamaClientTests.swift
│
└── README.md
```

---

## Dependencies

| Package | Source | Purpose |
|---------|--------|---------|
| WhisperKit | `https://github.com/argmaxinc/WhisperKit` | On-device STT via CoreML/ANE |
| Sparkle | `https://github.com/sparkle-project/Sparkle` | Auto-updates |
| KeyboardShortcuts | `https://github.com/sindresorhus/KeyboardShortcuts` | Hotkey recording UI |

**External (user-installed):**
| Tool | Purpose | Required? |
|------|---------|-----------|
| Ollama | Local LLM for text cleanup | Optional (graceful fallback) |

---

## System Requirements

- macOS 14 (Sonoma) or later
- Apple Silicon (M1/M2/M3/M4) — required for WhisperKit ANE acceleration
- 8 GB RAM minimum, 16 GB+ recommended
- ~2 GB disk for STT model + app
- Microphone access
- Accessibility permission (for global hotkeys + text injection)

---

## Milestones

| Milestone | Phases | What's Working |
|-----------|--------|----------------|
| **M1: Proof of Concept** | 1 + 2 | Hotkey → speak → transcript in console |
| **M2: Functional MVP** | 3 + 4 | Hotkey → speak → clean text in any app |
| **M3: Feature Complete** | 5 | All modes, dictionary, shortcuts |
| **M4: Release** | 6 | Polished, onboarding, auto-update |
