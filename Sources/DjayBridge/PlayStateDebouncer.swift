import Foundation

public struct PlayStateDebouncer {
    private var rawState: Bool = false
    private var reportedState: Bool = false
    private var lastRawChangeTime: Date = .distantPast
    private let threshold: TimeInterval

    public init(threshold: TimeInterval = 1.2) {
        self.threshold = threshold
    }

    /// Returns the debounced play state.
    /// Paused-to-playing requires `threshold` seconds of sustained `true` to avoid cue-preview false positives.
    /// Playing-to-paused is immediate.
    public mutating func update(isPlaying: Bool) -> Bool {
        if isPlaying != rawState {
            rawState = isPlaying
            lastRawChangeTime = Date()
        }

        if rawState && !reportedState {
            // Paused -> playing: require sustained true
            if Date().timeIntervalSince(lastRawChangeTime) >= threshold {
                reportedState = true
            }
        } else if !rawState && reportedState {
            // Playing -> paused: immediate
            reportedState = false
        }

        return reportedState
    }
}
