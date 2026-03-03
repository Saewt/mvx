import Foundation

public struct TerminalHyperlink: Equatable {
    public let range: Range<Int>
    public let url: URL
    public let text: String

    public init(range: Range<Int>, url: URL, text: String) {
        self.range = range
        self.url = url
        self.text = text
    }
}

public struct ParsedTerminalText: Equatable {
    public let visibleText: String
    public let attributedText: AttributedString
    public let links: [TerminalHyperlink]

    public init(visibleText: String, attributedText: AttributedString, links: [TerminalHyperlink]) {
        self.visibleText = visibleText
        self.attributedText = attributedText
        self.links = links
    }
}

public enum TerminalLinkParser {
    public static func parse(_ text: String) -> ParsedTerminalText {
        var visibleText = ""
        var attributedText = AttributedString()
        var links: [TerminalHyperlink] = []
        var currentURL: URL?
        var index = text.startIndex

        func appendVisible(_ segment: String) {
            guard !segment.isEmpty else {
                return
            }

            let startOffset = visibleText.count
            visibleText.append(segment)

            var chunk = AttributedString(segment)
            if let currentURL {
                chunk.link = currentURL
                links.append(
                    TerminalHyperlink(
                        range: startOffset..<(startOffset + segment.count),
                        url: currentURL,
                        text: segment
                    )
                )
            }

            attributedText.append(chunk)
        }

        while index < text.endIndex {
            let character = text[index]

            if character == "\r" {
                index = text.index(after: index)
                continue
            }

            if character == "\u{001B}" {
                let nextIndex = text.index(after: index)
                guard nextIndex < text.endIndex else {
                    break
                }

                let marker = text[nextIndex]
                if marker == "]" {
                    let sequence = parseOSCSequence(in: text, from: index)
                    guard let sequence else {
                        break
                    }

                    if sequence.payload.hasPrefix("8;") {
                        currentURL = resolvedURL(fromOsc8Payload: sequence.payload)
                    }

                    index = sequence.endIndex
                    continue
                }

                if marker == "[" {
                    index = skipCSISequence(in: text, from: nextIndex)
                    continue
                }

                index = text.index(after: nextIndex)
                continue
            }

            if let scalar = character.unicodeScalars.first?.value, scalar < 0x20, character != "\n", character != "\t" {
                index = text.index(after: index)
                continue
            }

            appendVisible(String(character))
            index = text.index(after: index)
        }

        return ParsedTerminalText(
            visibleText: visibleText,
            attributedText: attributedText,
            links: coalesced(links: links)
        )
    }

    public static func visibleText(from text: String) -> String {
        parse(text).visibleText
    }

    private static func resolvedURL(fromOsc8Payload payload: String) -> URL? {
        let remainder = String(payload.dropFirst(2))
        let parts = remainder.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else {
            return nil
        }

        let rawURL = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawURL.isEmpty else {
            return nil
        }

        guard let url = URL(string: rawURL), let scheme = url.scheme?.lowercased() else {
            return nil
        }

        switch scheme {
        case "http", "https":
            return url
        default:
            return nil
        }
    }

    private static func parseOSCSequence(
        in text: String,
        from escapeIndex: String.Index
    ) -> (payload: String, endIndex: String.Index)? {
        let payloadStart = text.index(escapeIndex, offsetBy: 2)
        var cursor = payloadStart

        while cursor < text.endIndex {
            if text[cursor] == "\u{0007}" {
                let payload = String(text[payloadStart..<cursor])
                return (payload, text.index(after: cursor))
            }

            if text[cursor] == "\u{001B}" {
                let terminator = text.index(after: cursor)
                if terminator < text.endIndex, text[terminator] == "\\" {
                    let payload = String(text[payloadStart..<cursor])
                    return (payload, text.index(after: terminator))
                }
            }

            cursor = text.index(after: cursor)
        }

        return nil
    }

    private static func skipCSISequence(in text: String, from markerIndex: String.Index) -> String.Index {
        var cursor = text.index(after: markerIndex)

        while cursor < text.endIndex {
            let scalar = text[cursor].unicodeScalars.first?.value ?? 0
            if scalar >= 0x40 && scalar <= 0x7E {
                return text.index(after: cursor)
            }
            cursor = text.index(after: cursor)
        }

        return text.endIndex
    }

    private static func coalesced(links: [TerminalHyperlink]) -> [TerminalHyperlink] {
        guard var current = links.first else {
            return []
        }

        var merged: [TerminalHyperlink] = []

        for link in links.dropFirst() {
            if current.url == link.url, current.range.upperBound == link.range.lowerBound {
                current = TerminalHyperlink(
                    range: current.range.lowerBound..<link.range.upperBound,
                    url: current.url,
                    text: current.text + link.text
                )
            } else {
                merged.append(current)
                current = link
            }
        }

        merged.append(current)
        return merged
    }
}
