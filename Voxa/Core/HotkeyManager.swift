import Cocoa
import Carbon

// MARK: - Hotkey Binding

/// A configurable hotkey combination (modifier flags + key code).
struct HotkeyBinding: Equatable {
    let keyCode: UInt16
    let modifiers: CGEventFlags

    /// Human-readable label like "Option+Space"
    var displayString: String {
        var parts: [String] = []
        if modifiers.contains(.maskControl) { parts.append("Ctrl") }
        if modifiers.contains(.maskAlternate) { parts.append("Option") }
        if modifiers.contains(.maskShift) { parts.append("Shift") }
        if modifiers.contains(.maskCommand) { parts.append("Cmd") }
        parts.append(Self.keyName(for: keyCode))
        return parts.joined(separator: "+")
    }

    /// Checks if the given event flags contain all required modifiers.
    func matchesModifiers(_ flags: CGEventFlags) -> Bool {
        let required: [(CGEventFlags, CGEventFlags)] = [
            (.maskControl, .maskControl),
            (.maskAlternate, .maskAlternate),
            (.maskShift, .maskShift),
            (.maskCommand, .maskCommand),
        ]
        for (flag, mask) in required {
            let needsFlag = modifiers.contains(flag)
            let hasFlag = flags.contains(mask)
            if needsFlag != hasFlag { return false }
        }
        return true
    }

    // MARK: - Persistence

    func save(key: String) {
        UserDefaults.standard.set(Int(keyCode), forKey: "\(key).keyCode")
        UserDefaults.standard.set(Int(modifiers.rawValue), forKey: "\(key).modifiers")
    }

    static func load(key: String, default defaultBinding: HotkeyBinding) -> HotkeyBinding {
        guard UserDefaults.standard.object(forKey: "\(key).keyCode") != nil else {
            return defaultBinding
        }
        let keyCode = UInt16(UserDefaults.standard.integer(forKey: "\(key).keyCode"))
        let modifiers = CGEventFlags(rawValue: UInt64(UserDefaults.standard.integer(forKey: "\(key).modifiers")))
        return HotkeyBinding(keyCode: keyCode, modifiers: modifiers)
    }

    // MARK: - Key Name Lookup

    static func keyName(for keyCode: UInt16) -> String {
        switch Int(keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_Tab: return "Tab"
        case kVK_Escape: return "Esc"
        case kVK_Delete: return "Delete"
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default: return "Key(\(keyCode))"
        }
    }
}

// MARK: - Default Bindings

extension HotkeyBinding {
    /// Option+Space — Push to Talk
    static let defaultPushToTalk = HotkeyBinding(
        keyCode: UInt16(kVK_Space),
        modifiers: .maskAlternate
    )
    /// Option+Shift+Space — Flow Mode
    static let defaultFlow = HotkeyBinding(
        keyCode: UInt16(kVK_Space),
        modifiers: [.maskAlternate, .maskShift]
    )
    /// Option+Cmd+Space — Command Mode
    static let defaultCommand = HotkeyBinding(
        keyCode: UInt16(kVK_Space),
        modifiers: [.maskAlternate, .maskCommand]
    )
    /// Ctrl+Space — Agent Mode
    static let defaultAgent = HotkeyBinding(
        keyCode: UInt16(kVK_Space),
        modifiers: .maskControl
    )
}

// MARK: - Hotkey Manager

final class HotkeyManager {
    /// Per-mode callbacks: (onDown, onUp)
    var onPushToTalkDown: (() -> Void)?
    var onPushToTalkUp: (() -> Void)?
    var onFlowDown: (() -> Void)?
    var onFlowUp: (() -> Void)?
    var onCommandDown: (() -> Void)?
    var onCommandUp: (() -> Void)?
    var onAgentDown: (() -> Void)?
    var onAgentUp: (() -> Void)?

    /// Configurable bindings per mode
    var pushToTalkBinding: HotkeyBinding
    var flowBinding: HotkeyBinding
    var commandBinding: HotkeyBinding
    var agentBinding: HotkeyBinding

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var currentFlags: CGEventFlags = []

    /// Which mode's hotkey is currently held down (to route keyUp correctly)
    private var activeMode: DictationModeType?

    init() {
        pushToTalkBinding = HotkeyBinding.load(key: "hotkey.pushToTalk", default: .defaultPushToTalk)
        flowBinding = HotkeyBinding.load(key: "hotkey.flow", default: .defaultFlow)
        commandBinding = HotkeyBinding.load(key: "hotkey.command", default: .defaultCommand)
        agentBinding = HotkeyBinding.load(key: "hotkey.agent", default: .defaultAgent)
    }

    func saveBindings() {
        pushToTalkBinding.save(key: "hotkey.pushToTalk")
        flowBinding.save(key: "hotkey.flow")
        commandBinding.save(key: "hotkey.command")
        agentBinding.save(key: "hotkey.agent")
    }

    /// Returns true if the event tap was successfully created.
    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else { return true }

        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: hotkeyEventCallback,
            userInfo: selfPtr
        ) else {
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        print("[HotkeyManager] Event tap started")
        return true
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        currentFlags = []
        activeMode = nil
        print("[HotkeyManager] Event tap stopped")
    }

    /// Called from the C callback — returns nil to swallow the event, or the event to pass through.
    fileprivate func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> CGEvent? {
        // Re-enable if the tap gets disabled by the system
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return event
        }

        // Track modifier state
        if type == .flagsChanged {
            currentFlags = event.flags
            return event
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        if type == .keyDown {
            // Ignore key repeats
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat)
            guard isRepeat == 0 else {
                // If it's a repeat of the active hotkey, swallow it
                return activeMode != nil ? nil : event
            }

            // Check each binding (most specific modifiers first to avoid ambiguity)
            // Agent mode: Ctrl+Space (unique modifier, check first)
            if agentBinding.keyCode == keyCode && agentBinding.matchesModifiers(currentFlags) {
                activeMode = .agent
                DispatchQueue.main.async { [weak self] in self?.onAgentDown?() }
                return nil
            }
            // Command mode: Option+Shift+Space
            if commandBinding.keyCode == keyCode && commandBinding.matchesModifiers(currentFlags) {
                activeMode = .command
                DispatchQueue.main.async { [weak self] in self?.onCommandDown?() }
                return nil
            }
            // Flow mode: Option+Cmd+Space
            if flowBinding.keyCode == keyCode && flowBinding.matchesModifiers(currentFlags) {
                activeMode = .flow
                DispatchQueue.main.async { [weak self] in self?.onFlowDown?() }
                return nil
            }
            // Push to talk: Option+Space (least specific, checked last)
            if pushToTalkBinding.keyCode == keyCode && pushToTalkBinding.matchesModifiers(currentFlags) {
                activeMode = .pushToTalk
                DispatchQueue.main.async { [weak self] in self?.onPushToTalkDown?() }
                return nil
            }

            return event
        }

        if type == .keyUp {
            // Route keyUp to whichever mode was activated on keyDown
            guard let mode = activeMode else { return event }

            // Only handle keyUp for the same key that was pressed
            let expectedKeyCode: UInt16
            switch mode {
            case .pushToTalk: expectedKeyCode = pushToTalkBinding.keyCode
            case .flow: expectedKeyCode = flowBinding.keyCode
            case .command: expectedKeyCode = commandBinding.keyCode
            case .agent: expectedKeyCode = agentBinding.keyCode
            }
            guard keyCode == expectedKeyCode else { return event }

            activeMode = nil
            switch mode {
            case .pushToTalk:
                DispatchQueue.main.async { [weak self] in self?.onPushToTalkUp?() }
            case .flow:
                DispatchQueue.main.async { [weak self] in self?.onFlowUp?() }
            case .command:
                DispatchQueue.main.async { [weak self] in self?.onCommandUp?() }
            case .agent:
                DispatchQueue.main.async { [weak self] in self?.onAgentUp?() }
            }
            return nil
        }

        return event
    }
}

// MARK: - C Callback

private func hotkeyEventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }

    let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
    if let result = manager.handleEvent(proxy: proxy, type: type, event: event) {
        return Unmanaged.passUnretained(result)
    }
    return nil
}
