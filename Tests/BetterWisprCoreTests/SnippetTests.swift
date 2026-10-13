import Foundation
import Testing
@testable import BetterWisprCore

private let address = Snippet(cue: "my address", text: "1 Main Street\nSpringfield")
private let link = Snippet(cue: "my calendar link", text: "https://cal.example/ryan")

private func expand(_ text: String, _ snippets: [Snippet] = [address, link]) -> String {
    SnippetExpander.expand(snippets, in: text).text
}

@Test func snippetCueInsideASentenceIsReplaced() {
    #expect(expand("Send it to my address, please.") == "Send it to 1 Main Street\nSpringfield, please.")
    #expect(expand("Book here: my calendar link. Thanks") == "Book here: https://cal.example/ryan. Thanks")
    #expect(SnippetExpander.expand([address], in: "Nothing to see here.") == ("Nothing to see here.", false))
}

@Test func snippetCueIgnoresCasePunctuationAndSpacing() {
    #expect(expand("Ship to My,  address today") == "Ship to 1 Main Street\nSpringfield today")
    #expect(expand("Use MY CALENDAR-LINK.") == "Use https://cal.example/ryan.")
}

@Test func dictationThatIsOnlyTheCueBecomesExactlyTheText() {
    #expect(expand("My address.") == address.text)
    #expect(expand("  my, address!  ") == address.text)
    #expect(SnippetExpander.expand([address], in: "My address?").expanded)
}

@Test func longestSnippetCueWinsWithoutOverlap() {
    let short = Snippet(cue: "my link", text: "SHORT")
    let long = Snippet(cue: "my link for calls", text: "LONG")
    #expect(expand("Here is my link for calls and my link", [short, long]) == "Here is LONG and SHORT")
    let book = Snippet(cue: "address book", text: "BOOK")
    #expect(expand("Open my address book", [address, book]) == "Open my BOOK")
}

@Test func snippetCueNeverMatchesPartOfAWord() {
    let sign = Snippet(cue: "sign off", text: "Best, Ryan")
    #expect(expand("Please resign offline", [sign]) == "Please resign offline")
    #expect(expand("my addresses", [address]) == "my addresses")
    #expect(expand("I don't know", [Snippet(cue: "don", text: "X")]) == "I don't know")
    #expect(expand("Thanks, sign off", [sign]) == "Thanks, Best, Ryan")
}

@Test func snippetCueKeepsAPossessive() {
    #expect(expand("Is my address's zip right?", [address]) == "Is 1 Main Street\nSpringfield's zip right?")
}

@Test func snippetCueMatchesVoiceCommandNumbers() {
    let room = Snippet(cue: "room twenty five", text: "Room 25, Building B")
    #expect(expand("Meet in room 25.", [room]) == "Meet in Room 25, Building B.")
}

@Test func snippetValidationRejectsBadCues() {
    #expect(Snippet.problem(cue: "my address", text: "x", among: []) == nil)
    #expect(Snippet.problem(cue: "", text: "x", among: []) != nil)
    #expect(Snippet.problem(cue: "?!", text: "x", among: []) != nil)
    #expect(Snippet.problem(cue: String(repeating: "a", count: 61), text: "x", among: []) != nil)
    #expect(Snippet.problem(cue: "hello", text: "", among: []) != nil)
    #expect(Snippet.problem(cue: "hello", text: String(repeating: "a", count: 4_001), among: []) != nil)
    #expect(Snippet.problem(cue: "My Address.", text: "x", among: [address]) != nil)
    #expect(Snippet.problem(cue: "new line", text: "x", among: []) != nil)
    #expect(Snippet.problem(cue: "question mark", text: "x", among: []) != nil)
}

@Test func olderWorkspaceDecodesWithoutSnippets() throws {
    let data = try JSONSerialization.data(withJSONObject: [
        "version": 1, "history": [], "vocabulary": [],
        "settings": try JSONSerialization.jsonObject(with: JSONEncoder().encode(AppSettings())),
    ])
    #expect(try JSONDecoder().decode(SavedState.self, from: data).snippets == [])
}

@Test func snippetsSurviveSaveAndLoad() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = LocalStore(directory: directory)
    var state = SavedState()
    state.snippets = [address, link]
    try store.save(state)
    #expect(try store.load().snippets == [address, link])
}
