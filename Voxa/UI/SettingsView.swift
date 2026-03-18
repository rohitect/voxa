import SwiftUI
import ServiceManagement

// MARK: - Sidebar Navigation

enum SettingsPage: String, CaseIterable, Identifiable {
    case home = "Home"
    case dictionary = "Dictionary"
    case snippets = "Snippets"
    case models = "Models"
    case agent = "Agent"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: return "house"
        case .dictionary: return "character.book.closed"
        case .snippets: return "text.quote"
        case .models: return "cpu"
        case .agent: return "brain.head.profile"
        case .settings: return "gear"
        }
    }
}

// MARK: - Main Settings View

struct SettingsView: View {
    let appState: AppState
    @State private var selectedPage: SettingsPage = .home

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 700, minHeight: 480)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Logo
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .font(.title2)
                    .foregroundStyle(.primary)
                Text("Voxa")
                    .font(.title2)
                    .fontWeight(.bold)
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 24)

            // Nav items
            VStack(spacing: 2) {
                ForEach(SettingsPage.allCases) { page in
                    SidebarItem(
                        title: page.rawValue,
                        icon: page.icon,
                        isSelected: selectedPage == page
                    ) {
                        selectedPage = page
                    }
                }
            }
            .padding(.horizontal, 8)

            Spacer()

            // Bottom info
            VStack(alignment: .leading, spacing: 8) {
                Divider()
                    .padding(.horizontal, 16)

                HStack(spacing: 6) {
                    Circle()
                        .fill(appState.textCleanupEngine.ollamaAvailable ? .green : .red)
                        .frame(width: 6, height: 6)
                    Text(appState.textCleanupEngine.ollamaAvailable ? "Ollama connected" : "Ollama offline")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)

                Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0")")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 16)
            }
            .padding(.bottom, 16)
        }
        .frame(minWidth: 180, maxWidth: 180)
        .background(.background)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch selectedPage {
        case .home:
            HomePage(appState: appState)
        case .dictionary:
            DictionaryPage()
        case .snippets:
            SnippetsPage()
        case .models:
            ModelsPage(appState: appState)
        case .agent:
            AgentSettingsPage(appState: appState)
        case .settings:
            SettingsPage_(appState: appState)
        }
    }
}

// MARK: - Sidebar Item

private struct SidebarItem: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .frame(width: 20)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Home Page

private struct HomePage: View {
    let appState: AppState
    private let history = TranscriptionHistory.shared
    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Welcome back")
                            .font(.title)
                            .fontWeight(.bold)
                    }

                    Spacer()

                    // Stats
                    HStack(spacing: 20) {
                        StatBadge(
                            icon: "waveform",
                            value: "\(history.entries.count)",
                            label: "dictations"
                        )
                        StatBadge(
                            icon: "textformat",
                            value: formatWordCount(history.totalWords),
                            label: "words"
                        )
                    }
                }

                // Status cards
                HStack(spacing: 12) {
                    StatusCard(
                        title: "Speech Model",
                        status: appState.transcriptionEngine.isLoaded ? "Ready" : "Not loaded",
                        color: appState.transcriptionEngine.isLoaded ? .green : .orange,
                        icon: "cpu"
                    )
                    StatusCard(
                        title: "LLM Cleanup",
                        status: appState.textCleanupEngine.ollamaAvailable && appState.textCleanupEngine.modelReady
                            ? "Active" : "Inactive",
                        color: appState.textCleanupEngine.ollamaAvailable && appState.textCleanupEngine.modelReady
                            ? .green : .secondary,
                        icon: "brain"
                    )
                    StatusCard(
                        title: "Mode",
                        status: appState.currentMode.rawValue,
                        color: .blue,
                        icon: appState.currentMode.icon
                    )
                }

                // History
                if !history.entries.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("History")
                                .font(.headline)
                            Spacer()
                            Button("Clear") {
                                history.clear()
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .buttonStyle(.plain)
                        }

                        ForEach(history.groupedEntries, id: \.label) { group in
                            Text(group.label.uppercased())
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.tertiary)
                                .padding(.top, 4)

                            VStack(spacing: 1) {
                                ForEach(group.entries) { entry in
                                    HStack(alignment: .top, spacing: 16) {
                                        Text(timeFormatter.string(from: entry.timestamp))
                                            .font(.system(size: 12, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .frame(width: 70, alignment: .trailing)

                                        Text(entry.text)
                                            .font(.system(size: 13))
                                            .lineLimit(2)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 12)
                                    .background(Color(.controlBackgroundColor))
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                } else {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "waveform.path")
                            .font(.system(size: 32))
                            .foregroundStyle(.tertiary)
                        Text("No dictations yet")
                            .foregroundStyle(.secondary)
                        Text("Press **Option+Space** to start dictating")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(24)
        }
    }

    private func formatWordCount(_ count: Int) -> String {
        if count >= 1000 {
            return String(format: "%.1fK", Double(count) / 1000.0)
        }
        return "\(count)"
    }
}

private struct StatBadge: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.semibold)
                .font(.system(size: 13))
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }
}

private struct StatusCard: View {
    let title: String
    let status: String
    let color: Color
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(color)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                Text(status)
                    .font(.system(size: 12, weight: .medium))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Dictionary Page

private struct DictionaryPage: View {
    @State private var newMisheard = ""
    @State private var newCorrect = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Dictionary")
                    .font(.title)
                    .fontWeight(.bold)
                Text("Add words that are commonly misheard during transcription.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
            .padding(24)

            // Add form
            HStack(spacing: 12) {
                TextField("Misheard word", text: $newMisheard)
                    .textFieldStyle(.roundedBorder)
                Image(systemName: "arrow.right")
                    .foregroundStyle(.tertiary)
                TextField("Correct spelling", text: $newCorrect)
                    .textFieldStyle(.roundedBorder)
                Button {
                    DictionaryManager.shared.addEntry(misheard: newMisheard, correct: newCorrect)
                    newMisheard = ""
                    newCorrect = ""
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .foregroundStyle(newMisheard.isEmpty || newCorrect.isEmpty ? Color.gray.opacity(0.3) : Color.accentColor)
                .disabled(newMisheard.isEmpty || newCorrect.isEmpty)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)

            Divider()

            // List
            if DictionaryManager.shared.entries.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "character.book.closed")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("No entries yet")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(DictionaryManager.shared.entries.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                            HStack {
                                Text(key)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 150, alignment: .trailing)
                                Image(systemName: "arrow.right")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                Text(value)
                                    .fontWeight(.medium)
                                Spacer()
                                Button {
                                    DictionaryManager.shared.removeEntry(misheard: key)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            .background(Color(.controlBackgroundColor))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(24)
                }
            }
        }
    }
}

// MARK: - Snippets Page

private struct SnippetsPage: View {
    @State private var newTrigger = ""
    @State private var newExpansion = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Snippets")
                    .font(.title)
                    .fontWeight(.bold)
                Text("Say a trigger phrase and it expands to predefined text.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
            .padding(24)

            // Add form
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    TextField("Trigger phrase (e.g. \"insert disclaimer\")", text: $newTrigger)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        ShortcutManager.shared.addShortcut(trigger: newTrigger, expansion: newExpansion)
                        newTrigger = ""
                        newExpansion = ""
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(newTrigger.isEmpty || newExpansion.isEmpty ? Color.gray.opacity(0.3) : Color.accentColor)
                    .disabled(newTrigger.isEmpty || newExpansion.isEmpty)
                }
                TextField("Expansion text", text: $newExpansion, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...3)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)

            Divider()

            // List
            if ShortcutManager.shared.shortcuts.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "text.quote")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("No snippets yet")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(ShortcutManager.shared.shortcuts) { shortcut in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(shortcut.trigger)
                                        .fontWeight(.semibold)
                                        .font(.system(size: 13))
                                    Text(shortcut.expansion)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(3)
                                }
                                Spacer()
                                Button {
                                    ShortcutManager.shared.removeShortcut(trigger: shortcut.trigger)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(14)
                            .background(Color(.controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(24)
                }
            }
        }
    }
}

// MARK: - Models Page

private struct ModelsPage: View {
    let appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Models")
                        .font(.title)
                        .fontWeight(.bold)
                    Text("Manage speech-to-text and LLM models.")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }

                // STT Provider Picker
                VStack(alignment: .leading, spacing: 12) {
                    Text("Speech Engine")
                        .font(.headline)

                    VStack(spacing: 1) {
                        ForEach(STTProvider.allCases) { provider in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(provider.rawValue)
                                        .font(.system(size: 13, weight: .medium))
                                    Text(provider.description)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if provider == appState.transcriptionEngine.provider {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.accentColor)
                                } else {
                                    Button("Switch") {
                                        appState.switchProvider(to: provider)
                                    }
                                    .font(.caption)
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color(.controlBackgroundColor))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                // STT Model
                VStack(alignment: .leading, spacing: 12) {
                    Text("Speech-to-Text Model")
                        .font(.headline)

                    let models = ModelManager.availableModels(for: appState.modelManager.provider)
                    VStack(spacing: 1) {
                        ForEach(models, id: \.self) { model in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(model)
                                        .font(.system(size: 13, weight: .medium))
                                    if appState.modelManager.availableLocalModels.contains(model) {
                                        Text("Downloaded")
                                            .font(.caption2)
                                            .foregroundStyle(.green)
                                    }
                                }

                                Spacer()

                                if model == appState.modelManager.selectedModel {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.accentColor)
                                } else {
                                    Button("Select") {
                                        appState.modelManager.selectModel(model)
                                    }
                                    .font(.caption)
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color(.controlBackgroundColor))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    ModelDownloadView(modelManager: appState.modelManager)
                }

                // LLM Model
                VStack(alignment: .leading, spacing: 12) {
                    Text("LLM Text Cleanup")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(Constants.ollamaDefaultModel)
                                    .font(.system(size: 13, weight: .medium))
                                Text("via Ollama")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(appState.textCleanupEngine.ollamaAvailable && appState.textCleanupEngine.modelReady ? .green : .red)
                                    .frame(width: 6, height: 6)
                                Text(appState.textCleanupEngine.ollamaAvailable && appState.textCleanupEngine.modelReady ? "Ready" : "Not available")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if appState.textCleanupEngine.ollamaAvailable && !appState.textCleanupEngine.modelReady {
                            Button("Download Model") {
                                Task { await appState.textCleanupEngine.downloadModel() }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        Button("Refresh Ollama Status") {
                            Task { await appState.refreshOllamaStatus() }
                        }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(24)
        }
    }
}

// MARK: - Agent Settings Page

private struct AgentSettingsPage: View {
    let appState: AppState
    @State private var openAIKey: String = KeychainHelper.load(key: OpenAIProvider.apiKeyKeychainKey) ?? ""
    @State private var geminiKey: String = KeychainHelper.load(key: GeminiProvider.apiKeyKeychainKey) ?? ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Agent")
                        .font(.title)
                        .fontWeight(.bold)
                    Text("Configure the AI agent LLM provider and model.")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }

                // Provider picker
                SettingsSection(title: "Provider") {
                    ForEach(appState.agentCoordinator.providerManager.availableProviderNames, id: \.self) { name in
                        SettingsRow(label: name) {
                            if appState.agentCoordinator.providerManager.activeProviderName == name {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                            } else {
                                Button("Select") {
                                    appState.agentCoordinator.providerManager.setActiveProvider(name)
                                }
                                .font(.caption)
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                }

                // Model config
                SettingsSection(title: "Model") {
                    SettingsRow(label: "Active Model") {
                        TextField("Model ID", text: Binding(
                            get: { appState.agentCoordinator.providerManager.activeModel },
                            set: { appState.agentCoordinator.providerManager.setModel($0, for: appState.agentCoordinator.providerManager.activeProviderName) }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                    }
                }

                // API Keys
                SettingsSection(title: "API Keys") {
                    SettingsRow(label: "OpenAI") {
                        SecureField("sk-...", text: $openAIKey)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 220)
                            .onChange(of: openAIKey) { _, newValue in
                                if newValue.isEmpty {
                                    KeychainHelper.delete(key: OpenAIProvider.apiKeyKeychainKey)
                                } else {
                                    KeychainHelper.save(key: OpenAIProvider.apiKeyKeychainKey, value: newValue)
                                }
                            }
                    }
                    SettingsRow(label: "Gemini") {
                        SecureField("AI...", text: $geminiKey)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 220)
                            .onChange(of: geminiKey) { _, newValue in
                                if newValue.isEmpty {
                                    KeychainHelper.delete(key: GeminiProvider.apiKeyKeychainKey)
                                } else {
                                    KeychainHelper.save(key: GeminiProvider.apiKeyKeychainKey, value: newValue)
                                }
                            }
                    }
                }

                // Hotkey
                SettingsSection(title: "Hotkey") {
                    SettingsRow(label: "Agent Mode") {
                        HotkeyLabel(binding: appState.hotkeyManager.agentBinding)
                    }
                }

                // Panel Mode
                SettingsSection(title: "Agent Panel") {
                    SettingsRow(label: "Panel Mode") {
                        Picker("", selection: Binding(
                            get: { AgentPanel.shared.state.panelMode },
                            set: { AgentPanel.shared.state.panelMode = $0 }
                        )) {
                            Text("Persistent").tag(AgentPanelState.PanelMode.persistent)
                            Text("Pop-up").tag(AgentPanelState.PanelMode.popUp)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                    }
                    Text("Persistent: panel stays open across turns. Pop-up: appears per turn, auto-dismisses.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                }

                // Tools
                SettingsSection(title: "Tools") {
                    ForEach(appState.agentCoordinator.toolRegistry.allTools, id: \.name) { tool in
                        SettingsRow(label: toolDisplayName(tool.name)) {
                            HStack(spacing: 6) {
                                if tool.requiresConfirmation {
                                    Image(systemName: "shield.fill")
                                        .foregroundStyle(.orange)
                                        .font(.caption)
                                        .help("Requires user confirmation")
                                }
                                Toggle("", isOn: Binding(
                                    get: { appState.agentCoordinator.toolRegistry.settings.isEnabled(tool.name) },
                                    set: { appState.agentCoordinator.toolRegistry.settings.setEnabled(tool.name, enabled: $0) }
                                ))
                                .toggleStyle(.switch)
                                .controlSize(.small)
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    private func toolDisplayName(_ name: String) -> String {
        name.split(separator: "_").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}

// MARK: - Settings Page

private struct SettingsPage_: View {
    let appState: AppState
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Settings")
                        .font(.title)
                        .fontWeight(.bold)
                    Text("Configure Voxa to work the way you want.")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }

                // General
                SettingsSection(title: "General") {
                    SettingsRow(label: "Launch at Login") {
                        Toggle("", isOn: $launchAtLogin)
                            .labelsHidden()
                            .onChange(of: launchAtLogin) { _, newValue in
                                do {
                                    if newValue {
                                        try SMAppService.mainApp.register()
                                    } else {
                                        try SMAppService.mainApp.unregister()
                                    }
                                } catch {
                                    launchAtLogin = SMAppService.mainApp.status == .enabled
                                }
                            }
                    }

                    SettingsRow(label: "Sound Feedback") {
                        Toggle("", isOn: Binding(
                            get: { SoundManager.shared.isEnabled },
                            set: { SoundManager.shared.isEnabled = $0 }
                        ))
                        .labelsHidden()
                    }

                    SettingsRow(label: "LLM Cleanup") {
                        Toggle("", isOn: Bindable(appState.textCleanupEngine).isEnabled)
                            .labelsHidden()
                            .disabled(!appState.textCleanupEngine.ollamaAvailable)
                    }
                }

                // Hotkeys
                SettingsSection(title: "Hotkeys") {
                    SettingsRow(label: "Push to Talk") {
                        HotkeyLabel(binding: appState.hotkeyManager.pushToTalkBinding)
                    }
                    SettingsRow(label: "Flow Mode") {
                        HotkeyLabel(binding: appState.hotkeyManager.flowBinding)
                    }
                    SettingsRow(label: "Command Mode") {
                        HotkeyLabel(binding: appState.hotkeyManager.commandBinding)
                    }
                    SettingsRow(label: "Agent Mode") {
                        HotkeyLabel(binding: appState.hotkeyManager.agentBinding)
                    }
                }

                // Audio
                SettingsSection(title: "Audio") {
                    SettingsRow(label: "Microphone") {
                        Picker("", selection: Binding(
                            get: { appState.audioEngine.selectedDeviceID ?? 0 },
                            set: { appState.audioEngine.selectDevice($0) }
                        )) {
                            ForEach(appState.audioEngine.availableInputDevices) { device in
                                Text(device.name).tag(device.id)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 200)
                    }
                }

                // About
                SettingsSection(title: "About") {
                    SettingsRow(label: "Version") {
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0")
                            .foregroundStyle(.secondary)
                    }

                    SettingsRow(label: "Data Directory") {
                        Text(Constants.dataDirectory.path)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(24)
        }
    }
}

// MARK: - Settings Helpers

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title.uppercased())
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 6)

            VStack(spacing: 1) {
                content
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

private struct SettingsRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
            Spacer()
            content
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.controlBackgroundColor))
    }
}

// MARK: - Hotkey Label

private struct HotkeyLabel: View {
    let binding: HotkeyBinding

    var body: some View {
        Text(binding.displayString)
            .font(.system(size: 12, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(.controlBackgroundColor).opacity(0.5))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
