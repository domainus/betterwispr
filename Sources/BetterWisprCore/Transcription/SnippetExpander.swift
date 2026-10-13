import Foundation

/// Replaces spoken snippet cues with their saved text. Dictation runs it last, so no later step rewrites that text.
public enum SnippetExpander {
    /// A word of the dictation: lowercased for matching, with its place in the original text.
    struct Word {
        let key: String
        let range: Range<String.Index>
    }

    private struct Match {
        let range: Range<String.Index>
        let words: Range<Int>
        let text: String
    }

    /// Expands whole-word cues, ignoring case and the punctuation and spacing around and between their words.
    /// The longest cue wins and matches never overlap. A dictation that is only a cue becomes exactly its text.
    public static func expand(_ snippets: [Snippet], in text: String) -> (text: String, expanded: Bool) {
        let words = Self.words(in: text)
        guard !snippets.isEmpty, !words.isEmpty else { return (text, false) }
        // Voice commands run first, so "room twenty five" is also matched as they write it, "room 25".
        let cues = snippets.flatMap { snippet in
            [snippet.cue, VoiceCommands.apply(snippet.cue)].map { (cue: Self.words($0), text: snippet.text) }
        }
        .enumerated()
        .sorted { ($1.element.cue.joined(separator: " ").count, $0.offset) < ($0.element.cue.joined(separator: " ").count, $1.offset) }
        .map(\.element)

        var taken = Set<Int>()
        var matches: [Match] = []
        for (cue, replacement) in cues where !cue.isEmpty && cue.count <= words.count {
            var start = 0
            while start + cue.count <= words.count {
                let span = start..<(start + cue.count)
                if !span.contains(where: taken.contains), let end = end(of: cue, at: start, in: words, text: text) {
                    taken.formUnion(span)
                    matches.append(Match(range: words[start].range.lowerBound..<end, words: span, text: replacement))
                    start = span.upperBound
                } else {
                    start += 1
                }
            }
        }
        guard !matches.isEmpty else { return (text, false) }
        if matches.count == 1, matches[0].words == words.indices, matches[0].range.upperBound == words[words.count - 1].range.upperBound {
            return (matches[0].text, true)
        }
        var output = ""
        var cursor = text.startIndex
        for match in matches.sorted(by: { $0.range.lowerBound < $1.range.lowerBound }) {
            output += text[cursor..<match.range.lowerBound]
            output += match.text
            cursor = match.range.upperBound
        }
        output += text[cursor...]
        return (output, true)
    }

    /// The lowercased words of a cue, so cues that differ only in case, punctuation or spacing compare equal.
    public static func words(_ text: String) -> [String] {
        words(in: text).map(\.key)
    }

    /// Runs of letters, numbers and underscores; an apostrophe between letters stays inside the word ("don't").
    static func words(in text: String) -> [Word] {
        var words: [Word] = []
        var start: String.Index?
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(after: index)
            let inner = start != nil && isApostrophe(text[index]) && next < text.endIndex && isWordCharacter(text[next])
            if isWordCharacter(text[index]) || inner {
                if start == nil { start = index }
            } else if let first = start {
                words.append(word(text[first..<index]))
                start = nil
            }
            index = next
        }
        if let first = start { words.append(word(text[first...])) }
        return words
    }

    /// Where a cue starting at a word ends, or nil. The last word may carry a possessive "'s", which stays after the text.
    private static func end(of cue: [String], at start: Int, in words: [Word], text: String) -> String.Index? {
        for (offset, key) in cue.enumerated() {
            let word = words[start + offset]
            if word.key == key { continue }
            guard offset == cue.count - 1, word.key == key + "'s",
                  let apostrophe = text[word.range].lastIndex(where: isApostrophe) else { return nil }
            return apostrophe
        }
        return words[start + cue.count - 1].range.upperBound
    }

    private static func word(_ text: Substring) -> Word {
        Word(key: text.lowercased().replacingOccurrences(of: "’", with: "'"), range: text.startIndex..<text.endIndex)
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }

    private static func isApostrophe(_ character: Character) -> Bool {
        character == "'" || character == "’"
    }
}
