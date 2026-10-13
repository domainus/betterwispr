import Foundation

public struct SavedState: Codable, Equatable, Sendable {
    public var version = 1
    public var settings = AppSettings()
    public var history: [Transcript] = []
    public var vocabulary: [VocabularyEntry] = []
    /// Lowercased spellings the user removed after BetterWispr learned them; learning never adds them back.
    public var declinedTerms: [String] = []
    public var snippets: [Snippet] = []
    public init() {}

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        settings = try container.decode(AppSettings.self, forKey: .settings)
        history = try container.decode([Transcript].self, forKey: .history)
        vocabulary = try container.decode([VocabularyEntry].self, forKey: .vocabulary)
        declinedTerms = try container.decodeIfPresent([String].self, forKey: .declinedTerms) ?? []
        snippets = try container.decodeIfPresent([Snippet].self, forKey: .snippets) ?? []
    }
}

public struct LocalStore: Sendable {
    public let directory: URL
    public var stateURL: URL { directory.appendingPathComponent("workspace.json") }

    public init(directory: URL? = nil) {
        self.directory = directory ?? URL.applicationSupportDirectory.appendingPathComponent("BetterWispr", isDirectory: true)
    }

    public func load() throws -> SavedState {
        guard FileManager.default.fileExists(atPath: stateURL.path) else { return SavedState() }
        let state = try JSONDecoder().decode(SavedState.self, from: Data(contentsOf: stateURL))
        guard state.version == 1 else { throw StoreError.unsupportedVersion(state.version) }
        return state
    }

    public func save(_ state: SavedState) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: stateURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stateURL.path)
    }
}

public enum StoreError: LocalizedError {
    case unsupportedVersion(Int)
    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version): "This workspace uses version \(version). Update BetterWispr before opening it."
        }
    }
}
