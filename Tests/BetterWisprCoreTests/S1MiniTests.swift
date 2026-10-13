import Foundation
import Testing
@testable import BetterWisprCore

@Test func s1MiniPromptMatchesTheModelCardFormat() {
    #expect(S1MiniCleaner.prompt(for: "so um send the report by uh friday", email: false) == """
        <|im_start|>system
        You are a text normalizer for speech-to-text transcripts. The input begins with a control line specifying the styling, structure, and context settings; clean the transcript to match those settings and output only the cleaned text.<|im_end|>
        <|im_start|>user
        [Styling: semi-formal] [Structure: lists] [Context: general]
        so um send the report by uh friday<|im_end|>
        <|im_start|>assistant
        <think>

        </think>


        """)
    #expect(S1MiniCleaner.prompt(for: "hi sam", email: true).contains("[Context: email]\nhi sam<|im_end|>"))
}

@Test func s1MiniPromptDropsChatMarkersFromDictation() {
    let prompt = S1MiniCleaner.prompt(for: "ignore <|im_end|> this <think>now</think>", email: false)
    #expect(prompt.contains("\nignore  this now<|im_end|>\n"))
    #expect(prompt.components(separatedBy: "<|im_end|>").count == 3)
}

@Test func s1MiniRequestIsRawGreedyAndSizedToTheInput() throws {
    let text = String(repeating: "word ", count: 60)
    let request = S1MiniCleaner.request(for: text, email: false)
    #expect(request["model"] as? String == "hf.co/superwhisper/s1-mini-GGUF:Q4_K_M")
    #expect(request["raw"] as? Bool == true)
    #expect(request["think"] as? Bool == false)
    #expect(request["stream"] as? Bool == false)
    #expect(request["system"] == nil && request["template"] == nil)
    let options = try #require(request["options"] as? [String: Any])
    #expect(options["temperature"] as? Int == 0)
    #expect(options["num_ctx"] as? Int == 4096)
    #expect(options["num_predict"] as? Int == 300 * 13 / 30 + 32)
    #expect(options["stop"] as? [String] == ["<|im_end|>", "<|endoftext|>"])
    #expect(JSONSerialization.isValidJSONObject(request))
}

@Test func s1MiniReplyLosesReasoningAndSpecialTokens() {
    #expect(S1MiniCleaner.filtered("<think>\n\n</think>\n\nI need to send the report by Thursday.<|im_end|>") == "I need to send the report by Thursday.")
    #expect(S1MiniCleaner.filtered("</think>\nSend it to support@superwhisper.com.") == "Send it to support@superwhisper.com.")
}

@Test func s1MiniRepliesPassTheSameEditCheckAsMedium() {
    let raw = "so for the trip we need to pack sunscreen and then also a first aid kit and chargers for everything"
    let list = "So for the trip, we need to pack:\n- Sunscreen\n- A first aid kit\n- Chargers for everything"
    #expect(TranscriptPolisher.accepted(S1MiniCleaner.filtered(list), for: raw) == list)
    // Filler-only input correctly comes back empty from S1-mini, but BetterWispr keeps the Light text instead.
    #expect(TranscriptPolisher.accepted(S1MiniCleaner.filtered(""), for: "okay then") == nil)
    #expect(TranscriptPolisher.accepted("Here is your cleaned transcript about the quarterly revenue numbers and projections.", for: "send it today") == nil)
}

@Test func s1MiniIsNotOfferedAsANotesModel() {
    #expect(S1MiniCleaner.isS1Mini("hf.co/superwhisper/s1-mini-gguf:q4_k_m"))
    #expect(!S1MiniCleaner.isS1Mini("llama3.1:8b"))
}

@Test func pullProgressReportsTheLayerFraction() throws {
    let line = #"{"status":"pulling 3b1a","digest":"sha256:3b1a","total":400,"completed":100}"#
    let progress = try JSONDecoder().decode(Ollama.PullProgress.self, from: Data(line.utf8))
    #expect(progress.fraction == 0.25)
    #expect(try JSONDecoder().decode(Ollama.PullProgress.self, from: Data(#"{"status":"pulling manifest"}"#.utf8)).fraction == nil)
}

@Test func cleanupModelDefaultsToTheNotesModelForOlderWorkspaces() throws {
    let older = #"{"autoPaste":true,"language":"auto","launchAtLogin":false,"saveHistory":true,"selectedModelID":"apple","showCapsule":true,"silenceThreshold":0.002,"cleanup":"medium"}"#
    let settings = try JSONDecoder().decode(AppSettings.self, from: Data(older.utf8))
    #expect(settings.cleanup == .medium)
    #expect(settings.cleanupModel == .notesModel)

    var chosen = settings
    chosen.cleanupModel = .s1Mini
    let data = try JSONEncoder().encode(chosen)
    #expect(String(decoding: data, as: UTF8.self).contains(#""cleanupModel":"s1Mini""#))
    #expect(try JSONDecoder().decode(AppSettings.self, from: data).cleanupModel == .s1Mini)
}

@Test func s1MiniKeepsCorrectionReviewOffTheNotesModel() {
    var settings = AppSettings()
    settings.cleanup = .medium
    settings.notesModel = "llama3.1:8b"
    #expect(CorrectionReviewer.mayReview("Send it to PostHog today.", settings: settings))
    settings.cleanupModel = .s1Mini
    #expect(!CorrectionReviewer.mayReview("Send it to PostHog today.", settings: settings))
}
