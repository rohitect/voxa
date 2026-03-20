import SwiftUI
import ServiceManagement

// MARK: - Sidebar Navigation

enum SettingsPage: String, CaseIterable, Identifiable {
    case home = "Home"
    case chat = "Chat"
    case dictionary = "Dictionary"
    case snippets = "Snippets"
    case agent = "Agent"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: return "house"
        case .chat: return "bubble.left.and.bubble.right"
        case .dictionary: return "character.book.closed"
        case .snippets: return "text.quote"
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
            .padding(.top, 38)
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
        .background(Color.primary.opacity(0.04))
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch selectedPage {
        case .home:
            HomePage(appState: appState)
        case .chat:
            AgentChatPage(appState: appState)
        case .dictionary:
            DictionaryPage()
        case .snippets:
            SnippetsPage()
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

    @State private var isHovered = false

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
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected
                          ? VoxaTheme.surfaceOverlayActive
                          : isHovered ? VoxaTheme.surfaceOverlay : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
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
                                    .background(Color.primary.opacity(0.06))
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
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
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
                            .background(Color.primary.opacity(0.06))
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
                            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                            )
                        }
                    }
                    .padding(24)
                }
            }
        }
    }
}

// MARK: - Agent Settings Page

// MARK: - Agent Settings Tab Enum

private enum AgentTab: String, CaseIterable, Identifiable {
    case general = "General"
    case persona = "Persona"
    case tools = "Tools"
    case agents = "Agents"
    case marketplace = "Marketplace"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .persona: return "sparkles"
        case .tools: return "wrench"
        case .agents: return "person.3"
        case .marketplace: return "bag"
        }
    }
}

private struct AgentSettingsPage: View {
    let appState: AppState
    @State private var selectedTab: AgentTab = .general

    var body: some View {
        VStack(spacing: 0) {
            // Header + Tab bar
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Agent")
                        .font(.title)
                        .fontWeight(.bold)
                    Text("Configure the AI agent, persona, tools, and sub-agents.")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }

                HStack(spacing: 2) {
                    ForEach(AgentTab.allCases) { tab in
                        Button {
                            selectedTab = tab
                        } label: {
                            Label(tab.rawValue, systemImage: tab.icon)
                                .font(.system(size: 12, weight: selectedTab == tab ? .semibold : .regular))
                                .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    selectedTab == tab
                                        ? Color.primary.opacity(0.08)
                                        : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 6)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(24)
            .padding(.bottom, -8)

            Divider().padding(.horizontal, 24)

            // Tab content
            Group {
                switch selectedTab {
                case .general:
                    AgentGeneralTab(appState: appState)
                case .persona:
                    AgentPersonaTab(appState: appState)
                case .tools:
                    AgentToolsTab(appState: appState)
                case .agents:
                    AgentAgentsTab(appState: appState)
                case .marketplace:
                    MCPMarketplaceView(mcpManager: appState.agentCoordinator.mcpManager)
                }
            }
        }
    }
}

// MARK: - General Tab

private struct AgentGeneralTab: View {
    let appState: AppState
    @State private var openAIKey: String = KeychainHelper.load(key: OpenAIProvider.apiKeyKeychainKey) ?? ""
    @State private var geminiKey: String = KeychainHelper.load(key: GeminiProvider.apiKeyKeychainKey) ?? ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
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
            }
            .padding(24)
        }
    }
}

// MARK: - Persona Tab

private struct AgentPersonaTab: View {
    let appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SettingsSection(title: "Identity & Soul") {
                    PersonaFileRow(
                        label: "Identity",
                        icon: "person.text.rectangle",
                        description: "Name, role, and vibe",
                        content: appState.agentCoordinator.personaManager.identity,
                        onSave: { appState.agentCoordinator.personaManager.saveIdentity($0) }
                    )
                    PersonaFileRow(
                        label: "Soul",
                        icon: "sparkles",
                        description: "Personality, voice, and boundaries",
                        content: appState.agentCoordinator.personaManager.soul,
                        onSave: { appState.agentCoordinator.personaManager.saveSoul($0) }
                    )
                }

                SettingsSection(title: "Memory") {
                    SettingsRow(label: "Auto-extract memories") {
                        Toggle("", isOn: Binding(
                            get: { appState.agentCoordinator.personaManager.autoExtract },
                            set: { appState.agentCoordinator.personaManager.autoExtract = $0 }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    }
                    Text("Automatically learn preferences and context from conversations.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)

                    let memoryCount = appState.agentCoordinator.personaManager.memoryStore.entries.count
                    SettingsRow(label: "Stored memories") {
                        Text("\(memoryCount)")
                            .font(.system(size: 13).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(24)
        }
    }
}

// MARK: - Tools Tab

private struct AgentToolsTab: View {
    let appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SettingsSection(title: "Built-in Tools") {
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

                SettingsSection(title: "MCP Servers") {
                    MCPSettingsView(mcpManager: appState.agentCoordinator.mcpManager)
                }
            }
            .padding(24)
        }
    }

    private func toolDisplayName(_ name: String) -> String {
        name.split(separator: "_").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}

// MARK: - Agents Tab

private struct AgentAgentsTab: View {
    let appState: AppState
    @State private var showMainAgentMCPSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Main Agent
                SettingsSection(title: "Main Agent") {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Voxa")
                                .font(.system(size: 13, weight: .medium))
                            Text("The primary agent that handles all voice commands and chat.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        // MCP server count badge
                        let mcpCount = appState.agentCoordinator.mcpManager.mainAgentMCPServerIDs?.count
                            ?? appState.agentCoordinator.mcpManager.configStore.servers.filter(\.enabled).count
                        if mcpCount > 0 {
                            Text("\(mcpCount) MCP\(mcpCount == 1 ? "" : "s")")
                                .font(.system(size: 10))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.12))
                                .clipShape(Capsule())
                        }

                        Button("MCPs") {
                            showMainAgentMCPSheet = true
                        }
                        .font(.system(size: 11))
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.primary.opacity(0.06))
                }
                .sheet(isPresented: $showMainAgentMCPSheet) {
                    MainAgentMCPSheet(mcpManager: appState.agentCoordinator.mcpManager)
                }

                // Sub-Agents
                SettingsSection(title: "Sub-Agents") {
                    SubAgentSettingsView(subAgentManager: appState.agentCoordinator.subAgentManager, mcpConfigStore: appState.agentCoordinator.mcpManager.configStore)
                }
            }
            .padding(24)
        }
    }
}

// MARK: - Persona File Row

private struct PersonaFileRow: View {
    let label: String
    let icon: String
    let description: String
    let content: String
    let onSave: (String) -> Void

    @State private var showEditor = false

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(label).md")
                    .font(.system(size: 13, weight: .medium))
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(content.count) chars")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Button("Edit") {
                showEditor = true
            }
            .font(.system(size: 11))
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .sheet(isPresented: $showEditor) {
            PersonaFileEditor(
                title: label,
                initialContent: content,
                onSave: onSave
            )
        }
    }
}

// MARK: - Persona File Editor

private struct PersonaFileEditor: View {
    let title: String
    let initialContent: String
    let onSave: (String) -> Void

    @State private var text: String = ""
    @State private var hasChanges = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(title.lowercased()).md")
                        .font(.headline)
                    Text("~/.voxa/agent/\(title.lowercased()).md")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                }

                Spacer()

                if hasChanges {
                    Text("Unsaved changes")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                Button("Save") {
                    onSave(text)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!hasChanges)
            }
            .padding(16)

            Divider()

            // Editor
            TextEditor(text: $text)
                .font(.system(size: 13, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(12)
                .onChange(of: text) { _, newValue in
                    hasChanges = newValue != initialContent
                }
        }
        .frame(minWidth: 560, minHeight: 420)
        .onAppear {
            text = initialContent
        }
    }
}

// MARK: - Settings Page

// MARK: - Settings Tab Enum

private enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case models = "Models"
    case hotkeys = "Hotkeys"
    case audio = "Audio"
    case permissions = "Permissions"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .models: return "cpu"
        case .hotkeys: return "keyboard"
        case .audio: return "mic"
        case .permissions: return "lock.shield"
        }
    }
}

private struct SettingsPage_: View {
    let appState: AppState
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Settings")
                    .font(.title)
                    .fontWeight(.bold)
                Text("Configure Voxa to work the way you want.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 16)

            // Tab bar
            HStack(spacing: 0) {
                ForEach(SettingsTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 12))
                            Text(tab.rawValue)
                                .font(.system(size: 13, weight: selectedTab == tab ? .semibold : .regular))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(selectedTab == tab ? Color.accentColor.opacity(0.12) : Color.clear)
                        )
                        .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 24)

            Divider()
                .padding(.top, 8)

            // Tab content
            Group {
                switch selectedTab {
                case .general:
                    SettingsGeneralTab(appState: appState)
                case .models:
                    SettingsModelsTab(appState: appState)
                case .hotkeys:
                    SettingsHotkeysTab(appState: appState)
                case .audio:
                    SettingsAudioTab(appState: appState)
                case .permissions:
                    SettingsPermissionsTab(appState: appState)
                }
            }
        }
    }
}

// MARK: - General Tab

private struct SettingsGeneralTab: View {
    let appState: AppState
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
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

                    SettingsRow(label: "Show Companion") {
                        Toggle("", isOn: Binding(
                            get: { CompanionState.shared.isVisible },
                            set: { newValue in
                                CompanionState.shared.isVisible = newValue
                                if newValue { CompanionWindow.shared.show() }
                                else { CompanionWindow.shared.hide() }
                            }
                        ))
                        .labelsHidden()
                    }
                }

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

// MARK: - Models Tab

private struct SettingsModelsTab: View {
    let appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // STT Provider Picker
                SettingsSection(title: "Speech Engine") {
                    ForEach(STTProvider.allCases) { provider in
                        SettingsRow(label: provider.rawValue) {
                            HStack(spacing: 8) {
                                Text(provider.description)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)

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
                        }
                    }
                }

                // STT Model
                VStack(alignment: .leading, spacing: 12) {
                    Text("SPEECH-TO-TEXT MODEL")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.tertiary)
                        .padding(.bottom, 6)

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
                            .background(Color.primary.opacity(0.06))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    ModelDownloadView(modelManager: appState.modelManager)
                }

                // LLM Model
                SettingsSection(title: "LLM Text Cleanup") {
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
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.primary.opacity(0.06))

                    if appState.textCleanupEngine.ollamaAvailable && !appState.textCleanupEngine.modelReady {
                        Button("Download Model") {
                            Task { await appState.textCleanupEngine.downloadModel() }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.primary.opacity(0.06))
                    }

                    HStack {
                        Spacer()
                        Button("Refresh Ollama Status") {
                            Task { await appState.refreshOllamaStatus() }
                        }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.primary.opacity(0.06))
                }
            }
            .padding(24)
        }
    }
}

// MARK: - Hotkeys Tab

private struct SettingsHotkeysTab: View {
    let appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
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
            }
            .padding(24)
        }
    }
}

// MARK: - Audio Tab

private struct SettingsAudioTab: View {
    let appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SettingsSection(title: "Audio Input") {
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
            }
            .padding(24)
        }
    }
}

// MARK: - Permissions Tab

private struct SettingsPermissionsTab: View {
    let appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PermissionsSection(permissionManager: appState.permissionManager)
            }
            .padding(24)
        }
    }
}

// MARK: - Permissions Section

import ScreenCaptureKit

private struct PermissionsSection: View {
    let permissionManager: PermissionManager
    @State private var screenRecordingGranted = false

    var body: some View {
        SettingsSection(title: "Permissions") {
            // Microphone
            SettingsRow(label: "Microphone") {
                HStack(spacing: 8) {
                    statusBadge(granted: permissionManager.microphoneGranted)
                    if !permissionManager.microphoneGranted {
                        Button("Grant") {
                            permissionManager.requestMicrophone()
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button("Open Settings") {
                            openSystemSettings("com.apple.preference.security?Privacy_Microphone")
                        }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
            }

            // Accessibility
            SettingsRow(label: "Accessibility") {
                HStack(spacing: 8) {
                    statusBadge(granted: permissionManager.accessibilityGranted)
                    if !permissionManager.accessibilityGranted {
                        Button("Grant") {
                            permissionManager.promptAccessibility()
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button("Open Settings") {
                            openSystemSettings("com.apple.preference.security?Privacy_Accessibility")
                        }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
            }

            // Screen Recording (needed for ScreenCaptureTool)
            VStack(alignment: .leading, spacing: 6) {
                SettingsRow(label: "Screen Recording") {
                    HStack(spacing: 8) {
                        statusBadge(granted: screenRecordingGranted)
                        if !screenRecordingGranted {
                            Button("Open Settings") {
                                openScreenRecordingSettings()
                            }
                            .font(.caption)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
                if !screenRecordingGranted {
                    Text("Click \"+\" in System Settings to add Voxa manually, then enable the toggle.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 6)
                        .background(Color.primary.opacity(0.06))
                }
            }
            .background(Color.primary.opacity(0.06))

            // Check All
            HStack {
                Spacer()
                Button("Check All") {
                    permissionManager.requestMicrophone()
                    permissionManager.checkAccessibility()
                    checkScreenRecording()
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.06))
        }
        .onAppear {
            checkScreenRecording()
        }
    }

    private func statusBadge(granted: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(granted ? .green : .red)
                .font(.system(size: 14))
            Text(granted ? "Granted" : "Not Granted")
                .font(.caption)
                .foregroundStyle(granted ? .green : .red)
        }
    }

    private func checkScreenRecording() {
        // Use ScreenCaptureKit to register in macOS 15+ "Screen and System Audio Recording" pane
        Task {
            do {
                _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                await MainActor.run { screenRecordingGranted = true }
            } catch {
                await MainActor.run { screenRecordingGranted = false }
            }
        }
    }

    private func openSystemSettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openScreenRecordingSettings() {
        // macOS 15+ uses a new pane for Screen & System Audio Recording
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture"
        ]
        for urlString in urls {
            if let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
                return
            }
        }
    }
}

// MARK: - Main Agent MCP Sheet

private struct MainAgentMCPSheet: View {
    let mcpManager: MCPManager
    @State private var selectedIDs: Set<String> = []
    @State private var useAll = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Main Agent — MCP Servers")
                    .font(.headline)
                Spacer()
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Use all enabled MCP servers", isOn: $useAll)
                        .font(.system(size: 13))

                    if useAll {
                        Text("The main agent will automatically use every enabled MCP server.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Select which MCP servers the main agent can use:")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        if mcpManager.configStore.servers.isEmpty {
                            Text("No MCP servers configured. Add servers in the MCP settings section.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 4)
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(mcpManager.configStore.servers) { server in
                                    HStack(spacing: 8) {
                                        Toggle("", isOn: Binding(
                                            get: { selectedIDs.contains(server.id) },
                                            set: { isOn in
                                                if isOn {
                                                    selectedIDs.insert(server.id)
                                                } else {
                                                    selectedIDs.remove(server.id)
                                                }
                                            }
                                        ))
                                        .toggleStyle(.checkbox)
                                        .controlSize(.small)

                                        Text(server.name)
                                            .font(.system(size: 12))

                                        Text(server.transport.rawValue.uppercased())
                                            .font(.system(size: 9, weight: .semibold))
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(Color.secondary.opacity(0.12))
                                            .clipShape(Capsule())

                                        if !server.enabled {
                                            Text("DISABLED")
                                                .font(.system(size: 9, weight: .semibold))
                                                .foregroundStyle(.orange)
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(Color.orange.opacity(0.12))
                                                .clipShape(Capsule())
                                        }

                                        Spacer()
                                    }
                                }
                            }
                            .padding(8)
                            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
                .padding()
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    if useAll {
                        mcpManager.mainAgentMCPServerIDs = nil
                    } else {
                        mcpManager.mainAgentMCPServerIDs = Array(selectedIDs)
                    }
                    // Reconnect with new assignments
                    Task { await reconnectMainAgent() }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 420, height: 400)
        .onAppear {
            if let ids = mcpManager.mainAgentMCPServerIDs {
                useAll = false
                selectedIDs = Set(ids)
            } else {
                useAll = true
                selectedIDs = Set(mcpManager.configStore.servers.filter(\.enabled).map(\.id))
            }
        }
    }

    private func reconnectMainAgent() async {
        await mcpManager.disconnectAll()
        await mcpManager.connectAll()
    }
}

// MARK: - Settings Helpers

struct SettingsSection<Content: View>: View {
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

struct SettingsRow<Content: View>: View {
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
        .background(Color.primary.opacity(0.06))
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
            .background(Color.primary.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
