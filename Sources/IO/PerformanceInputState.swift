//
//  PerformanceInputState.swift
//  MIDIKit
//

import CoreMIDI


/// Facts about one physical attack. This layer deliberately contains no score or chord-boundary
/// policy; onset membership is inferred independently by every alignment hypothesis.
struct PerformanceNoteAttack {
    let pitch: UInt8
    let velocity: UInt8
    let timestamp: MIDITimeStamp?
    let wasDepressed: Bool
    let hadDepressedKeysBeforeAttack: Bool
    let wasReleasedSincePreviousAttack: Bool
    let previousAttackTimestamp: MIDITimeStamp?
    let previousReleaseTimestamp: MIDITimeStamp?
    let eventOrdinal: UInt64
}

struct PerformanceNoteRelease {
    let pitch: UInt8
    let timestamp: MIDITimeStamp?
    let attackTimestamp: MIDITimeStamp?
    let eventOrdinal: UInt64

    var dwellTicks: Double? {
        guard let timestamp, let attackTimestamp, timestamp > attackTimestamp else { return nil }
        return Double(timestamp - attackTimestamp)
    }
}

/// Stateful interpretation of serialized MIDI as physical key and pedal activity.
///
/// MIDI timestamps are optional evidence: zero and nonmonotonic values are retained as unknown
/// relationships rather than repaired or used as ordering gates. Event order is always the order
/// in which `consume` is called.
struct PerformanceInputState {
    private(set) var depressedMask: UInt128 = 0
    private(set) var sustainIsDown = false
    private(set) var sostenutoIsDown = false
    private(set) var sustainChangedAt: MIDITimeStamp?
    private(set) var sostenutoChangedAt: MIDITimeStamp?

    private var lastAttack = Array<MIDITimeStamp?>(repeating: nil, count: 128)
    private var lastRelease = Array<MIDITimeStamp?>(repeating: nil, count: 128)
    private var releasedAfterAttack = Array(repeating: false, count: 128)
    private var ordinal: UInt64 = 0

    mutating func reset() {
        depressedMask = 0
        sustainIsDown = false
        sostenutoIsDown = false
        sustainChangedAt = nil
        sostenutoChangedAt = nil
        lastAttack = Array(repeating: nil, count: 128)
        lastRelease = Array(repeating: nil, count: 128)
        releasedAfterAttack = Array(repeating: false, count: 128)
        ordinal = 0
    }

    mutating func noteOn(
        pitch: UInt8,
        velocity: UInt8,
        timestamp: MIDITimeStamp
    ) -> PerformanceNoteAttack {
        let index = Int(pitch)
        let bit = EngravingScoreFeatureIndex.pitchBit(pitch)
        let validTimestamp = Self.valid(timestamp)
        let attack = PerformanceNoteAttack(
            pitch: pitch,
            velocity: velocity,
            timestamp: validTimestamp,
            wasDepressed: depressedMask & bit != 0,
            hadDepressedKeysBeforeAttack: depressedMask != 0,
            wasReleasedSincePreviousAttack: releasedAfterAttack[index],
            previousAttackTimestamp: lastAttack[index],
            previousReleaseTimestamp: lastRelease[index],
            eventOrdinal: ordinal
        )
        ordinal &+= 1
        depressedMask |= bit
        lastAttack[index] = validTimestamp
        releasedAfterAttack[index] = false
        return attack
    }

    @discardableResult
    mutating func noteOff(
        pitch: UInt8,
        timestamp: MIDITimeStamp
    ) -> PerformanceNoteRelease {
        let index = Int(pitch)
        let bit = EngravingScoreFeatureIndex.pitchBit(pitch)
        let validTimestamp = Self.valid(timestamp)
        depressedMask &= ~bit
        lastRelease[index] = validTimestamp
        releasedAfterAttack[index] = true
        let releaseOrdinal = ordinal
        ordinal &+= 1
        return PerformanceNoteRelease(
            pitch: pitch,
            timestamp: validTimestamp,
            attackTimestamp: lastAttack[index],
            eventOrdinal: releaseOrdinal
        )
    }

    mutating func controlChange(
        control: UInt8,
        value: UInt8,
        timestamp: MIDITimeStamp
    ) {
        ordinal &+= 1
        switch control {
        case 64:
            sustainIsDown = value >= 64
            sustainChangedAt = Self.valid(timestamp)
        case 66:
            sostenutoIsDown = value >= 64
            sostenutoChangedAt = Self.valid(timestamp)
        default: break
        }
    }

    private static func valid(_ timestamp: MIDITimeStamp) -> MIDITimeStamp? {
        timestamp == 0 ? nil : timestamp
    }
}
