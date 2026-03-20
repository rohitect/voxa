import SwiftUI

/// Renders markdown content in chat bubbles with support for headers, bold, italic,
/// inline code, fenced code blocks, links, and lists.
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
    }

    // MARK: - Parsing

    /// Split content into text blocks and fenced code blocks
    private func parseBlocks() -> [Block] {
        var blocks: [Block] = []
        let lines = content.components(separatedBy: "\n")
        var currentText: [String] = []
        var inCodeBlock = false
        var codeLines: [String] = []
        var codeLanguage: String?

        for line in lines {
            if !inCodeBlock && line.hasPrefix("```") {
                // Flush accumulated text
                if !currentText.isEmpty {
                    blocks.append(.text(currentText.joined(separator: "\n")))
                    currentText = []
                }
                inCodeBlock = true
                codeLanguage = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                if codeLanguage?.isEmpty == true { codeLanguage = nil }
                codeLines = []
            } else if inCodeBlock && line.hasPrefix("```") {
                blocks.append(.codeBlock(language: codeLanguage, code: codeLines.joined(separator: "\n")))
                inCodeBlock = false
                codeLines = []
                codeLanguage = nil
            } else if inCodeBlock {
                codeLines.append(line)
            } else {
                currentText.append(line)
            }
        }

        // Flush remaining
        if inCodeBlock {
            // Unclosed code block — treat as code anyway
            blocks.append(.codeBlock(language: codeLanguage, code: codeLines.joined(separator: "\n")))
        }
        if !currentText.isEmpty {
            blocks.append(.text(currentText.joined(separator: "\n")))
        }

        return blocks
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
        }
    }

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
        let attributed = parseInlineMarkdown(text)
        return Text(attributed)
            .lineSpacing(fontSize > 12 ? 3 : 2)
            .textSelection(.enabled)
    }

    private func parseInlineMarkdown(_ text: String) -> AttributedString {
        // Try Apple's built-in markdown parser first
        if let result = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            var styled = result
            // Apply base font
            styled.font = .system(size: fontSize)
            // Style inline code runs
            for run in styled.runs {
                if run.inlinePresentationIntent?.contains(.code) == true {
                    let range = run.range
                    styled[range].font = .system(size: fontSize - 1, design: .monospaced)
                    styled[range].backgroundColor = isUser
                        ? Color.white.opacity(0.15)
                        : Color(.textBackgroundColor).opacity(0.6)
                }
            }
            return styled
        }

        // Fallback: plain text
        var plain = AttributedString(text)
        plain.font = .system(size: fontSize)
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
