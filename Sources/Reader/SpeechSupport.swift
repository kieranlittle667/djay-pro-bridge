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
    private let speechQueue = DispatchQueue(label: "speech-coordinator")
    private let schedulerQueue = DispatchQueue(label: "speech-scheduler")
    private var lastSpokenAtByKey: [String: Date] = [:]
    private var pendingWorkByKey: [String: DispatchWorkItem] = [:]
    private var generationByKey: [String: Int] = [:]
    private let logAnnouncements: Bool
    private let backend: SpeechBackend
    private let minimumGap: TimeInterval

    init(
        preferredVoiceName: String? = nil,
        rate: Float = 0.42,
        logAnnouncements: Bool = true,
        backend: SpeechBackend = .auto,
        minimumGap: TimeInterval = 0.08
    ) {
        self.preferredVoiceName = preferredVoiceName
        self.rate = rate
        self.logAnnouncements = logAnnouncements
        self.backend = backend
        self.minimumGap = minimumGap
        super.init()
    }

    func speak(
        _ text: String,
        key: String,
        minInterval: TimeInterval = 0.75,
        coalesce: Bool = false,
        settleDelay: TimeInterval = 0
    ) {
        if coalesce || settleDelay > 0 {
            schedulerQueue.async {
                if self.pendingWorkByKey[key] != nil {
                    Logger.shared.log("COALESCE replace key=\(key) text=\(text)")
                }
                self.pendingWorkByKey[key]?.cancel()

                let generation = (self.generationByKey[key] ?? 0) + 1
                self.generationByKey[key] = generation

                var work: DispatchWorkItem?
                work = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    guard let work else { return }

                    if work.isCancelled {
                        Logger.shared.log("DROP cancelled key=\(key) text=\(text)")
                        return
                    }
                    guard self.generationByKey[key] == generation else {
                        Logger.shared.log("DROP stale_generation key=\(key) text=\(text)")
                        return
                    }

                    self.pendingWorkByKey[key] = nil
                    self.enqueueSpeech(text, key: key, minInterval: minInterval, generation: generation)
                }

                self.pendingWorkByKey[key] = work
                self.schedulerQueue.asyncAfter(deadline: .now() + max(settleDelay, minInterval), execute: work!)
            }
        } else {
            enqueueSpeech(text, key: key, minInterval: minInterval, generation: nil)
        }
    }

    private func enqueueSpeech(_ text: String, key: String, minInterval: TimeInterval, generation: Int?) {
        speechQueue.async {
            if let generation, self.generationByKey[key] != generation {
                Logger.shared.log("DROP stale_before_speak key=\(key) text=\(text)")
                return
            }

            let now = Date()
            if let last = self.lastSpokenAtByKey[key], now.timeIntervalSince(last) < minInterval {
                Logger.shared.log("DROP rate_limit key=\(key) text=\(text)")
                return
            }
            self.lastSpokenAtByKey[key] = now

            if self.logAnnouncements {
                print("ANNOUNCE: \(text)")
                fflush(stdout)
                Logger.shared.log("ANNOUNCE key=\(key) text=\(text)")
            }

            switch self.backend {
            case .say:
                _ = self.speakWithSay(text)
            case .voiceOver:
                if !self.speakWithVoiceOver(text) {
                    _ = self.speakWithSay(text)
                }
            case .avSpeech:
                self.speakWithSystemVoice(text)
            case .auto:
                if self.isVoiceOverRunning(), self.speakWithVoiceOver(text) {
                    return
                }
                if self.speakWithSay(text) {
                    return
                }
                self.speakWithSystemVoice(text)
            }
        }
    }

    private func estimatedDuration(for text: String) -> TimeInterval {
        let words = max(1, text.split(whereSeparator: { $0.isWhitespace }).count)
        return max(0.45, Double(words) * 0.22 + minimumGap)
    }

    private func voiceOverCooldown(for text: String) -> TimeInterval {
        let words = max(1, text.split(whereSeparator: { $0.isWhitespace }).count)
        return min(0.18, max(0.05, Double(words) * 0.025))
    }

    private func escapeAppleScript(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func isVoiceOverRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.apple.VoiceOver" ||
            $0.localizedName == "VoiceOver"
        }
    }

    @discardableResult
    private func speakWithVoiceOver(_ text: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e",
            "tell application \"VoiceOver\" to output \"\(escapeAppleScript(text))\"",
        ]
        do {
            try process.run()
            process.waitUntilExit()
            Thread.sleep(forTimeInterval: voiceOverCooldown(for: text))
            return process.terminationStatus == 0
        } catch {
            printError("⚠️ Failed to send VoiceOver output: \(error)")
            return false
        }
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
            process.waitUntilExit()
            Thread.sleep(forTimeInterval: minimumGap)
            return process.terminationStatus == 0
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
        Thread.sleep(forTimeInterval: voiceOverCooldown(for: text))
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
    private var seededDecks: Set<Int> = []
    private var pendingLoopSizeAnnouncement: Set<Int> = []
    private var lastKnownLoopSizeByDeck: [Int: String] = [:]

    init(speaker: SpeechCoordinator) {
        self.speaker = speaker
    }

    func process(deckNumber: Int, deck: DeckInfo) {
        if let loop = deck.loopSize?.trimmingCharacters(in: .whitespacesAndNewlines), !loop.isEmpty {
            lastKnownLoopSizeByDeck[deckNumber] = loop
        }
        defer { previousDecks[deckNumber] = deck }

        guard isMeaningful(deck) else { return }

        guard seededDecks.contains(deckNumber) else {
            seededDecks.insert(deckNumber)
            return
        }

        let previous = previousDecks[deckNumber] ?? DeckInfo()
        guard isMeaningful(previous) else { return }
        guard !looksLikeBulkRefresh(previous: previous, current: deck) else { return }

        announceTrackChange(deckNumber: deckNumber, previous: previous, current: deck)
        announcePlayState(deckNumber: deckNumber, previous: previous, current: deck)
        announceLoopChange(deckNumber: deckNumber, previous: previous, current: deck)
        announceFXChanges(deckNumber: deckNumber, previous: previous, current: deck)
    }

    private func isMeaningful(_ deck: DeckInfo) -> Bool {
        deck.title?.isEmpty == false || deck.artist?.isEmpty == false || deck.bpm?.isEmpty == false || !deck.fxSlots.isEmpty || deck.loopSize?.isEmpty == false || deck.loopEnabled != nil
    }

    private func looksLikeBulkRefresh(previous: DeckInfo, current: DeckInfo) -> Bool {
        var changes = 0
        if previous.title != current.title { changes += 1 }
        if previous.artist != current.artist { changes += 1 }
        if previous.loopEnabled != current.loopEnabled { changes += 1 }
        if previous.loopSize != current.loopSize { changes += 1 }
        if previous.isPlaying != current.isPlaying { changes += 1 }
        if previous.fxSlots != current.fxSlots { changes += 1 }
        return changes >= 3
    }

    private func announceTrackChange(deckNumber: Int, previous: DeckInfo, current: DeckInfo) {
        guard let title = current.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty,
              let previousTitle = previous.title?.trimmingCharacters(in: .whitespacesAndNewlines), !previousTitle.isEmpty,
              title != previousTitle else { return }
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
        let previousEnabled = previous.loopEnabled ?? false
        let currentEnabled = current.loopEnabled ?? false
        let previousLoop = previous.loopSize?.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentLoop = current.loopSize?.trimmingCharacters(in: .whitespacesAndNewlines)

        if previousEnabled != currentEnabled {
            if currentEnabled {
                let loopToSpeak = currentLoop ?? previousLoop ?? lastKnownLoopSizeByDeck[deckNumber]
                if let loopToSpeak, !loopToSpeak.isEmpty {
                    pendingLoopSizeAnnouncement.remove(deckNumber)
                    speaker.speak(
                        "Deck \(deckNumber) loop \(loopToSpeak)",
                        key: "deck\(deckNumber)-loop-enabled",
                        minInterval: 0.05,
                        coalesce: true,
                        settleDelay: 0.15
                    )
                } else {
                    pendingLoopSizeAnnouncement.insert(deckNumber)
                    speaker.speak(
                        "Deck \(deckNumber) loop on",
                        key: "deck\(deckNumber)-loop-enabled",
                        minInterval: 0.05,
                        coalesce: true,
                        settleDelay: 0.12
                    )
                }
            } else {
                pendingLoopSizeAnnouncement.remove(deckNumber)
                speaker.speak(
                    "Deck \(deckNumber) loop off",
                    key: "deck\(deckNumber)-loop-enabled",
                    minInterval: 0.05,
                    coalesce: true,
                    settleDelay: 0.18
                )
            }
            return
        }

        guard let currentLoop, !currentLoop.isEmpty else { return }

        if pendingLoopSizeAnnouncement.contains(deckNumber) {
            pendingLoopSizeAnnouncement.remove(deckNumber)
            speaker.speak(
                "Deck \(deckNumber) loop \(currentLoop)",
                key: "deck\(deckNumber)-loop-size",
                minInterval: 0.05,
                coalesce: true,
                settleDelay: 0.12
            )
            return
        }

        guard let previousLoop, !previousLoop.isEmpty, currentLoop != previousLoop else { return }

        speaker.speak(
            currentEnabled ? "Deck \(deckNumber) loop \(currentLoop)" : "Deck \(deckNumber) loop size \(currentLoop)",
            key: currentEnabled ? "deck\(deckNumber)-loop-size-active" : "deck\(deckNumber)-loop-size-selected",
            minInterval: 0.05,
            coalesce: true,
            settleDelay: currentEnabled ? 0.22 : 0.14
        )
    }

    private func announceFXChanges(deckNumber: Int, previous: DeckInfo, current: DeckInfo) {
        let slots = Set(previous.fxSlots.keys).union(current.fxSlots.keys)
        for slot in slots.sorted() {
            let old = previous.fxSlots[slot] ?? FXSlotInfo()
            let new = current.fxSlots[slot] ?? FXSlotInfo()

            if let name = new.parameterName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
               let oldName = old.parameterName?.trimmingCharacters(in: .whitespacesAndNewlines), !oldName.isEmpty,
               name != oldName {
                speaker.speak(
                    "Deck \(deckNumber) FX \(slot) \(name)",
                    key: "deck\(deckNumber)-fx\(slot)-name",
                    minInterval: 0.1,
                    coalesce: true,
                    settleDelay: 0.2
                )
            }

            if let enabled = new.isEnabled, let oldEnabled = old.isEnabled, enabled != oldEnabled {
                speaker.speak(
                    "Deck \(deckNumber) FX \(slot) \(enabled ? "on" : "off")",
                    key: "deck\(deckNumber)-fx\(slot)-enabled",
                    minInterval: 0.1,
                    coalesce: true,
                    settleDelay: 0.1
                )
            }
        }
    }
}
