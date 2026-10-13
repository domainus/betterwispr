import Foundation

public enum SpeechEngine: String, Codable, Sendable {
    case apple, whisperKit, parakeet, cohere, canary, api

    /// Engines whose models download to this Mac from an explicit installation.
    public var installsModels: Bool { self != .apple && self != .api }
}

public struct SpeechModel: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let detail: String
    public let sizeLabel: String
    public let engine: SpeechEngine
    public let modelName: String
    public let tokenizerName: String?
    public let connection: SpeechConnection?
    /// Language codes the model recognizes; nil when its coverage is not a known fixed list.
    public let languages: [String]?
    /// The oldest major macOS version that can load the model; nil for the app's own minimum.
    public let minimumMacOS: Int?

    public init(id: String, name: String, detail: String, sizeLabel: String, engine: SpeechEngine,
                modelName: String, tokenizerName: String? = nil, connection: SpeechConnection? = nil, languages: [String]? = nil,
                minimumMacOS: Int? = nil) {
        self.id = id
        self.name = name
        self.detail = detail
        self.sizeLabel = sizeLabel
        self.engine = engine
        self.modelName = modelName
        self.tokenizerName = tokenizerName
        self.connection = connection
        self.languages = languages
        self.minimumMacOS = minimumMacOS
    }

    /// False when this Mac's macOS is older than the model needs.
    public var isSupported: Bool {
        minimumMacOS.map { ProcessInfo.processInfo.isOperatingSystemAtLeast(.init(majorVersion: $0, minorVersion: 0, patchVersion: 0)) } ?? true
    }

    private static let parakeetV3Languages = [
        "bg", "hr", "cs", "da", "nl", "en", "et", "fi", "fr", "de", "el", "hu", "it",
        "lv", "lt", "mt", "pl", "pt", "ro", "sk", "sl", "es", "sv", "ru", "uk",
    ]

    /// The languages FluidAudio's Cohere prompt accepts (`CohereAsrConfig.Language`).
    static let cohereLanguages = ["en", "fr", "de", "es", "it", "pt", "nl", "pl", "el", "ar", "ja", "zh", "vi", "ko"]

    /// The prompt language for a model that can't detect one. A fixed setting must be in `supported`;
    /// automatic uses the first preferred macOS language in `supported`, then English. Nil when unsupported.
    nonisolated static func promptLanguage(for code: String?, supported: [String], preferred: [String] = Locale.preferredLanguages) -> String? {
        func base(_ identifier: String) -> String? { Locale(identifier: identifier).language.languageCode?.identifier }
        if let code, code != "auto" { return base(code).flatMap { supported.contains($0) ? $0 : nil } }
        return preferred.lazy.compactMap(base).first(where: supported.contains) ?? "en"
    }

    public static let catalog: [SpeechModel] = [
        .init(id: "apple", name: "Apple on-device", detail: "Uses an available macOS language pack. No cloud fallback.",
              sizeLabel: "System managed", engine: .apple, modelName: "apple"),
        .init(id: "parakeet-ultra", name: "Parakeet Ultra", detail: "Parakeet TDT v3 further trained by Moondream for fewer mistakes, with punctuation, the same 25 European languages and the same speed.",
              sizeLabel: "~730 MB", engine: .parakeet, modelName: "parakeet-ultra", languages: parakeetV3Languages),
        .init(id: "parakeet-v3", name: "Parakeet TDT v3", detail: "NVIDIA's multilingual model for 25 European languages, with punctuation. Fast on the Neural Engine.",
              sizeLabel: "~580 MB", engine: .parakeet, modelName: "parakeet-tdt-0.6b-v3", languages: parakeetV3Languages),
        .init(id: "parakeet-redux", name: "Parakeet Redux", detail: "Parakeet TDT v3 retrained by Moondream with three-value weights for a smaller download. The same 25 European languages, with punctuation.",
              sizeLabel: "~320 MB", engine: .parakeet, modelName: "parakeet-redux", languages: parakeetV3Languages, minimumMacOS: 15),
        .init(id: "parakeet-v2", name: "Parakeet TDT v2", detail: "NVIDIA's English-only model, tuned for English accuracy, with punctuation.",
              sizeLabel: "~560 MB", engine: .parakeet, modelName: "parakeet-tdt-0.6b-v2", languages: ["en"]),
        .init(id: "phonon-2", name: "Phonon-2", detail: "Fermion Research's English-only retraining of Parakeet TDT v3 with compressed weights, with punctuation.",
              sizeLabel: "~480 MB", engine: .parakeet, modelName: "phonon-2", languages: ["en"], minimumMacOS: 15),
        .init(id: "parakeet-110m", name: "Parakeet TDT-CTC 110M", detail: "A small English-only model for Macs with less memory to spare.",
              sizeLabel: "~330 MB", engine: .parakeet, modelName: "parakeet-tdt-ctc-110m", languages: ["en"]),
        .init(id: "parakeet-ja", name: "Parakeet Japanese", detail: "NVIDIA's Parakeet model for Japanese speech.",
              sizeLabel: "~720 MB", engine: .parakeet, modelName: "parakeet-ja", languages: ["ja"]),
        .init(id: "cohere-transcribe", name: "Cohere Transcribe", detail: "Cohere's large model for 14 languages, including Arabic, Chinese, Japanese and Korean, with punctuation. Slower than Parakeet and uses more memory, and the first transcription after each launch can take over a minute. It can't detect the language, so Detect automatically uses your Mac's language when Cohere supports it, otherwise English.",
              sizeLabel: "~2.2 GB", engine: .cohere, modelName: "cohere-transcribe-03-2026", languages: cohereLanguages),
        .init(id: "canary-1b-v2", name: "Canary 1B v2", detail: "NVIDIA's encoder-decoder model for the same 25 European languages as Parakeet v3, with punctuation. FluidAudio marks this build as beta. It can't detect the language, so Detect automatically uses your Mac's language when Canary supports it, otherwise English.",
              sizeLabel: "~570 MB", engine: .canary, modelName: "canary-1b-v2", languages: parakeetV3Languages, minimumMacOS: 15),
        .init(id: "whisper-turbo", name: "Whisper Large v3 Turbo", detail: "Broadest language coverage, including languages Parakeet does not support.",
              sizeLabel: "~1.6 GB", engine: .whisperKit, modelName: "openai_whisper-large-v3-v20240930_turbo", tokenizerName: "openai/whisper-large-v3"),
        .init(id: "whisper-turbo-compressed", name: "Whisper Large v3 Turbo (compressed)", detail: "The languages of Whisper Large v3 Turbo in a compressed build that takes less disk space.",
              sizeLabel: "~650 MB", engine: .whisperKit, modelName: "openai_whisper-large-v3-v20240930_turbo_632MB", tokenizerName: "openai/whisper-large-v3"),
        .init(id: "whisper-large-v3", name: "Whisper Large v3", detail: "The full Large v3 model that Turbo is based on, for the same languages. It has 32 decoder layers to Turbo's 4, so it needs more memory and time.",
              sizeLabel: "~3.1 GB", engine: .whisperKit, modelName: "openai_whisper-large-v3", tokenizerName: "openai/whisper-large-v3"),
        .init(id: "whisper-distil-large-v3", name: "Distil-Whisper Large v3", detail: "Hugging Face's distilled Large v3 for English only, with 2 decoder layers instead of 32.",
              sizeLabel: "~1.5 GB", engine: .whisperKit, modelName: "distil-whisper_distil-large-v3", tokenizerName: "openai/whisper-large-v3", languages: ["en"]),
        .init(id: "whisper-small", name: "Whisper Small", detail: "A lighter multilingual Whisper model with a smaller download.",
              sizeLabel: "~490 MB", engine: .whisperKit, modelName: "openai_whisper-small", tokenizerName: "openai/whisper-small"),
        .init(id: "whisper-base", name: "Whisper Base", detail: "A small multilingual Whisper model for Macs with little memory or disk space to spare.",
              sizeLabel: "~150 MB", engine: .whisperKit, modelName: "openai_whisper-base", tokenizerName: "openai/whisper-base"),
    ]
}

@MainActor
public protocol SpeechProvider: AnyObject {
    var onProgress: (@MainActor @Sendable (Double) -> Void)? { get set }
    var onPartialTranscript: (@MainActor @Sendable (String) -> Void)? { get set }
    /// Local providers may download only with `download: true`. API providers only validate here;
    /// their explicitly selected connection authorizes network use during transcription.
    func prepare(model: SpeechModel, download: Bool) async throws
    func transcribe(audioURL: URL, language: String?, vocabulary: [String]) async throws -> String
    /// Vocabulary terms the provider itself corrected during the last transcription.
    var vocabularyFixes: Int { get }
    func cancel()
}

extension SpeechProvider {
    public var vocabularyFixes: Int { 0 }
}

extension SpeechModel {
    @MainActor public func makeProvider() -> any SpeechProvider {
        switch engine {
        case .apple: AppleSpeechProvider()
        case .whisperKit: WhisperKitProvider()
        case .parakeet: ParakeetProvider()
        case .cohere: CohereProvider()
        case .canary: CanaryProvider()
        case .api: APISpeechProvider()
        }
    }

    /// Whether a downloadable model's files are complete in the default models folder; false for system and API models.
    @MainActor public var isInstalledLocally: Bool {
        switch engine {
        case .whisperKit: WhisperKitProvider.isInstalled(self)
        case .parakeet: ParakeetProvider.isInstalled(self)
        case .cohere: CohereProvider.isInstalled(self)
        case .canary: CanaryProvider.isInstalled(self)
        case .apple, .api: false
        }
    }
}

public enum SpeechError: LocalizedError, Sendable {
    case modelNotInstalled(String)
    case invalidModel
    case notPrepared
    case busy
    case permissionDenied
    case onDeviceUnavailable(String)
    case timedOut
    case emptyAudio
    case audioUnavailable
    case downloadFailed
    case needsNewerMacOS(model: String, version: Int)
    case unsupportedLanguage(model: String, language: String)

    public var errorDescription: String? {
        switch self {
        case .modelNotInstalled(let name): "Download \(name) in Models first. Transcription never downloads files."
        case .invalidModel: "This speech provider cannot load the selected model."
        case .notPrepared: "Prepare a speech model before starting dictation."
        case .busy: "A speech operation is already running."
        case .permissionDenied: "Allow Speech Recognition for BetterWispr in System Settings → Privacy & Security."
        case .onDeviceUnavailable(let locale): "Apple on-device recognition is unavailable for \(locale). Install a Whisper model for offline dictation."
        case .timedOut: "On-device speech recognition timed out. Try a shorter recording or a Whisper model."
        case .emptyAudio: "The recording contains no audio."
        case .audioUnavailable: "Select an existing local audio file."
        case .downloadFailed: "Hugging Face didn’t send the model files. Check your internet connection and try again."
        case .needsNewerMacOS(let model, let version): "\(model) needs macOS \(version) or later."
        case .unsupportedLanguage(let model, let language):
            "\(model) doesn’t support \(Locale.current.localizedString(forLanguageCode: language) ?? language). Choose another spoken language in Settings or another model."
        }
    }
}
