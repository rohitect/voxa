import SwiftUI

/// Renders markdown content in chat bubbles with support for headers, bold, italic,
/// inline code, fenced code blocks, links, lists, blockquotes, and horizontal rules.
struct MarkdownView: View {
    let content: String
    let fontSize: CGFloat
    let isUser: Bool

    init(_ content: String, fontSize: CGFloat = 13, isUser: Bool = false) {
        self.content = content
        self.fontSize = fontSize
        self.isUser = isUser
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(parseBlocks().enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    // MARK: - Block Types

    private enum Block {
        case text(String)
        case codeBlock(language: String?, code: String)
        case header(level: Int, text: String)
        case bulletList(items: [String])
        case numberedList(items: [String])
        case blockquote(String)
        case horizontalRule
    }

    // MARK: - Parsing

    /// Split content into structured blocks
    private func parseBlocks() -> [Block] {
        var blocks: [Block] = []
        let lines = content.components(separatedBy: "\n")
        var currentText: [String] = []
        var inCodeBlock = false
        var codeLines: [String] = []
        var codeLanguage: String?

        // Accumulators for lists
        var bulletItems: [String] = []
        var numberedItems: [String] = []

        func flushText() {
            if !currentText.isEmpty {
                let text = currentText.joined(separator: "\n")
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    blocks.append(.text(text))
                }
                currentText = []
            }
        }

        func flushBulletList() {
            if !bulletItems.isEmpty {
                blocks.append(.bulletList(items: bulletItems))
                bulletItems = []
            }
        }

        func flushNumberedList() {
            if !numberedItems.isEmpty {
                blocks.append(.numberedList(items: numberedItems))
                numberedItems = []
            }
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // --- Fenced code blocks ---
            if !inCodeBlock && trimmed.hasPrefix("```") {
                flushText()
                flushBulletList()
                flushNumberedList()
                inCodeBlock = true
                codeLanguage = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                if codeLanguage?.isEmpty == true { codeLanguage = nil }
                codeLines = []
                continue
            }
            if inCodeBlock && trimmed.hasPrefix("```") {
                blocks.append(.codeBlock(language: codeLanguage, code: codeLines.joined(separator: "\n")))
                inCodeBlock = false
                codeLines = []
                codeLanguage = nil
                continue
            }
            if inCodeBlock {
                codeLines.append(line)
                continue
            }

            // --- Horizontal rule ---
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushText()
                flushBulletList()
                flushNumberedList()
                blocks.append(.horizontalRule)
                continue
            }

            // --- Headers ---
            if let headerMatch = parseHeader(trimmed) {
                flushText()
                flushBulletList()
                flushNumberedList()
                blocks.append(.header(level: headerMatch.level, text: headerMatch.text))
                continue
            }

            // --- Blockquote ---
            if trimmed.hasPrefix("> ") || trimmed == ">" {
                flushText()
                flushBulletList()
                flushNumberedList()
                let quoteText = trimmed.hasPrefix("> ") ? String(trimmed.dropFirst(2)) : ""
                blocks.append(.blockquote(quoteText))
                continue
            }

            // --- Bullet list ---
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                flushText()
                flushNumberedList()
                let item = String(trimmed.dropFirst(2))
                bulletItems.append(item)
                continue
            }

            // --- Numbered list ---
            if let numItem = parseNumberedListItem(trimmed) {
                flushText()
                flushBulletList()
                numberedItems.append(numItem)
                continue
            }

            // --- Regular text ---
            flushBulletList()
            flushNumberedList()
            currentText.append(line)
        }

        // Flush remaining
        if inCodeBlock {
            blocks.append(.codeBlock(language: codeLanguage, code: codeLines.joined(separator: "\n")))
        }
        flushText()
        flushBulletList()
        flushNumberedList()

        return blocks
    }

    private func parseHeader(_ line: String) -> (level: Int, text: String)? {
        var level = 0
        for ch in line {
            if ch == "#" { level += 1 } else { break }
        }
        guard level >= 1, level <= 6, line.count > level, line[line.index(line.startIndex, offsetBy: level)] == " " else {
            return nil
        }
        let text = String(line.dropFirst(level + 1))
        return (level, text)
    }

    private func parseNumberedListItem(_ line: String) -> String? {
        // Match "1. ", "2. ", "10. ", etc.
        guard let dotIndex = line.firstIndex(of: ".") else { return nil }
        let prefix = line[line.startIndex..<dotIndex]
        guard !prefix.isEmpty, prefix.allSatisfy(\.isNumber) else { return nil }
        let afterDot = line.index(after: dotIndex)
        guard afterDot < line.endIndex, line[afterDot] == " " else { return nil }
        return String(line[line.index(after: afterDot)...])
    }

    // MARK: - Block Views

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block {
        case .text(let text):
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                inlineMarkdownText(text)
            }
        case .codeBlock(let language, let code):
            codeBlockView(language: language, code: code)
        case .header(let level, let text):
            headerView(level: level, text: text)
        case .bulletList(let items):
            bulletListView(items: items)
        case .numberedList(let items):
            numberedListView(items: items)
        case .blockquote(let text):
            blockquoteView(text: text)
        case .horizontalRule:
            Divider()
                .padding(.vertical, 4)
        }
    }

    // MARK: - Header

    private func headerView(level: Int, text: String) -> some View {
        let (size, weight): (CGFloat, Font.Weight) = {
            switch level {
            case 1: return (fontSize + 8, .bold)
            case 2: return (fontSize + 5, .bold)
            case 3: return (fontSize + 3, .semibold)
            case 4: return (fontSize + 1, .semibold)
            default: return (fontSize, .semibold)
            }
        }()
        return Text(parseInlineMarkdown(text, baseSize: size))
            .font(.system(size: size, weight: weight))
            .textSelection(.enabled)
            .padding(.top, level <= 2 ? 6 : 2)
    }

    // MARK: - Lists

    private func bulletListView(items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\u{2022}")
                        .font(.system(size: fontSize))
                        .foregroundStyle(.secondary)
                    Text(parseInlineMarkdown(item, baseSize: fontSize))
                        .font(.system(size: fontSize))
                        .textSelection(.enabled)
                        .lineSpacing(2)
                }
            }
        }
        .padding(.leading, 4)
    }

    private func numberedListView(items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(index + 1).")
                        .font(.system(size: fontSize, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 20, alignment: .trailing)
                    Text(parseInlineMarkdown(item, baseSize: fontSize))
                        .font(.system(size: fontSize))
                        .textSelection(.enabled)
                        .lineSpacing(2)
                }
            }
        }
        .padding(.leading, 4)
    }

    // MARK: - Blockquote

    private func blockquoteView(text: String) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 3)
            Text(parseInlineMarkdown(text, baseSize: fontSize))
                .font(.system(size: fontSize))
                .italic()
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineSpacing(2)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Code Block

    private func codeBlockView(language: String?, code: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let lang = language, !lang.isEmpty {
                HStack {
                    Text(lang)
                        .font(.system(size: fontSize - 2, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    CodeCopyButton(code: code)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(.separatorColor).opacity(0.15))
            } else {
                HStack {
                    Spacer()
                    CodeCopyButton(code: code)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            }

            Text(code)
                .font(.system(size: fontSize - 1, design: .monospaced))
                .textSelection(.enabled)
                .lineSpacing(2)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isUser ? Color.white.opacity(0.1) : Color.primary.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(.separatorColor).opacity(0.3), lineWidth: 0.5)
        )
    }

    // MARK: - Inline Markdown → AttributedString

    private func inlineMarkdownText(_ text: String) -> some View {
        let attributed = parseInlineMarkdown(text, baseSize: fontSize)
        return Text(attributed)
            .lineSpacing(fontSize > 12 ? 3 : 2)
            .textSelection(.enabled)
    }

    private func parseInlineMarkdown(_ text: String, baseSize: CGFloat) -> AttributedString {
        // Try Apple's built-in markdown parser first
        if let result = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            var styled = result
            styled.font = .system(size: baseSize)
            for run in styled.runs {
                if run.inlinePresentationIntent?.contains(.code) == true {
                    let range = run.range
                    styled[range].font = .system(size: baseSize - 1, design: .monospaced)
                    styled[range].backgroundColor = isUser
                        ? Color.white.opacity(0.15)
                        : Color(.textBackgroundColor).opacity(0.6)
                }
            }
            return styled
        }

        var plain = AttributedString(text)
        plain.font = .system(size: baseSize)
        return plain
    }
}

// MARK: - Code Copy Button

private struct CodeCopyButton: View {
    let code: String
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(code, forType: .string)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 10))
                .foregroundStyle(copied ? .green : .secondary)
        }
        .buttonStyle(.plain)
        .help("Copy code")
    }
}
