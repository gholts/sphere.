import Foundation

enum EmojiTextNormalizer {
    static func normalized(_ value: String) -> String {
        guard value.contains("\\") || value.contains("&#") else { return value }

        var output = ""
        var index = value.startIndex
        while index < value.endIndex {
            if value[index] == "\\",
                let parsed = parseUnicodeEscape(in: value, at: index) {
                output.append(parsed.text)
                index = parsed.nextIndex
                continue
            }

            if value[index] == "&",
                let parsed = parseNumericEntity(in: value, at: index) {
                output.append(parsed.text)
                index = parsed.nextIndex
                continue
            }

            output.append(value[index])
            index = value.index(after: index)
        }
        return output
    }

    private static func parseUnicodeEscape(in value: String, at index: String.Index) -> ParsedText? {
        let next = value.index(after: index)
        guard next < value.endIndex else { return nil }

        switch value[next] {
        case "U":
            return parseFixedEscape(in: value, at: index, prefixLength: 2, hexLength: 8)
        case "u":
            if let braced = parseBracedEscape(in: value, at: index) {
                return braced
            }
            guard
                let first = parseHexValue(
                    in: value, afterPrefixAt: index, prefixLength: 2, hexLength: 4)
            else {
                return nil
            }
            if isHighSurrogate(first.value),
                let second = parseSurrogateTail(in: value, at: first.nextIndex),
                let scalar = UnicodeScalar(combine(high: first.value, low: second.value)) {
                return ParsedText(text: String(scalar), nextIndex: second.nextIndex)
            }
            guard !isSurrogate(first.value), let scalar = UnicodeScalar(first.value) else {
                return nil
            }
            return ParsedText(text: String(scalar), nextIndex: first.nextIndex)
        default:
            return nil
        }
    }

    private static func parseFixedEscape(
        in value: String,
        at index: String.Index,
        prefixLength: Int,
        hexLength: Int
    ) -> ParsedText? {
        guard
            let parsed = parseHexValue(
                in: value,
                afterPrefixAt: index,
                prefixLength: prefixLength,
                hexLength: hexLength
            ),
            !isSurrogate(parsed.value),
            let scalar = UnicodeScalar(parsed.value)
        else {
            return nil
        }
        return ParsedText(text: String(scalar), nextIndex: parsed.nextIndex)
    }

    private static func parseBracedEscape(in value: String, at index: String.Index) -> ParsedText? {
        guard var cursor = value.index(index, offsetBy: 2, limitedBy: value.endIndex) else {
            return nil
        }
        guard cursor < value.endIndex, value[cursor] == "{" else { return nil }
        cursor = value.index(after: cursor)

        var digits = ""
        while cursor < value.endIndex, value[cursor] != "}" {
            guard digits.count < 6, isHexDigit(value[cursor]) else { return nil }
            digits.append(value[cursor])
            cursor = value.index(after: cursor)
        }
        guard !digits.isEmpty, cursor < value.endIndex, value[cursor] == "}",
            let scalarValue = UInt32(digits, radix: 16),
            !isSurrogate(scalarValue),
            let scalar = UnicodeScalar(scalarValue)
        else {
            return nil
        }
        return ParsedText(text: String(scalar), nextIndex: value.index(after: cursor))
    }

    private static func parseSurrogateTail(in value: String, at index: String.Index) -> HexParse? {
        guard index < value.endIndex,
            value[index] == "\\",
            let parsed = parseHexValue(
                in: value, afterPrefixAt: index, prefixLength: 2, hexLength: 4),
            isLowSurrogate(parsed.value)
        else {
            return nil
        }
        return parsed
    }

    private static func parseHexValue(
        in value: String,
        afterPrefixAt index: String.Index,
        prefixLength: Int,
        hexLength: Int
    ) -> HexParse? {
        var cursor = index
        for _ in 0..<prefixLength {
            cursor = value.index(after: cursor)
            guard cursor <= value.endIndex else { return nil }
        }
        guard cursor <= value.endIndex else { return nil }

        var digits = ""
        for _ in 0..<hexLength {
            guard cursor < value.endIndex, isHexDigit(value[cursor]) else { return nil }
            digits.append(value[cursor])
            cursor = value.index(after: cursor)
        }
        guard let parsed = UInt32(digits, radix: 16) else { return nil }
        return HexParse(value: parsed, nextIndex: cursor)
    }

    private static func parseNumericEntity(in value: String, at index: String.Index) -> ParsedText? {
        guard value.distance(from: index, to: value.endIndex) >= 4 else { return nil }
        var cursor = value.index(after: index)
        guard cursor < value.endIndex, value[cursor] == "#" else { return nil }
        cursor = value.index(after: cursor)

        var radix = 10
        if cursor < value.endIndex, value[cursor] == "x" || value[cursor] == "X" {
            radix = 16
            cursor = value.index(after: cursor)
        }

        var digits = ""
        while cursor < value.endIndex, value[cursor] != ";" {
            let character = value[cursor]
            guard digits.count < 10, radix == 16 ? isHexDigit(character) : character.isNumber else {
                return nil
            }
            digits.append(character)
            cursor = value.index(after: cursor)
        }
        guard !digits.isEmpty,
            cursor < value.endIndex,
            value[cursor] == ";",
            let scalarValue = UInt32(digits, radix: radix),
            !isSurrogate(scalarValue),
            let scalar = UnicodeScalar(scalarValue)
        else {
            return nil
        }
        return ParsedText(text: String(scalar), nextIndex: value.index(after: cursor))
    }

    private static func combine(high: UInt32, low: UInt32) -> UInt32 {
        0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00)
    }

    private static func isHighSurrogate(_ value: UInt32) -> Bool {
        (0xD800...0xDBFF).contains(value)
    }

    private static func isLowSurrogate(_ value: UInt32) -> Bool {
        (0xDC00...0xDFFF).contains(value)
    }

    private static func isSurrogate(_ value: UInt32) -> Bool {
        (0xD800...0xDFFF).contains(value)
    }

    private static func isHexDigit(_ character: Character) -> Bool {
        character.isHexDigit
    }
}

private struct ParsedText {
    var text: String
    var nextIndex: String.Index
}

private struct HexParse {
    var value: UInt32
    var nextIndex: String.Index
}

extension String {
    var emojiNormalizedForDisplay: String {
        EmojiTextNormalizer.normalized(self)
    }

    var backendNameForDisplay: String {
        BackendNameDisplay.text(self)
    }
}

extension ProxyItem {
    var displayName: String {
        name.backendNameForDisplay
    }
}

enum BackendNameDisplay {
    static func text(_ value: String) -> String {
        simulatorSafeFlagText(value.emojiNormalizedForDisplay)
    }

    private static func simulatorSafeFlagText(_ value: String) -> String {
        #if targetEnvironment(simulator)
            var output = String.UnicodeScalarView()
            let scalars = Array(value.unicodeScalars)
            var index = 0
            while index < scalars.count {
                let current = scalars[index]
                if current.isRegionalIndicator,
                    index + 1 < scalars.count,
                    scalars[index + 1].isRegionalIndicator {
                    output.append(
                        contentsOf:
                            "[\(current.regionalIndicatorLetter)\(scalars[index + 1].regionalIndicatorLetter)]"
                            .unicodeScalars)
                    index += 2
                } else {
                    output.append(current)
                    index += 1
                }
            }
            return String(output)
        #else
            return value
        #endif
    }
}

fileprivate extension Unicode.Scalar {
    var isRegionalIndicator: Bool {
        (0x1F1E6...0x1F1FF).contains(value)
    }
    var regionalIndicatorLetter: Character {
        UnicodeScalar(value - 0x1F1E6 + 65).map(Character.init) ?? "?"
    }
}
