import Foundation

public enum SessionAgentStatus: String, Codable, CaseIterable {
    case none
    case running
    case waiting
    case done
    case error

    public var showsBadge: Bool {
        self != .none
    }

    public var needsAttention: Bool {
        self == .waiting || self == .error
    }

    public var badgeLabel: String? {
        guard showsBadge else {
            return nil
        }

        switch self {
        case .none:
            return nil
        case .running:
            return "Running"
        case .waiting:
            return "Waiting for Input"
        case .done:
            return "Done"
        case .error:
            return "Error"
        }
    }

    public var badgeColorName: String? {
        guard showsBadge else {
            return nil
        }

        switch self {
        case .none:
            return nil
        case .running:
            return "green"
        case .waiting:
            return "orange"
        case .done:
            return "blue"
        case .error:
            return "red"
        }
    }
}

extension SessionAgentStatus: Equatable, Hashable {}

public struct SessionAgentStatusUpdate: Equatable {
    public static let oscCode = "7777"

    public let status: SessionAgentStatus

    public init(status: SessionAgentStatus) {
        self.status = status
    }

    public var payload: String {
        "\(Self.oscCode);state=\(status.rawValue)"
    }

    public var sequence: String {
        "\u{001B}]\(payload)\u{0007}"
    }

    public static func parse(_ rawSequence: String) -> SessionAgentStatusUpdate? {
        let trimmed = rawSequence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        var sequence = trimmed
        if sequence.hasPrefix("\u{001B}]") {
            sequence.removeFirst(2)
        }

        if sequence.hasSuffix("\u{0007}") {
            sequence.removeLast()
        } else if sequence.hasSuffix("\u{001B}\\") {
            sequence.removeLast(2)
        }

        let segments = sequence.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
        guard let code = segments.first, code == oscCode else {
            return nil
        }

        var parsedFields: [String: String] = [:]

        for field in segments.dropFirst() {
            let parts = field.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else {
                return nil
            }

            let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty else {
                return nil
            }

            parsedFields[key] = value
        }

        guard
            let stateValue = parsedFields["state"],
            let status = SessionAgentStatus(rawValue: stateValue)
        else {
            return nil
        }

        return SessionAgentStatusUpdate(status: status)
    }
}
