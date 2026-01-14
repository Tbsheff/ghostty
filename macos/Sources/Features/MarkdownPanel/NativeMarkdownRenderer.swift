import SwiftUI
import AppKit
import GhosttyKit

// MARK: - Search Environment Key

struct SearchQueryKey: EnvironmentKey {
    static let defaultValue: String = ""
}

extension EnvironmentValues {
    var searchQuery: String {
        get { self[SearchQueryKey.self] }
        set { self[SearchQueryKey.self] = newValue }
    }
}

// MARK: - Markdown Parser

/// A native Swift markdown parser that converts markdown text into structured blocks.
/// No external dependencies - pure Swift implementation.
struct MarkdownParser {

    // MARK: - Cached Regex Patterns (compiled once, reused)
    private static let boldItalicRegex = try! NSRegularExpression(pattern: #"\*\*\*(.+?)\*\*\*"#)
    private static let boldRegex = try! NSRegularExpression(pattern: #"\*\*(.+?)\*\*"#)
    private static let italicRegex = try! NSRegularExpression(pattern: #"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#)
    private static let codeRegex = try! NSRegularExpression(pattern: #"`([^`]+)`"#)
    private static let linkRegex = try! NSRegularExpression(pattern: #"\[([^\]]+)\]\(([^)]+)\)"#)
    private static let strikethroughRegex = try! NSRegularExpression(pattern: #"~~(.+?)~~"#)
    private static let orderedListRegex = try! NSRegularExpression(pattern: #"^\d+\.\s"#)
    private static let taskListRegex = try! NSRegularExpression(pattern: #"^[-*+]\s+\[([ xX])\]\s"#)
    private static let imageRegex = try! NSRegularExpression(pattern: #"^!\[([^\]]*)\]\(([^)]+)\)$"#)
    // HTML img tag: <img src="url" alt="text" ...>
    private static let htmlImgRegex = try! NSRegularExpression(pattern: #"<img\s+[^>]*src\s*=\s*[\"']([^\"']+)[\"'][^>]*>"#, options: .caseInsensitive)
    private static let htmlImgAltRegex = try! NSRegularExpression(pattern: #"alt\s*=\s*[\"']([^\"']*)[\"']"#, options: .caseInsensitive)
    // Generic HTML tag stripper
    private static let htmlTagRegex = try! NSRegularExpression(pattern: #"<[^>]+>"#)
    // HTML comment stripper
    private static let htmlCommentRegex = try! NSRegularExpression(pattern: #"<!--.*?-->"#, options: .dotMatchesLineSeparators)

    /// Parse markdown text into an array of blocks
    static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = text.components(separatedBy: "\n")
        var i = 0
        var hrIndex = 0  // Track horizontal rule index for stable IDs
        var tableIndex = 0  // Track table index for stable IDs
        var imageIndex = 0  // Track image index for stable IDs
        var currentCodeBlock: (language: String?, lines: [String])? = nil

        while i < lines.count {
            let line = lines[i]

            // Handle code blocks
            if line.hasPrefix("```") {
                if let codeBlock = currentCodeBlock {
                    // End code block - check if it's mermaid
                    let code = codeBlock.lines.joined(separator: "\n")
                    if codeBlock.language?.lowercased() == "mermaid" {
                        blocks.append(.mermaid(code: code))
                    } else {
                        blocks.append(.codeBlock(language: codeBlock.language, code: code))
                    }
                    currentCodeBlock = nil
                } else {
                    // Start code block
                    let language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    currentCodeBlock = (language.isEmpty ? nil : language, [])
                }
                i += 1
                continue
            }

            if currentCodeBlock != nil {
                currentCodeBlock?.lines.append(line)
                i += 1
                continue
            }

            // Skip empty lines
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                i += 1
                continue
            }

            // Skip HTML-only lines (tags like <h1>, </p>, <br>, <!-- comments -->)
            if isHtmlOnlyLine(line) {
                i += 1
                continue
            }

            // Check for HTML img tag (can be anywhere in the line)
            if containsHtmlImg(line), let imageMatch = parseImageLine(line) {
                blocks.append(.image(alt: imageMatch.alt, url: imageMatch.url, index: imageIndex))
                imageIndex += 1
                i += 1
                continue
            }

            // Headers
            if line.hasPrefix("######") {
                blocks.append(.heading(level: 6, text: parseInline(String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces))))
            } else if line.hasPrefix("#####") {
                blocks.append(.heading(level: 5, text: parseInline(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))))
            } else if line.hasPrefix("####") {
                blocks.append(.heading(level: 4, text: parseInline(String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces))))
            } else if line.hasPrefix("###") {
                blocks.append(.heading(level: 3, text: parseInline(String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces))))
            } else if line.hasPrefix("##") {
                blocks.append(.heading(level: 2, text: parseInline(String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces))))
            } else if line.hasPrefix("#") {
                blocks.append(.heading(level: 1, text: parseInline(String(line.dropFirst(1)).trimmingCharacters(in: .whitespaces))))
            }
            // Blockquote
            else if line.hasPrefix(">") {
                var quoteLines: [String] = []
                while i < lines.count && lines[i].hasPrefix(">") {
                    quoteLines.append(String(lines[i].dropFirst(1)).trimmingCharacters(in: .whitespaces))
                    i += 1
                }
                blocks.append(.blockquote(text: parseInline(quoteLines.joined(separator: "\n"))))
                continue
            }
            // Horizontal rule
            else if line.trimmingCharacters(in: .whitespaces).starts(with: "---") ||
                    line.trimmingCharacters(in: .whitespaces).starts(with: "***") ||
                    line.trimmingCharacters(in: .whitespaces).starts(with: "___") {
                blocks.append(.horizontalRule(index: hrIndex))
                hrIndex += 1
            }
            // Table (check before lists since tables start with |)
            else if isTableRow(line) {
                if let result = parseTable(lines: lines, startIndex: i) {
                    blocks.append(.table(
                        headers: result.headers,
                        alignments: result.alignments,
                        rows: result.rows,
                        index: tableIndex
                    ))
                    tableIndex += 1
                    i = result.endIndex
                    continue
                } else {
                    // Not a valid table, treat as paragraph
                    blocks.append(.paragraph(content: parseInline(line)))
                }
            }
            // Image (standalone line: ![alt](url))
            else if let imageMatch = parseImageLine(line) {
                blocks.append(.image(alt: imageMatch.alt, url: imageMatch.url, index: imageIndex))
                imageIndex += 1
            }
            // Task list (must check before unordered list)
            else if isTaskListItem(line.trimmingCharacters(in: .whitespaces)) {
                var items: [(checked: Bool, content: InlineContent)] = []
                while i < lines.count {
                    let listLine = lines[i].trimmingCharacters(in: .whitespaces)
                    if let taskItem = parseTaskListItem(listLine) {
                        items.append(taskItem)
                        i += 1
                    } else {
                        break
                    }
                }
                blocks.append(.taskList(items: items))
                continue
            }
            // Unordered list
            else if line.trimmingCharacters(in: .whitespaces).hasPrefix("- ") ||
                    line.trimmingCharacters(in: .whitespaces).hasPrefix("* ") ||
                    line.trimmingCharacters(in: .whitespaces).hasPrefix("+ ") {
                var items: [InlineContent] = []
                while i < lines.count {
                    let listLine = lines[i].trimmingCharacters(in: .whitespaces)
                    if listLine.hasPrefix("- ") || listLine.hasPrefix("* ") || listLine.hasPrefix("+ ") {
                        items.append(parseInline(String(listLine.dropFirst(2))))
                        i += 1
                    } else {
                        break
                    }
                }
                blocks.append(.unorderedList(items: items))
                continue
            }
            // Ordered list or Paragraph (check ordered list first with properly matched string/range)
            else {
                let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                let trimmedRange = NSRange(trimmedLine.startIndex..., in: trimmedLine)
                if orderedListRegex.firstMatch(in: trimmedLine, range: trimmedRange) != nil {
                    // Ordered list
                    var items: [InlineContent] = []
                    while i < lines.count {
                        let listLine = lines[i].trimmingCharacters(in: .whitespaces)
                        let nsRange = NSRange(listLine.startIndex..., in: listLine)
                        if let match = orderedListRegex.firstMatch(in: listLine, range: nsRange) {
                            guard let matchRange = Range(match.range, in: listLine) else {
                                break
                            }
                            items.append(parseInline(String(listLine[matchRange.upperBound...])))
                            i += 1
                        } else {
                            break
                        }
                    }
                    blocks.append(.orderedList(items: items))
                    continue
                } else {
                    // Paragraph - strip HTML tags from content
                    var paragraphLines: [String] = []
                    // Add first line, stripping HTML
                    let strippedFirst = stripHtmlTags(line)
                    if !strippedFirst.isEmpty {
                        paragraphLines.append(strippedFirst)
                    }
                    i += 1
                    while i < lines.count {
                        let nextLine = lines[i]
                        if nextLine.trimmingCharacters(in: .whitespaces).isEmpty ||
                           nextLine.hasPrefix("#") ||
                           nextLine.hasPrefix(">") ||
                           nextLine.hasPrefix("```") ||
                           nextLine.hasPrefix("- ") ||
                           nextLine.hasPrefix("* ") ||
                           isTableRow(nextLine) ||
                           containsHtmlImg(nextLine) {
                            break
                        }
                        // Strip HTML from continuation lines too
                        let strippedNext = stripHtmlTags(nextLine)
                        if !strippedNext.isEmpty && !isHtmlOnlyLine(nextLine) {
                            paragraphLines.append(strippedNext)
                        }
                        i += 1
                    }
                    // Only create paragraph if there's actual content
                    let paragraphText = paragraphLines.joined(separator: " ").trimmingCharacters(in: .whitespaces)
                    if !paragraphText.isEmpty {
                        blocks.append(.paragraph(content: parseInline(paragraphText)))
                    }
                    continue
                }
            }

            i += 1
        }

        // Close any unclosed code block
        if let codeBlock = currentCodeBlock {
            blocks.append(.codeBlock(language: codeBlock.language, code: codeBlock.lines.joined(separator: "\n")))
        }

        return blocks
    }

    /// Detect if content looks like a full HTML document rather than markdown.
    static func looksLikeHTMLDocument(_ text: String) -> Bool {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                continue
            }
            let lower = trimmed.lowercased()
            if lower.hasPrefix("```") {
                return false
            }
            if lower.hasPrefix("<!doctype html") ||
                lower.hasPrefix("<html") ||
                lower.hasPrefix("<head") ||
                lower.hasPrefix("<body") {
                return true
            }
            if lower.hasPrefix("<meta") && (lower.contains("charset") || lower.contains("content-security-policy")) {
                return true
            }
            return false
        }
        return false
    }

    /// Parse inline markdown elements (bold, italic, code, links)
    /// Uses cached NSRegularExpression patterns for efficiency
    static func parseInline(_ text: String) -> InlineContent {
        var segments: [InlineSegment] = []
        var currentIndex = text.startIndex

        while currentIndex < text.endIndex {
            let remainingString = String(text[currentIndex...])
            let nsRange = NSRange(location: 0, length: remainingString.utf16.count)

            // Find earliest match among all patterns
            var earliestMatch: (type: InlineMatchType, range: Range<String.Index>, nsMatch: NSTextCheckingResult)?

            let patterns: [(NSRegularExpression, InlineMatchType)] = [
                (boldItalicRegex, .boldItalic),
                (boldRegex, .bold),
                (italicRegex, .italic),
                (codeRegex, .code),
                (linkRegex, .link),
                (strikethroughRegex, .strikethrough)
            ]

            for (regex, type) in patterns {
                if let nsMatch = regex.firstMatch(in: remainingString, range: nsRange),
                   let swiftRange = Range(nsMatch.range, in: remainingString) {
                    if earliestMatch == nil || swiftRange.lowerBound < earliestMatch!.range.lowerBound {
                        earliestMatch = (type, swiftRange, nsMatch)
                    }
                }
            }

            if let match = earliestMatch {
                // Add text before match
                let distance = text.distance(from: remainingString.startIndex, to: match.range.lowerBound)
                let beforeEnd = text.index(currentIndex, offsetBy: distance)
                if currentIndex < beforeEnd {
                    segments.append(.text(String(text[currentIndex..<beforeEnd])))
                }

                // Extract matched content
                let matchedText = String(remainingString[match.range])
                switch match.type {
                case .boldItalic:
                    segments.append(.boldItalic(String(matchedText.dropFirst(3).dropLast(3))))
                case .bold:
                    segments.append(.bold(String(matchedText.dropFirst(2).dropLast(2))))
                case .italic:
                    segments.append(.italic(String(matchedText.dropFirst(1).dropLast(1))))
                case .code:
                    segments.append(.code(String(matchedText.dropFirst(1).dropLast(1))))
                case .link:
                    // Extract link text and URL from capture groups
                    if match.nsMatch.numberOfRanges >= 3,
                       let textRange = Range(match.nsMatch.range(at: 1), in: remainingString),
                       let urlRange = Range(match.nsMatch.range(at: 2), in: remainingString) {
                        segments.append(.link(text: String(remainingString[textRange]), url: String(remainingString[urlRange])))
                    }
                case .strikethrough:
                    segments.append(.strikethrough(String(matchedText.dropFirst(2).dropLast(2))))
                }

                // Move past the match
                currentIndex = text.index(currentIndex, offsetBy: text.distance(from: remainingString.startIndex, to: match.range.upperBound))
            } else {
                // No match - take remaining text
                segments.append(.text(remainingString))
                break
            }
        }

        // Merge adjacent text segments in a single pass
        guard !segments.isEmpty else { return InlineContent(segments: []) }
        var merged: [InlineSegment] = []
        merged.reserveCapacity(segments.count)

        for segment in segments {
            if case .text(let newText) = segment,
               let lastIndex = merged.indices.last,
               case .text(let prevText) = merged[lastIndex] {
                merged[lastIndex] = .text(prevText + newText)
            } else {
                merged.append(segment)
            }
        }

        return InlineContent(segments: merged)
    }

    private enum InlineMatchType {
        case boldItalic, bold, italic, code, link, strikethrough
    }

    /// Check if a line is a task list item (e.g., "- [ ] task" or "- [x] task")
    private static func isTaskListItem(_ line: String) -> Bool {
        let nsRange = NSRange(line.startIndex..., in: line)
        return taskListRegex.firstMatch(in: line, range: nsRange) != nil
    }

    /// Parse a standalone image line: ![alt](url) or <img src="url" alt="text">
    private static func parseImageLine(_ line: String) -> (alt: String, url: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let nsRange = NSRange(trimmed.startIndex..., in: trimmed)

        // Try markdown image syntax first: ![alt](url)
        if let match = imageRegex.firstMatch(in: trimmed, range: nsRange),
           match.numberOfRanges >= 3,
           let altRange = Range(match.range(at: 1), in: trimmed),
           let urlRange = Range(match.range(at: 2), in: trimmed) {
            return (String(trimmed[altRange]), String(trimmed[urlRange]))
        }

        // Try HTML img tag: <img src="url" alt="text" ...>
        if let imgMatch = htmlImgRegex.firstMatch(in: trimmed, range: nsRange),
           imgMatch.numberOfRanges >= 2,
           let srcRange = Range(imgMatch.range(at: 1), in: trimmed) {
            let src = String(trimmed[srcRange])
            // Extract alt text if present
            var alt = ""
            if let altMatch = htmlImgAltRegex.firstMatch(in: trimmed, range: nsRange),
               altMatch.numberOfRanges >= 2,
               let altRange = Range(altMatch.range(at: 1), in: trimmed) {
                alt = String(trimmed[altRange])
            }
            return (alt, src)
        }

        return nil
    }

    /// Strip HTML tags from text, keeping only the text content
    private static func stripHtmlTags(_ text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        // First remove HTML comments
        var result = htmlCommentRegex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        // Then remove HTML tags
        let resultRange = NSRange(result.startIndex..., in: result)
        result = htmlTagRegex.stringByReplacingMatches(in: result, range: resultRange, withTemplate: "")
        // Clean up multiple spaces and trim
        return result.replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// Check if a line contains an HTML img tag
    private static func containsHtmlImg(_ line: String) -> Bool {
        let range = NSRange(line.startIndex..., in: line)
        return htmlImgRegex.firstMatch(in: line, range: range) != nil
    }

    /// Check if a line is primarily HTML (starts with < and ends with >)
    private static func isHtmlOnlyLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        // Skip HTML comments
        if trimmed.hasPrefix("<!--") { return true }
        // Skip standalone HTML tags like <h1>, </p>, <br>, etc.
        if trimmed.hasPrefix("<") && trimmed.hasSuffix(">") && !containsHtmlImg(trimmed) {
            let stripped = stripHtmlTags(trimmed)
            return stripped.isEmpty
        }
        return false
    }

    /// Parse a task list item and return (checked, content) or nil if not a task item
    private static func parseTaskListItem(_ line: String) -> (checked: Bool, content: InlineContent)? {
        let nsRange = NSRange(line.startIndex..., in: line)
        guard let match = taskListRegex.firstMatch(in: line, range: nsRange),
              let matchRange = Range(match.range, in: line),
              match.numberOfRanges >= 2,
              let checkboxRange = Range(match.range(at: 1), in: line) else {
            return nil
        }

        let checkboxChar = String(line[checkboxRange])
        let isChecked = checkboxChar.lowercased() == "x"
        let contentText = String(line[matchRange.upperBound...])
        return (isChecked, parseInline(contentText))
    }

    // MARK: - Table Parsing

    /// Check if a line looks like a table row (starts with |)
    private static func isTableRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("|")
    }

    /// Check if a line is a table separator row (contains only |, -, :, and whitespace)
    private static func isTableSeparator(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("|") else { return false }
        let separatorChars = CharacterSet(charactersIn: "|:- ")
        return trimmed.unicodeScalars.allSatisfy { separatorChars.contains($0) } &&
               trimmed.contains("-")
    }

    /// Parse table cells from a row
    private static func parseTableCells(_ line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Remove leading and trailing pipes
        var content = trimmed
        if content.hasPrefix("|") { content = String(content.dropFirst()) }
        if content.hasSuffix("|") { content = String(content.dropLast()) }

        // Split by pipe and trim each cell
        return content.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Parse alignment from separator row
    private static func parseAlignments(_ separatorLine: String) -> [TableAlignment] {
        let cells = parseTableCells(separatorLine)
        return cells.map { cell in
            let trimmed = cell.trimmingCharacters(in: .whitespaces)
            let startsWithColon = trimmed.hasPrefix(":")
            let endsWithColon = trimmed.hasSuffix(":")

            if startsWithColon && endsWithColon {
                return .center
            } else if endsWithColon {
                return .right
            } else {
                return .left
            }
        }
    }

    /// Parse a complete table starting at index i
    static func parseTable(lines: [String], startIndex: Int) -> (headers: [InlineContent], alignments: [TableAlignment], rows: [[InlineContent]], endIndex: Int)? {
        var i = startIndex

        // Need at least 2 lines (header + separator)
        guard i + 1 < lines.count else { return nil }

        // First line should be header row
        guard isTableRow(lines[i]) else { return nil }
        let headerLine = lines[i]

        // Second line should be separator
        guard isTableSeparator(lines[i + 1]) else { return nil }
        let separatorLine = lines[i + 1]

        // Parse header cells and alignments
        let headerCells = parseTableCells(headerLine)
        var alignments = parseAlignments(separatorLine)

        // Ensure alignments array matches header count
        while alignments.count < headerCells.count {
            alignments.append(.left)
        }
        if alignments.count > headerCells.count {
            alignments = Array(alignments.prefix(headerCells.count))
        }

        // Parse headers with inline formatting
        let headers = headerCells.map { parseInline($0) }

        // Move past header and separator
        i += 2

        // Parse data rows
        var rows: [[InlineContent]] = []
        while i < lines.count && isTableRow(lines[i]) && !isTableSeparator(lines[i]) {
            let cells = parseTableCells(lines[i])
            // Ensure row has same number of cells as headers (pad or truncate)
            var rowCells = cells.map { parseInline($0) }
            while rowCells.count < headers.count {
                rowCells.append(InlineContent(segments: []))
            }
            if rowCells.count > headers.count {
                rowCells = Array(rowCells.prefix(headers.count))
            }
            rows.append(rowCells)
            i += 1
        }

        return (headers, alignments, rows, i)
    }
}

// MARK: - Markdown Data Structures

/// Column alignment for table cells
enum TableAlignment: Equatable {
    case left
    case center
    case right
}

enum MarkdownBlock: Identifiable, Equatable {
    case heading(level: Int, text: InlineContent)
    case paragraph(content: InlineContent)
    case codeBlock(language: String?, code: String)
    case mermaid(code: String)
    case blockquote(text: InlineContent)
    case unorderedList(items: [InlineContent])
    case orderedList(items: [InlineContent])
    case taskList(items: [(checked: Bool, content: InlineContent)])
    case horizontalRule(index: Int)  // Index prevents ID collisions
    case table(headers: [InlineContent], alignments: [TableAlignment], rows: [[InlineContent]], index: Int)
    case image(alt: String, url: String, index: Int)

    var id: String {
        switch self {
        case .heading(let level, let text):
            return "h\(level)-\(text.plainText.prefix(20).hashValue)"
        case .paragraph(let content):
            return "p-\(content.plainText.prefix(30).hashValue)"
        case .codeBlock(let lang, let code):
            return "code-\(lang ?? "")-\(code.prefix(30).hashValue)"
        case .mermaid(let code):
            return "mermaid-\(code.prefix(30).hashValue)"
        case .blockquote(let text):
            return "quote-\(text.plainText.prefix(20).hashValue)"
        case .unorderedList(let items):
            return "ul-\(items.count)-\(items.first?.plainText.prefix(10).hashValue ?? 0)"
        case .orderedList(let items):
            return "ol-\(items.count)-\(items.first?.plainText.prefix(10).hashValue ?? 0)"
        case .taskList(let items):
            return "task-\(items.count)-\(items.first?.content.plainText.prefix(10).hashValue ?? 0)"
        case .horizontalRule(let index):
            return "hr-\(index)"
        case .table(let headers, _, let rows, let index):
            return "table-\(index)-\(headers.count)-\(rows.count)"
        case .image(_, _, let index):
            return "img-\(index)"
        }
    }

    // Equatable conformance for taskList
    static func == (lhs: MarkdownBlock, rhs: MarkdownBlock) -> Bool {
        switch (lhs, rhs) {
        case (.heading(let l1, let t1), .heading(let l2, let t2)):
            return l1 == l2 && t1 == t2
        case (.paragraph(let c1), .paragraph(let c2)):
            return c1 == c2
        case (.codeBlock(let l1, let c1), .codeBlock(let l2, let c2)):
            return l1 == l2 && c1 == c2
        case (.mermaid(let c1), .mermaid(let c2)):
            return c1 == c2
        case (.blockquote(let t1), .blockquote(let t2)):
            return t1 == t2
        case (.unorderedList(let i1), .unorderedList(let i2)):
            return i1 == i2
        case (.orderedList(let i1), .orderedList(let i2)):
            return i1 == i2
        case (.taskList(let i1), .taskList(let i2)):
            guard i1.count == i2.count else { return false }
            for (a, b) in zip(i1, i2) {
                if a.checked != b.checked || a.content != b.content { return false }
            }
            return true
        case (.horizontalRule(let i1), .horizontalRule(let i2)):
            return i1 == i2
        case (.table(let h1, let a1, let r1, let idx1), .table(let h2, let a2, let r2, let idx2)):
            return h1 == h2 && a1 == a2 && r1 == r2 && idx1 == idx2
        case (.image(let a1, let u1, let i1), .image(let a2, let u2, let i2)):
            return a1 == a2 && u1 == u2 && i1 == i2
        default:
            return false
        }
    }
}

struct InlineContent: Equatable {
    let segments: [InlineSegment]

    var plainText: String {
        segments.map { segment in
            switch segment {
            case .text(let t): return t
            case .bold(let t): return t
            case .italic(let t): return t
            case .boldItalic(let t): return t
            case .code(let t): return t
            case .link(let text, _): return text
            case .strikethrough(let t): return t
            }
        }.joined()
    }
}

enum InlineSegment: Equatable {
    case text(String)
    case bold(String)
    case italic(String)
    case boldItalic(String)
    case code(String)
    case link(text: String, url: String)
    case strikethrough(String)
}

// MARK: - SwiftUI Renderer

/// Native SwiftUI markdown renderer with full theme support
struct NativeMarkdownView: View {
    let blocks: [MarkdownBlock]
    @Binding var scrollTarget: Int?
    var onExecuteCode: ((String) -> Void)?
    var onClose: (() -> Void)? = nil
    var basePath: String? = nil  // Directory containing the markdown file for relative paths
    var config: Ghostty.Config? = nil  // Ghostty config for theme customization

    @Environment(\.colorScheme) private var colorScheme

    private var theme: MarkdownTheme {
        MarkdownTheme(colorScheme: colorScheme, config: config)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                        MarkdownBlockView(block: block, theme: theme, basePath: basePath, onExecuteCode: onExecuteCode)
                            .id(index)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .frame(maxWidth: 800, alignment: .leading)
            }
            .background(theme.background)
            .onChange(of: scrollTarget) { targetIndex in
                if let index = targetIndex {
                    withAnimation(.easeOut(duration: 0.35)) {
                        proxy.scrollTo(index, anchor: .top)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        scrollTarget = nil
                    }
                }
            }
        }
    }
}

// MARK: - Block Views

struct MarkdownBlockView: View {
    let block: MarkdownBlock
    let theme: MarkdownTheme
    var basePath: String? = nil
    var onExecuteCode: ((String) -> Void)?

    var body: some View {
        switch block {
        case .heading(let level, let text):
            HeadingView(level: level, content: text, theme: theme)
        case .paragraph(let content):
            ParagraphView(content: content, theme: theme)
        case .codeBlock(let language, let code):
            CodeBlockView(language: language, code: code, theme: theme, onExecute: onExecuteCode)
        case .mermaid(let code):
            MermaidBlockView(code: code, theme: theme)
        case .blockquote(let text):
            BlockquoteView(content: text, theme: theme)
        case .unorderedList(let items):
            UnorderedListView(items: items, theme: theme)
        case .orderedList(let items):
            OrderedListView(items: items, theme: theme)
        case .taskList(let items):
            TaskListView(items: items, theme: theme)
        case .horizontalRule:
            HorizontalRuleView(theme: theme)
        case .table(let headers, let alignments, let rows, _):
            TableView(headers: headers, alignments: alignments, rows: rows, theme: theme)
        case .image(let alt, let url, _):
            ImageBlockView(alt: alt, url: url, basePath: basePath, theme: theme)
        }
    }
}

struct HeadingView: View {
    let level: Int
    let content: InlineContent
    let theme: MarkdownTheme

    private var fontSize: CGFloat {
        switch level {
        case 1: return 28
        case 2: return 22
        case 3: return 18
        case 4: return 16
        case 5: return 14
        default: return 13
        }
    }

    private var fontWeight: Font.Weight {
        level <= 2 ? .bold : .semibold
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            InlineContentView(content: content, theme: theme)
                .font(.system(size: fontSize, weight: fontWeight, design: .default))
                .foregroundColor(theme.textPrimary)
                .tracking(-0.3)

            if level <= 2 {
                Rectangle()
                    .fill(theme.border.opacity(0.5))
                    .frame(height: 1)
                    .padding(.top, 8)
            }
        }
        .padding(.top, level == 1 ? 0 : 24)
        .padding(.bottom, 12)
    }
}

struct ParagraphView: View {
    let content: InlineContent
    let theme: MarkdownTheme

    var body: some View {
        InlineContentView(content: content, theme: theme)
            .font(.system(size: theme.fontSize))
            .foregroundColor(theme.textPrimary)
            .lineSpacing(theme.fontSize * (theme.lineHeight - 1))
            .padding(.bottom, 16)
    }
}

struct CodeBlockView: View {
    let language: String?
    let code: String
    let theme: MarkdownTheme
    var onExecute: ((String) -> Void)?

    @State private var isHovered = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Language label + action buttons
            if language != nil || isHovered {
                HStack {
                    if let lang = language {
                        Text(lang.uppercased())
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(theme.textMuted)
                    }
                    Spacer()

                    // Run button
                    if onExecute != nil {
                        Button(action: { onExecute?(code) }) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(theme.success)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .opacity(isHovered ? 1 : 0)
                        .help("Run in terminal")
                    }

                    Button(action: copyCode) {
                        HStack(spacing: 4) {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 10, weight: .medium))
                            if copied {
                                Text("Copied!")
                                    .font(.system(size: 10, weight: .medium))
                            }
                        }
                        .foregroundColor(copied ? theme.success : theme.textMuted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(theme.surfaceElevated.opacity(isHovered ? 1 : 0))
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .opacity(isHovered || copied ? 1 : 0)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }

            // Code content with syntax highlighting
            ScrollView(.horizontal, showsIndicators: false) {
                Text(SyntaxHighlighter.highlight(code, language: language, theme: theme))
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        .background(theme.codeBackground)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(theme.border, lineWidth: 1)
        )
        .padding(.vertical, 12)
        .onHover { isHovered = $0 }
    }

    private func copyCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        copied = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copied = false
        }
    }
}

struct BlockquoteView: View {
    let content: InlineContent
    let theme: MarkdownTheme

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(theme.accent)
                .frame(width: 3)

            InlineContentView(content: content, theme: theme)
                .font(.system(size: 15))
                .italic()
                .foregroundColor(theme.textSecondary)
                .padding(.leading, 16)
                .padding(.vertical, 8)
        }
        .background(
            LinearGradient(
                colors: [theme.accent.opacity(0.1), Color.clear],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .cornerRadius(0)
        .padding(.vertical, 12)
    }
}

struct UnorderedListView: View {
    let items: [InlineContent]
    let theme: MarkdownTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 12) {
                    Circle()
                        .fill(theme.accent)
                        .frame(width: 6, height: 6)
                        .padding(.top, theme.fontSize * 0.47)

                    InlineContentView(content: item, theme: theme)
                        .font(.system(size: theme.fontSize))
                        .foregroundColor(theme.textPrimary)
                }
            }
        }
        .padding(.vertical, 12)
    }
}

struct OrderedListView: View {
    let items: [InlineContent]
    let theme: MarkdownTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(index + 1).")
                        .font(.system(size: theme.fontSize, weight: .medium))
                        .foregroundColor(theme.textMuted)
                        .frame(width: 24, alignment: .trailing)

                    InlineContentView(content: item, theme: theme)
                        .font(.system(size: theme.fontSize))
                        .foregroundColor(theme.textPrimary)
                }
            }
        }
        .padding(.vertical, 12)
    }
}

struct TaskListView: View {
    let items: [(checked: Bool, content: InlineContent)]
    let theme: MarkdownTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: item.checked ? "checkmark.square.fill" : "square")
                        .font(.system(size: theme.fontSize - 1))
                        .foregroundColor(item.checked ? theme.success : theme.textMuted)
                        .padding(.top, 2)

                    InlineContentView(content: item.content, theme: theme)
                        .font(.system(size: theme.fontSize))
                        .foregroundColor(item.checked ? theme.textSecondary : theme.textPrimary)
                        .strikethrough(item.checked, color: theme.textMuted)
                }
            }
        }
        .padding(.vertical, 12)
    }
}

struct HorizontalRuleView: View {
    let theme: MarkdownTheme

    var body: some View {
        Rectangle()
            .fill(theme.border)
            .frame(height: 1)
            .padding(.vertical, 24)
    }
}

// MARK: - Image View

struct ImageBlockView: View {
    let alt: String
    let url: String
    var basePath: String? = nil  // Directory containing the markdown file
    let theme: MarkdownTheme

    /// Check if URL is a local file path (relative or absolute)
    private var isLocalFile: Bool {
        !url.hasPrefix("http://") && !url.hasPrefix("https://") && !url.hasPrefix("data:")
    }

    /// Resolve local file path (relative paths resolved against basePath)
    /// Returns nil for absolute paths outside basePath (path traversal protection)
    private var localImage: NSImage? {
        var resolvedPath: String

        if url.hasPrefix("/") {
            resolvedPath = url
        } else if url.hasPrefix("file://") {
            resolvedPath = String(url.dropFirst(7))
        } else if let base = basePath {
            // Relative path - resolve against markdown file's directory
            resolvedPath = (base as NSString).appendingPathComponent(url)
        } else {
            // No basePath and not absolute - cannot safely resolve
            return nil
        }

        // Canonicalize path to resolve .. and symlinks
        resolvedPath = (resolvedPath as NSString).standardizingPath

        // Path traversal protection: relative paths must stay within basePath
        if let base = basePath {
            let canonicalBase = (base as NSString).standardizingPath
            guard resolvedPath.hasPrefix(canonicalBase) || resolvedPath.hasPrefix("/") && url.hasPrefix("/") else {
                // Attempted path traversal (e.g., ../../../etc/passwd)
                return nil
            }
        }

        return NSImage(contentsOfFile: resolvedPath)
    }

    var body: some View {
        Group {
            if isLocalFile {
                // Local file: use NSImage directly
                if let nsImage = localImage {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .cornerRadius(8)
                } else {
                    errorView
                }
            } else {
                // Remote URL: use AsyncImage
                AsyncImage(url: URL(string: url)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .cornerRadius(8)
                    case .failure:
                        errorView
                    case .empty:
                        loadingView
                    @unknown default:
                        EmptyView()
                    }
                }
            }
        }
        .frame(maxWidth: 600, alignment: .leading)
        .padding(.vertical, 12)
    }

    private var errorView: some View {
        HStack(spacing: 8) {
            Image(systemName: "photo")
                .font(.system(size: 16))
            Text(alt.isEmpty ? "Image failed to load" : alt)
                .font(.system(size: 14))
        }
        .foregroundColor(theme.textMuted)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.codeBackground)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(theme.border, lineWidth: 1)
        )
    }

    private var loadingView: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            if !alt.isEmpty {
                Text(alt)
                    .font(.system(size: 14))
                    .foregroundColor(theme.textMuted)
            }
        }
        .frame(height: 100)
        .frame(maxWidth: .infinity, alignment: .center)
        .background(theme.codeBackground)
        .cornerRadius(8)
    }
}

// MARK: - Table View

struct TableView: View {
    let headers: [InlineContent]
    let alignments: [TableAlignment]
    let rows: [[InlineContent]]
    let theme: MarkdownTheme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Header row
                HStack(spacing: 0) {
                    ForEach(Array(headers.enumerated()), id: \.offset) { index, header in
                        TableCellView(
                            content: header,
                            alignment: index < alignments.count ? alignments[index] : .left,
                            isHeader: true,
                            theme: theme
                        )
                        .frame(minWidth: 100)
                    }
                }
                .background(theme.surfaceElevated)

                // Header separator
                Rectangle()
                    .fill(theme.border)
                    .frame(height: 2)

                // Data rows
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            ForEach(Array(row.enumerated()), id: \.offset) { colIndex, cell in
                                TableCellView(
                                    content: cell,
                                    alignment: colIndex < alignments.count ? alignments[colIndex] : .left,
                                    isHeader: false,
                                    theme: theme
                                )
                                .frame(minWidth: 100)
                            }
                        }
                        .background(rowIndex % 2 == 0 ? Color.clear : theme.codeBackground.opacity(0.5))

                        // Row separator (except for last row)
                        if rowIndex < rows.count - 1 {
                            Rectangle()
                                .fill(theme.border.opacity(0.5))
                                .frame(height: 1)
                        }
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(theme.border, lineWidth: 1)
            )
            .cornerRadius(8)
        }
        .padding(.vertical, 12)
    }
}

struct TableCellView: View {
    let content: InlineContent
    let alignment: TableAlignment
    let isHeader: Bool
    let theme: MarkdownTheme

    private var horizontalAlignment: HorizontalAlignment {
        switch alignment {
        case .left: return .leading
        case .center: return .center
        case .right: return .trailing
        }
    }

    private var textAlignment: TextAlignment {
        switch alignment {
        case .left: return .leading
        case .center: return .center
        case .right: return .trailing
        }
    }

    var body: some View {
        VStack(alignment: horizontalAlignment) {
            InlineContentView(content: content, theme: theme)
                .font(.system(size: 14, weight: isHeader ? .semibold : .regular))
                .foregroundColor(isHeader ? theme.textPrimary : theme.textSecondary)
                .multilineTextAlignment(textAlignment)
        }
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: horizontalAlignment, vertical: .center))
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

// MARK: - Inline Content View

struct InlineContentView: View {
    let content: InlineContent
    let theme: MarkdownTheme

    @Environment(\.searchQuery) private var searchQuery

    var body: some View {
        content.segments.reduce(Text("")) { result, segment in
            result + textForSegment(segment)
        }
    }

    private func textForSegment(_ segment: InlineSegment) -> Text {
        switch segment {
        case .text(let text):
            return highlightedText(text)
        case .bold(let text):
            return highlightedText(text, modifier: { $0.bold() })
        case .italic(let text):
            return highlightedText(text, modifier: { $0.italic() })
        case .boldItalic(let text):
            return highlightedText(text, modifier: { $0.bold().italic() })
        case .code(let text):
            return highlightedText(text, modifier: {
                $0.font(.system(size: theme.codeFontSize, design: .monospaced))
                    .foregroundColor(theme.accent)
            })
        case .link(let text, let url):
            if let linkURL = URL(string: url) {
                return highlightedAttributedLink(text: text, url: linkURL)
            }
            return highlightedText(text, modifier: {
                $0.foregroundColor(theme.accent).underline()
            })
        case .strikethrough(let text):
            return highlightedText(text, modifier: { $0.strikethrough() })
        }
    }

    /// Creates Text with search highlighting applied
    private func highlightedText(_ text: String, modifier: ((Text) -> Text)? = nil) -> Text {
        guard !searchQuery.isEmpty else {
            let baseText = Text(text)
            return modifier?(baseText) ?? baseText
        }

        // Find all match ranges using case-insensitive search on original text
        // This ensures indices are valid for the original string
        var matches: [Range<String.Index>] = []
        var searchStart = text.startIndex
        while let range = text.range(of: searchQuery, options: .caseInsensitive, range: searchStart..<text.endIndex) {
            matches.append(range)
            searchStart = range.upperBound
        }

        guard !matches.isEmpty else {
            let baseText = Text(text)
            return modifier?(baseText) ?? baseText
        }

        // Build text with highlights
        var result = Text("")
        var currentIndex = text.startIndex

        for matchRange in matches {
            // Add text before match
            if currentIndex < matchRange.lowerBound {
                let beforeText = String(text[currentIndex..<matchRange.lowerBound])
                let beforeTextView = Text(beforeText)
                result = result + (modifier?(beforeTextView) ?? beforeTextView)
            }

            // Add highlighted match (convert to original case from the text)
            let matchText = String(text[matchRange])
            var attrStr = AttributedString(matchText)
            attrStr.backgroundColor = theme.searchHighlight
            let highlightedTextView = Text(attrStr)
            result = result + (modifier?(highlightedTextView) ?? highlightedTextView)

            currentIndex = matchRange.upperBound
        }

        // Add remaining text after last match
        if currentIndex < text.endIndex {
            let afterText = String(text[currentIndex...])
            let afterTextView = Text(afterText)
            result = result + (modifier?(afterTextView) ?? afterTextView)
        }

        return result
    }

    /// Creates highlighted attributed link text
    private func highlightedAttributedLink(text: String, url: URL) -> Text {
        guard !searchQuery.isEmpty else {
            var attrStr = AttributedString(text)
            attrStr.link = url
            attrStr.foregroundColor = NSColor(theme.accent)
            attrStr.underlineStyle = .single
            return Text(attrStr)
        }

        // Find all match ranges using case-insensitive search on original text
        // This ensures indices are valid for the original string
        var matches: [Range<String.Index>] = []
        var searchStart = text.startIndex
        while let range = text.range(of: searchQuery, options: .caseInsensitive, range: searchStart..<text.endIndex) {
            matches.append(range)
            searchStart = range.upperBound
        }

        guard !matches.isEmpty else {
            var attrStr = AttributedString(text)
            attrStr.link = url
            attrStr.foregroundColor = NSColor(theme.accent)
            attrStr.underlineStyle = .single
            return Text(attrStr)
        }

        // Build attributed string with highlights
        var result = AttributedString("")
        var currentIndex = text.startIndex

        for matchRange in matches {
            // Add text before match
            if currentIndex < matchRange.lowerBound {
                var beforeStr = AttributedString(String(text[currentIndex..<matchRange.lowerBound]))
                beforeStr.link = url
                beforeStr.foregroundColor = NSColor(theme.accent)
                beforeStr.underlineStyle = .single
                result += beforeStr
            }

            // Add highlighted match
            let matchText = String(text[matchRange])
            var highlightedStr = AttributedString(matchText)
            highlightedStr.link = url
            highlightedStr.foregroundColor = NSColor(theme.accent)
            highlightedStr.underlineStyle = .single
            highlightedStr.backgroundColor = NSColor(theme.searchHighlight)
            result += highlightedStr

            currentIndex = matchRange.upperBound
        }

        // Add remaining text after last match
        if currentIndex < text.endIndex {
            var afterStr = AttributedString(String(text[currentIndex...]))
            afterStr.link = url
            afterStr.foregroundColor = NSColor(theme.accent)
            afterStr.underlineStyle = .single
            result += afterStr
        }

        return Text(result)
    }
}

// MARK: - Theme

struct MarkdownTheme {
    let colorScheme: ColorScheme
    let config: Ghostty.Config?

    init(colorScheme: ColorScheme, config: Ghostty.Config? = nil) {
        self.colorScheme = colorScheme
        self.config = config
    }

    /// Whether to use terminal colors (when markdown-theme = "terminal")
    private var useTerminalColors: Bool {
        config?.markdownTheme == "terminal"
    }

    // MARK: - Font Sizes (configurable via Ghostty config)
    var fontSize: CGFloat {
        config?.markdownFontSize ?? 15
    }

    var codeFontSize: CGFloat {
        config?.markdownCodeFontSize ?? 13
    }

    var lineHeight: CGFloat {
        config?.markdownLineHeight ?? 1.4
    }

    // MARK: - Default Colors (fallback when not using terminal theme)

    private var defaultBackground: Color {
        colorScheme == .dark
            ? Color(hex: "1C1C1E")
            : Color(hex: "FFFFFF")
    }

    private var defaultTextPrimary: Color {
        colorScheme == .dark
            ? Color(hex: "E5E5E7")
            : Color(hex: "1D1D1F")
    }

    private var defaultTextSecondary: Color {
        colorScheme == .dark
            ? Color(hex: "A1A1A6")
            : Color(hex: "6E6E73")
    }

    private var defaultTextMuted: Color {
        colorScheme == .dark
            ? Color(hex: "636366")
            : Color(hex: "8E8E93")
    }

    private var defaultAccent: Color {
        colorScheme == .dark
            ? Color(hex: "0A84FF")
            : Color(hex: "007AFF")
    }

    private var defaultSuccess: Color {
        colorScheme == .dark
            ? Color(hex: "30D158")
            : Color(hex: "34C759")
    }

    private var defaultCodeBackground: Color {
        colorScheme == .dark
            ? Color(hex: "1E1E20")
            : Color(hex: "F6F8FA")
    }

    private var defaultSyntaxKeyword: Color {
        colorScheme == .dark
            ? Color(hex: "FF79C6")  // Pink
            : Color(hex: "D73A49")  // Red
    }

    private var defaultSyntaxString: Color {
        colorScheme == .dark
            ? Color(hex: "F1FA8C")  // Yellow
            : Color(hex: "22863A")  // Green
    }

    private var defaultSyntaxComment: Color {
        colorScheme == .dark
            ? Color(hex: "6272A4")  // Muted blue
            : Color(hex: "6A737D")  // Gray
    }

    // MARK: - Backgrounds

    /// Background color - uses terminal background when theme is "terminal"
    var background: Color {
        if useTerminalColors, let termBg = config?.terminalBackground {
            return termBg
        }
        return defaultBackground
    }

    var surfaceElevated: Color {
        if useTerminalColors, let termBg = config?.terminalBackground {
            return termBg.adjustBrightness(by: colorScheme == .dark ? 0.05 : -0.03)
        }
        return colorScheme == .dark
            ? Color(hex: "2C2C2E")
            : Color(hex: "F5F5F7")
    }

    /// Code background - slightly darker than background when using terminal theme
    var codeBackground: Color {
        if useTerminalColors, let termBg = config?.terminalBackground {
            return termBg.adjustBrightness(by: colorScheme == .dark ? -0.02 : -0.03)
        }
        return defaultCodeBackground
    }

    // MARK: - Text

    /// Primary text - uses terminal foreground when theme is "terminal"
    var textPrimary: Color {
        if useTerminalColors, let termFg = config?.terminalForeground {
            return termFg
        }
        return defaultTextPrimary
    }

    /// Secondary text - uses palette[8] (bright black) when theme is "terminal"
    var textSecondary: Color {
        if useTerminalColors, let palette8 = config?.paletteColor(8) {
            return palette8
        }
        return defaultTextSecondary
    }

    /// Muted text - uses palette[8] with reduced opacity when theme is "terminal"
    var textMuted: Color {
        if useTerminalColors, let palette8 = config?.paletteColor(8) {
            return palette8.opacity(0.8)
        }
        return defaultTextMuted
    }

    // MARK: - Accent & UI

    /// Accent/links - uses palette[4] (blue) when theme is "terminal"
    var accent: Color {
        if useTerminalColors, let palette4 = config?.paletteColor(4) {
            return palette4
        }
        return defaultAccent
    }

    /// Success color - uses palette[2] (green) when theme is "terminal"
    var success: Color {
        if useTerminalColors, let palette2 = config?.paletteColor(2) {
            return palette2
        }
        return defaultSuccess
    }

    var border: Color {
        if useTerminalColors, let termFg = config?.terminalForeground {
            return termFg.opacity(0.2)
        }
        return colorScheme == .dark
            ? Color(hex: "38383A")
            : Color(hex: "D1D1D6")
    }

    // MARK: - Search

    var searchHighlight: Color {
        if useTerminalColors, let palette3 = config?.paletteColor(3) {
            return palette3.opacity(0.4)
        }
        return colorScheme == .dark
            ? Color(hex: "FFD60A").opacity(0.4)
            : Color(hex: "FFD60A").opacity(0.5)
    }

    // MARK: - Syntax Highlighting Colors

    /// Syntax keyword - uses palette[5] (magenta) when theme is "terminal"
    var syntaxKeyword: Color {
        if useTerminalColors, let palette5 = config?.paletteColor(5) {
            return palette5
        }
        return defaultSyntaxKeyword
    }

    /// Syntax string - uses palette[3] (yellow) when theme is "terminal"
    var syntaxString: Color {
        if useTerminalColors, let palette3 = config?.paletteColor(3) {
            return palette3
        }
        return defaultSyntaxString
    }

    /// Syntax comment - uses palette[8] (bright black) when theme is "terminal"
    var syntaxComment: Color {
        if useTerminalColors, let palette8 = config?.paletteColor(8) {
            return palette8
        }
        return defaultSyntaxComment
    }

    var syntaxNumber: Color {
        if useTerminalColors, let palette6 = config?.paletteColor(6) {
            return palette6
        }
        return colorScheme == .dark
            ? Color(hex: "BD93F9")
            : Color(hex: "005CC5")
    }

    var syntaxType: Color {
        if useTerminalColors, let palette6 = config?.paletteColor(6) {
            return palette6
        }
        return colorScheme == .dark
            ? Color(hex: "8BE9FD")
            : Color(hex: "6F42C1")
    }

    var syntaxFunction: Color {
        if useTerminalColors, let palette2 = config?.paletteColor(2) {
            return palette2
        }
        return colorScheme == .dark
            ? Color(hex: "50FA7B")
            : Color(hex: "6F42C1")
    }
}

// MARK: - Color Brightness Extension

extension Color {
    /// Adjust the brightness of a color by a percentage (-1.0 to 1.0)
    func adjustBrightness(by amount: Double) -> Color {
        let nsColor = NSColor(self)
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0

        if let calibratedColor = nsColor.usingColorSpace(.deviceRGB) {
            calibratedColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        } else {
            return self
        }

        let newBrightness = max(0, min(1, brightness + CGFloat(amount)))
        return Color(NSColor(hue: hue, saturation: saturation, brightness: newBrightness, alpha: alpha))
    }
}

// MARK: - Syntax Highlighter

struct SyntaxHighlighter {

    // MARK: - Language Detection
    enum Language: String, CaseIterable {
        case swift, python, py, javascript, js, typescript, ts, json
        case shell, bash, sh, zsh, zig, go, golang, rust
        case c, cpp, cxx, ruby, rb, java, kotlin, sql
        case yaml, yml, toml, css, html
        case unknown

        static func from(_ string: String?) -> Language {
            guard let s = string?.lowercased() else { return .unknown }
            return Language(rawValue: s) ?? .unknown
        }
    }

    // MARK: - Cached Regex Patterns

    // Comments
    private static let singleLineComment = try! NSRegularExpression(pattern: #"//.*$"#, options: .anchorsMatchLines)
    private static let hashComment = try! NSRegularExpression(pattern: #"#.*$"#, options: .anchorsMatchLines)
    private static let multiLineComment = try! NSRegularExpression(pattern: #"/\*[\s\S]*?\*/"#)

    // Strings
    private static let doubleQuoteString = try! NSRegularExpression(pattern: #""(?:[^"\\]|\\.)*""#)
    private static let singleQuoteString = try! NSRegularExpression(pattern: #"'(?:[^'\\]|\\.)*'"#)
    private static let backtickString = try! NSRegularExpression(pattern: #"`(?:[^`\\]|\\.)*`"#)
    private static let tripleQuoteString = try! NSRegularExpression(pattern: #"\"\"\"[\s\S]*?\"\"\""#)

    // Numbers
    private static let numbers = try! NSRegularExpression(
        pattern: #"\b(?:0x[0-9A-Fa-f]+|0b[01]+|0o[0-7]+|\d+\.?\d*(?:[eE][+-]?\d+)?)\b"#
    )

    // Language keywords
    private static let swiftKeywords = try! NSRegularExpression(
        pattern: #"\b(func|let|var|if|else|guard|switch|case|default|for|while|repeat|do|try|catch|throw|throws|rethrows|return|break|continue|fallthrough|in|where|is|as|nil|true|false|self|Self|super|init|deinit|class|struct|enum|protocol|extension|import|typealias|associatedtype|static|final|lazy|private|fileprivate|internal|public|open|override|mutating|nonmutating|convenience|required|optional|weak|unowned|inout|some|any|async|await|actor|nonisolated|isolated|@\w+)\b"#
    )

    private static let pythonKeywords = try! NSRegularExpression(
        pattern: #"\b(def|class|if|elif|else|for|while|try|except|finally|with|as|import|from|return|yield|break|continue|pass|raise|in|is|not|and|or|lambda|global|nonlocal|assert|True|False|None|async|await|@\w+)\b"#
    )

    private static let jsKeywords = try! NSRegularExpression(
        pattern: #"\b(function|const|let|var|if|else|for|while|do|switch|case|default|break|continue|return|throw|try|catch|finally|new|delete|typeof|instanceof|void|this|super|class|extends|static|get|set|async|await|yield|import|export|from|as|default|true|false|null|undefined|of|in)\b"#
    )

    private static let tsKeywords = try! NSRegularExpression(
        pattern: #"\b(interface|type|enum|namespace|module|declare|abstract|implements|private|protected|public|readonly|keyof|infer|extends|never|unknown|any|void|boolean|number|string|symbol|bigint|object)\b"#
    )

    private static let shellKeywords = try! NSRegularExpression(
        pattern: #"\b(if|then|else|elif|fi|for|while|do|done|case|esac|in|function|return|exit|export|source|alias|unalias|local|readonly|declare|typeset|set|unset|shift|true|false)\b"#
    )

    private static let zigKeywords = try! NSRegularExpression(
        pattern: #"\b(fn|const|var|if|else|for|while|switch|break|continue|return|defer|errdefer|try|catch|unreachable|pub|extern|export|inline|comptime|noalias|threadlocal|allowzero|volatile|struct|enum|union|error|opaque|test|and|or|orelse|null|undefined|true|false|@\w+)\b"#
    )

    private static let goKeywords = try! NSRegularExpression(
        pattern: #"\b(func|package|import|var|const|type|struct|interface|map|chan|go|defer|return|if|else|for|range|switch|case|default|break|continue|fallthrough|select|nil|true|false|iota|make|new|len|cap|append|copy|delete|panic|recover)\b"#
    )

    private static let rustKeywords = try! NSRegularExpression(
        pattern: #"\b(fn|let|mut|const|static|if|else|match|loop|while|for|in|break|continue|return|move|ref|pub|crate|mod|use|as|self|Self|super|struct|enum|trait|impl|type|where|dyn|unsafe|extern|async|await|true|false|None|Some|Ok|Err)\b"#
    )

    private static let cKeywords = try! NSRegularExpression(
        pattern: #"\b(auto|break|case|char|const|continue|default|do|double|else|enum|extern|float|for|goto|if|inline|int|long|register|restrict|return|short|signed|sizeof|static|struct|switch|typedef|union|unsigned|void|volatile|while|class|public|private|protected|virtual|template|typename|namespace|using|try|catch|throw|new|delete|this|nullptr|true|false|bool|constexpr|noexcept|override|final|decltype)\b"#
    )

    private static let rubyKeywords = try! NSRegularExpression(
        pattern: #"\b(def|end|class|module|if|elsif|else|unless|case|when|while|until|for|do|begin|rescue|ensure|raise|return|break|next|redo|retry|yield|self|super|nil|true|false|and|or|not|in|then|alias|@\w+)\b"#
    )

    private static let javaKeywords = try! NSRegularExpression(
        pattern: #"\b(abstract|assert|boolean|break|byte|case|catch|char|class|const|continue|default|do|double|else|enum|extends|final|finally|float|for|goto|if|implements|import|instanceof|int|interface|long|native|new|null|package|private|protected|public|return|short|static|strictfp|super|switch|synchronized|this|throw|throws|transient|true|false|try|void|volatile|while|var|record|sealed|permits|yield)\b"#
    )

    private static let kotlinKeywords = try! NSRegularExpression(
        pattern: #"\b(fun|val|var|if|else|when|for|while|do|break|continue|return|throw|try|catch|finally|class|interface|object|data|sealed|enum|annotation|companion|init|constructor|this|super|null|true|false|is|as|in|out|by|where|typealias|import|package|suspend|inline|crossinline|noinline|reified|operator|infix|tailrec|external|internal|private|protected|public|open|final|abstract|override|lateinit)\b"#
    )

    private static let sqlKeywords = try! NSRegularExpression(
        pattern: #"\b(?i)(SELECT|FROM|WHERE|AND|OR|NOT|IN|LIKE|BETWEEN|IS|NULL|AS|JOIN|LEFT|RIGHT|INNER|OUTER|ON|GROUP|BY|HAVING|ORDER|ASC|DESC|LIMIT|OFFSET|INSERT|INTO|VALUES|UPDATE|SET|DELETE|CREATE|TABLE|INDEX|VIEW|DROP|ALTER|ADD|COLUMN|PRIMARY|KEY|FOREIGN|REFERENCES|UNIQUE|CHECK|DEFAULT|CONSTRAINT|CASCADE|DISTINCT|UNION|ALL|EXISTS|CASE|WHEN|THEN|ELSE|END|COUNT|SUM|AVG|MIN|MAX|TRUE|FALSE)\b"#
    )

    // Types (capitalized identifiers)
    private static let types = try! NSRegularExpression(pattern: #"\b([A-Z][a-zA-Z0-9]*)\b"#)

    // Function calls
    private static let functionCalls = try! NSRegularExpression(pattern: #"\b([a-zA-Z_][a-zA-Z0-9_]*)\s*\("#)

    // JSON/YAML keys
    private static let jsonKeys = try! NSRegularExpression(pattern: #""([^"]+)"\s*:"#)
    private static let yamlKeys = try! NSRegularExpression(pattern: #"^(\s*)([a-zA-Z_][a-zA-Z0-9_-]*):"#, options: .anchorsMatchLines)

    // MARK: - Highlight Method

    static func highlight(_ code: String, language: String?, theme: MarkdownTheme) -> AttributedString {
        var attrStr = AttributedString(code)
        let fullRange = NSRange(location: 0, length: (code as NSString).length)

        // Base style - use configurable code font size
        attrStr.font = .monospacedSystemFont(ofSize: theme.codeFontSize, weight: .regular)
        attrStr.foregroundColor = NSColor(theme.textPrimary)

        let lang = Language.from(language)
        var highlighted: [NSRange] = []

        // Helper to apply color
        func apply(_ regex: NSRegularExpression, color: Color, bold: Bool = false, group: Int = 0) {
            for match in regex.matches(in: code, range: fullRange) {
                let range = group < match.numberOfRanges ? match.range(at: group) : match.range
                guard range.location != NSNotFound else { continue }

                // Skip overlapping
                if highlighted.contains(where: { NSIntersectionRange($0, range).length > 0 }) { continue }

                if let swiftRange = Range(range, in: code) {
                    let startOffset = code.distance(from: code.startIndex, to: swiftRange.lowerBound)
                    let endOffset = code.distance(from: code.startIndex, to: swiftRange.upperBound)
                    let startIndex = attrStr.index(attrStr.startIndex, offsetByCharacters: startOffset)
                    let endIndex = attrStr.index(attrStr.startIndex, offsetByCharacters: endOffset)
                    let attrRange = startIndex..<endIndex
                    attrStr[attrRange].foregroundColor = NSColor(color)
                    if bold {
                        attrStr[attrRange].font = .monospacedSystemFont(ofSize: theme.codeFontSize, weight: .bold)
                    }
                    highlighted.append(range)
                }
            }
        }

        // 1. Comments first (highest priority)
        switch lang {
        case .python, .py, .shell, .bash, .sh, .zsh, .ruby, .rb, .yaml, .yml, .toml:
            apply(hashComment, color: theme.syntaxComment)
        case .sql:
            apply(hashComment, color: theme.syntaxComment)
            apply(singleLineComment, color: theme.syntaxComment)
        case .css, .html:
            apply(multiLineComment, color: theme.syntaxComment)
        default:
            apply(singleLineComment, color: theme.syntaxComment)
            apply(multiLineComment, color: theme.syntaxComment)
        }

        // 2. Strings
        if lang == .python || lang == .py {
            apply(tripleQuoteString, color: theme.syntaxString)
        }
        apply(doubleQuoteString, color: theme.syntaxString)
        apply(singleQuoteString, color: theme.syntaxString)
        apply(backtickString, color: theme.syntaxString)

        // 3. Numbers
        apply(numbers, color: theme.syntaxNumber)

        // 4. Language keywords
        switch lang {
        case .swift:
            apply(swiftKeywords, color: theme.syntaxKeyword, bold: true)
        case .python, .py:
            apply(pythonKeywords, color: theme.syntaxKeyword, bold: true)
        case .javascript, .js:
            apply(jsKeywords, color: theme.syntaxKeyword, bold: true)
        case .typescript, .ts:
            apply(jsKeywords, color: theme.syntaxKeyword, bold: true)
            apply(tsKeywords, color: theme.syntaxType, bold: true)
        case .shell, .bash, .sh, .zsh:
            apply(shellKeywords, color: theme.syntaxKeyword, bold: true)
        case .zig:
            apply(zigKeywords, color: theme.syntaxKeyword, bold: true)
        case .go, .golang:
            apply(goKeywords, color: theme.syntaxKeyword, bold: true)
        case .rust:
            apply(rustKeywords, color: theme.syntaxKeyword, bold: true)
        case .c, .cpp, .cxx:
            apply(cKeywords, color: theme.syntaxKeyword, bold: true)
        case .ruby, .rb:
            apply(rubyKeywords, color: theme.syntaxKeyword, bold: true)
        case .java:
            apply(javaKeywords, color: theme.syntaxKeyword, bold: true)
        case .kotlin:
            apply(kotlinKeywords, color: theme.syntaxKeyword, bold: true)
        case .sql:
            apply(sqlKeywords, color: theme.syntaxKeyword, bold: true)
        case .json:
            apply(jsonKeys, color: theme.syntaxType, group: 1)
        case .yaml, .yml:
            apply(yamlKeys, color: theme.syntaxType, group: 2)
        default:
            break
        }

        // 5. Types (lower priority)
        if lang != .json && lang != .yaml && lang != .yml {
            apply(types, color: theme.syntaxType, group: 1)
        }

        // 6. Function calls
        if lang != .json && lang != .yaml && lang != .yml && lang != .toml {
            apply(functionCalls, color: theme.syntaxFunction, group: 1)
        }

        return attrStr
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
