import Foundation

public struct FXSlotInfo: Equatable {
    public var parameterName: String?
    public var parameterValue: String?
    public var wetDry: String?
    public var isEnabled: Bool?

    public init(
        parameterName: String? = nil,
        parameterValue: String? = nil,
        wetDry: String? = nil,
        isEnabled: Bool? = nil
    ) {
        self.parameterName = parameterName
        self.parameterValue = parameterValue
        self.wetDry = wetDry
        self.isEnabled = isEnabled
    }
}

public struct DeckInfo: Equatable {
    public var key: String?
    public var title: String?
    public var artist: String?
    public var bpm: String?
    public var elapsedTime: String?
    public var remainingTime: String?
    public var bpmPercent: String?
    public var isPlaying: Bool
    public var lineVolume: String?
    public var keyLockEnabled: Bool?
    public var quantizeEnabled: Bool?
    public var loopEnabled: Bool?
    public var loopSize: String?
    public var neuralInstrumentalEnabled: Bool?
    public var neuralPercussiveEnabled: Bool?
    public var neuralAcapellaEnabled: Bool?
    public var neuralTonalEnabled: Bool?
    public var filter: String?
    public var gain: String?
    public var eqHigh: String?
    public var eqMid: String?
    public var eqLow: String?
    public var fxSlots: [Int: FXSlotInfo]

    public init(
        key: String? = nil,
        title: String? = nil,
        artist: String? = nil,
        bpm: String? = nil,
        elapsedTime: String? = nil,
        remainingTime: String? = nil,
        bpmPercent: String? = nil,
        isPlaying: Bool = false,
        lineVolume: String? = nil,
        keyLockEnabled: Bool? = nil,
        quantizeEnabled: Bool? = nil,
        loopEnabled: Bool? = nil,
        loopSize: String? = nil,
        neuralInstrumentalEnabled: Bool? = nil,
        neuralPercussiveEnabled: Bool? = nil,
        neuralAcapellaEnabled: Bool? = nil,
        neuralTonalEnabled: Bool? = nil,
        filter: String? = nil,
        gain: String? = nil,
        eqHigh: String? = nil,
        eqMid: String? = nil,
        eqLow: String? = nil,
        fxSlots: [Int: FXSlotInfo] = [:]
    ) {
        self.key = key
        self.title = title
        self.artist = artist
        self.bpm = bpm
        self.elapsedTime = elapsedTime
        self.remainingTime = remainingTime
        self.bpmPercent = bpmPercent
        self.isPlaying = isPlaying
        self.lineVolume = lineVolume
        self.keyLockEnabled = keyLockEnabled
        self.quantizeEnabled = quantizeEnabled
        self.loopEnabled = loopEnabled
        self.loopSize = loopSize
        self.neuralInstrumentalEnabled = neuralInstrumentalEnabled
        self.neuralPercussiveEnabled = neuralPercussiveEnabled
        self.neuralAcapellaEnabled = neuralAcapellaEnabled
        self.neuralTonalEnabled = neuralTonalEnabled
        self.filter = filter
        self.gain = gain
        self.eqHigh = eqHigh
        self.eqMid = eqMid
        self.eqLow = eqLow
        self.fxSlots = fxSlots
    }
}

public struct ElementInfo {
    public var label: String?
    public var role: String?
    public var value: String?
    public var subrole: String?

    public init(label: String? = nil, role: String? = nil, value: String? = nil, subrole: String? = nil) {
        self.label = label
        self.role = role
        self.value = value
        self.subrole = subrole
    }
}
