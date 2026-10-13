import Testing
@testable import BetterWisprCore

private let dictionary: Set<String> = ["the", "thanks", "monday", "slack", "active", "window", "application", "content", "hi", "see", "you", "on"]

private func terms(_ text: String, excluding known: Set<String> = []) -> [String] {
    WindowTerms.terms(in: text, excluding: known) { dictionary.contains($0.lowercased()) }
}

@Test func windowTermsPickNamesAndProductWordsFromAChat() {
    let chat = """
        Active Window: Kartik Labhshetwar
        Application: Slack

        Window Content:
        Kartik: Thanks, the PostHog dashboard is live
        Hi Kartik, see you on Monday. iPhone build is THERE
        """
    #expect(terms(chat) == ["Kartik", "iPhone", "PostHog", "Labhshetwar"])
}

@Test func windowTermsSkipKnownSpellingsShortWordsAndNumbers() {
    #expect(terms("Kartik met Al about GPT4 and PostHog", excluding: ["posthog"]) == ["Kartik"])
    #expect(terms("kartik wrote in lowercase") == [])
}

@Test func windowTermsStopAtTheLimit() {
    let names = (0..<30).map { "Zq" + String(repeating: "x", count: $0 + 1) }
    #expect(terms(names.joined(separator: " ")).count == WindowTerms.limit)
}

@Test func windowTermsKeepOnlyNamesTheDictationSpelled() {
    #expect(WindowTerms.used(["Kartik", "PostHog", "Labhshetwar"], in: "Thanks Kartik, the posthog numbers look good.") == ["Kartik"])
}
