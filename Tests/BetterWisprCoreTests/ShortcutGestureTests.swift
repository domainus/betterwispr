import BetterWisprCore
import Testing

@Test func holdingTalksAndReleasingFinishes() {
    var gesture = ShortcutGesture()
    #expect(gesture.press(at: 10, mode: .hold, session: .idle) == .startHeld)
    #expect(gesture.press(at: 10.5, mode: .hold, session: .recording) == .ignore) // Repeat while held.
    #expect(gesture.release(at: 12, session: .recording) == .finish)
    #expect(gesture.release(at: 12.1, session: .transcribing) == .ignore)
}

@Test func releasingAHoldBeforeTheMicrophoneIsReadyAbandons() {
    var gesture = ShortcutGesture()
    _ = gesture.press(at: 0, mode: .hold, session: .idle)
    #expect(gesture.release(at: 0.8, session: .preparing) == .abandonEarly)
}

@Test func aQuickTapLocksHandsFreeAndALaterPressFinishes() {
    var gesture = ShortcutGesture()
    _ = gesture.press(at: 0, mode: .hold, session: .idle)
    #expect(gesture.release(at: 0.15, session: .preparing) == .lockHandsFree)
    #expect(gesture.press(at: 3, mode: .hold, session: .recording) == .finish)
    #expect(gesture.release(at: 3.1, session: .transcribing) == .ignore)
}

@Test func doubleTapKeepsRecordingThroughTheSecondPressAndRelease() {
    var gesture = ShortcutGesture()
    _ = gesture.press(at: 0, mode: .hold, session: .idle)
    #expect(gesture.release(at: 0.12, session: .recording) == .lockHandsFree)
    #expect(gesture.press(at: 0.4, mode: .hold, session: .recording) == .ignore)
    #expect(gesture.release(at: 2, session: .recording) == .ignore) // Even after holding the second press.
    #expect(gesture.press(at: 5, mode: .hold, session: .recording) == .finish)
}

@Test func aPressAfterTheDoubleTapWindowFinishes() {
    var gesture = ShortcutGesture()
    _ = gesture.press(at: 0, mode: .hold, session: .idle)
    _ = gesture.release(at: 0.1, session: .recording)
    #expect(gesture.press(at: 0.5, mode: .hold, session: .recording) == .finish)
}

@Test func onlyTheSecondPressOfADoubleTapIsIgnored() {
    var gesture = ShortcutGesture()
    _ = gesture.press(at: 0, mode: .hold, session: .idle)
    _ = gesture.release(at: 0.1, session: .recording)
    #expect(gesture.press(at: 0.2, mode: .hold, session: .recording) == .ignore)
    _ = gesture.release(at: 0.25, session: .recording)
    #expect(gesture.press(at: 0.35, mode: .hold, session: .recording) == .finish)
}

@Test func aPressWhilePreparingOrTranscribingDoesNothing() {
    var gesture = ShortcutGesture()
    _ = gesture.press(at: 0, mode: .hold, session: .idle)
    _ = gesture.release(at: 0.1, session: .preparing)
    #expect(gesture.press(at: 2, mode: .hold, session: .preparing) == .ignore)
    #expect(gesture.press(at: 4, mode: .toggle, session: .transcribing) == .ignore)
}

@Test func toggleModeStartsAndFinishesButIgnoresADoubleTap() {
    var gesture = ShortcutGesture()
    #expect(gesture.press(at: 0, mode: .toggle, session: .idle) == .startHandsFree)
    #expect(gesture.release(at: 0.1, session: .preparing) == .ignore)
    #expect(gesture.press(at: 0.3, mode: .toggle, session: .recording) == .ignore)
    #expect(gesture.release(at: 0.4, session: .recording) == .ignore)
    #expect(gesture.press(at: 3, mode: .toggle, session: .recording) == .finish)

    // A long first press is not a tap, so a quick second press still finishes.
    #expect(gesture.press(at: 10, mode: .toggle, session: .idle) == .startHandsFree)
    _ = gesture.release(at: 11, session: .recording)
    #expect(gesture.press(at: 11.1, mode: .toggle, session: .recording) == .finish)
}

@Test func aSessionThatEndedBeforeTheReleaseIgnoresIt() {
    var gesture = ShortcutGesture()
    _ = gesture.press(at: 0, mode: .hold, session: .idle)
    #expect(gesture.release(at: 0.1, session: .idle) == .ignore) // For example, the model was missing.
    #expect(gesture.press(at: 0.2, mode: .hold, session: .idle) == .startHeld)
}

@Test func resetForgetsAPendingDoubleTap() {
    var gesture = ShortcutGesture()
    _ = gesture.press(at: 0, mode: .hold, session: .idle)
    _ = gesture.release(at: 0.1, session: .recording)
    gesture.reset()
    #expect(gesture.press(at: 0.2, mode: .hold, session: .recording) == .finish)
}
