import SwiftUI

struct MCPMarketplaceView: View {
    let mcpManager: MCPManager
    @State private var searchText: String = ""
    @State private var selectedCategory: MCPCatalogCategory?
    @State private var selectedEntry: MCPCatalogEntry?
    @State private var installingIDs: Set<String> = []

    private var filteredEntries: [MCPCatalogEntry] {
        MCPCatalog.all.filter { entry in
            let matchesCategory = selectedCategory == nil || entry.category == selectedCategory
            let matchesSearch = searchText.isEmpty
                || entry.name.localizedCaseInsensitiveContains(searchText)
                || entry.description.localizedCaseInsensitiveContains(searchText)
                || entry.author.localizedCaseInsensitiveContains(searchText)
            return matchesCategory && matchesSearch
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Search
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.tertiary)
                    TextField("Search MCP servers...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(10)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))

                // Category chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        CategoryChip(label: "All", icon: "square.grid.2x2", isSelected: selectedCategory == nil) {
                            selectedCategory = nil
                        }
                        ForEach(MCPCatalogCategory.allCases) { category in
                            CategoryChip(
                                label: category.rawValue,
                                icon: category.icon,
                                isSelected: selectedCategory == category
                            ) {
                                selectedCategory = selectedCategory == category ? nil : category
                            }
                        }
                    }
                }

                // Grid
                if filteredEntries.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.largeTitle)
                            .foregroundStyle(.tertiary)
                        Text("No MCP servers found")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(filteredEntries) { entry in
                            MCPCatalogCard(
                                entry: entry,
                                isInstalled: isInstalled(entry),
                                isInstalling: installingIDs.contains(entry.id),
                                onInstall: { installEntry(entry) },
                                onDetail: { selectedEntry = entry }
                            )
                        }
                    }
                }
            }
            .padding(24)
        }
        .sheet(item: $selectedEntry) { entry in
            MCPCatalogDetailSheet(
                entry: entry,
                isInstalled: isInstalled(entry),
                isInstalling: installingIDs.contains(entry.id),
                onInstall: { installEntry(entry) }
            )
        }
    }

    // MARK: - Helpers

    private func isInstalled(_ entry: MCPCatalogEntry) -> Bool {
        mcpManager.configStore.servers.contains { server in
            guard let repo = server.repository else { return false }
            return normalizeRepoURL(repo) == normalizeRepoURL(entry.repository)
        }
    }

    private func normalizeRepoURL(_ url: String) -> String {
        var s = url.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasSuffix(".git") { s = String(s.dropLast(4)) }
        if s.hasSuffix("/") { s = String(s.dropLast()) }
        return s
    }

    private func installEntry(_ entry: MCPCatalogEntry) {
        guard !installingIDs.contains(entry.id), !isInstalled(entry) else { return }
        installingIDs.insert(entry.id)

        Task {
            do {
                _ = try await mcpManager.installFromRepo(
                    repository: entry.repository,
                    name: entry.name,
                    buildCommand: entry.buildCommand,
                    command: entry.defaultCommand,
                    args: entry.defaultArgs,
                    transport: entry.transport
                )
            } catch {
                print("[Marketplace] Install failed for \(entry.name): \(error)")
            }
            await MainActor.run {
                installingIDs.remove(entry.id)
            }
        }
    }
}

// MARK: - Category Chip

private struct CategoryChip: View {
    let label: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .white : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    isSelected ? Color.accentColor : Color.primary.opacity(0.06),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Catalog Card

private struct MCPCatalogCard: View {
    let entry: MCPCatalogEntry
    let isInstalled: Bool
    let isInstalling: Bool
    let onInstall: () -> Void
    let onDetail: () -> Void

    var body: some View {
        Button(action: onDetail) {
            VStack(alignment: .leading, spacing: 10) {
                // Header
                HStack(spacing: 10) {
                    Image(systemName: entry.iconName)
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 36, height: 36)
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(entry.author)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()
                }

                // Description
                Text(entry.description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                // Footer
                HStack {
                    // Category badge
                    Text(entry.category.rawValue)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.06), in: Capsule())

                    // Tool count
                    Label("\(entry.toolCount) tools", systemImage: "wrench")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)

                    Spacer()

                    // Install button
                    installButton
                }
            }
            .padding(14)
            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var installButton: some View {
        if isInstalled {
            Label("Installed", systemImage: "checkmark.circle.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.green)
        } else if isInstalling {
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.mini)
                Text("Installing...")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        } else {
            Button {
                onInstall()
            } label: {
                Text("Install")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.accentColor, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Detail Sheet

private struct MCPCatalogDetailSheet: View {
    let entry: MCPCatalogEntry
    let isInstalled: Bool
    let isInstalling: Bool
    let onInstall: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 14) {
                Image(systemName: entry.iconName)
                    .font(.title)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 48, height: 48)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.name)
                        .font(.title2)
                        .fontWeight(.bold)
                    HStack(spacing: 8) {
                        Text(entry.author)
                            .foregroundStyle(.secondary)
                        if let license = entry.license {
                            Text(license)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Color.primary.opacity(0.06), in: Capsule())
                        }
                        Text(entry.category.rawValue)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.primary.opacity(0.06), in: Capsule())
                    }
                    .font(.subheadline)
                }

                Spacer()

                installButton
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Description
                    Text(entry.detailedDescription)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)

                    // Permissions
                    if !entry.requiredPermissions.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Required Permissions", systemImage: "lock.shield")
                                .font(.system(size: 12, weight: .semibold))
                            ForEach(entry.requiredPermissions, id: \.self) { perm in
                                HStack(spacing: 6) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.orange)
                                    Text(perm)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    }

                    // Tools
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Tools")
                                .font(.system(size: 12, weight: .semibold))
                            Text("(\(entry.toolCount))")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                        }

                        VStack(spacing: 0) {
                            ForEach(Array(entry.tools.enumerated()), id: \.offset) { index, tool in
                                HStack(spacing: 8) {
                                    Text(tool.name)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text(tool.description)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }
                                .padding(.vertical, 6)
                                .padding(.horizontal, 10)

                                if index < entry.tools.count - 1 {
                                    Divider().padding(.leading, 10)
                                }
                            }
                        }
                        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                        )
                    }

                    // Repo link
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                            .font(.system(size: 10))
                        Text(entry.repository)
                            .font(.system(size: 11, design: .monospaced))
                    }
                    .foregroundStyle(.tertiary)
                }
                .padding(20)
            }

            Divider()

            // Footer
            HStack {
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
            }
            .padding(16)
        }
        .frame(width: 540, height: 520)
    }

    @ViewBuilder
    private var installButton: some View {
        if isInstalled {
            Label("Installed", systemImage: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.green)
        } else if isInstalling {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Installing...")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        } else {
            Button {
                onInstall()
            } label: {
                Label("Install", systemImage: "arrow.down.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.accentColor, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}
