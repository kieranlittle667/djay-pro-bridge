import DjayBridge
import AVFoundation
import AppKit
import Foundation

enum SpeechBackend {
    case auto
    case say
    case voiceOver
    case avSpeech
}

final class SpeechCoordinator: NSObject {
    private let synthesizer = AVSpeechSynthesizer()
    private let preferredVoiceName: String?
    private let rate: Float
    private let queue = DispatchQueue(label: "speech-coordinator")
    private var lastSpokenAtByKey: [String: Date] = [:]
    private let logAnnouncements: Bool
    private let backend: SpeechBackend

    init(
        preferredVoiceName: String? = nil,
        rate: Float = 0.42,
        logAnnouncements: Bool = true,
        backend: SpeechBackend = .say
    ) {
        self.preferredVoiceName = preferredVoiceName
        self.rate = rate
        self.logAnnouncements = logAnnouncements
        self.backend = backend
        super.init()
    }

    func speak(_ text: String, key: String, minInterval: TimeInterval = 0.75) {
        queue.async {
            let now = Date()
            if let last = self.lastSpokenAtByKey[key], now.timeIntervalSince(last) < minInterval {
                return
            }
            self.lastSpokenAtByKey[key] = now

            if self.logAnnouncements {
                print("ANNOUNCE: \(text)")
                fflush(stdout)
            }

            switch self.backend {
            case .say:
                _ = self.speakWithSay(text)
            case .voiceOver:
                if !self.postVoiceOverAnnouncement(text) {
                    _ = self.speakWithSay(text)
                }
            case .avSpeech:
                self.speakWithSystemVoice(text)
            case .auto:
                if self.isVoiceOverRunning(), self.postVoiceOverAnnouncement(text) {
                    return
                }
                if self.speakWithSay(text) {
                    return
                }
                self.speakWithSystemVoice(text)
            }
        }
    }

    private func isVoiceOverRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.apple.VoiceOver" ||
            $0.localizedName == "VoiceOver"
        }
    }

    @discardableResult
    private func postVoiceOverAnnouncement(_ text: String) -> Bool {
        let userInfo: [NSAccessibility.NotificationUserInfoKey: Any] = [
            .announcement: text,
            .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ]
        NSAccessibility.post(
            element: self,
            notification: .announcementRequested,
            userInfo: userInfo
        )
        return true
    }

    @discardableResult
    private func speakWithSay(_ text: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        var arguments: [String] = []
        if let preferredVoiceName, !preferredVoiceName.isEmpty {
            arguments += ["-v", preferredVoiceName]
        }
        arguments.append(text)
        process.arguments = arguments
        do {
            try process.run()
            return true
        } catch {
            printError("⚠️ Failed to run say: \(error)")
            return false
        }
    }

    private func speakWithSystemVoice(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = rate
        utterance.voice = resolveVoice()
        synthesizer.speak(utterance)
    }

    private func resolveVoice() -> AVSpeechSynthesisVoice? {
        guard let preferredVoiceName else { return nil }
        return AVSpeechSynthesisVoice.speechVoices().first {
            $0.name.caseInsensitiveCompare(preferredVoiceName) == .orderedSame
        }
    }
}

final class DeckAnnouncer {
    private let speaker: SpeechCoordinator
    private var previousDecks: [Int: DeckInfo] = [:]
    private var hasSeeded = false

    init(speaker: SpeechCoordinator) {
        self.speaker = speaker
    }

    func process(deckNumber: Int, deck: DeckInfo) {
        defer { previousDecks[deckNumber] = deck }

        guard hasSeeded else { return }
        let previous = previousDecks[deckNumber] ?? DeckInfo()

        announceTrackChange(deckNumber: deckNumber, previous: previous, current: deck)
        announcePlayState(deckNumber: deckNumber, previous: previous, current: deck)
        announceLoopChange(deckNumber: deckNumber, previous: previous, current: deck)
        announceFXChanges(deckNumber: deckNumber, previous: previous, current: deck)
    }

    func seedCompleted() {
        hasSeeded = true
    }

    private func announceTrackChange(deckNumber: Int, previous: DeckInfo, current: DeckInfo) {
        guard let title = current.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty,
              title != previous.title else { return }
        let trimmedArtist = current.artist?.trimmingCharacters(in: .whitespacesAndNewlines)
        let artistPart = (trimmedArtist?.isEmpty == false) ? trimmedArtist : nil
        let message = artistPart.map { "Deck \(deckNumber) loaded \(title) by \($0)" } ?? "Deck \(deckNumber) loaded \(title)"
        speaker.speak(message, key: "deck\(deckNumber)-track", minInterval: 1.25)
    }

    private func announcePlayState(deckNumber: Int, previous: DeckInfo, current: DeckInfo) {
        guard previous.isPlaying != current.isPlaying else { return }
        let state = current.isPlaying ? "playing" : "paused"
        speaker.speak("Deck \(deckNumber) \(state)", key: "deck\(deckNumber)-play", minInterval: 0.4)
    }

    private func announceLoopChange(deckNumber: Int, previous: DeckInfo, current: DeckInfo) {
        guard let loop = current.loopSize?.trimmingCharacters(in: .whitespacesAndNewlines), !loop.isEmpty,
              loop != previous.loopSize else { return }
        speaker.speak("Deck \(deckNumber) loop \(loop)", key: "deck\(deckNumber)-loop", minInterval: 0.5)
    }

    private func announceFXChanges(deckNumber: Int, previous: DeckInfo, current: DeckInfo) {
        let slots = Set(previous.fxSlots.keys).union(current.fxSlots.keys)
        for slot in slots.sorted() {
            let old = previous.fxSlots[slot] ?? FXSlotInfo()
            let new = current.fxSlots[slot] ?? FXSlotInfo()

            if let name = new.parameterName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
               name != old.parameterName {
                speaker.speak("Deck \(deckNumber) FX \(slot) \(name)", key: "deck\(deckNumber)-fx\(slot)-name", minInterval: 0.5)
            }

            if let enabled = new.isEnabled, enabled != old.isEnabled {
                speaker.speak(
                    "Deck \(deckNumber) FX \(slot) \(enabled ? "on" : "off")",
                    key: "deck\(deckNumber)-fx\(slot)-enabled",
                    minInterval: 0.35
                )
            }
        }
    }
}
