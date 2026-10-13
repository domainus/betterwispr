import Foundation

/// Saved text that a spoken cue inserts during dictation, such as an address or a scheduling link.
public struct Snippet: Codable, Identifiable, Equatable, Sendable {
    public static let cueLimit = 60
    public static let textLimit = 4_000
    public static let countLimit = 100

    public var id: UUID
    /// What the user says.
    public var cue: String
    /// What dictation inserts, exactly as typed.
    public var text: String

    public init(id: UUID = UUID(), cue: String, text: String) {
        self.id = id
        self.cue = cue
        self.text = text
    }

    /// Why a trimmed cue and text can't be saved beside the other snippets, or nil when they can.
    public static func problem(cue: String, text: String, among others: [Snippet]) -> String? {
        let words = SnippetExpander.words(cue)
        if words.isEmpty { return "Enter words to say." }
        if cue.count > cueLimit { return "Keep what you say to \(cueLimit) characters." }
        if text.isEmpty { return "Enter the text to insert." }
        if text.count > textLimit { return "Keep the inserted text to 4,000 characters." }
        if VoiceCommands.isSpokenCommand(cue) { return "“\(cue)” is a voice command. Choose other words." }
        if others.contains(where: { SnippetExpander.words($0.cue) == words }) { return "You already have a snippet for “\(cue)”." }
        return nil
    }
}
