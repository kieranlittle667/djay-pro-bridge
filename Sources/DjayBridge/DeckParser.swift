import ApplicationServices

// MARK: - Find Decks group

public func findDecksGroup(_ app: AXUIElement) -> AXUIElement? {
    for window in getChildren(app) {
        for child in getChildren(window) {
            let label = getLabel(child) ?? ""
            let title = getTitle(child) ?? ""
            if label == "Decks" || title == "Decks" {
                return child
            }
        }
    }
    return nil
}

// MARK: - Parse deck number from label

/// Extracts the deck number from labels like "Key, Deck 1" → 1
public func parseDeckNumber(from label: String) -> Int? {
    guard let range = label.range(of: #"Deck (\d+)"#, options: .regularExpression) else {
        return nil
    }
    let match = label[range]
    let numberStr = match.dropFirst(5)  // drop "Deck "
    return Int(numberStr)
}

private struct LabeledElement {
    let label: String
    let value: String?
}

// MARK: - Get deck info (used by Reader)

private func findLabeledElements(_ element: AXUIElement, prefix: String, depth: Int = 0) -> [LabeledElement] {
    var results: [LabeledElement] = []

    let label = getLabel(element) ?? ""
    let value = getValue(element) ?? getTitle(element)

    if !label.isEmpty && label.contains(prefix) {
        results.append(LabeledElement(label: label, value: value))
    }

    if depth < 6 {
        for child in getChildren(element) {
            results.append(contentsOf: findLabeledElements(child, prefix: prefix, depth: depth + 1))
        }
    }

    return results
}

/// Extracts the property name from a label like "Key, Deck 1" → "Key"
private func labelPrefix(_ label: String) -> String {
    if let commaRange = label.range(of: ", Deck ") {
        return String(label[label.startIndex..<commaRange.lowerBound])
    }
    return label
}

private func parseSlotNumber(from property: String) -> Int? {
    let patterns = [#"\bfx\s*(\d+)\b"#, #"\bslot\s*(\d+)\b"#]
    for pattern in patterns {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
        let nsrange = NSRange(property.startIndex..<property.endIndex, in: property)
        guard let match = regex.firstMatch(in: property, options: [], range: nsrange), match.numberOfRanges > 1,
            let range = Range(match.range(at: 1), in: property)
        else { continue }
        return Int(property[range])
    }
    return nil
}

private func fxParts(from prop: String) -> (name: String, slot: Int)? {
    guard let range = prop.range(of: #",\s*FX\s*(\d+)"#, options: .regularExpression) else {
        return nil
    }
    let name = String(prop[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    let suffix = String(prop[range.lowerBound...])
    guard let slot = parseSlotNumber(from: suffix) else { return nil }
    return (name, slot)
}

private func looksLikeLoopLength(_ value: String) -> Bool {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }
    let lower = trimmed.lowercased()
    return lower.contains("beat") || lower.contains("bar") || lower.contains("loop") || lower.range(of: #"^\d+(/\d+)?$"#, options: .regularExpression) != nil
}

private func setFXSlotValue(_ info: inout DeckInfo, slot: Int, update: (inout FXSlotInfo) -> Void) {
    var fxSlot = info.fxSlots[slot] ?? FXSlotInfo()
    update(&fxSlot)
    info.fxSlots[slot] = fxSlot
}

public func getDeckInfo(app: AXUIElement, deckNumber: Int) -> DeckInfo {
    let prefix = "Deck \(deckNumber)"
    let allElements = findLabeledElements(app, prefix: prefix)

    var info = DeckInfo()
    for element in allElements {
        let label = element.label
        let valueString = element.value ?? ""
        let lower = label.lowercased()
        let prop = labelPrefix(label)
        let lowerProp = prop.lowercased()

        if lower.starts(with: "key,") { info.key = valueString }
        else if lower.starts(with: "title,") { info.title = valueString }
        else if lower.starts(with: "artist,") { info.artist = valueString }
        else if lower.starts(with: "elapsed time,") { info.elapsedTime = valueString }
        else if lower.starts(with: "remaining time,") { info.remainingTime = valueString }
        else if lower.starts(with: "play /") { info.isPlaying = (valueString == "Active") }
        else if lowerProp.starts(with: "key lock") { info.keyLockEnabled = (valueString == "Active") }
        else if lowerProp.starts(with: "quantize") { info.quantizeEnabled = (valueString == "Active") }
        else if lowerProp == "loop" {
            let trimmed = valueString.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "Active" {
                info.loopEnabled = true
            } else if trimmed.isEmpty {
                if info.loopEnabled == nil { info.loopEnabled = false }
            } else if looksLikeLoopLength(trimmed) {
                info.loopSize = trimmed
            }
        }
        // Value-as-label: BPM is a numeric label like "124.0, Deck 1"
        else if prop.range(of: #"^\d+\.\d+$"#, options: .regularExpression) != nil {
            info.bpm = prop
        }
        // Value-as-label: BPM% is a percentage label like "+7.3%, Deck 1" or "-2.0%, Deck 1"
        else if prop.range(of: #"^[+-]?\d+\.\d+%$"#, options: .regularExpression) != nil {
            info.bpmPercent = prop
        }
        else if lowerProp.starts(with: "line volume") { info.lineVolume = valueString }
        else if lowerProp == "filter" { info.filter = valueString }
        else if lowerProp == "gain" { info.gain = valueString }
        else if lowerProp == "high" || lowerProp == "high eq" { info.eqHigh = valueString }
        else if lowerProp == "mid" || lowerProp == "mid eq" { info.eqMid = valueString }
        else if lowerProp == "low" || lowerProp == "low eq" { info.eqLow = valueString }
        else if let fx = fxParts(from: prop) {
            let fxNameLower = fx.name.lowercased()
            if fxNameLower == "enabled" {
                setFXSlotValue(&info, slot: fx.slot) { $0.isEnabled = (valueString == "Active") }
            } else if fxNameLower == "parameter" {
                setFXSlotValue(&info, slot: fx.slot) { $0.parameterValue = valueString }
            } else if fxNameLower == "wet/dry" || fxNameLower == "wet dry" {
                setFXSlotValue(&info, slot: fx.slot) { $0.wetDry = valueString }
            } else if fxNameLower != "previous" && fxNameLower != "next" {
                setFXSlotValue(&info, slot: fx.slot) { $0.parameterName = fx.name }
            }
        }
    }
    return info
}

// MARK: - Get crossfader (global, not per-deck)

public func getCrossfader(app: AXUIElement) -> String? {
    let elements = findLabeledElements(app, prefix: "Crossfader")
    return elements.first(where: { $0.label == "Crossfader" })?.value ?? nil
}

// MARK: - Get all elements (used by Dump)

public func getAllElements(decksGroup: AXUIElement) -> [String: [ElementInfo]] {
    var result: [String: [ElementInfo]] = [:]

    for child in getChildren(decksGroup) {
        let label = getLabel(child) ?? ""
        guard !label.isEmpty else { continue }

        let element = ElementInfo(
            label: label,
            role: getRole(child),
            value: getValue(child) ?? getTitle(child),
            subrole: getAttr(child, "AXSubrole") as? String
        )

        let deckKey: String
        if let deckNumber = parseDeckNumber(from: label) {
            deckKey = "\(deckNumber)"
        } else {
            deckKey = "other"
        }

        result[deckKey, default: []].append(element)
    }

    return result
}
