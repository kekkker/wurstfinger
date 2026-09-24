//
//  YAMLMapping.swift
//  Wurstfinger
//
//  A small YAML reader for key modifications: block and flow mappings,
//  plain and quoted scalars, comments, anchors, aliases and merge keys.
//  Sequences are not part of the key modification format.
//

import Foundation

/// A parsed YAML node.
indirect enum YAMLNode: Equatable {
    case scalar(String)
    /// Entries in document order.
    case mapping([(key: String, value: YAMLNode)])

    static func == (lhs: YAMLNode, rhs: YAMLNode) -> Bool {
        switch (lhs, rhs) {
        case let (.scalar(left), .scalar(right)):
            left == right
        case let (.mapping(left), .mapping(right)):
            left.count == right.count && zip(left, right).allSatisfy { $0.key == $1.key && $0.value == $1.value }
        default:
            false
        }
    }

    var entries: [(key: String, value: YAMLNode)]? {
        if case let .mapping(entries) = self {
            return entries
        }
        return nil
    }

    var scalar: String? {
        if case let .scalar(value) = self {
            return value
        }
        return nil
    }
}

struct YAMLError: Error, Equatable, CustomStringConvertible {
    let line: Int
    let message: String

    var description: String {
        String(localized: "Line \(line): \(message)")
    }
}

enum YAMLMapping {
    /// Parses a document whose root is a mapping. An empty document is an
    /// empty mapping.
    static func parse(_ text: String) throws -> YAMLNode {
        var parser = Parser(text: text)
        return try parser.parseDocument()
    }

    private struct Line {
        let number: Int
        let indent: Int
        let content: String
        let indentedWithTab: Bool
    }

    private struct Parser {
        private var lines: [Line] = []
        private var position = 0
        private var anchors: [String: YAMLNode] = [:]

        init(text: String) {
            for (index, raw) in text.components(separatedBy: .newlines).enumerated() {
                let content = Self.stripComment(raw)
                let trimmed = content.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, trimmed != "---", trimmed != "..." else { continue }
                let indent = content.prefix { $0 == " " || $0 == "\t" }
                lines.append(Line(
                    number: index + 1, indent: indent.count, content: trimmed,
                    indentedWithTab: indent.contains("\t")
                ))
            }
        }

        mutating func parseDocument() throws -> YAMLNode {
            guard let first = lines.first else { return .mapping([]) }
            if let tabbed = lines.first(where: \.indentedWithTab) {
                throw YAMLError(line: tabbed.number, message: String(localized: "Use spaces for indentation, not tabs."))
            }
            let root = try parseBlock(indent: first.indent)
            if position < lines.count {
                throw YAMLError(line: lines[position].number, message: String(localized: "Unexpected indentation."))
            }
            return root
        }

        /// Parses mapping entries at exactly `indent`.
        private mutating func parseBlock(indent: Int) throws -> YAMLNode {
            var entries: [(key: String, value: YAMLNode)] = []
            while position < lines.count {
                let line = lines[position]
                if line.indent < indent {
                    break
                }
                if line.indent > indent {
                    throw YAMLError(line: line.number, message: String(localized: "Unexpected indentation."))
                }
                if line.content.hasPrefix("- ") || line.content == "-" {
                    throw YAMLError(line: line.number, message: String(localized: "Lists are not supported here."))
                }
                position += 1

                var cursor = Cursor(text: line.content, line: line.number)
                let key = try cursor.readKey()
                var rest = cursor.remainder.trimmingCharacters(in: .whitespaces)

                var anchor: String?
                if rest.hasPrefix("&") {
                    let name = rest.dropFirst().prefix { !$0.isWhitespace }
                    anchor = String(name)
                    rest = rest.dropFirst(name.count + 1).trimmingCharacters(in: .whitespaces)
                }

                let value: YAMLNode
                if rest.isEmpty {
                    // Nested block, or an empty value.
                    if position < lines.count, lines[position].indent > indent {
                        value = try parseBlock(indent: lines[position].indent)
                    } else {
                        value = .scalar("")
                    }
                } else if rest.hasPrefix("{") {
                    // Flow mappings may continue on following, deeper lines.
                    var flow = rest
                    while !Self.isBalanced(flow), position < lines.count, lines[position].indent > indent {
                        flow += " " + lines[position].content
                        position += 1
                    }
                    var flowCursor = Cursor(text: flow, line: line.number)
                    value = try flowCursor.readFlowValue(anchors: anchors)
                    try flowCursor.expectEnd()
                } else {
                    var valueCursor = Cursor(text: rest, line: line.number)
                    value = try valueCursor.readFlowValue(anchors: anchors, inFlow: false)
                    try valueCursor.expectEnd()
                }

                if let anchor {
                    anchors[anchor] = value
                }
                if key == "<<" {
                    // Merge key: copy entries not set explicitly.
                    guard let merged = value.entries else {
                        throw YAMLError(line: line.number, message: String(localized: "Only mappings can be merged."))
                    }
                    for entry in merged where !entries.contains(where: { $0.key == entry.key }) {
                        entries.append(entry)
                    }
                } else {
                    Self.set(key, value, in: &entries)
                }
            }
            return .mapping(entries)
        }

        /// Sets `key`, keeping the position of an existing entry.
        private static func set(_ key: String, _ value: YAMLNode, in entries: inout [(key: String, value: YAMLNode)]) {
            if let index = entries.firstIndex(where: { $0.key == key }) {
                entries[index].value = value
            } else {
                entries.append((key, value))
            }
        }

        private static func stripComment(_ line: String) -> String {
            var quote: Character?
            var previous: Character = " "
            for (offset, character) in line.enumerated() {
                if let open = quote {
                    if character == open, previous != "\\" || open == "'" {
                        quote = nil
                    }
                } else if character == "\"" || character == "'" {
                    quote = character
                } else if character == "#", previous.isWhitespace {
                    return String(line.prefix(offset))
                }
                previous = character
            }
            return line
        }

        private static func isBalanced(_ text: String) -> Bool {
            var depth = 0
            var quote: Character?
            var previous: Character = " "
            for character in text {
                if let open = quote {
                    if character == open, previous != "\\" || open == "'" {
                        quote = nil
                    }
                } else if character == "\"" || character == "'" {
                    quote = character
                } else if character == "{" {
                    depth += 1
                } else if character == "}" {
                    depth -= 1
                }
                previous = character
            }
            return depth <= 0
        }
    }

    /// Character reader for one logical line.
    private struct Cursor {
        private let characters: [Character]
        private var index = 0
        let line: Int

        init(text: String, line: Int) {
            characters = Array(text)
            self.line = line
        }

        var remainder: String {
            String(characters[index...])
        }

        private var current: Character? {
            index < characters.count ? characters[index] : nil
        }

        private mutating func skipSpaces() {
            while let character = current, character == " " {
                index += 1
            }
        }

        private func error(_ message: String) -> YAMLError {
            YAMLError(line: line, message: message)
        }

        /// Reads `key:` and positions after the colon.
        mutating func readKey(terminators: Set<Character> = []) throws -> String {
            skipSpaces()
            let key: String
            if current == "\"" || current == "'" {
                key = try readQuoted()
            } else {
                var text = ""
                while let character = current {
                    if character == ":", index + 1 == characters.count || characters[index + 1] == " " {
                        break
                    }
                    if terminators.contains(character) {
                        break
                    }
                    text.append(character)
                    index += 1
                }
                key = text.trimmingCharacters(in: .whitespaces)
            }
            skipSpaces()
            guard current == ":", !key.isEmpty else {
                throw error(String(localized: "Expected \"key: value\"."))
            }
            index += 1
            return key
        }

        /// Reads a value: flow mapping, alias, quoted or plain scalar.
        mutating func readFlowValue(anchors: [String: YAMLNode], inFlow: Bool = true) throws -> YAMLNode {
            skipSpaces()
            let value: YAMLNode
            switch current {
            case "{":
                value = try readFlowMapping(anchors: anchors)
            case "*":
                index += 1
                var name = ""
                while let character = current, !character.isWhitespace, character != ",", character != "}" {
                    name.append(character)
                    index += 1
                }
                guard let resolved = anchors[name] else {
                    throw error(String(localized: "Unknown alias *\(name)."))
                }
                value = resolved
            case "\"", "'":
                value = try .scalar(readQuoted())
            case "[":
                throw error(String(localized: "Lists are not supported here."))
            default:
                var text = ""
                while let character = current {
                    if inFlow, character == "," || character == "}" {
                        break
                    }
                    text.append(character)
                    index += 1
                }
                value = .scalar(text.trimmingCharacters(in: .whitespaces))
            }
            return value
        }

        private mutating func readFlowMapping(anchors: [String: YAMLNode]) throws -> YAMLNode {
            index += 1 // {
            var entries: [(key: String, value: YAMLNode)] = []
            while true {
                skipSpaces()
                if current == "}" {
                    index += 1
                    return .mapping(entries)
                }
                guard current != nil else {
                    throw error(String(localized: "Missing \"}\"."))
                }
                let key = try readKey(terminators: [",", "}"])
                let value = try readFlowValue(anchors: anchors)
                if let index = entries.firstIndex(where: { $0.key == key }) {
                    entries[index].value = value
                } else {
                    entries.append((key, value))
                }
                skipSpaces()
                if current == "," {
                    index += 1
                } else if current != "}" {
                    throw error(String(localized: "Expected \",\" or \"}\"."))
                }
            }
        }

        private mutating func readQuoted() throws -> String {
            guard let quote = current else { return "" }
            index += 1
            var text = ""
            while let character = current {
                index += 1
                if character == quote {
                    if quote == "'", current == "'" {
                        text.append("'")
                        index += 1
                        continue
                    }
                    return text
                }
                if quote == "\"", character == "\\" {
                    text += try readEscape()
                } else {
                    text.append(character)
                }
            }
            throw error(String(localized: "Missing closing quote."))
        }

        private mutating func readEscape() throws -> String {
            guard let character = current else {
                throw error(String(localized: "Missing closing quote."))
            }
            index += 1
            switch character {
            case "n": return "\n"
            case "t": return "\t"
            case "\\": return "\\"
            case "\"": return "\""
            case "/": return "/"
            case "0": return "\0"
            case "u": return try readCodePoint(digits: 4)
            case "U": return try readCodePoint(digits: 8)
            default: return "\\" + String(character)
            }
        }

        private mutating func readCodePoint(digits: Int) throws -> String {
            guard index + digits <= characters.count,
                  let value = UInt32(String(characters[index ..< index + digits]), radix: 16),
                  let scalar = Unicode.Scalar(value)
            else { throw error(String(localized: "Invalid Unicode escape.")) }
            index += digits
            return String(Character(scalar))
        }

        mutating func expectEnd() throws {
            skipSpaces()
            if current != nil {
                throw error(String(localized: "Unexpected text after the value."))
            }
        }
    }
}
