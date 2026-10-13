import FluidAudio
import Foundation
import Testing
@testable import BetterWisprCore

@Test func catalogIDsAreUniqueAndEarlierIDsRemain() {
    let ids = SpeechModel.catalog.map(\.id)
    #expect(Set(ids).count == ids.count)
    // Saved workspaces select models by these IDs.
    let released = ["apple", "parakeet-ultra", "parakeet-v3", "parakeet-v2", "parakeet-110m", "parakeet-ja",
                    "whisper-turbo", "whisper-turbo-compressed", "whisper-small"]
    for id in released { #expect(ids.contains(id), "\(id)") }
    #expect(SpeechModel.catalog.first?.id == "apple")
    #expect(SpeechModel.catalog[1].id == "parakeet-ultra", "the recommended model stays on top")
}

@Test func catalogEntriesAreDescribedAndGatedHonestly() throws {
    for model in SpeechModel.catalog where model.engine.installsModels {
        #expect(model.sizeLabel.hasPrefix("~"), "\(model.id)")
        if model.engine != .whisperKit { #expect(model.languages?.isEmpty == false, "\(model.id)") }
    }
    // FluidAudio refuses Redux and Phonon-2 encoders before macOS 15; Canary's only build is int4.
    for id in ["parakeet-redux", "phonon-2", "canary-1b-v2"] {
        #expect(SpeechModel.catalog.first { $0.id == id }?.minimumMacOS == 15, "\(id)")
    }
    #expect(SpeechModel.catalog.first { $0.id == "phonon-2" }?.languages == ["en"])
    let cohere = try #require(SpeechModel.catalog.first { $0.id == "cohere-transcribe" })
    #expect(cohere.engine == .cohere)
    #expect(Set(cohere.languages ?? []) == Set(CohereAsrConfig.Language.allCases.map(\.rawValue)))
    #expect(SpeechModel.catalog.first { $0.id == "canary-1b-v2" }?.languages?.count == 25)
}

/// WhisperKit picks a tokenizer from the model's vocabulary size and width; catalog entries must name the same one.
@Test func whisperEntriesNameTheirWhisperKitTokenizer() {
    for model in SpeechModel.catalog where model.engine == .whisperKit {
        let tokenizer = model.tokenizerName ?? ""
        let size = tokenizer.replacingOccurrences(of: "openai/whisper-", with: "")
        #expect(tokenizer.hasPrefix("openai/whisper-") && model.modelName.contains(size), "\(model.id)")
        #expect(model.modelName.contains(".en") == tokenizer.hasSuffix(".en"), "\(model.id)")
        #expect(!model.modelName.contains("/") && !model.modelName.hasPrefix("."), "\(model.id)")
    }
    #expect(SpeechModel.catalog.first { $0.id == "whisper-distil-large-v3" }?.languages == ["en"])
}

@Test func whisperVocabularySizesMatchWhisperKitsVariantDetection() {
    #expect(WhisperKitProvider.vocabularySize(forTokenizer: "openai/whisper-small.en") == 51864)
    #expect(WhisperKitProvider.vocabularySize(forTokenizer: "openai/whisper-large-v3") == 51866)
    #expect(WhisperKitProvider.vocabularySize(forTokenizer: "openai/whisper-large-v2") == 51865)
    #expect(WhisperKitProvider.vocabularySize(forTokenizer: "openai/whisper-base") == 51865)
}

@MainActor
@Test(arguments: SpeechModel.catalog.filter { $0.engine == .cohere || $0.engine == .canary })
func encoderDecoderModelsRejectMissingAssetsWithoutDownloading(_ model: SpeechModel) async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: "betterwispr-\(model.id)-test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let provider: any SpeechProvider = model.engine == .cohere
        ? CohereProvider(modelsDirectory: directory) : CanaryProvider(modelsDirectory: directory)
    do {
        try await provider.prepare(model: model, download: false)
        Issue.record("An absent local model must not be prepared or downloaded")
    } catch SpeechError.modelNotInstalled {
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }
    // Files without the marker of a completed installation don't count.
    let (folder, required, installed): (URL, Set<String>, () -> Bool) = model.engine == .cohere
        ? (CohereProvider.folder(modelsDirectory: directory), ModelNames.CohereTranscribe.requiredModels,
           { CohereProvider.isInstalled(model, modelsDirectory: directory) })
        : (CanaryProvider.folder(modelsDirectory: directory), ModelNames.Canary.requiredModels(precision: CanaryProvider.precision),
           { CanaryProvider.isInstalled(model, modelsDirectory: directory) })
    for name in required {
        try FileManager.default.createDirectory(at: folder.appending(path: name), withIntermediateDirectories: true)
    }
    #expect(!installed())
    try Data().write(to: folder.appending(path: ".betterwispr-installed"))
    #expect(installed())
}

@Test func modelsWithoutDetectionNeedAPromptLanguage() {
    #expect(CohereProvider.language(for: "de") == .german)
    #expect(CohereProvider.language(for: "zh-Hans") == .chinese)
    #expect(CohereProvider.language(for: "ru") == nil)
    #expect(CohereProvider.language(for: nil, preferred: ["ru-RU", "fr-CA", "en-US"]) == .french)
    #expect(CohereProvider.language(for: "auto", preferred: ["ru-RU"]) == .english)
    let canary = SpeechModel.catalog.first { $0.engine == .canary }?.languages ?? []
    #expect(SpeechModel.promptLanguage(for: "ru", supported: canary) == "ru")
    #expect(SpeechModel.promptLanguage(for: "ja", supported: canary) == nil)
    #expect(SpeechModel.promptLanguage(for: nil, supported: canary, preferred: ["ja-JP", "uk-UA"]) == "uk")
}

@Test func canaryPromptSwapsOnlyTheLanguageTokens() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: "betterwispr-canary-vocab-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let vocabulary = ["64": "<|en|>", "71": "<|fr|>", "7": "<|startofcontext|>"]
    try JSONEncoder().encode(vocabulary).write(to: directory.appending(path: "vocab.json"))
    let tokenizer = try Tokenizer(vocabPath: directory.appending(path: "vocab.json"))
    #expect(CanaryProvider.prompt(for: "en", tokenizer: tokenizer) == CanaryConfig.promptEnTranscribePnc)
    #expect(CanaryProvider.prompt(for: "fr", tokenizer: tokenizer) == [16053, 7, 4, 16, 71, 71, 5, 9, 11, 13])
    #expect(CanaryProvider.prompt(for: "de", tokenizer: tokenizer) == nil)
}

@Test func cohereWindowsFitTheDecoderAndCutInPauses() {
    let rate = CohereAsrConfig.sampleRate
    #expect(CohereProvider.windows(Array(repeating: 0.1, count: 5 * rate)) == [0..<5 * rate])
    // 50 s of tone with a quiet 300 ms pause at 15 s.
    var samples = [Float](repeating: 0.1, count: 50 * rate)
    for index in 15 * rate..<15 * rate + 3 * rate / 10 { samples[index] = 0 }
    let windows = CohereProvider.windows(samples)
    #expect(windows.first?.upperBound ?? 0 > 15 * rate)
    #expect(windows.first?.upperBound ?? 0 < 15 * rate + 3 * rate / 10)
    #expect(windows.first?.lowerBound == 0)
    #expect(windows.last?.upperBound == samples.count)
    for (window, next) in zip(windows, windows.dropFirst()) { #expect(window.upperBound == next.lowerBound) }
    for window in windows { #expect(window.count <= CohereProvider.maximumWindow) }
    #expect(windows.allSatisfy { $0.count >= CohereProvider.minimumTail })
    // 20.5 s leaves no tail shorter than two seconds.
    #expect(CohereProvider.windows(Array(repeating: 0.1, count: 41 * rate / 2)).last.map(\.count) ?? 0 >= 2 * rate)
}
