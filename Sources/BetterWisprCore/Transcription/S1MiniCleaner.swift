import Foundation

/// Medium cleanup with S1-mini by Superwhisper, a 0.6B English transcript normalizer, through the local Ollama server.
/// It takes only the transcript and a control line, so vocabulary, screen context and mode instructions are not sent.
/// See docs/s1-mini.md for the model card's input format and license.
public enum S1MiniCleaner {
    /// The Q4_K_M build, on which the model card measured its accuracy.
    public static let model = "hf.co/superwhisper/s1-mini-GGUF:Q4_K_M"
    public static let licenseName = "Apache 2.0 with the S1-mini naming term"
    public static let licenseURL = URL(string: "https://huggingface.co/superwhisper/s1-mini/blob/main/LICENSE")!
    /// The model card requires this exact wording.
    static let system = "You are a text normalizer for speech-to-text transcripts. The input begins with a control line specifying the styling, structure, and context settings; clean the transcript to match those settings and output only the cleaned text."
    /// The GGUF card's Ollama context length; warm-up sends the same so Ollama doesn't load the model twice.
    static let contextLength = 4096
    /// Keeps one pass under the card's ~1,000-token guidance; a 2-minute dictation stays below it.
    static let wordLimit = 700

    public enum Status: Equatable, Sendable {
        case ollamaNotRunning, notInstalled, ready
    }

    /// Asks Ollama which models are on this Mac. Never downloads anything.
    public static func status() async -> Status {
        guard let data = try? await Ollama.send("tags", timeout: 3),
              let tags = try? JSONDecoder().decode(Ollama.Tags.self, from: data) else { return .ollamaNotRunning }
        return tags.localNames.contains(where: isS1Mini) ? .ready : .notInstalled
    }

    static func isS1Mini(_ name: String) -> Bool {
        name.caseInsensitiveCompare(model) == .orderedSame
    }

    /// Cleans English dictation; nil keeps the Light text. Fails fast when Ollama isn't running or S1-mini isn't installed,
    /// because Ollama's API never downloads a missing model for a generate request.
    public static func clean(_ text: String, email: Bool) async -> String? {
        let words = text.split(whereSeparator: \.isWhitespace).count
        guard (1...wordLimit).contains(words),
              let data = try? await Ollama.send("generate", request(for: text, email: email), timeout: TimeInterval(10 + words / 10)),
              let reply = try? JSONDecoder().decode(Reply.self, from: data) else { return nil }
        return TranscriptPolisher.accepted(filtered(reply.response), for: text)
    }

    /// Loads S1-mini into memory with an empty prompt, which generates nothing.
    public static func warmUp() async {
        _ = try? await Ollama.send("generate", ["model": model, "options": ["num_ctx": contextLength]], timeout: 60)
    }

    /// A raw prompt in the card's literal format, so the result doesn't depend on the template Ollama picks for the GGUF.
    /// `think: false` keeps Ollama's thinking parser off; greedy decoding as the card requires.
    static func request(for text: String, email: Bool) -> [String: Any] {
        ["model": model, "prompt": prompt(for: text, email: email), "raw": true, "think": false, "stream": false,
         "options": ["temperature": 0, "num_ctx": contextLength, "num_predict": tokenLimit(for: text),
                     "stop": ["<|im_end|>", "<|endoftext|>"]] as [String: Any]]
    }

    /// Semi-formal is the card's default and BetterWispr's Formal tone; the app's tone is applied afterwards.
    static func prompt(for text: String, email: Bool) -> String {
        let control = "[Styling: semi-formal] [Structure: lists] [Context: \(email ? "email" : "general")]"
        return "<|im_start|>system\n\(system)<|im_end|>\n<|im_start|>user\n\(control)\n\(escaped(text))<|im_end|>\n"
            + "<|im_start|>assistant\n<think>\n\n</think>\n\n"
    }

    /// The card's `1.3 × input tokens + 32`, guessing a token per 3 characters so the limit errs high.
    static func tokenLimit(for text: String) -> Int {
        text.count * 13 / 30 + 32
    }

    /// Removes chat-format markers so dictated text can't end the user turn early.
    static func escaped(_ text: String) -> String {
        text.replacing(#/<\|[a-z_]+\|>|</?think>/#, with: "")
    }

    /// Strips reasoning blocks, stray think tags and special tokens from a reply.
    static func filtered(_ reply: String) -> String {
        escaped(TranscriptPolisher.filtered(reply)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    struct Reply: Decodable { let response: String }
}
