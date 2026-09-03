//
//  PerformanceGestureAssembler.swift
//  MIDIKit
//

import CoreMIDI


struct PerformanceGesture: Hashable {
    var pitchMask: UInt128
    var releasedPitchMask: UInt128
    var startedAt: MIDITimeStamp?
    var lastAttackAt: MIDITimeStamp?
    var lastReleaseAt: MIDITimeStamp?
    var attackCount: Int
    var velocityTotal: Int

    var averageVelocity: Double {
        Double(velocityTotal) / Double(max(1, attackCount))
    }
}

struct PerformanceGestureContext {
    let currentMasks: EngravingPitchMasks
    let nextMasks: EngravingPitchMasks
    let attack: EngravingReference.Attack
    let timing: PerformanceTimingModel.GestureHint

    static let unknown = Self(
        currentMasks: EngravingPitchMasks(),
        nextMasks: EngravingPitchMasks(),
        attack: .block,
        timing: .init(
            estimatedInterOnsetTicks: nil,
            estimatedChordSpanTicks: nil,
            reliability: 0
        )
    )
}

enum PerformanceGestureChange {
    case began(PerformanceGesture)
    case extended(PerformanceGesture)
    case crossedBoundary(completed: PerformanceGesture, current: PerformanceGesture)
}

/// Converts serialized MIDI note messages into physical musical gestures.
///
/// The assembler has no fixed chord timeout. It keeps adding attacks that are plausible members
/// of the current notated gesture, even when those attacks arrive slowly or earlier keys have
/// already been released. A score transition is exposed at most once for each incoming note.
struct PerformanceGestureAssembler {
    private(set) var current: PerformanceGesture?
    private var sustainIsDown = false
    private var sostenutoIsDown = false

    mutating func reset() {
        current = nil
        sustainIsDown = false
        sostenutoIsDown = false
    }

    mutating func noteOn(
        pitch: UInt8,
        velocity: UInt8,
        timestamp: MIDITimeStamp,
        context: PerformanceGestureContext
    ) -> PerformanceGestureChange {
        let bit = EngravingScoreFeatureIndex.pitchBit(pitch)
        guard var gesture = current else {
            let started = Self.newGesture(bit: bit, velocity: velocity, timestamp: timestamp)
            current = started
            return .began(started)
        }

        if shouldCrossBoundary(
            for: bit,
            at: timestamp,
            gesture: gesture,
            context: context
        ) {
            let completed = gesture
            let started = Self.newGesture(bit: bit, velocity: velocity, timestamp: timestamp)
            current = started
            return .crossedBoundary(completed: completed, current: started)
        }

        gesture.pitchMask |= bit
        gesture.attackCount += 1
        gesture.velocityTotal += Int(velocity)
        if timestamp != 0 { gesture.lastAttackAt = timestamp }
        current = gesture
        return .extended(gesture)
    }

    mutating func noteOff(pitch: UInt8, timestamp: MIDITimeStamp) {
        guard var current else { return }
        let bit = EngravingScoreFeatureIndex.pitchBit(pitch)
        if current.pitchMask & bit != 0 {
            current.releasedPitchMask |= bit
            if timestamp != 0 { current.lastReleaseAt = timestamp }
        }
        self.current = current
    }

    mutating func controlChange(control: UInt8, value: UInt8) {
        switch control {
        case 64: sustainIsDown = value >= 64
        case 66: sostenutoIsDown = value >= 64
        default: break
        }
    }

    private func shouldCrossBoundary(
        for pitch: UInt128,
        at newAttackTimestamp: MIDITimeStamp,
        gesture: PerformanceGesture,
        context: PerformanceGestureContext
    ) -> Bool {
        let repeated = gesture.pitchMask & pitch != 0
        if repeated {
            // Re-articulation after key release is the strongest tempo-independent boundary cue.
            return gesture.releasedPitchMask & pitch != 0
        }

        var belongsToCurrent = false
        var belongsToNext = false
        var maximumCoverage = 0.0
        for mode in EngravingHandMode.allCases {
            let currentMask = context.currentMasks[mode]
            let nextMask = context.nextMasks[mode]
            belongsToCurrent = belongsToCurrent || currentMask & pitch != 0
            belongsToNext = belongsToNext || nextMask & pitch != 0
            if currentMask != 0 {
                maximumCoverage = max(
                    maximumCoverage,
                    Double((gesture.pitchMask & currentMask).nonzeroBitCount)
                        / Double(currentMask.nonzeroBitCount)
                )
            }
        }

        // A still-unplayed notated chord member remains in the same gesture. This rule is what
        // makes slow rolls and serialized two-hand block chords independent of MIDI ordering.
        if belongsToCurrent { return false }

        let hasPhysicalRelease = gesture.releasedPitchMask != 0
        let completeEnough: Double = context.attack == .rolled ? 0.82 : 0.72
        let timingEvidence = context.timing.boundaryEvidence(
            gestureStartedAt: gesture.startedAt,
            lastAttackAt: gesture.lastAttackAt,
            newAttackAt: newAttackTimestamp
        )
        // Timing can move a threshold only slightly. It cannot close a chord by itself.
        let timingAdjustment = min(0.08, max(-0.08, timingEvidence * 0.08))
        if maximumCoverage >= completeEnough - timingAdjustment { return true }
        if belongsToNext, maximumCoverage >= 0.45 - timingAdjustment { return true }

        // A released monophonic or sparse gesture followed by an unrelated pitch is much more
        // likely a new, erroneous gesture than another constituent of the previous one. Pedals
        // weaken but do not erase the key-release evidence because they affect sound, not attack.
        let pedalRequiresMoreSupport = sustainIsDown || sostenutoIsDown
        return hasPhysicalRelease
            && gesture.pitchMask.nonzeroBitCount <= (pedalRequiresMoreSupport ? 1 : 2)
    }

    private static func newGesture(
        bit: UInt128,
        velocity: UInt8,
        timestamp: MIDITimeStamp
    ) -> PerformanceGesture {
        PerformanceGesture(
            pitchMask: bit,
            releasedPitchMask: 0,
            startedAt: timestamp == 0 ? nil : timestamp,
            lastAttackAt: timestamp == 0 ? nil : timestamp,
            lastReleaseAt: nil,
            attackCount: 1,
            velocityTotal: Int(velocity)
        )
    }
}
