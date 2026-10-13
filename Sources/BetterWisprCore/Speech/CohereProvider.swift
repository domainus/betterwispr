import FluidAudio
import Foundation

/// Cohere Transcribe 03-2026 through FluidAudio's Core ML pipeline: an INT8 encoder and a cache-external decoder.
@MainActor
public final class CohereProvider: SpeechProvider {
    public var onProgress: (@MainActor @Sendable (Double) -> Void)?
    public var onPartialTranscript: (@MainActor @Sendable (String) -> Void)?
    private let modelsDirectory: URL
    private var models: CoherePipeline.LoadedModels?
    private var loadedModelID: String?
    private var preparing = false
    private var transcriptionTask: Task<String, any Error>?

    nonisolated static let repo = Repo.cohereTranscribeCoreml
    /// The decoder holds 108 tokens, prompt included, per call. Windows this long keep ordinary speech well below it.
    nonisolated static let maximumWindow = 20 * CohereAsrConfig.sampleRate
    nonisolated static let earliestCut = 12 * CohereAsrConfig.sampleRate
    nonisolated static let minimumTail = 2 * CohereAsrConfig.sampleRate

    public init(modelsDirectory: URL = WhisperKitProvider.defaultModelsDirectory) {
        self.modelsDirectory = modelsDirectory
    }

    /// `ModelHub.download` places the repository's `q8` files in `Cohere/cohere-transcribe/q8`.
    nonisolated static func folder(modelsDirectory: URL) -> URL {
        modelsDirectory.appending(path: "Cohere/\(repo.folderName)", directoryHint: .isDirectory)
    }

    public static func isInstalled(_ model: SpeechModel, modelsDirectory: URL = WhisperKitProvider.defaultModelsDirectory) -> Bool {
        guard model.engine == .cohere else { return false }
        let folder = folder(modelsDirectory: modelsDirectory)
        return ([".betterwispr-installed"] + ModelNames.CohereTranscribe.requiredModels).allSatisfy {
            FileManager.default.fileExists(atPath: folder.appending(path: $0).path)
        }
    }

    public func prepare(model: SpeechModel, download: Bool) async throws {
        guard model.engine == .cohere else { throw SpeechError.invalidModel }
        guard !preparing, transcriptionTask == nil else { throw SpeechError.busy }
        if loadedModelID == model.id, models != nil { onProgress?(1); return }
        preparing = true
        defer { preparing = false }
        try Task.checkCancellation()
        let folder = Self.folder(modelsDirectory: modelsDirectory)
        if download && !Self.isInstalled(model, modelsDirectory: modelsDirectory) {
            let parent = modelsDirectory.appending(path: "Cohere", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            onProgress?(0)
            let progress = onProgress
            try await ModelHub.download(Self.repo, to: parent) { value in
                let fraction = ParakeetProvider.downloadedFraction(value) * 0.9
                Task { @MainActor in progress?(fraction) }
            }
            try Task.checkCancellation()
        }
        guard download || Self.isInstalled(model, modelsDirectory: modelsDirectory) else { throw SpeechError.modelNotInstalled(model.name) }
        onProgress?(0.95)
        models = nil
        loadedModelID = nil
        // Loads the compiled models and vocabulary from this folder only; it never downloads.
        let loaded = try await CoherePipeline.loadModels(encoderDir: folder, decoderDir: folder, vocabDir: folder)
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
        guard let spoken = Self.language(for: language) else {
            throw SpeechError.unsupportedLanguage(model: "Cohere Transcribe", language: language ?? "")
        }
        try Task.checkCancellation()
        let task = Task { try await Self.transcript(of: audioURL, language: spoken, models: models) }
        transcriptionTask = task
        defer { transcriptionTask = nil }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }

    public func cancel() {
        transcriptionTask?.cancel()
    }

    /// The prompt language for a spoken-language setting; see `SpeechModel.promptLanguage`.
    nonisolated static func language(for code: String?, preferred: [String] = Locale.preferredLanguages) -> CohereAsrConfig.Language? {
        let supported = CohereAsrConfig.Language.allCases.map(\.rawValue)
        return SpeechModel.promptLanguage(for: code, supported: supported, preferred: preferred).flatMap(CohereAsrConfig.Language.init(rawValue:))
    }

    /// Splits audio into windows of at most `maximumWindow` samples, cutting at the quietest 100 ms after `earliestCut`
    /// and leaving no tail shorter than `minimumTail`, so words are rarely split and each window fits the decoder.
    nonisolated static func windows(_ samples: [Float]) -> [Range<Int>] {
        let frame = CohereAsrConfig.sampleRate / 10
        var windows: [Range<Int>] = []
        var start = 0
        while samples.count - start > maximumWindow {
            let end = min(start + maximumWindow, samples.count - minimumTail)
            var cut = end
            var quietest = Float.infinity
            var frameStart = start + earliestCut
            while frameStart + frame <= end {
                let energy = samples[frameStart..<frameStart + frame].reduce(0) { $0 + $1 * $1 }
                if energy < quietest {
                    quietest = energy
                    cut = frameStart + frame / 2
                }
                frameStart += frame
            }
            windows.append(start..<cut)
            start = cut
        }
        windows.append(start..<samples.count)
        return windows
    }

    @concurrent
    private nonisolated static func transcript(
        of audioURL: URL, language: CohereAsrConfig.Language, models: CoherePipeline.LoadedModels
    ) async throws -> String {
        let samples = try AudioConverter().resampleAudioFile(audioURL)
        try Task.checkCancellation()
        // Like Whisper, an encoder-decoder model can write words for digital silence.
        guard WhisperKitProvider.containsSignal(in: samples) else { return "" }
        let pipeline = CoherePipeline()
        var parts: [String] = []
        for window in windows(samples) {
            try Task.checkCancellation()
            let result = try await pipeline.transcribe(audio: Array(samples[window]), models: models, language: language)
            parts.append(result.text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        try Task.checkCancellation()
        let separator = language == .japanese || language == .chinese ? "" : " "
        return parts.filter { !$0.isEmpty }.joined(separator: separator)
    }
}
