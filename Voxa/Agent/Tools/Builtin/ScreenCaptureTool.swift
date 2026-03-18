import AppKit
import CoreGraphics
import Foundation
import Vision

struct ScreenCaptureTool: AgentTool {
    let name = "screen_capture"
    let description = "Capture the screen or focused window and optionally extract text via OCR."
    let parameters: [ToolParameter] = [
        ToolParameter(
            name: "action",
            type: "string",
            description: "What to do with the capture.",
            enumValues: ["capture_and_ocr", "capture"]
        ),
        ToolParameter(
            name: "region",
            type: "string",
            description: "What region to capture (default: focused_window).",
            required: false,
            enumValues: ["full_screen", "focused_window"]
        ),
    ]

    func execute(arguments: [String: Any]) async throws -> ToolResult {
        guard let action = arguments["action"] as? String else {
            throw ToolError.invalidArguments("Missing required parameter 'action'")
        }

        let region = arguments["region"] as? String ?? "focused_window"

        guard let image = captureScreen(region: region) else {
            return .error("Failed to capture screen. Screen recording permission may be required.")
        }

        switch action {
        case "capture_and_ocr":
            let text = try await performOCR(on: image)
            if text.isEmpty {
                return .success("(No text found in the captured image)")
            }
            return .success(text)

        case "capture":
            let path = try saveTempImage(image)
            return .success("Screenshot saved to: \(path)")

        default:
            throw ToolError.invalidArguments("Unknown action: \(action)")
        }
    }

    private func captureScreen(region: String) -> CGImage? {
        if region == "focused_window" {
            // Try to capture focused window
            if let windowID = getFocusedWindowID() {
                let imageRef = CGWindowListCreateImage(
                    .null,
                    .optionIncludingWindow,
                    windowID,
                    [.boundsIgnoreFraming, .bestResolution]
                )
                if let imageRef = imageRef { return imageRef }
            }
        }

        // Fallback: full screen
        return CGWindowListCreateImage(
            CGRect.infinite,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution]
        )
    }

    private func getFocusedWindowID() -> CGWindowID? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = frontApp.processIdentifier

        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        for window in windowList {
            if let ownerPID = window[kCGWindowOwnerPID as String] as? Int32,
               ownerPID == pid,
               let windowID = window[kCGWindowNumber as String] as? CGWindowID,
               let layer = window[kCGWindowLayer as String] as? Int,
               layer == 0 {
                return windowID
            }
        }

        return nil
    }

    private func performOCR(on image: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: ToolError.executionFailed("OCR failed: \(error.localizedDescription)"))
                    return
                }

                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let text = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }.joined(separator: "\n")

                continuation.resume(returning: text)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: ToolError.executionFailed("OCR handler failed: \(error.localizedDescription)"))
            }
        }
    }

    private func saveTempImage(_ image: CGImage) throws -> String {
        let tempDir = FileManager.default.temporaryDirectory
        let filename = "voxa_capture_\(Int(Date().timeIntervalSince1970)).png"
        let url = tempDir.appendingPathComponent(filename)

        let rep = NSBitmapImageRep(cgImage: image)
        guard let pngData = rep.representation(using: .png, properties: [:]) else {
            throw ToolError.executionFailed("Failed to create PNG data")
        }

        try pngData.write(to: url)
        return url.path
    }
}
