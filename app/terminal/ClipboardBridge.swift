import Foundation

public struct ClipboardPolicy: Codable, Equatable {
    public var allowOSC52Read: Bool
    public var allowOSC52Write: Bool

    public init(allowOSC52Read: Bool = true, allowOSC52Write: Bool = true) {
        self.allowOSC52Read = allowOSC52Read
        self.allowOSC52Write = allowOSC52Write
    }
}

public struct OSC52Response: Codable, Equatable {
    public let handled: Bool
    public let action: String
    public let replySequence: String?

    public init(handled: Bool, action: String, replySequence: String?) {
        self.handled = handled
        self.action = action
        self.replySequence = replySequence
    }
}

public final class ClipboardBridge {
    private let escape = "\u{001B}"

    public let policy: ClipboardPolicy
    private(set) public var contents: String

    public init(policy: ClipboardPolicy = ClipboardPolicy(), contents: String = "") {
        self.policy = policy
        self.contents = contents
    }

    public func copy(_ selection: String) {
        contents = selection
    }

    public func paste() -> String {
        contents
    }

    public func handleOSC52(_ sequence: String) -> OSC52Response {
        let trimmed = normalize(sequence)
        guard trimmed.hasPrefix("52;") else {
            return OSC52Response(handled: false, action: "ignored", replySequence: nil)
        }

        let segments = trimmed.split(separator: ";", maxSplits: 2, omittingEmptySubsequences: false)
        guard segments.count == 3 else {
            return OSC52Response(handled: false, action: "malformed", replySequence: nil)
        }

        let payload = String(segments[2])
        if payload == "?" {
            guard policy.allowOSC52Read else {
                return OSC52Response(handled: true, action: "query-denied", replySequence: nil)
            }

            let encoded = Data(contents.utf8).base64EncodedString()
            return OSC52Response(
                handled: true,
                action: "query",
                replySequence: "\(escape)]52;c;\(encoded)\u{0007}"
            )
        }

        if payload.isEmpty {
            guard policy.allowOSC52Write else {
                return OSC52Response(handled: true, action: "write-denied", replySequence: nil)
            }

            contents = ""
            return OSC52Response(handled: true, action: "cleared", replySequence: nil)
        }

        guard policy.allowOSC52Write else {
            return OSC52Response(handled: true, action: "write-denied", replySequence: nil)
        }

        guard let decoded = Data(base64Encoded: payload).flatMap({ String(data: $0, encoding: .utf8) }) else {
            return OSC52Response(handled: false, action: "invalid-base64", replySequence: nil)
        }

        contents = decoded
        return OSC52Response(handled: true, action: "set", replySequence: nil)
    }

    private func normalize(_ sequence: String) -> String {
        var value = sequence
        if value.hasPrefix("\(escape)]") {
            value.removeFirst(2)
        }
        if value.hasSuffix("\u{0007}") {
            value.removeLast()
        } else if value.hasSuffix("\(escape)\\") {
            value.removeLast(2)
        }
        return value
    }
}
