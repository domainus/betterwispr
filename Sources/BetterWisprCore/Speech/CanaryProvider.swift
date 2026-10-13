import FluidAudio
import Foundation

/// NVIDIA Canary 1B v2 through FluidAudio's int4 Core ML pipeline. FluidAudio marks the conversion as beta.
@MainActor
public final class CanaryProvider: SpeechProvider {
    public var onProgress: (@MainActor @Sendable (Double) -> Void)?
    public var onPartialTranscript: (@MainActor @Sendable (String) -> Void)?
    private let modelsDirectory: URL
    private var models: CanaryModels?
    private var loadedModelID: String?
    private var preparing = false
    private var transcriptionTask: Task<String, any Error>?

    nonisolated static let repo = Repo.canary1bV2
    /// The only build in the repository; its int4 weights need macOS 15.
    nonisolated static let precision = CanaryPrecision.int4

    public init(modelsDirectory: URL = WhisperKitProvider.defaultModelsDirectory) {
        self.modelsDirectory = modelsDirectory
    }

    /// `ModelHub.download` places the repository in `Canary/canary-1b-v2`.
    nonisolated static func folder(modelsDirectory: URL) -> URL {
        modelsDirectory.appending(path: "Canary/\(repo.folderName)", directoryHint: .isDirectory)
    }

    public static func isInstalled(_ model: SpeechModel, modelsDirectory: URL = WhisperKitProvider.defaultModelsDirectory) -> Bool {
        guard model.engine == .canary else { return false }
        let folder = folder(modelsDirectory: modelsDirectory)
        return ([".betterwispr-installed"] + ModelNames.Canary.requiredModels(precision: precision)).allSatisfy {
            FileManager.default.fileExists(atPath: folder.appending(path: $0).path)
        }
    }

    public func prepare(model: SpeechModel, download: Bool) async throws {
        guard model.engine == .canary else { throw SpeechError.invalidModel }
        guard !preparing, transcriptionTask == nil else { throw SpeechError.busy }
        if loadedModelID == model.id, models != nil { onProgress?(1); return }
        preparing = true
        defer { preparing = false }
        try Task.checkCancellation()
        let folder = Self.folder(modelsDirectory: modelsDirectory)
        if download && !Self.isInstalled(model, modelsDirectory: modelsDirectory) {
            if let version = model.minimumMacOS, !model.isSupported { throw SpeechError.needsNewerMacOS(model: model.name, version: version) }
            let parent = modelsDirectory.appending(path: "Canary", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            onProgress?(0)
            let progress = onProgress
            try await ModelHub.download(Self.repo, to: parent, variant: Self.precision.rawValue) { value in
                let fraction = ParakeetProvider.downloadedFraction(value) * 0.9
                Task { @MainActor in progress?(fraction) }
            }
            try Task.checkCancellation()
        }
        guard download || Self.isInstalled(model, modelsDirectory: modelsDirectory) else { throw SpeechError.modelNotInstalled(model.name) }
        onProgress?(0.95)
        models = nil
        loadedModelID = nil
        // `CanaryModels.load` reads this folder only; it never downloads.
        let loaded = try await Task.detached { try CanaryModels.load(from: folder, precision: Self.precision) }.value
        guard Self.prompt(for: "en", tokenizer: loaded.tokenizer) == CanaryConfig.promptEnTranscribePnc else { throw SpeechError.invalidModel }
        try Task.checkCancellation()
        if download {
            try Data(model.modelName.utf8).write(to: folder.appending(path: ".betterwispr-installed"), options: .atomic)
        }
        models = loaded
        loadedModelID = model.id
        onProgress?(1)
    }

    public func transcribe(audioURL: URL, language: String?, vocabulary: [String]) async throws -> String {
        guard let models, !preparing else { throw SpeechError.notPrepared }
        guard transcriptionTask == nil else { throw SpeechError.busy }
        guard audioURL.isFileURL, FileManager.default.fileExists(atPath: audioURL.path) else { throw SpeechError.audioUnavailable }
        let supported = SpeechModel.catalog.first { $0.engine == .canary }?.languages ?? ["en"]
        guard let spoken = SpeechModel.promptLanguage(for: language, supported: supported),
              let prompt = Self.prompt(for: spoken, tokenizer: models.tokenizer) else {
            throw SpeechError.unsupportedLanguage(model: "Canary 1B v2", language: language ?? "")
        }
        try Task.checkCancellation()
        let manager = CanaryManager(models: models, prompt: prompt)
        let task = Task { try await Self.transcript(of: audioURL, manager: manager) }
        transcriptionTask = task
        defer { transcriptionTask = nil }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }

    public func cancel() {
        transcriptionTask?.cancel()
    }

    /// Canary 2's transcription prompt, as in `CanaryConfig.promptEnTranscribePnc`, with the language token
    /// as both source and target: ▁ <|startofcontext|> <|startoftranscript|> <|emo:undefined|> <|xx|> <|xx|>
    /// <|pnc|> <|noitn|> <|notimestamp|> <|nodiarize|>. Nil when the vocabulary has no token for the language.
    nonisolated static func prompt(for language: String, tokenizer: Tokenizer) -> [Int32]? {
        let english = CanaryConfig.promptEnTranscribePnc
        guard let token = tokenizer.vocabulary.first(where: { $0.value == "<|\(language)|>" })?.key else { return nil }
        return english.prefix(4) + [Int32(token), Int32(token)] + english.suffix(4)
    }

    @concurrent
    private nonisolated static func transcript(of audioURL: URL, manager: CanaryManager) async throws -> String {
        let samples = try AudioConverter().resampleAudioFile(audioURL)
        try Task.checkCancellation()
        // Like Whisper, an encoder-decoder model can write words for digital silence.
        guard WhisperKitProvider.containsSignal(in: samples) else { return "" }
        // FluidAudio splits audio longer than 15 seconds into overlapping windows and merges them.
        let text = try await manager.transcribe(audio: samples)
        try Task.checkCancellation()
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
