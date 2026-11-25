import Foundation

enum NoteBlock: Int, CaseIterable {
    case body, heading, subheading, bullet, numbered, quote

    var prefix: String {
        switch self {
        case .body: ""
        case .heading: "# "
        case .subheading: "## "
        case .bullet: "- "
        case .numbered: "1. "
        case .quote: "> "
        }
    }

    var label: String {
        switch self {
        case .body: "正文"
        case .heading: "一级标题"
        case .subheading: "二级标题"
        case .bullet: "项目列表"
        case .numbered: "编号列表"
        case .quote: "引用"
        }
    }

    var symbol: String {
        switch self {
        case .body: "text.alignleft"
        case .heading: "textformat.size.larger"
        case .subheading: "textformat.size.smaller"
        case .bullet: "list.bullet"
        case .numbered: "list.number"
        case .quote: "quote.opening"
        }
    }

    var repeatsOnReturn: Bool { self == .bullet || self == .numbered }
}

struct NoteStyle: OptionSet {
    let rawValue: Int
    static let bold = Self(rawValue: 1)
    static let italic = Self(rawValue: 2)
    static let underline = Self(rawValue: 4)

    static let marks: [(style: Self, open: String, close: String)] = [
        (.bold, "**", "**"), (.italic, "_", "_"), (.underline, "<u>", "</u>")
    ]
}

extension NSAttributedString.Key {
    static let noteBlock = Self("app.liubai.note.block")
    static let noteStyle = Self("app.liubai.note.style")
    static let noteNumber = Self("app.liubai.note.number")
}

extension NSAttributedString {
    func noteBlock(at index: Int) -> NoteBlock {
        guard index < length, index >= 0, let raw = attribute(.noteBlock, at: index, effectiveRange: nil) as? Int
        else { return .body }
        return NoteBlock(rawValue: raw) ?? .body
    }

    func noteStyle(at index: Int) -> NoteStyle {
        guard index < length, index >= 0, let raw = attribute(.noteStyle, at: index, effectiveRange: nil) as? Int
        else { return [] }
        return NoteStyle(rawValue: raw)
    }
}

enum NoteMarkup {
    // Escaping these bound characters keeps user text literal in Markdown and in the editor.
    private static let escaped: Set<Character> = Set("\\*_<>#[]`~!|+.-&")

    static func encode(_ text: NSAttributedString) -> String {
        guard !text.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        let string = text.string as NSString
        var lines: [(block: NoteBlock, value: String)] = []
        var numbered = 0
        enumerateParagraphs(in: string) { paragraph, content in
            let block = text.noteBlock(at: paragraph.location)
            numbered = block == .numbered ? numbered + 1 : 0
            var value = block == .numbered ? "\(numbered). " : block.prefix
            var open: [(style: NoteStyle, open: String, close: String)] = []
            text.enumerateAttribute(.noteStyle, in: content) { raw, range, _ in
                let style = NoteStyle(rawValue: raw as? Int ?? 0)
                let next = NoteStyle.marks.filter { style.contains($0.style) }
                let shared = zip(open, next).prefix(while: { $0.style == $1.style }).count
                value += open.dropFirst(shared).reversed().map(\.close).joined()
                value += next.dropFirst(shared).map(\.open).joined()
                open = next
                for character in string.substring(with: range) {
                    if escaped.contains(character) { value.append("\\") }
                    value.append(character)
                }
            }
            value += open.reversed().map(\.close).joined()
            lines.append((block, value))
        }
        if text.string.hasSuffix("\n") { lines.append((.body, "")) }
        return lines.enumerated().map { index, line in
            let next = lines.indices.contains(index + 1) ? lines[index + 1] : nil
            if line.block == .body, !line.value.isEmpty, next?.block == .body, next?.value.isEmpty == false {
                return line.value + "  "
            }
            return line.value
        }.joined(separator: "\n")
    }

    static func decode(_ markdown: String) -> NSAttributedString {
        let value = NSMutableAttributedString()
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            let (block, rawContent) = parseBlock(line)
            let isHardBreak = block == .body && index + 1 < lines.count && line.hasSuffix("  ")
                && !lines[index + 1].isEmpty && parseBlock(lines[index + 1]).0 == .body
            let content = isHardBreak ? String(rawContent.dropLast(2)) : rawContent
            appendInline(content, block: block, to: value)
            if index < lines.count - 1 {
                value.append(NSAttributedString(string: "\n", attributes: [.noteBlock: block.rawValue]))
            }
        }
        return value
    }

    static func enumerateParagraphs(in text: NSString, _ visit: (NSRange, NSRange) -> Void) {
        var offset = 0
        while offset < text.length {
            var start = 0
            var end = 0
            var contentsEnd = 0
            text.getParagraphStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: offset, length: 0))
            visit(NSRange(location: start, length: end - start),
                  NSRange(location: start, length: contentsEnd - start))
            offset = end
        }
    }

    private static func parseBlock(_ line: String) -> (NoteBlock, String) {
        for block in [NoteBlock.heading, .subheading, .bullet, .quote] where line.hasPrefix(block.prefix) {
            return (block, String(line.dropFirst(block.prefix.count)))
        }
        let digits = line.prefix { $0.isASCII && $0.isNumber }
        if !digits.isEmpty, line.dropFirst(digits.count).hasPrefix(". ") {
            return (.numbered, String(line.dropFirst(digits.count + 2)))
        }
        return (.body, line)
    }

    private static func appendInline(_ content: String, block: NoteBlock, to result: NSMutableAttributedString) {
        var cursor = content.startIndex
        var style: NoteStyle = []
        var buffer = ""

        func flush() {
            if !buffer.isEmpty {
                result.append(NSAttributedString(string: buffer, attributes: [
                    .noteBlock: block.rawValue, .noteStyle: style.rawValue
                ]))
                buffer = ""
            }
        }

        while cursor < content.endIndex {
            let rest = content[cursor...]
            if rest.hasPrefix("\\"), content.index(after: cursor) != content.endIndex {
                cursor = content.index(after: cursor)
                buffer.append(content[cursor])
                cursor = content.index(after: cursor)
                continue
            }
            if let mark = NoteStyle.marks.first(where: {
                rest.hasPrefix(style.contains($0.style) ? $0.close : $0.open)
            }) {
                flush()
                let token = style.contains(mark.style) ? mark.close : mark.open
                style.formSymmetricDifference(mark.style)
                cursor = content.index(cursor, offsetBy: token.count)
            } else {
                buffer.append(content[cursor])
                cursor = content.index(after: cursor)
            }
        }
        flush()
    }
}
