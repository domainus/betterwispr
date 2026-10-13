import Foundation

public struct LearnedCorrection: Equatable, Sendable {
    public var heard: String
    public var corrected: String

    public init(heard: String, corrected: String) {
        self.heard = heard
        self.corrected = corrected
    }

    /// Whether this edit changes a learned replacement back to the words it replaced.
    public func undoes(_ entry: VocabularyEntry) -> Bool {
        entry.learned && !entry.replacement.isEmpty
            && heard.caseInsensitiveCompare(entry.replacement) == .orderedSame && corrected.caseInsensitiveCompare(entry.phrase) == .orderedSame
    }
}

public enum CorrectionLearner {
    static let commonWords = Set("""
        the and for not with you this but his from they say her she will one all would
        there their what out about who get which when make can like time just him know
        take into year your good some could them see other than then now look only come
        over think also back after use two how our work first well way even new want
        because any these give day most are was were been has had did does said went
        made got came took saw knew thought where why here very much many still too again
        off down never every own same another both each few more less last next while
        before through under between should might must being have that its yes okay
        """.split(whereSeparator: \.isWhitespace).map(String.init))

    /// Returns word-level fixes the user made to dictated text, skipping rewrites and ordinary word swaps.
    public static func corrections(from original: String, to edited: String) -> [LearnedCorrection] {
        var seen = Set<String>()
        return wordEdits(from: original, to: edited).filter { change in
            seen.insert(change.corrected.lowercased()).inserted && isVocabulary(change)
        }
    }

    /// Learned replacements the user changed back in this edit, so they can be forgotten instead of learned in reverse.
    public static func reverted(_ vocabulary: [VocabularyEntry], from original: String, to edited: String) -> [VocabularyEntry] {
        let edits = wordEdits(from: original, to: edited)
        return vocabulary.filter { entry in edits.contains { $0.undoes(entry) } }
    }

    /// Swaps of one to three words; none when the edit rewrote more than half the words.
    private static func wordEdits(from original: String, to edited: String) -> [LearnedCorrection] {
        let before = tokenize(original), after = tokenize(edited)
        guard !before.isEmpty, !after.isEmpty, before != after else { return [] }
        let edits = substitutions(before, after)
        return edits.count <= max(1, before.count / 2) ? edits : []
    }

    /// Whether the heard phrase is an everyday word that must not be rewritten everywhere.
    public static func isCommon(_ phrase: String) -> Bool {
        commonWords.contains(phrase.lowercased())
    }

    static func tokenize(_ text: String) -> [String] {
        let edges = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_")).inverted
        return text.split(whereSeparator: \.isWhitespace)
            .map { $0.trimmingCharacters(in: edges) }
            .filter { !$0.isEmpty }
    }

    private static func isVocabulary(_ change: LearnedCorrection) -> Bool {
        let heard = change.heard.lowercased(), corrected = change.corrected.lowercased()
        // Like Wispr Flow, skip paths, addresses and code symbols.
        guard corrected.contains(where: \.isLetter), !corrected.contains(where: { "/\\@_".contains($0) }) else { return false }
        if heard == corrected { return change.corrected.dropFirst().contains(where: \.isUppercase) }
        if change.corrected.count < 3, !change.corrected.contains(where: \.isUppercase) { return false }
        if commonWords.contains(corrected) { return false }
        let compactHeard = heard.filter { !$0.isWhitespace }, compactCorrected = corrected.filter { !$0.isWhitespace }
        let distance = editDistance(Array(compactHeard), Array(compactCorrected))
        return Double(distance) / Double(max(compactHeard.count, compactCorrected.count)) <= 0.65
    }

    private static func substitutions(_ before: [String], _ after: [String]) -> [LearnedCorrection] {
        let m = before.count, n = after.count
        var lcs = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in stride(from: m - 1, through: 0, by: -1) {
            for j in stride(from: n - 1, through: 0, by: -1) {
                lcs[i][j] = before[i] == after[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
            }
        }
        var result: [LearnedCorrection] = []
        var removed: [String] = [], added: [String] = []
        func flush() {
            if (1...3).contains(removed.count), (1...3).contains(added.count) {
                result.append(LearnedCorrection(heard: removed.joined(separator: " "), corrected: added.joined(separator: " ")))
            }
            removed = []
            added = []
        }
        var i = 0, j = 0
        while i < m || j < n {
            if i < m, j < n, before[i] == after[j] {
                flush()
                i += 1
                j += 1
            } else if j < n, i == m || lcs[i][j + 1] > lcs[i + 1][j] {
                added.append(after[j])
                j += 1
            } else {
                removed.append(before[i])
                i += 1
            }
        }
        flush()
        return result
    }

    private static func editDistance(_ a: [Character], _ b: [Character]) -> Int {
        var previous = Array(0...b.count)
        for (i, x) in a.enumerated() {
            var current = [i + 1]
            for (j, y) in b.enumerated() {
                current.append(x == y ? previous[j] : 1 + min(previous[j], previous[j + 1], current[j]))
            }
            previous = current
        }
        return previous[b.count]
    }
}
