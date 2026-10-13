import AppKit

/// Names and product-style words in the window the user dictates into, such as the people in a chat, passed to the speech model as hints for one dictation.
public enum WindowTerms {
    static let limit = 20

    /// Engines whose hints bias recognition. Whisper is left out because a keyword prompt raised average WER in published tests (docs/accuracy.md).
    public static func helps(_ engine: SpeechEngine) -> Bool {
        engine == .parakeet || engine == .apple
    }

    /// Hints from the window and selected text that the vocabulary doesn't already give, skipping phrases the vocabulary rewrites.
    @MainActor
    public static func hints(from context: DictationContext?, vocabulary: [VocabularyEntry]) -> [String] {
        let text = [context?.window, context?.selectedText].compactMap { $0 }.joined(separator: "\n")
        let known = Set(VocabularyProcessor.hints(vocabulary).map { $0.lowercased() }
            + vocabulary.filter { !$0.replacement.isEmpty }.map { $0.phrase.lowercased() })
        // The spelling dictionary accepts many capitalized names, such as Kartik, but not in lowercase.
        return terms(in: text, excluding: known) { word in
            NSSpellChecker.shared.checkSpelling(of: word.lowercased(), startingAt: 0).location == NSNotFound
        }
    }

    /// Words with inner capitals, such as PostHog, and capitalized words that aren't ordinary words, such as Kartik; most frequent first, then most recent.
    static func terms(in text: String, excluding known: Set<String>, isOrdinaryWord: (String) -> Bool) -> [String] {
        var counts: [String: (term: String, count: Int, last: Int)] = [:]
        var rejected = Set<String>()
        for (position, word) in CorrectionLearner.tokenize(text).enumerated() {
            let key = word.lowercased()
            if let seen = counts[key] {
                counts[key] = (seen.term, seen.count + 1, position)
            } else if !rejected.contains(word), !known.contains(key) {
                if isDistinctive(word, isOrdinaryWord: isOrdinaryWord) { counts[key] = (word, 1, position) } else { rejected.insert(word) }
            }
        }
        return counts.values.sorted { ($0.count, $0.last) > ($1.count, $1.last) }.prefix(limit).map(\.term)
    }

    /// The hints the final text spells exactly, as whole words: names the user said, which Wispr Flow-style learning keeps.
    public static func used(_ hints: [String], in text: String) -> [String] {
        let words = Set(CorrectionLearner.tokenize(text))
        return hints.filter(words.contains)
    }

    private static func isDistinctive(_ word: String, isOrdinaryWord: (String) -> Bool) -> Bool {
        guard (3...32).contains(word.count), word.allSatisfy(\.isLetter), let first = word.first, word.contains(where: \.isLowercase) else { return false }
        if word.dropFirst().contains(where: \.isUppercase) { return true }
        return first.isUppercase && !isOrdinaryWord(word)
    }
}
