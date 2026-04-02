import Foundation

public enum ClipboardShortcutAction: String, Codable, Equatable {
    case copySelection
    case pasteClipboard
}

public enum KeyboardCommand: Equatable {
    case text(String)
    case returnKey
    case commandC
    case commandV
    case controlC
}

public enum TerminalKeyFallback {
    public static func fallbackText(for characters: String?) -> String? {
        guard let characters, !characters.isEmpty else {
            return nil
        }

        for scalar in characters.unicodeScalars {
            if (0xF700...0xF8FF).contains(scalar.value) {
                return nil
            }
        }

        return characters
    }
}

public enum TerminalKeyEquivalentDisposition: Equatable {
    case allowSystemHandling
    case deferToTextInput
    case sendRawToTerminal
}

public struct TerminalKeyEquivalentPolicy {
    public struct Modifiers: OptionSet, Equatable, Hashable, Sendable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let shift = Modifiers(rawValue: 1 << 0)
        public static let control = Modifiers(rawValue: 1 << 1)
        public static let option = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)
    }

    public static func disposition(
        modifiers: Modifiers,
        characters: String?,
        charactersIgnoringModifiers: String?
    ) -> TerminalKeyEquivalentDisposition {
        if modifiers == [.command],
           charactersIgnoringModifiers?.lowercased() == "q" {
            return .allowSystemHandling
        }

        if modifiers.contains(.option),
           !modifiers.contains(.command),
           !modifiers.contains(.control),
           TerminalKeyFallback.fallbackText(for: characters) != nil {
            return .deferToTextInput
        }

        return .sendRawToTerminal
    }
}

public struct KeyboardDispatch: Equatable {
    public let bytes: [UInt8]
    public let clipboardAction: ClipboardShortcutAction?

    public init(bytes: [UInt8], clipboardAction: ClipboardShortcutAction?) {
        self.bytes = bytes
        self.clipboardAction = clipboardAction
    }
}

public enum MouseTrackingMode: String, CaseIterable, Codable, Hashable {
    case x10 = "1000"
    case drag = "1002"
    case motion = "1003"
    case sgr = "1006"
}

public enum MouseButton: Int, Codable, Equatable {
    case left = 0
    case middle = 1
    case right = 2
}

public enum MouseEventKind: Equatable {
    case press(MouseButton)
    case release(MouseButton)
    case drag(MouseButton)
    case scrollUp
    case scrollDown
}

public struct MouseEvent: Equatable {
    public let kind: MouseEventKind
    public let column: Int
    public let row: Int

    public init(kind: MouseEventKind, column: Int, row: Int) {
        self.kind = kind
        self.column = max(column, 1)
        self.row = max(row, 1)
    }
}

public final class InputBridge {
    private let escape = "\u{001B}"

    public init() {}

    public func dispatch(_ command: KeyboardCommand, selection: String? = nil) -> KeyboardDispatch {
        switch command {
        case .text(let text):
            return KeyboardDispatch(bytes: Array(text.utf8), clipboardAction: nil)
        case .returnKey:
            return KeyboardDispatch(bytes: [0x0A], clipboardAction: nil)
        case .commandC:
            if let selection, !selection.isEmpty {
                return KeyboardDispatch(bytes: [], clipboardAction: .copySelection)
            }
            return KeyboardDispatch(bytes: [], clipboardAction: nil)
        case .commandV:
            return KeyboardDispatch(bytes: [], clipboardAction: .pasteClipboard)
        case .controlC:
            return KeyboardDispatch(bytes: [0x03], clipboardAction: nil)
        }
    }

    public func encodeMouse(_ event: MouseEvent, enabledModes: Set<MouseTrackingMode>) -> [UInt8] {
        guard enabledModes.contains(.sgr) else {
            return []
        }

        let code: Int
        let terminator: Character

        switch event.kind {
        case .press(let button):
            code = button.rawValue
            terminator = "M"
        case .release:
            code = 0
            terminator = "m"
        case .drag(let button):
            guard enabledModes.contains(.drag) || enabledModes.contains(.motion) else {
                return []
            }
            code = button.rawValue + 32
            terminator = "M"
        case .scrollUp:
            code = 64
            terminator = "M"
        case .scrollDown:
            code = 65
            terminator = "M"
        }

        let sequence = "\(escape)[<\(code);\(event.column);\(event.row)\(terminator)"
        return Array(sequence.utf8)
    }
}
