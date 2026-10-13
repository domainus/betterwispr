import Foundation

/// Turns presses and releases of the dictation shortcut into dictation actions.
///
/// Hold mode: hold to talk and release to finish. A quick tap keeps recording
/// hands-free, and the next press finishes. Toggle mode: one press starts and the
/// next press finishes. In both modes, the second press of a double-tap (a press
/// soon after the starting tap is released) keeps recording, and so does its release.
public struct ShortcutGesture: Sendable {
    /// The dictation phase when the event arrives. Any phase that is not busy is `idle`.
    public enum Session: Sendable { case idle, preparing, recording, transcribing }

    public enum Action: Equatable, Sendable {
        /// Start push-to-talk; the release decides what happens next.
        case startHeld
        /// Start a session that records until the next press.
        case startHandsFree
        /// A quick tap released a held session; keep recording without holding.
        case lockHandsFree
        case finish
        /// Released after holding but before the microphone was ready.
        case abandonEarly
        case ignore
    }

    /// A press released sooner than this is a tap, not a hold.
    public static let tapDuration: TimeInterval = 0.3
    /// A press this soon after a tap's release is the second press of a double-tap.
    /// With a typical 0.15 s tap, this matches Wispr Flow's half second from the first press.
    public static let doubleTapWindow: TimeInterval = 0.35

    /// The press that started the current session, until it is released.
    private var startingPress: (time: TimeInterval, held: Bool)?
    /// When the tap that started the current session was released.
    private var tapReleasedAt: TimeInterval?

    public init() {}

    /// `time` is any monotonic clock in seconds, such as `ProcessInfo.systemUptime`.
    public mutating func press(at time: TimeInterval, mode: DictationMode, session: Session) -> Action {
        if session == .idle {
            startingPress = (time, mode == .hold)
            tapReleasedAt = nil
            return mode == .hold ? .startHeld : .startHandsFree
        }
        // The starting press is still down, so this is a repeat.
        guard startingPress == nil else { return .ignore }
        if let released = tapReleasedAt.take(), time - released <= Self.doubleTapWindow { return .ignore }
        return session == .recording ? .finish : .ignore
    }

    public mutating func release(at time: TimeInterval, session: Session) -> Action {
        guard let press = startingPress.take(), session == .preparing || session == .recording else { return .ignore }
        let isTap = time - press.time < Self.tapDuration
        if isTap { tapReleasedAt = time }
        guard press.held else { return .ignore }
        if isTap { return .lockHandsFree }
        return session == .preparing ? .abandonEarly : .finish
    }

    /// Forgets the current gesture, for example after a cancellation.
    public mutating func reset() {
        startingPress = nil
        tapReleasedAt = nil
    }
}
