import BetterWisprCore
import SwiftUI

/// Whether S1-mini is ready in Ollama, and the download the user started. Owned by `AppModel` so a download
/// keeps going when the Style page closes.
@MainActor @Observable
final class S1MiniSetup {
    enum State: Equatable {
        case checking, ollamaNotRunning, notInstalled, ready
        case downloading(fraction: Double?, status: String)
        case failed(String)
    }

    private(set) var state = State.checking
    @ObservationIgnored private var download: Task<Void, Never>?

    func refresh() async {
        guard download == nil else { return }
        state = switch await S1MiniCleaner.status() {
        case .ollamaNotRunning: .ollamaNotRunning
        case .notInstalled: .notInstalled
        case .ready: .ready
        }
    }

    /// Runs only from the Download button; nothing else pulls the model.
    func startDownload() {
        guard download == nil else { return }
        state = .downloading(fraction: nil, status: "Starting download…")
        download = Task {
            do {
                try await Ollama.pull(S1MiniCleaner.model) { progress in
                    self.state = .downloading(fraction: progress.fraction, status: progress.status)
                }
                download = nil
                await refresh()
            } catch {
                download = nil
                if Task.isCancelled { await refresh() } else { state = .failed(error.localizedDescription) }
            }
        }
    }

    func cancelDownload() {
        download?.cancel()
    }
}

/// S1-mini's status, download controls and license, shown in Style when Medium cleanup uses it.
struct S1MiniSettings: View {
    let setup: S1MiniSetup

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Label(statusText, systemImage: statusSymbol)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                action
            }
            if case .downloading(let fraction, _) = setup.state {
                ProgressView(value: fraction)
                    .accessibilityLabel("Downloading S1-mini")
            }
            Text("Cleans English punctuation, capitals, numbers, lists and email layout. It doesn’t take your vocabulary, screen context or mode instructions; vocabulary still applies afterwards.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Link("S1-mini by Superwhisper · \(S1MiniCleaner.licenseName)", destination: S1MiniCleaner.licenseURL)
                .font(.callout)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .task { await setup.refresh() }
    }

    @ViewBuilder private var action: some View {
        switch setup.state {
        case .checking: ProgressView().controlSize(.small)
        case .ollamaNotRunning: Button("Check Again") { Task { await setup.refresh() } }
        case .notInstalled, .failed: Button("Download S1-mini", action: setup.startDownload)
        case .downloading: Button("Cancel", action: setup.cancelDownload)
        case .ready: EmptyView()
        }
    }

    private var statusText: String {
        switch setup.state {
        case .checking: "Checking Ollama…"
        case .ollamaNotRunning: "Ollama isn’t running. Install or open Ollama, then check again. Until then, Medium dictations get Light cleanup."
        case .notInstalled: "S1-mini isn’t downloaded. Download saves about 460 MB from Hugging Face into Ollama. Until then, Medium dictations get Light cleanup."
        case .downloading(let fraction, let status):
            fraction.map { "Downloading S1-mini… \($0.formatted(.percent.precision(.fractionLength(0))))" } ?? status.prefix(1).uppercased() + status.dropFirst()
        case .failed(let message): "Download stopped: \(message)"
        case .ready: "Ready on this Mac through Ollama."
        }
    }

    private var statusSymbol: String {
        switch setup.state {
        case .ready: "checkmark.circle"
        case .checking, .downloading: "arrow.down.circle"
        case .ollamaNotRunning, .notInstalled, .failed: "exclamationmark.triangle"
        }
    }
}
