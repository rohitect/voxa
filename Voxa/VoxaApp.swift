import SwiftUI
import ServiceManagement

// MARK: - App State

enum AppStatus {
    case idle
    case listening
    case processing

    var displayText: String {
        switch self {
        case .idle: "Idle"
        case .listening: "Listening..."
        case .processing: "Processing..."
        }
    }
}

@Observable
final class AppState {
    var status: AppStatus = .idle
    var lastTranscription: String?
    /// Tracks the most recently used mode (updated automatically by hotkey press).
    var currentMode: DictationModeType = .pushToTalk

    let permissionManager = PermissionManager()
    let hotkeyManager = HotkeyManager()
    let audioEngine = AudioEngine()
    let modelManager = ModelManager()
    let transcriptionEngine = TranscriptionEngine()
    let textCleanupEngine = TextCleanupEngine()
    let agentCoordinator: AgentCoordinator

    init() {
        agentCoordinator = AgentCoordinator(audioEngine: audioEngine, transcriptionEngine: transcriptionEngine)
        setupHotkeyCallbacks()
        setupAudioLevelLogging()
        setupModelReadyCallback()
    }

    /// Checks if Ollama is running and refreshes available models.
    func refreshOllamaStatus() async {
        await textCleanupEngine.refreshStatus()
    }

    /// Switches the STT provider, unloads the current model, and loads the new one.
    func switchProvider(to provider: STTProvider) {
        transcriptionEngine.unloadModel()
        transcriptionEngine.provider = provider
        modelManager.provider = provider
        Task {
            await loadTranscriptionModel()
        }
    }

    func requestPermissions() {
        permissionManager.requestMicrophone()
        permissionManager.requestAccessibility()
    }

    func startHotkeyListening() {
        // Try creating the event tap directly — this is the real permission check.
        // AXIsProcessTrusted() can return false for debug builds even when granted.
        let success = hotkeyManager.start()
        if success {
            permissionManager.accessibilityGranted = true
            permissionManager.stopPolling()
        }
    }

    /// Loads the transcription model. Downloads first if not available locally.
    func loadTranscriptionModel() async {
        // If model isn't ready locally, download it
        if case .notDownloaded = modelManager.modelState {
            Log.model.info("Selected model not found locally — downloading \(self.modelManager.selectedModel)")
            await modelManager.downloadSelectedModel()
        }

        guard case .ready(let path) = modelManager.modelState else {
            Log.model.info("No model ready to load")
            return
        }
        guard !transcriptionEngine.isLoaded else { return }

        do {
            try await transcriptionEngine.loadModel(from: path)
        } catch {
            Log.model.error("Failed to load transcription model: \(error)")
        }
    }

    private func setupHotkeyCallbacks() {
        // Each mode has its own dedicated hotkey
        hotkeyManager.onPushToTalkDown = { [weak self] in
            guard let self else { return }
            self.currentMode = .pushToTalk
            PushToTalkMode.onHotkeyDown(appState: self)
        }
        hotkeyManager.onPushToTalkUp = { [weak self] in
            guard let self else { return }
            PushToTalkMode.onHotkeyUp(appState: self)
        }

        hotkeyManager.onFlowDown = { [weak self] in
            guard let self else { return }
            self.currentMode = .flow
            FlowMode.onHotkeyDown(appState: self)
        }
        hotkeyManager.onFlowUp = { [weak self] in
            guard let self else { return }
            FlowMode.onHotkeyUp(appState: self)
        }

        hotkeyManager.onCommandDown = { [weak self] in
            guard let self else { return }
            self.currentMode = .command
            CommandMode.onHotkeyDown(appState: self)
        }
        hotkeyManager.onCommandUp = { [weak self] in
            guard let self else { return }
            CommandMode.onHotkeyUp(appState: self)
        }

        hotkeyManager.onAgentDown = { [weak self] in
            guard let self else { return }
            self.currentMode = .agent
            self.agentCoordinator.onHotkeyDown(appState: self)
        }
        hotkeyManager.onAgentUp = { [weak self] in
            guard let self else { return }
            self.agentCoordinator.onHotkeyUp(appState: self)
        }
    }

    private func setupModelReadyCallback() {
        modelManager.onModelReady = { [weak self] path in
            guard let self else { return }
            Task {
                self.transcriptionEngine.unloadModel()
                do {
                    try await self.transcriptionEngine.loadModel(from: path)
                } catch {
                    Log.model.error("Failed to load model after ready: \(error)")
                }
            }
        }
    }

    private func setupAudioLevelLogging() {
        audioEngine.onAudioLevel = { level in
            let bars = Int(level * 50)
            let meter = String(repeating: "|", count: min(bars, 50))
            print("[AudioLevel] \(String(format: "%.4f", level)) \(meter)")
        }
    }
}

// MARK: - App Entry Point

@main
struct VoxaApp: App {
    @State private var appState = AppState()
    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: "onboardingComplete")
    @State private var showSettings = false

    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra("Voxa", systemImage: "waveform") {
            MenuBarView(appState: appState, showSettings: $showSettings)
        }

        Window("Voxa", id: "settings") {
            SettingsView(appState: appState)
                .onAppear {
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .defaultSize(width: 700, height: 480)

        Window("Welcome to Voxa", id: "onboarding") {
            OnboardingView(appState: appState) {
                showOnboarding = false
            }
        }
        .defaultSize(width: 440, height: 380)
        .windowResizability(.contentSize)
    }

    init() {
        DispatchQueue.main.async { [self] in
            appState.requestPermissions()

            // Always try — event tap creation is the real permission check
            appState.startHotkeyListening()

            if !appState.permissionManager.accessibilityGranted {
                // Prompt once to register the current binary
                appState.permissionManager.promptAccessibility()
                observeAccessibility()
            }

            // Auto-load model if already downloaded, check Ollama status
            Task {
                await appState.loadTranscriptionModel()
                await appState.refreshOllamaStatus()
            }

            // Open the main window on launch
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
                openWindow(id: "settings")
            }
        }
    }

    private func observeAccessibility() {
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { timer in
            // Try creating the event tap directly — the real permission check
            appState.startHotkeyListening()
            if appState.permissionManager.accessibilityGranted {
                timer.invalidate()
            }
        }
    }
}
